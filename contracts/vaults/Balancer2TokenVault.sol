// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.8.11;
pragma abicoder v2;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Token, VaultState, VaultAccount} from "../global/Types.sol";
import {BalancerUtils} from "../utils/BalancerUtils.sol";
import {OracleHelper} from "../utils/OracleHelper.sol";
import {BaseStrategyVault} from "./BaseStrategyVault.sol";
import {WETH9} from "../../interfaces/WETH9.sol";
import {IStrategyVault} from "../../interfaces/notional/IStrategyVault.sol";
import {VaultConfig} from "../../interfaces/notional/IVaultController.sol";
import {IBoostController} from "../../interfaces/notional/IBoostController.sol";
import {IVeBalDelegator} from "../../interfaces/notional/IVeBalDelegator.sol";
import {IBalancerVault} from "../../interfaces/balancer/IBalancerVault.sol";
import {IBalancerMinter} from "../../interfaces/balancer/IBalancerMinter.sol";
import {ILiquidityGauge} from "../../interfaces/balancer/ILiquidityGauge.sol";
import {IBalancerPool} from "../../interfaces/balancer/IBalancerPool.sol";
import {IPriceOracle} from "../../interfaces/balancer/IPriceOracle.sol";
import {ITradingModule, Trade, TradeType} from "../../interfaces/trading/ITradingModule.sol";
import {TradeHandler} from "../trading/TradeHandler.sol";

