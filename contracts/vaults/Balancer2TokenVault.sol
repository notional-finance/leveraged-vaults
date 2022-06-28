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
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
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
        bytes32 balancerPoolId;
        IBoostController boostController;
        ILiquidityGauge liquidityGauge;
        ITradingModule tradingModule;
        uint32 settlementPeriodInSeconds;
    }

    struct InitParams {
        string name;
        uint16 borrowCurrencyId;
        VaultSettings settings;
    }

    struct VaultSettings {
        uint256 maxUnderlyingSurplus;
        uint32 oracleWindowInSeconds;
        uint16 balancerOracleWeight;
        uint16 maxBalancerPoolShare;
        uint16 settlementSlippageLimit;
        uint16 settlementCoolDownInMinutes;
        uint16 postMaturitySettlementSlippageLimit;
        uint16 postMaturitySettlementCoolDownInMinutes;
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

    struct StrategyVaultState {
        /// @notice Total number of strategy tokens across all maturities
        uint256 totalStrategyTokenGlobal;
        uint256 maxUnderlyingSurplus;
        uint32 lastSettlementTimestamp;
        uint32 lastPostMaturitySettlementTimestamp;
        /// @notice Balancer oracle window in seconds
        uint32 oracleWindowInSeconds;
        // @audit marking all of these storage values as public adds a getter for each one, which
        // adds a decent amount of bytecode. consider making them internal and then creating a single
        // getter for all the parameters (or just move them into structs and mark those as public)
        uint16 maxBalancerPoolShare;
        /// @notice Slippage limit for normal settlement
        uint16 settlementSlippageLimit;
        /// @notice Slippage limit for emergency settlement (vault owns too much of the Balancer pool)
        uint16 postMaturitySettlementSlippageLimit;
        uint16 balancerOracleWeight;
        /// @notice Cool down in minutes for normal settlement
        uint16 settlementCoolDownInMinutes;
        /// @notice Cool down in minutes for post maturity settlement
        uint16 postMaturitySettlementCoolDownInMinutes;
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
    event VaultSettingsUpdated(VaultSettings settings);

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
    uint16 internal constant MAX_SETTLEMENT_COOLDOWN_IN_MINUTES = 24 * 60; // 1 day

    /// @notice Precision for all percentages, 1e4 = 100% (i.e. settlementSlippageLimit)
    uint16 internal constant VAULT_PERCENTAGE_PRECISION = 1e4;
    uint16 internal constant BALANCER_POOL_SHARE_BUFFER = 8e3; // 1e4 = 100%, 8e3 = 80%
    /// @notice Internal precision is 1e8
    uint256 internal constant INTERNAL_PRECISION_DIFF = 1e10;
    WETH9 public constant WETH =
        WETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    /** Immutables */
    // @audit similar remark here, each public variable adds an external getter so all of these
    // will result in larger bytecode size, consider just making one method that returns all the
    // immutables
    uint16 public immutable SECONDARY_BORROW_CURRENCY_ID;
    bytes32 public immutable BALANCER_POOL_ID;
    IBalancerPool public immutable BALANCER_POOL_TOKEN;
    ERC20 public immutable SECONDARY_TOKEN;
    IBoostController public immutable BOOST_CONTROLLER;
    ILiquidityGauge public immutable LIQUIDITY_GAUGE;
    IVeBalDelegator public immutable VEBAL_DELEGATOR;
    ERC20 public immutable BAL_TOKEN;
    uint8 public immutable PRIMARY_INDEX;
    uint32 public immutable SETTLEMENT_PERIOD_IN_SECONDS;
    uint256 public immutable PRIMARY_WEIGHT;
    uint256 public immutable SECONDARY_WEIGHT;
    uint256 internal immutable PRIMARY_DECIMALS;
    uint256 internal immutable SECONDARY_DECIMALS;

    /// @notice Keeps track of the possible gauge reward tokens
    mapping(address => bool) private gaugeRewardTokens;

    StrategyVaultState internal vaultState;

    constructor(NotionalProxy notional_, DeploymentParams memory params)
        BaseStrategyVault(notional_, params.tradingModule)
        initializer
    {
        // @audit we should validate in this method that the balancer oracle is enabled otherwise none
        // of the methods will work:
        // https://dev.balancer.fi/references/contracts/apis/pools/weightedpool2tokens#getmiscdata

        SECONDARY_BORROW_CURRENCY_ID = params.secondaryBorrowCurrencyId;
        BALANCER_POOL_ID = params.balancerPoolId;
        BALANCER_POOL_TOKEN = IBalancerPool(
            BalancerUtils.getPoolAddress(params.balancerPoolId)
        );

        // prettier-ignore
        (
            address[] memory tokens,
            /* uint256[] memory balances */,
            /* uint256 lastChangeBlock */
        ) = BalancerUtils.BALANCER_VAULT.getPoolTokens(BALANCER_POOL_ID);

        // Balancer tokens are sorted by address, so we need to figure out
        // the correct index for the primary token
        PRIMARY_INDEX = tokens[0] == _tokenAddress(address(_underlyingToken()))
            ? 0
            : 1;
        uint8 secondaryIndex;
        unchecked {
            secondaryIndex = 1 - PRIMARY_INDEX;
        }

        // Since this is always a 2-token vault, SECONDARY_INDEX = 1-PRIMARY_INDEX
        SECONDARY_TOKEN = SECONDARY_BORROW_CURRENCY_ID > 0
            ? ERC20(_getUnderlyingAddress(SECONDARY_BORROW_CURRENCY_ID))
            : ERC20(tokens[secondaryIndex]);

        // Make sure the deployment parameters are correct
        if (tokens[PRIMARY_INDEX] != _tokenAddress(address(_underlyingToken())))
            revert InvalidPrimaryToken(tokens[PRIMARY_INDEX]);
        if (tokens[secondaryIndex] != _tokenAddress(address(SECONDARY_TOKEN)))
            revert InvalidSecondaryToken(tokens[secondaryIndex]);

        PRIMARY_DECIMALS = address(_underlyingToken()) ==
            TradeHandler.ETH_ADDRESS
            ? 18
            : _underlyingToken().decimals();
        SECONDARY_DECIMALS = address(SECONDARY_TOKEN) ==
            TradeHandler.ETH_ADDRESS
            ? 18
            : SECONDARY_TOKEN.decimals();

        uint256[] memory weights = BALANCER_POOL_TOKEN.getNormalizedWeights();

        PRIMARY_WEIGHT = weights[PRIMARY_INDEX];
        SECONDARY_WEIGHT = weights[secondaryIndex];

        BOOST_CONTROLLER = params.boostController;
        LIQUIDITY_GAUGE = params.liquidityGauge;
        VEBAL_DELEGATOR = IVeBalDelegator(BOOST_CONTROLLER.VEBAL_DELEGATOR());
        BAL_TOKEN = ERC20(
            IBalancerMinter(VEBAL_DELEGATOR.BALANCER_MINTER())
                .getBalancerToken()
        );
        SETTLEMENT_PERIOD_IN_SECONDS = params.settlementPeriodInSeconds;
    }

    function initialize(InitParams calldata params)
        external
        initializer
        onlyNotionalOwner
    {
        __INIT_VAULT(params.name, params.borrowCurrencyId);
        _setVaultSettings(params.settings);
        _initRewardTokenList();
        _approveTokens();
    }

    function _setVaultSettings(VaultSettings memory settings) private {
        uint256 largestQueryWindow = IPriceOracle(address(BALANCER_POOL_TOKEN))
            .getLargestSafeQueryWindow();
        require(largestQueryWindow <= type(uint32).max); /// @dev largestQueryWindow overflow
        require(settings.oracleWindowInSeconds <= uint32(largestQueryWindow));
        require(
            settings.settlementCoolDownInMinutes <=
                MAX_SETTLEMENT_COOLDOWN_IN_MINUTES
        );
        require(
            settings.postMaturitySettlementCoolDownInMinutes <=
                MAX_SETTLEMENT_COOLDOWN_IN_MINUTES
        );
        require(settings.balancerOracleWeight <= VAULT_PERCENTAGE_PRECISION);
        require(settings.maxBalancerPoolShare <= VAULT_PERCENTAGE_PRECISION);
        require(settings.settlementSlippageLimit <= VAULT_PERCENTAGE_PRECISION);
        require(
            settings.postMaturitySettlementSlippageLimit <=
                VAULT_PERCENTAGE_PRECISION
        );

        vaultState.oracleWindowInSeconds = settings.oracleWindowInSeconds;
        vaultState.balancerOracleWeight = settings.balancerOracleWeight;
        vaultState.maxBalancerPoolShare = settings.maxBalancerPoolShare;
        vaultState.maxUnderlyingSurplus = settings.maxUnderlyingSurplus;
        vaultState.settlementSlippageLimit = settings.settlementSlippageLimit;
        vaultState.postMaturitySettlementSlippageLimit = settings
            .postMaturitySettlementSlippageLimit;
        vaultState.settlementCoolDownInMinutes = settings
            .settlementCoolDownInMinutes;
        vaultState.postMaturitySettlementCoolDownInMinutes = settings
            .postMaturitySettlementCoolDownInMinutes;

        emit VaultSettingsUpdated(settings);
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
            address(BalancerUtils.BALANCER_VAULT),
            address(_underlyingToken()),
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
            vaultState.oracleWindowInSeconds,
            PRIMARY_INDEX,
            PRIMARY_WEIGHT,
            SECONDARY_WEIGHT,
            PRIMARY_DECIMALS,
            bptClaim
        );

        if (SECONDARY_BORROW_CURRENCY_ID == 0) return primaryBalance.toInt256();

        // Get the amount of secondary fCash borrowed
        // We directly use the fCash amount instead of converting to underlying
        // as an approximation with built-in interest and haircut parameters
        (
            /* uint256 debtShares */,
            uint256 borrowedSecondaryfCashAmount
        ) = getDebtSharesToRepay(
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
            BALANCER_POOL_ID,
            address(TRADING_MODULE),
            vaultState.oracleWindowInSeconds,
            vaultState.balancerOracleWeight
        );

        // borrowedSecondaryfCashAmount is in internal precision (1e8), raise it to 1e18
        borrowedSecondaryfCashAmount *= INTERNAL_PRECISION_DIFF;

        uint256 secondaryBorrowedDenominatedInPrimary;
        if (PRIMARY_INDEX == 0) {
            secondaryBorrowedDenominatedInPrimary =
                (borrowedSecondaryfCashAmount * BalancerUtils.BALANCER_PRECISION) /
                pairPrice;
        } else {
            secondaryBorrowedDenominatedInPrimary =
                (borrowedSecondaryfCashAmount * pairPrice) /
                BalancerUtils.BALANCER_PRECISION;
        }

        return primaryBalance.toInt256() - secondaryBorrowedDenominatedInPrimary.toInt256();
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
                account,
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
        }

        BalancerUtils.joinPool(
            BALANCER_POOL_ID,
            address(_underlyingToken()),
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
        if (vaultState.totalStrategyTokenGlobal == 0) {
            strategyTokensMinted = bptAmount;
        } else {
            // @audit the calculation for the next three variables can be made into a helper method since
            // it is used more than once
            uint256 totalBPTHeld = bptHeld();
            uint256 totalStrategyTokenSupplyInMaturity = totalSupplyInMaturity(
                maturity
            );
            uint256 bptHeldInMaturity = (totalBPTHeld *
                totalStrategyTokenSupplyInMaturity) /
                vaultState.totalStrategyTokenGlobal;
            strategyTokensMinted =
                (totalStrategyTokenSupplyInMaturity * bptAmount) /
                // @audit leave a comment on this math here, but looks correct
                (bptHeldInMaturity - bptAmount);
        }

        // Update global supply count
        vaultState.totalStrategyTokenGlobal += strategyTokensMinted;
    }

    // @audit for readability, it might be nice to group some of these methods closer to where they are
    // called by other functions (this would be better to group near convertStrategyToUnderlying)
    /// @notice Converts strategy tokens to BPT
    function convertStrategyTokensToBPTClaim(
        uint256 strategyTokenAmount,
        uint256 maturity
    ) public view returns (uint256 bptClaim) {
        // @audit-ok math looks good
        if (vaultState.totalStrategyTokenGlobal == 0)
            return strategyTokenAmount;

        // @audit use a helper method for these next three calculations
        uint256 totalBPTHeld = bptHeld();
        uint256 totalStrategyTokenSupplyInMaturity = totalSupplyInMaturity(
            maturity
        );
        uint256 bptHeldInMaturity = (totalBPTHeld *
            totalStrategyTokenSupplyInMaturity) /
            vaultState.totalStrategyTokenGlobal;
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
        if (vaultState.totalStrategyTokenGlobal == 0) return bptClaim;

        // @audit use a helper method for these next three calculations
        uint256 totalBPTHeld = bptHeld();
        uint256 totalStrategyTokenSupplyInMaturity = totalSupplyInMaturity(
            maturity
        );
        uint256 bptHeldInMaturity = (totalBPTHeld *
            totalStrategyTokenSupplyInMaturity) /
            vaultState.totalStrategyTokenGlobal;
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
    ) internal returns (uint256) {
        RedeemParams memory params = abi.decode(data, (RedeemParams));

        uint256 primaryBalance = _underlyingToken().balanceOf(address(this));

        BalancerUtils.exitPool(
            BALANCER_POOL_ID,
            address(_underlyingToken()),
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
                account,
                SECONDARY_BORROW_CURRENCY_ID,
                maturity,
                borrowedSecondaryfCashAmount,
                params.secondarySlippageLimit,
                params.callbackData
            );
        }

        return _underlyingToken().balanceOf(address(this)) - primaryBalance;
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
                address(_underlyingToken()),
                address(SECONDARY_TOKEN),
                underlyingRequired - secondaryBalance, // @audit can mark unchecked
                TradeHandler.getLimitAmount(
                    address(TRADING_MODULE),
                    uint16(TradeType.EXACT_OUT_SINGLE),
                    address(_underlyingToken()),
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
        if (SECONDARY_BORROW_CURRENCY_ID == 1) {
            // @audit use a named constant for 1
            payable(address(NOTIONAL)).transfer(underlyingRequired);
        } else {
            SECONDARY_TOKEN.safeTransfer(address(NOTIONAL), underlyingRequired);
        }

        if (secondaryBalance > 0) {
            // Sell residual secondary balance
            trade = Trade(
                TradeType.EXACT_IN_SINGLE,
                address(SECONDARY_TOKEN),
                address(_underlyingToken()),
                secondaryBalance,
                TradeHandler.getLimitAmount(
                    address(TRADING_MODULE),
                    uint16(TradeType.EXACT_OUT_SINGLE),
                    address(SECONDARY_TOKEN),
                    address(_underlyingToken()),
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
        uint256 bptClaim = convertStrategyTokensToBPTClaim(
            strategyTokens,
            maturity
        );

        if (bptClaim > 0) {
            // Withdraw gauge token from VeBALDelegator
            BOOST_CONTROLLER.withdrawToken(address(LIQUIDITY_GAUGE), bptClaim);

            // Unstake BPT
            LIQUIDITY_GAUGE.withdraw(bptClaim, false);

            // Calculate the amount of debt shares to repay
            (
                uint256 debtShares, 
                uint256 borrowedSecondaryfCashAmount
            ) = getDebtSharesToRepay(account, maturity, strategyTokens);

            // Token transfers are handled in the base strategy
            tokensFromRedeem = _exitPool(
                account,
                bptClaim,
                maturity,
                debtShares,
                data
            );

            // Update global strategy token balance
            vaultState.totalStrategyTokenGlobal -= bptClaim;
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
            _validateSettlementCoolDown(
                vaultState.lastPostMaturitySettlementTimestamp,
                vaultState.postMaturitySettlementCoolDownInMinutes
            );
            _validateSettlementSlippage(
                data,
                vaultState.postMaturitySettlementSlippageLimit
            );
        } else {
            if (maturity - SETTLEMENT_PERIOD_IN_SECONDS <= block.timestamp) {
                // In settlement window
                _validateSettlementCoolDown(
                    vaultState.lastSettlementTimestamp,
                    vaultState.settlementCoolDownInMinutes
                );
                _validateSettlementSlippage(
                    data,
                    vaultState.settlementSlippageLimit
                );
            } else {
                // Not in settlement window, check if BPT held is greater than maxBalancerPoolShare * total BPT supply
                // @audit this variable should be emergencyBPTWithdrawThreshold
                uint256 bptTotalSupply = BALANCER_POOL_TOKEN.totalSupply();
                uint256 maxBPTAmount = (bptTotalSupply *
                    vaultState.maxBalancerPoolShare) /
                    VAULT_PERCENTAGE_PRECISION;
                uint256 _bptHeld = bptHeld();
                // @audit this error message should be InvalidEmergencySettlement()
                if (_bptHeld <= maxBPTAmount) revert NotInSettlementWindow();

                // desiredPoolShare = maxPoolShare * bufferPercentage
                uint256 desiredPoolShare = (vaultState.maxBalancerPoolShare *
                    BALANCER_POOL_SHARE_BUFFER) / VAULT_PERCENTAGE_PRECISION;
                uint256 desiredBPTAmount = (bptTotalSupply * desiredPoolShare) /
                    VAULT_PERCENTAGE_PRECISION;
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
            int256(vaultState.maxUnderlyingSurplus)
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
            _tokenAddress(address(_underlyingToken()))
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

        uint256 primaryAmountBefore = _tokenBalance(
            address(_underlyingToken())
        );
        params.primaryTrade.execute(TRADING_MODULE, params.primaryTradeDexId);
        primaryAmount =
            _tokenBalance(address(_underlyingToken())) -
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
            BALANCER_POOL_ID,
            address(_underlyingToken()),
            primaryAmount,
            address(SECONDARY_TOKEN),
            secondaryAmount,
            PRIMARY_INDEX,
            params.minBPT
        );

        // TODO: emit event here
    }

    /** Setters */

    /// @notice Updates the vault settings
    /// @param settings vault settings
    function setVaultSettings(VaultSettings calldata settings)
        external
        onlyNotionalOwner
    {
        _setVaultSettings(settings);
    }

    /** Public view functions */

    function getVaultState() external view returns (StrategyVaultState memory) {
        return vaultState;
    }

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
            vaultState.oracleWindowInSeconds,
            PRIMARY_INDEX,
            PRIMARY_WEIGHT,
            SECONDARY_WEIGHT,
            PRIMARY_DECIMALS,
            SECONDARY_DECIMALS,
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

    /// @notice Gets the amount of debt shares needed to pay off the secondary debt
    /// @param account account address
    /// @param maturity maturity timestamp
    /// @param strategyTokenAmount amount of strategy tokens
    /// @return debtSharesToRepay amount of secondary debt shares
    /// @return borrowedSecondaryfCashAmount amount of secondary fCash borrowed
    function getDebtSharesToRepay(
        address account,
        uint256 maturity,
        uint256 strategyTokenAmount
    )
        public
        view
        returns (
            uint256 debtSharesToRepay,
            uint256 borrowedSecondaryfCashAmount
        )
    {
        if (SECONDARY_BORROW_CURRENCY_ID > 0) {
            // prettier-ignore
            (
                uint256 totalfCashBorrowed,
                uint256 totalAccountDebtShares
            ) = NOTIONAL.getSecondaryBorrow(
                address(this),
                SECONDARY_BORROW_CURRENCY_ID,
                maturity
            );

            uint256 _totalSupplyInMaturity = totalSupplyInMaturity(maturity);

            if (account == address(this)) {
                debtSharesToRepay =
                    (totalAccountDebtShares * strategyTokenAmount) /
                    _totalSupplyInMaturity;
                borrowedSecondaryfCashAmount =
                    (totalfCashBorrowed * strategyTokenAmount) /
                    _totalSupplyInMaturity;
            } else {
                // prettier-ignore
                (
                    /* uint256 debtSharesMaturity */,
                    uint256[2] memory accountDebtShares,
                    uint256 accountStrategyTokens
                ) = NOTIONAL.getVaultAccountDebtShares(account, address(this));

                debtSharesToRepay =
                    (accountDebtShares[0] * strategyTokenAmount) /
                    accountStrategyTokens;
                borrowedSecondaryfCashAmount =
                    (debtSharesToRepay * totalfCashBorrowed) /
                    totalAccountDebtShares;
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

    function totalSupplyInMaturity(uint256 maturity)
        public
        view
        returns (uint256)
    {
        VaultState memory state = NOTIONAL.getVaultState(
            address(this),
            maturity
        );
        return state.totalStrategyTokens;
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal override onlyNotionalOwner {}

    // @audit add a storage gap down here `uint256[100] private __gap;`
}