contract Balancer2TokenVault is
    UUPSUpgradeable,
    Initializable,
    BaseStrategyVault
{
    using TradeHandler for Trade;
    using SafeERC20 for ERC20;
    // @audit SafeInt256 has casts between uint and int and probably uses less bytecode space
    using SafeCast for uint256;

    struct DeploymentParams {
        uint16 secondaryBorrowCurrencyId;
        IBalancerVault balancerVault;
        bytes32 balancerPoolId;
        IBoostController boostController;
        ILiquidityGauge liquidityGauge;
        ITradingModule tradingModule;
        uint256 settlementPeriod;
    }

    struct InitParams {
        uint32 oracleWindowInSeconds;
        uint32 settlementCooldownInSeconds;
        uint32 balancerOracleWeight;
        uint32 maxBalancerPoolShare;
        uint256 maxUnderylingSurplus;
        uint32 settlementSlippageLimit;
        uint32 emergencySettlementSlippageLimit;
        uint32 settlementCoolDownInSeconds;
        uint32 emergencySettlementCoolDownInSeconds;
    }

    struct DepositParams {
        uint256 minBPT;
        uint256 secondaryfCashAmount;
        uint32 secondarySlippageLimit;
    }

    struct RedeemParams {
        uint32 secondarySlippageLimit;
        uint256 minPrimary;
        uint256 minSecondary;
        bool withdrawFromWETH;
        bytes callbackData;
    }

    struct RepaySecondaryCallbackParams {
        uint16 dexId;
        uint32 slippageLimit; // @audit the denomination of this should be marked in the variable name
        uint256 deadline;
        bytes exchangeData;
    }

    struct RewardTokenTradeParams {
        uint16 primaryTradeDexId;
        Trade primaryTrade;
        uint16 secondaryTradeDexId;
        Trade secondaryTrade;
    }

    struct ReinvestRewardParams {
        bytes tradeData;
        uint256 minBPT;
    }

    /** Errors */
    error InvalidPrimaryToken(address token);
    error InvalidSecondaryToken(address token);
    error NotionalOwnerRequired(address sender);
    error NotInSettlementWindow();
    error RedeemingTooMuch(
        int256 underlyingRedeemed,
        int256 underlyingCashRequiredToSettle
    );
    error SlippageTooHigh(uint32 slippage, uint32 limit);
    error InSettlementCoolDown(uint32 lastTimestamp, uint32 coolDown);

    /** Events */
    event InitParamsUpdated(InitParams params);

    /// @notice Emitted when a vault is settled
    /// @param assetTokenProfits total amount of profit to vault account holders, if this is negative
    /// than there is a shortfall that must be covered by the protocol
    /// @param underlyingTokenProfits same as assetTokenProfits but denominated in underlying
    event VaultSettled(
        uint256 maturity,
        int256 assetTokenProfits,
        int256 underlyingTokenProfits
    );

    /** Constants */

    uint256 internal constant SECONDARY_BORROW_UPPER_LIMIT = 105;
    uint256 internal constant SECONDARY_BORROW_LOWER_LIMIT = 95;
    uint32 internal constant MAX_SETTLEMENT_COOLDOWN = 24 * 3600; // 1 day
    uint32 internal constant MAX_ORACLE_WEIGHT = 1e8; // 100%
    uint32 internal constant MAX_SLIPPAGE_LIMIT = 1e8; // 100%
    uint32 internal constant MAX_BALANCER_POOL_SHARE = 1e8; // 100%
    uint32 internal constant BALANCER_POOL_SHARE_BUFFER = 8e7; // 80%
    WETH9 public constant WETH =
        WETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    /** Immutables */
    // @audit similar remark here, each public variable adds an external getter so all of these
    // will result in larger bytecode size, consider just making one method that returns all the
    // immutables
    uint16 public immutable SECONDARY_BORROW_CURRENCY_ID;
    IBalancerVault public immutable BALANCER_VAULT;
    bytes32 public immutable BALANCER_POOL_ID;
    IBalancerPool public immutable BALANCER_POOL_TOKEN;
    ERC20 public immutable SECONDARY_TOKEN;
    IBoostController public immutable BOOST_CONTROLLER;
    ILiquidityGauge public immutable LIQUIDITY_GAUGE;
    IVeBalDelegator public immutable VEBAL_DELEGATOR;
    ITradingModule public immutable TRADING_MODULE;
    ERC20 public immutable BAL_TOKEN;
    uint8 public immutable PRIMARY_INDEX;
    uint256 public immutable SETTLEMENT_PERIOD;
    uint256 public immutable PRIMARY_WEIGHT;
    uint256 public immutable SECONDARY_WEIGHT;

    /// @notice account => (maturity => balance)
    mapping(address => mapping(uint256 => uint256))
        private secondaryAmountfCashBorrowed;

    /// @notice Keeps track of the possible gauge reward tokens
    mapping(address => bool) private gaugeRewardTokens;

    /// @notice Total number of strategy tokens across all maturities
    uint256 public totalStrategyTokenGlobal;

    // @audit this can probably be a smaller value in storage, if you move this down a slot
    // it will pack in with the rest of the uint32 values
    /// @notice Balancer oracle window in seconds
    uint256 public oracleWindowInSeconds;

    uint256 public maxUnderylingSurplus;

    // @audit if you move oracleWindowInSeconds to right here and then you reduce the size of
    // settlementCoolDownInSeconds and emergencySettlementCoolDownInSeconds to uint16 on both,
    // using minutes instead of seconds to define them you will be able to pack all the rest of the
    // storage into a single slot. That should save some gas. To make it clearer you could make
    // a struct with all of these values.
    // @audit marking all of these storage values as public adds a getter for each one, which
    // adds a decent amount of bytecode. consider making them internal and then creating a single
    // getter for all the parameters (or just move them into structs and mark those as public)
    uint32 public maxBalancerPoolShare;

    /// @notice Slippage limit for normal settlement
    uint32 public settlementSlippageLimit;

    /// @notice Slippage limit for emergency settlement (vault owns too much of the Balancer pool)
    uint32 public emergencySettlementSlippageLimit;

    uint32 public balancerOracleWeight;

    /// @notice Cool down in seconds for normal settlement
    // @audit this can be a smaller value in storage especially if you use minutes in storage instead
    uint32 public settlementCoolDownInSeconds;

    /// @notice Cool down in seconds for emergency settlement
    // @audit this can be a smaller value in storage especially if you use minutes in storage instead
    uint32 public emergencySettlementCoolDownInSeconds;

    uint32 public lastSettlementTimestamp;

    uint32 public lastEmergencySettlementTimestamp;

    constructor(
        address notional_,
        uint16 borrowCurrencyId_,
        DeploymentParams memory params
    )
        BaseStrategyVault(
            // @audit this should have the token names in it if we have multiple versions of this
            // vault, consider using string(abi.encodePacked("Wrapped f", _symbol, " @ ", _maturity))
            // so that we can generate a consistent name based on the underlying tokens for the
            // vault. In the newer version of BaseStrategyVault the name is set in the initializer
            // since it is always a storage variable anyway.
            "Balancer 2-Token Strategy Vault",
            notional_,
            borrowCurrencyId_
        )
        initializer
    {
        // @audit we should validate in this method that the balancer oracle is enabled otherwise none
        // of the methods will work:
        // https://dev.balancer.fi/references/contracts/apis/pools/weightedpool2tokens#getmiscdata

        SECONDARY_BORROW_CURRENCY_ID = params.secondaryBorrowCurrencyId;
        BALANCER_VAULT = params.balancerVault;
        BALANCER_POOL_ID = params.balancerPoolId;
        BALANCER_POOL_TOKEN = IBalancerPool(
            BalancerUtils.getPoolAddress(
                params.balancerVault,
                params.balancerPoolId
            )
        );

        // prettier-ignore
        (
            address[] memory tokens,
            /* uint256[] memory balances */,
            /* uint256 lastChangeBlock */
        ) = BALANCER_VAULT.getPoolTokens(BALANCER_POOL_ID);

        // Balancer tokens are sorted by address, so we need to figure out
        // the correct index for the primary token
        PRIMARY_INDEX = tokens[0] == _tokenAddress(address(UNDERLYING_TOKEN))
            ? 0
            : 1;

        // Since this is always a 2-token vault, SECONDARY_INDEX = 1-PRIMARY_INDEX
        SECONDARY_TOKEN = SECONDARY_BORROW_CURRENCY_ID > 0
            ? ERC20(_getUnderlyingAddress(SECONDARY_BORROW_CURRENCY_ID))
            : ERC20(tokens[1 - PRIMARY_INDEX]);

        // Make sure the deployment parameters are correct
        if (tokens[PRIMARY_INDEX] != _tokenAddress(address(UNDERLYING_TOKEN)))
            revert InvalidPrimaryToken(tokens[PRIMARY_INDEX]);
        if (
            tokens[1 - PRIMARY_INDEX] != _tokenAddress(address(SECONDARY_TOKEN))
        ) revert InvalidSecondaryToken(tokens[1 - PRIMARY_INDEX]);

        uint256[] memory weights = BALANCER_POOL_TOKEN.getNormalizedWeights();

        PRIMARY_WEIGHT = weights[PRIMARY_INDEX];
        SECONDARY_WEIGHT = weights[1 - PRIMARY_INDEX];

        BOOST_CONTROLLER = params.boostController;
        LIQUIDITY_GAUGE = params.liquidityGauge;
        VEBAL_DELEGATOR = IVeBalDelegator(BOOST_CONTROLLER.VEBAL_DELEGATOR());
        BAL_TOKEN = ERC20(
            IBalancerMinter(VEBAL_DELEGATOR.BALANCER_MINTER())
                .getBalancerToken()
        );
        TRADING_MODULE = params.tradingModule;
        // @audit mark what units this will should be set in, (seconds?)
        SETTLEMENT_PERIOD = params.settlementPeriod;
    }

    function initialize(InitParams calldata params)
        external
        initializer
        onlyNotionalOwner
    {
        _initParams(params);
        _initRewardTokenList();
        _approveTokens();
    }

    function _initParams(InitParams calldata params) private {
        // @audit this should call a version of setInitParams instead so that there is validation on the first call
        oracleWindowInSeconds = params.oracleWindowInSeconds;
        settlementCoolDownInSeconds = params.settlementCooldownInSeconds;
        balancerOracleWeight = params.balancerOracleWeight;
        maxBalancerPoolShare = params.maxBalancerPoolShare;
        maxUnderylingSurplus = params.maxUnderylingSurplus;
        settlementSlippageLimit = params.settlementSlippageLimit;
        emergencySettlementSlippageLimit = params
            .emergencySettlementSlippageLimit;
        settlementCoolDownInSeconds = params.settlementCoolDownInSeconds;
        emergencySettlementCoolDownInSeconds = params
            .emergencySettlementCoolDownInSeconds;
    }

    /// @notice Special handling for ETH because UNDERLYING_TOKEN == address(0)
    /// and Balancer uses WETH
    function _tokenAddress(address token) private view returns (address) {
        // @audit consider using a constant for address(0) here like ETH_ADDRESS or something
        return token == address(0) ? address(WETH) : address(token);
    }

    function _tokenBalance(address token) private view returns (uint256) {
        // @audit consider using a constant for address(0) here like ETH_ADDRESS or something
        return
            token == address(0)
                ? address(this).balance
                : ERC20(token).balanceOf(address(this));
    }

    /// @notice Gets the underlying token address by currency ID
    function _getUnderlyingAddress(uint16 currencyId)
        private
        view
        returns (address)
    {
        // @audit there is an edge case around non-mintable tokens, you can see how this is
        // handled in the constructor in the base strategy vault. if this method is only called
        // once in the constructor maybe just inline the method call there otherwise this may
        // get called accidentally in non constructor methods?
        // prettier-ignore
        (
            /* Token memory assetToken */, 
            Token memory underlyingToken
        ) = NOTIONAL.getCurrency(currencyId);
        return underlyingToken.tokenAddress;
    }

    /// @notice This list is used to validate trades
    function _initRewardTokenList() private {
        // @audit is it possible that this token list ever updates? should we make this method callable
        // by the owner to update it? Also what if a a reward token is de-listed? It appears that this
        // is only used once, do you think we could just validate the rewardToken each time in
        // _executeRewardTrades?
        if (address(LIQUIDITY_GAUGE) != address(0)) {
            address[] memory rewardTokens = VEBAL_DELEGATOR
                .getGaugeRewardTokens(address(LIQUIDITY_GAUGE));
            for (uint256 i; i < rewardTokens.length; i++)
                gaugeRewardTokens[rewardTokens[i]] = true;
        }
    }

    /// @notice Approve necessary token transfers
    function _approveTokens() private {
        // Approving in external lib to reduce contract size
        // @audit would be nice to move this back into the contract if we have the space
        TradeHandler.approveTokens(
            address(BALANCER_VAULT),
            address(UNDERLYING_TOKEN),
            address(SECONDARY_TOKEN),
            address(BALANCER_POOL_TOKEN),
            address(LIQUIDITY_GAUGE),
            address(VEBAL_DELEGATOR)
        );
    }

    /// @notice Converts strategy tokens to underlyingValue
    /// @dev Secondary token value is converted to its primary token equivalent value
    /// using the Balancer time-weighted price oracle
    /// @param strategyTokenAmount strategy token amount
    /// @param maturity maturity timestamp
    /// @return underlyingValue underlying (primary token) value of the strategy tokens
    function convertStrategyToUnderlying(
        address account,
        uint256 strategyTokenAmount,
        uint256 maturity
    ) public view override returns (int256 underlyingValue) {
        uint256 bptClaim = convertStrategyTokensToBPTClaim(
            strategyTokenAmount,
            maturity
        );

        // @audit it would be more efficient to combine this method call with
        // the second method call to get the pairPrice. it looks like it is already
        // calculated inside this method so I would return it here.
        uint256 primaryBalance = OracleHelper.getTimeWeightedPrimaryBalance(
            address(BALANCER_POOL_TOKEN),
            oracleWindowInSeconds,
            PRIMARY_INDEX,
            PRIMARY_WEIGHT,
            SECONDARY_WEIGHT,
            // @audit consider storing this as immutable to save gas
            address(UNDERLYING_TOKEN) == address(0)
                ? 18
                : UNDERLYING_TOKEN.decimals(),
            bptClaim
        );

        if (SECONDARY_BORROW_CURRENCY_ID == 0) return primaryBalance.toInt256();

        // Get the amount of secondary fCash borrowed
        // We directly use the fCash amount instead of converting to underyling
        // as an approximation with built-in interest and haircut parameters
        uint256 borrowedSecondaryfCashAmount = getSecondaryBorrowedfCashAmount(
            account,
            maturity,
            strategyTokenAmount
        );

        // @audit every external method call adds a significant amount of bytecode for
        // loading the memory buffer and then unpacking it, reducing external calls will
        // save a lot of gas and bytecode space.
        // @audit this variable should be renamed to weightedOraclePairPrice or something to
        // make it clear it is an oracle price
        // @audit leave a comment here mentioning that the oracle price is normalized to 18 decimals
        uint256 pairPrice = OracleHelper.getPairPrice(
            address(BALANCER_POOL_TOKEN),
            address(BALANCER_VAULT),
            BALANCER_POOL_ID,
            address(TRADING_MODULE),
            oracleWindowInSeconds,
            balancerOracleWeight
        );

        // @audit I find this variable name a little confusing, maybe this should be named
        // "secondaryBorrowedDenominatedInPrimary"
        uint256 borrowedPrimaryAmount;
        if (PRIMARY_INDEX == 0) {
            borrowedPrimaryAmount =
                // @audit 1e18 should be a named constant here
                (borrowedSecondaryfCashAmount * 1e18) /
                pairPrice;
        } else {
            borrowedPrimaryAmount =
                (borrowedSecondaryfCashAmount * pairPrice) /
                1e18;
        }

        // @audit are you sure the precision here is matching? borrowedSecondaryfCashAmount is
        // always 8 decimal precision whereas primaryBalance should be in the native underlying
        // token precision
        return primaryBalance.toInt256() - borrowedPrimaryAmount.toInt256();
    }

    function _joinPool(
        address account,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) private {
        DepositParams memory params = abi.decode(data, (DepositParams));

        uint256 borrowedSecondaryAmount;
        if (SECONDARY_BORROW_CURRENCY_ID > 0) {
            uint256 optimalSecondaryAmount = getOptimalSecondaryBorrowAmount(
                deposit
            );

            // Borrow secondary currency from Notional (tokens will be transferred to this contract)
            borrowedSecondaryAmount = NOTIONAL.borrowSecondaryCurrencyToVault(
                SECONDARY_BORROW_CURRENCY_ID,
                maturity,
                params.secondaryfCashAmount,
                params.secondarySlippageLimit
            );

            // Require the secondary borrow amount to be within SECONDARY_BORROW_LOWER_LIMIT percent
            // of the optimal amount
            require(
                // @audit rearrange these so that the inequalities are always <= for clarity.
                borrowedSecondaryAmount >=
                    ((optimalSecondaryAmount * (SECONDARY_BORROW_LOWER_LIMIT)) /
                        100) &&
                    borrowedSecondaryAmount <=
                    (optimalSecondaryAmount * (SECONDARY_BORROW_UPPER_LIMIT)) /
                        100,
                // @audit return a typed error here like:
                // InvalidSecondaryBorrow(borrowedSecondaryAmount, optimalSecondaryAmount, params.secondaryfCashAmount)
                "invalid secondary amount"
            );

            // Track the amount borrowed per account and maturity on the contract
            // @audit the borrowed secondary fCash amount tracking is incorrect here, i'll have to think a bit more
            // about how we handle it but it needs to be a share of the total secondary fCash borrowed to account
            // for the situation where settlement occurs and the secondary fCash borrowed is repaid for the vault
            // as a whole.
            // @audit I will write a helper library for tracking secondary borrowed amounts, perhaps we should just
            // put it on the main Notional vault instead of doing it inside the vault here.
            secondaryAmountfCashBorrowed[account][maturity] += params
                .secondaryfCashAmount;
        }

        BalancerUtils.joinPool(
            address(BALANCER_VAULT), 
            BALANCER_POOL_ID, 
            address(UNDERLYING_TOKEN), 
            deposit, 
            address(SECONDARY_TOKEN), 
            borrowedSecondaryAmount, 
            PRIMARY_INDEX, 
            params.minBPT
        );
    }

    function _depositFromNotional(
        address account,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 strategyTokensMinted) {
        // Join pool
        uint256 bptBefore = BALANCER_POOL_TOKEN.balanceOf(address(this));
        _joinPool(account, deposit, maturity, data);
        uint256 bptAfter = BALANCER_POOL_TOKEN.balanceOf(address(this));

        uint256 bptAmount = bptAfter - bptBefore;

        // Stake liquidity
        LIQUIDITY_GAUGE.deposit(bptAmount);

        // Transfer gauge token to VeBALDelegator
        BOOST_CONTROLLER.depositToken(address(LIQUIDITY_GAUGE), bptAmount);

        // Mint strategy tokens
        if (totalStrategyTokenGlobal == 0) {
            strategyTokensMinted = bptAmount;
        } else {
            // @audit the calculation for the next three variables can be made into a helper method since
            // it is used more than once
            uint256 totalBPTHeld = bptHeld();
            uint256 totalStrategyTokenSupplyInMaturity = totalSupply(maturity);
            uint256 bptHeldInMaturity = (totalBPTHeld *
                totalStrategyTokenSupplyInMaturity) / totalStrategyTokenGlobal;
            strategyTokensMinted =
                (totalStrategyTokenSupplyInMaturity * bptAmount) /
                // @audit leave a comment on this math here, but looks correct
                (bptHeldInMaturity - bptAmount);
        }

        // Update global supply count
        totalStrategyTokenGlobal += strategyTokensMinted;
    }

    // @audit for readability, it might be nice to group some of these methods closer to where they are
    // called by other functions (this would be better to group near convertStrategyToUnderlying)
    /// @notice Converts strategy tokens to BPT
    function convertStrategyTokensToBPTClaim(
        uint256 strategyTokenAmount,
        uint256 maturity
    ) public view returns (uint256 bptClaim) {
        // @audit-ok math looks good
        if (totalStrategyTokenGlobal == 0) return strategyTokenAmount;

        // @audit use a helper method for these next three calculations
        uint256 totalBPTHeld = bptHeld();
        uint256 totalStrategyTokenSupplyInMaturity = totalSupply(maturity);
        uint256 bptHeldInMaturity = (totalBPTHeld *
            totalStrategyTokenSupplyInMaturity) / totalStrategyTokenGlobal;
        bptClaim =
            (bptHeldInMaturity * strategyTokenAmount) /
            totalStrategyTokenSupplyInMaturity;
    }

    /// @notice Converts BPT to strategy tokens
    function convertBPTClaimToStrategyTokens(uint256 bptClaim, uint256 maturity)
        public
        view
        returns (uint256 strategyTokenAmount)
    {
        if (totalStrategyTokenGlobal == 0) return bptClaim;

        // @audit use a helper method for these next three calculations
        uint256 totalBPTHeld = bptHeld();
        uint256 totalStrategyTokenSupplyInMaturity = totalSupply(maturity);
        uint256 bptHeldInMaturity = (totalBPTHeld *
            totalStrategyTokenSupplyInMaturity) / totalStrategyTokenGlobal;
        strategyTokenAmount =
            (totalStrategyTokenSupplyInMaturity * bptClaim) /
            bptHeldInMaturity;
    }

    function _exitPool(
        address account,
        uint256 bptExitAmount,
        uint256 maturity,
        uint256 borrowedSecondaryfCashAmount,
        bytes calldata data
    ) internal {
        RedeemParams memory params = abi.decode(data, (RedeemParams));

        BalancerUtils.exitPool(
            address(BALANCER_VAULT), 
            BALANCER_POOL_ID, 
            address(UNDERLYING_TOKEN), 
            params.minPrimary, 
            address(SECONDARY_TOKEN), 
            params.minSecondary, 
            PRIMARY_INDEX, 
            bptExitAmount, 
            params.withdrawFromWETH // @audit Notional expects ETH in the BaseStrategyVault so this
                                    // parameter is something to be careful about allowing the user to set
        );

        // Repay secondary debt
        if (borrowedSecondaryfCashAmount > 0) {
            NOTIONAL.repaySecondaryCurrencyFromVault(
                SECONDARY_BORROW_CURRENCY_ID,
                maturity,
                borrowedSecondaryfCashAmount,
                params.secondarySlippageLimit,
                params.callbackData
            );
            // @audit the user's secondaryfCash borrowed is never decremented here
        }
    }

    /// @notice Callback function for repaying secondary debt
    function _repaySecondaryBorrowCallback(
        uint256 underlyingRequired,
        bytes calldata data
    ) internal override returns (bytes memory returnData) {
        // @audit this is already checked in the external method
        require(msg.sender == address(NOTIONAL)); /// @dev invalid caller
        require(SECONDARY_BORROW_CURRENCY_ID > 0); /// @dev invalid secondary currency
        RepaySecondaryCallbackParams memory params = abi.decode(
            data,
            (RepaySecondaryCallbackParams)
        );

        uint256 secondaryBalance = _tokenBalance(address(SECONDARY_TOKEN));
        Trade memory trade;

        if (secondaryBalance < underlyingRequired) {
            // Not enough secondary balance to repay debt, sell some primary currency
            trade = Trade(
                TradeType.EXACT_OUT_SINGLE,
                address(UNDERLYING_TOKEN),
                address(SECONDARY_TOKEN),
                underlyingRequired - secondaryBalance, // @audit can mark unchecked
                TradeHandler.getLimitAmount(
                    address(TRADING_MODULE),
                    uint16(TradeType.EXACT_OUT_SINGLE),
                    address(UNDERLYING_TOKEN),
                    address(SECONDARY_TOKEN),
                    underlyingRequired - secondaryBalance, // @audit can mark unchecked, put this on the stack and calculate once
                    params.slippageLimit
                ),
                params.deadline, // @audit deadline should always be block.timestamp
                params.exchangeData
            );

            trade.execute(TRADING_MODULE, params.dexId);
        }

        // Update balance before transfer
        // @audit this will revert if secondaryBalance < underlyingRequired
        secondaryBalance -= underlyingRequired;

        // Transfer required secondary balance to Notional
        if (SECONDARY_BORROW_CURRENCY_ID == 1) { // @audit use a named constant for 1
            payable(address(NOTIONAL)).transfer(underlyingRequired);
        } else {
            SECONDARY_TOKEN.safeTransfer(address(NOTIONAL), underlyingRequired);
        }

        if (secondaryBalance > 0) {
            // Sell residual secondary balance
            trade = Trade(
                TradeType.EXACT_IN_SINGLE,
                address(SECONDARY_TOKEN),
                address(UNDERLYING_TOKEN),
                secondaryBalance,
                TradeHandler.getLimitAmount(
                    address(TRADING_MODULE),
                    uint16(TradeType.EXACT_OUT_SINGLE),
                    address(SECONDARY_TOKEN),
                    address(UNDERLYING_TOKEN),
                    secondaryBalance,
                    params.slippageLimit // @audit what denomination is slippage limit in here?
                ),
                params.deadline, // @audit deadline should be block.timestamp
                params.exchangeData
            );

            trade.execute(TRADING_MODULE, params.dexId);
        }
    }

    function _redeemFromNotional(
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 tokensFromRedeem) {
        // @audit the returned value for tokensForRedeem is incorrect here, it should be
        // the amount of primary underlying tokens as a result of the redemption
        tokensFromRedeem = convertStrategyTokensToBPTClaim(
            strategyTokens,
            maturity
        );

        if (tokensFromRedeem > 0) {
            // Withdraw gauge token from VeBALDelegator
            BOOST_CONTROLLER.withdrawToken(
                address(LIQUIDITY_GAUGE),
                tokensFromRedeem
            );

            // Unstake BPT
            LIQUIDITY_GAUGE.withdraw(tokensFromRedeem, false);

            // Calculate the amount of secondary tokens to repay
            uint256 borrowedSecondaryfCashAmount = getSecondaryBorrowedfCashAmount(
                    account,
                    maturity,
                    strategyTokens
                );

            _exitPool(
                account,
                tokensFromRedeem,
                maturity,
                borrowedSecondaryfCashAmount,
                data
            );
        }
    }

    function _validateSettlementSlippage(
        bytes memory data,
        uint32 slippageLimit
    ) private {
        RedeemParams memory params = abi.decode(data, (RedeemParams));
        RepaySecondaryCallbackParams memory callbackParams = abi.decode(
            params.callbackData,
            (RepaySecondaryCallbackParams)
        );
        if (callbackParams.slippageLimit > slippageLimit) {
            revert SlippageTooHigh(callbackParams.slippageLimit, slippageLimit);
        }
    }

    function _validateSettlementCoolDown(uint32 lastTimestamp, uint32 coolDown)
        private
    {
        if (lastTimestamp + coolDown > block.timestamp)
            revert InSettlementCoolDown(lastTimestamp, coolDown);
    }

    function settleVault(
        uint256 maturity,
        uint256 bptToSettle,
        bytes calldata data
    ) external {
        // @audit name this redeemStrategyTokenAmount so the denomination is clear, this also appears to be set to
        // zero in 2 of the 3 cases.
        uint256 redeemAmount;
        // @audit would this code be cleaner and safer if we just split it into three different external methods?
        if (maturity <= block.timestamp) {
            // Vault has reached maturity. settleVault becomes authenticated in this case
            if (msg.sender != NOTIONAL.owner())
                revert NotionalOwnerRequired(msg.sender);
            // @audit I'm not sure if it is correct to call this the the emergencySettlement, it is maybe more
            // correct to call this this post maturity settlement
            _validateSettlementCoolDown(
                lastEmergencySettlementTimestamp,
                emergencySettlementCoolDownInSeconds
            );
            _validateSettlementSlippage(data, emergencySettlementSlippageLimit);
        } else {
            if (maturity - SETTLEMENT_PERIOD <= block.timestamp) {
                // In settlement window
                _validateSettlementCoolDown(
                    lastSettlementTimestamp,
                    settlementCoolDownInSeconds
                );
                _validateSettlementSlippage(data, settlementSlippageLimit);
            } else {
                // Not in settlement window, check if BPT held is greater than maxBalancerPoolShare * total BPT supply
                // @audit this variable should be emergencyBPTWithdrawThreshold
                uint256 maxBPTAmount = (BALANCER_POOL_TOKEN.totalSupply() *
                    maxBalancerPoolShare) / 1e8; // @audit use a named constant for 1e8
                uint256 _bptHeld = bptHeld();
                // @audit this error message should be InvalidEmergencySettlement()
                if (_bptHeld <= maxBPTAmount) revert NotInSettlementWindow();

                // desiredPoolShare = maxPoolShare * bufferPercentage
                uint256 desiredPoolShare = (maxBalancerPoolShare *
                    BALANCER_POOL_SHARE_BUFFER) / 1e8;
                // @audit BalancerPool.totalSupply() is called twice here, just put it on the stack
                uint256 desiredBPTAmount = (BALANCER_POOL_TOKEN.totalSupply() *
                    desiredPoolShare) / 1e8;
                redeemAmount = convertBPTClaimToStrategyTokens(
                    _bptHeld - desiredBPTAmount,
                    maturity
                );
            }
        }

        // @audit this variable should be named the expected oracle value of underlying redeemed
        int256 underlyingRedeemed = convertStrategyToUnderlying(
            address(this),
            redeemAmount,
            maturity
        );

        // prettier-ignore
        (
            int256 assetCashRequiredToSettle,
            int256 underlyingCashRequiredToSettle
        ) = NOTIONAL.getCashRequiredToSettle(address(this), maturity);

        // Make sure we not redeeming too much to underlying
        // This allows BPT to be accrued as the profit token.
        if (
            // @audit this can use a comment on the nature of how the different signs will behave since
            // underlyingRedeemed can be negative and underlyingCashRequiredToSettle can be negative as well
            underlyingRedeemed - underlyingCashRequiredToSettle >
            int256(maxUnderylingSurplus)
        ) {
            revert RedeemingTooMuch(
                underlyingRedeemed,
                underlyingCashRequiredToSettle
            );
        }

        // prettier-ignore
        (
            int256 assetCashProfit,
            int256 underlyingCashProfit
        ) = NOTIONAL.redeemStrategyTokensToCash(maturity, redeemAmount, data);
        // @audit if assetCashProfit (i would rename this value) is < 0 AND we are past maturity 
        // then call NOTIONAL.settleVault(...) to mark the vault as settled in here.

        // Profits are the surplus in cash after the tokens have been settled, this is the negation of
        // what is returned from the method above
        emit VaultSettled(
            maturity,
            // @audit it's not necessary to emit these values, they are not profits they are just residuals from settlement
            -1 * assetCashProfit,
            -1 * underlyingCashProfit
        );
    }

    /// @notice Claim BAL token gauge reward
    /// @return balAmount amount of BAL claimed
    function claimBAL() external returns (uint256) {
        // @audit perhaps it would be more efficient to then call executeRewardTrades right after
        // this claim is done inside the same method?
        // @audit part of this BAL that is claimed needs to be donated to the Notional protocol,
        // we should set an percentage and then transfer to the TreasuryManager contract.
        return BOOST_CONTROLLER.claimBAL(address(LIQUIDITY_GAUGE));
    }

    /// @notice Claim other liquidity gauge reward tokens (i.e. LIDO)
    /// @return tokens addresses of reward tokens
    /// @return balancesTransferred amount of tokens claimed
    function claimGaugeTokens()
        external
        returns (address[] memory, uint256[] memory)
    {
        // @audit perhaps it would be more efficient to then call executeRewardTrades right after
        // this claim is done inside the same method?
        return BOOST_CONTROLLER.claimGaugeTokens(address(LIQUIDITY_GAUGE));
    }

    function _executeRewardTrades(bytes memory data)
        private
        returns (uint256 primaryAmount, uint256 secondaryAmount)
    {
        RewardTokenTradeParams memory params = abi.decode(
            data,
            (RewardTokenTradeParams)
        );

        // Validate trades
        if (!gaugeRewardTokens[params.primaryTrade.sellToken]) {
            revert InvalidPrimaryToken(params.primaryTrade.sellToken);
        }
        if (params.primaryTrade.sellToken != params.secondaryTrade.sellToken) {
            revert InvalidSecondaryToken(params.secondaryTrade.sellToken);
        }
        if (
            params.primaryTrade.buyToken !=
            _tokenAddress(address(UNDERLYING_TOKEN))
        ) {
            revert InvalidPrimaryToken(params.primaryTrade.buyToken);
        }
        if (
            params.secondaryTrade.buyToken !=
            _tokenAddress(address(SECONDARY_TOKEN))
        ) {
            revert InvalidSecondaryToken(params.secondaryTrade.buyToken);
        }

        // TODO: validate prices
        // TODO: make sure spot is close to pairPrice

        uint256 primaryAmountBefore = _tokenBalance(address(UNDERLYING_TOKEN));
        params.primaryTrade.execute(TRADING_MODULE, params.primaryTradeDexId);
        primaryAmount =
            _tokenBalance(address(UNDERLYING_TOKEN)) -
            primaryAmountBefore;

        uint256 secondaryAmountBefore = _tokenBalance(address(SECONDARY_TOKEN));
        params.secondaryTrade.execute(
            TRADING_MODULE,
            params.secondaryTradeDexId
        );
        secondaryAmount =
            _tokenBalance(address(SECONDARY_TOKEN)) -
            secondaryAmountBefore;
    }

    /// @notice Sell reward tokens for BPT and reinvest the proceeds
    /// @param params reward reinvestment params
    function reinvestReward(ReinvestRewardParams calldata params) external {
        // Decode trades in another function to avoid the stack too deep error
        (uint256 primaryAmount, uint256 secondaryAmount) = _executeRewardTrades(
            params.tradeData
        );

        BalancerUtils.joinPool(
            address(BALANCER_VAULT),
            BALANCER_POOL_ID,
            address(UNDERLYING_TOKEN),
            primaryAmount,
            address(SECONDARY_TOKEN),
            secondaryAmount,
            PRIMARY_INDEX,
            params.minBPT
        );

        // TODO: emit event here
    }

    /** Setters */

    /// @notice Updates the oracle window
    function setInitParams(InitParams calldata params)
        external
        onlyNotionalOwner
    {
        require(
            params.oracleWindowInSeconds <=
                IPriceOracle(address(BALANCER_POOL_TOKEN))
                    .getLargestSafeQueryWindow()
        );
        require(params.settlementCoolDownInSeconds <= MAX_SETTLEMENT_COOLDOWN);
        require(
            params.emergencySettlementCoolDownInSeconds <=
                MAX_SETTLEMENT_COOLDOWN
        );
        require(params.balancerOracleWeight <= MAX_ORACLE_WEIGHT);
        require(params.maxBalancerPoolShare <= MAX_BALANCER_POOL_SHARE);
        require(params.settlementSlippageLimit <= MAX_SLIPPAGE_LIMIT);
        require(params.emergencySettlementSlippageLimit <= MAX_SLIPPAGE_LIMIT);

        _initParams(params);

        emit InitParamsUpdated(params);
    }

    /** Public view functions */

    /// @notice Calculates the optimal secondary borrow amount using the
    /// Balancer time-weighted oracle price
    /// @dev Balancer pool needs to be fully initialized with at least 1024 trades
    /// @param primaryAmount primary borrow amount
    /// @return secondaryAmount optimal secondary borrow amount
    function getOptimalSecondaryBorrowAmount(uint256 primaryAmount)
        public
        view
        returns (uint256 secondaryAmount)
    {
        // @audit when you have a large amount of inputs into a method like this, there is a solidity
        // grammar you can use that works like this, it might help the readability for long parameter
        // lists and ensure that arguments don't get accidentally switched around
        //
        // OracleHelper.getOptimalSecondaryBorrowAmount({
        //     pool: address(BALANCER_POOL_TOKEN),
        //     oracleWindowInSeconds: oracleWindowInSeconds,
        //     ...
        // })
        secondaryAmount = OracleHelper.getOptimalSecondaryBorrowAmount(
            address(BALANCER_POOL_TOKEN),
            oracleWindowInSeconds,
            PRIMARY_INDEX,
            PRIMARY_WEIGHT,
            SECONDARY_WEIGHT,
            // @audit there is a bool called UNDERLYING_IS_ETH which can be used here instead.
            address(UNDERLYING_TOKEN) == address(0)
                ? 18
                : UNDERLYING_TOKEN.decimals(),
            // @audit consider putting this into an immutable variable
            address(SECONDARY_TOKEN) == address(0)
                ? 18
                : SECONDARY_TOKEN.decimals(),
            primaryAmount
        );
    }

    /// @dev Gets the total BPT held across the LIQUIDITY GAUGE, VeBal Delegator and the contract itself
    function bptHeld() public view returns (uint256) {
        // @audit this does add pretty significant gas costs, if we can guarantee that two of these
        // are always zero then let's simplify it.
        return (LIQUIDITY_GAUGE.balanceOf(address(this)) +
            BALANCER_POOL_TOKEN.balanceOf(address(this)) +
            VEBAL_DELEGATOR.getTokenBalance(
                address(LIQUIDITY_GAUGE),
                address(this)
            ));
    }

    /// @notice Gets the amount of secondary fCash borrowed
    /// @param account account address
    /// @param maturity maturity timestamp
    /// @param strategyTokenAmount amount of strategy tokens
    /// @return borrowedSecondaryfCashAmount amount of secondary fCash borrowed
    function getSecondaryBorrowedfCashAmount(
        address account,
        uint256 maturity,
        uint256 strategyTokenAmount
    ) public view returns (uint256 borrowedSecondaryfCashAmount) {
        if (SECONDARY_BORROW_CURRENCY_ID > 0) {
            // Return total second currency borrowed if account is the vault address
            if (account == address(this))
                // @audit this needs to be pro-rata as well when the vault partially settles. it
                // should also be rounded up by 1 in the same manner as the per account total
                return
                    NOTIONAL.getSecondaryBorrow(
                        address(this),
                        SECONDARY_BORROW_CURRENCY_ID,
                        maturity
                    );
            uint256 accountTotal = getStrategyTokenBalance(account);
            if (accountTotal > 0) {
                // @audit this math probably deserves a comment, this is the pro-rata amount
                // of secondaryfCash borrowed based for the strategy tokens.
                // @audit we should round up here instead of rounding down so that dust amounts
                // do not accrue in the borrowed secondary fCash amount. so every time we
                // return this value we would want to add 1 unless accountTotal == strategyTokenAmount
                // in which case we return the entire balance.
                borrowedSecondaryfCashAmount =
                    (secondaryAmountfCashBorrowed[account][maturity] *
                        strategyTokenAmount) /
                    accountTotal;
            }
        }
    }

    /// @notice Gets the total number of strategy tokens owned by the given account
    /// @param account account address
    // @audit this is not correct, if the vault holds asset cash then vault shares != strategy tokens,
    // I can expose a method to return the strategy token balance
    function getStrategyTokenBalance(address account)
        public
        view
        returns (uint256)
    {
        VaultAccount memory vaultAccount = NOTIONAL.getVaultAccount(
            account,
            address(this)
        );
        return vaultAccount.vaultShares;
    }

    // @audit would consider renaming this to totalSupplyInMaturity so it does not get confused
    function totalSupply(uint256 maturity) public view returns (uint256) {
        VaultState memory vaultState = NOTIONAL.getVaultState(
            address(this),
            maturity
        );
        return vaultState.totalStrategyTokens;
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal override onlyNotionalOwner {}

    // @audit add a storage gap down here `uint256[100] private __gap;`
}
