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
    using SafeCast for int256;

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
        StrategyVaultSettings settings;
    }

    struct StrategyVaultSettings {
        uint256 maxUnderlyingSurplus;
        /// @notice Balancer oracle window in seconds
        uint32 oracleWindowInSeconds;
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

    struct DepositParams {
        uint256 minBPT;
        uint256 secondaryfCashAmount;
        uint32 secondarySlippageLimit;
    }

    struct RedeemParams {
        uint32 secondarySlippageLimit;
        uint256 minPrimary;
        uint256 minSecondary;
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
        uint32 lastSettlementTimestamp;
        uint32 lastPostMaturitySettlementTimestamp;
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
    /// @notice settleVault called when there is no debt
    error SettlementNotRequired();
    error InvalidSecondaryBorrow(
        uint256 borrowedSecondaryAmount,
        uint256 optimalSecondaryAmount,
        uint256 secondaryfCashAmount
    );

    /** Events */
    event StrategyVaultSettingsUpdated(StrategyVaultSettings settings);
    event EmergencyVaultSettlement(
        uint256 maturity,
        uint256 bptToSettle,
        uint256 redeempStrategyTokenAmount
    );
    event NormalVaultSettlement(
        uint256 maturity,
        uint256 bptToSettle,
        uint256 redeempStrategyTokenAmount
    );

    /** Constants */

    uint256 internal constant SECONDARY_BORROW_UPPER_LIMIT = 105;
    uint256 internal constant SECONDARY_BORROW_LOWER_LIMIT = 95;
    uint16 internal constant MAX_SETTLEMENT_COOLDOWN_IN_MINUTES = 24 * 60; // 1 day

    /// @notice Precision for all percentages, 1e4 = 100% (i.e. settlementSlippageLimit)
    uint16 internal constant VAULT_PERCENTAGE_PRECISION = 1e4;
    uint16 internal constant BALANCER_POOL_SHARE_BUFFER = 8e3; // 1e4 = 100%, 8e3 = 80%
    /// @notice Difference between 1e18 and internal precision
    uint256 internal constant INTERNAL_PRECISION_DIFF = 1e10;
    uint256 internal constant INTERNAL_PRECISION = 1e8;

    /** Immutables */
    // @audit similar remark here, each public variable adds an external getter so all of these
    // will result in larger bytecode size, consider just making one method that returns all the
    // immutables
    uint16 internal immutable SECONDARY_BORROW_CURRENCY_ID;
    bytes32 internal immutable BALANCER_POOL_ID;
    IBalancerPool internal immutable BALANCER_POOL_TOKEN;
    ERC20 internal immutable SECONDARY_TOKEN;
    IBoostController internal immutable BOOST_CONTROLLER;
    ILiquidityGauge internal immutable LIQUIDITY_GAUGE;
    IVeBalDelegator internal immutable VEBAL_DELEGATOR;
    ERC20 internal immutable BAL_TOKEN;
    uint8 internal immutable PRIMARY_INDEX;
    uint32 internal immutable SETTLEMENT_PERIOD_IN_SECONDS;
    uint256 internal immutable PRIMARY_WEIGHT;
    uint256 internal immutable SECONDARY_WEIGHT;
    uint8 internal immutable PRIMARY_DECIMALS;
    uint8 internal immutable SECONDARY_DECIMALS;

    /// @notice Keeps track of the possible gauge reward tokens
    mapping(address => bool) private gaugeRewardTokens;

    StrategyVaultSettings internal vaultSettings;

    StrategyVaultState internal vaultState;

    /// @notice Keeps track of the primary settlement balance maturity => balance
    mapping(uint256 => uint256) primarySettlementBalance;

    /// @notice Keeps track of the secondary settlement balance maturity => balance
    mapping(uint256 => uint256) secondarySettlementBalance;

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

        uint256 primaryDecimals = address(_underlyingToken()) ==
            TradeHandler.ETH_ADDRESS
            ? 18
            : _underlyingToken().decimals();
        require(primaryDecimals <= type(uint8).max);
        PRIMARY_DECIMALS = uint8(primaryDecimals);

        uint256 secondaryDecimals = address(SECONDARY_TOKEN) ==
            TradeHandler.ETH_ADDRESS
            ? 18
            : SECONDARY_TOKEN.decimals();
        require(primaryDecimals <= type(uint8).max);
        SECONDARY_DECIMALS = uint8(secondaryDecimals);

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

    function _setVaultSettings(StrategyVaultSettings memory settings) private {
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

        vaultSettings.oracleWindowInSeconds = settings.oracleWindowInSeconds;
        vaultSettings.balancerOracleWeight = settings.balancerOracleWeight;
        vaultSettings.maxBalancerPoolShare = settings.maxBalancerPoolShare;
        vaultSettings.maxUnderlyingSurplus = settings.maxUnderlyingSurplus;
        vaultSettings.settlementSlippageLimit = settings
            .settlementSlippageLimit;
        vaultSettings.postMaturitySettlementSlippageLimit = settings
            .postMaturitySettlementSlippageLimit;
        vaultSettings.settlementCoolDownInMinutes = settings
            .settlementCoolDownInMinutes;
        vaultSettings.postMaturitySettlementCoolDownInMinutes = settings
            .postMaturitySettlementCoolDownInMinutes;

        emit StrategyVaultSettingsUpdated(settings);
    }

    /// @notice Special handling for ETH because UNDERLYING_TOKEN == address(0)
    /// and Balancer uses WETH
    function _tokenAddress(address token) private view returns (address) {
        // @audit consider using a constant for address(0) here like ETH_ADDRESS or something
        return
            token == address(0) ? address(BalancerUtils.WETH) : address(token);
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

        (uint256 primaryBalance, uint256 pairPrice) = OracleHelper
            .getTimeWeightedPrimaryBalance(
                address(BALANCER_POOL_TOKEN),
                vaultSettings.oracleWindowInSeconds,
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
        // prettier-ignore
        (
            /* uint256 debtShares */,
            uint256 borrowedSecondaryfCashAmount
        ) = getDebtSharesToRepay(account, maturity, strategyTokenAmount);

        // borrowedSecondaryfCashAmount is in internal precision (1e8), raise it to 1e18
        borrowedSecondaryfCashAmount *= INTERNAL_PRECISION_DIFF;

        uint256 secondaryBorrowedDenominatedInPrimary;
        if (PRIMARY_INDEX == 0) {
            secondaryBorrowedDenominatedInPrimary =
                (borrowedSecondaryfCashAmount *
                    BalancerUtils.BALANCER_PRECISION) /
                pairPrice;
        } else {
            secondaryBorrowedDenominatedInPrimary =
                (borrowedSecondaryfCashAmount * pairPrice) /
                BalancerUtils.BALANCER_PRECISION;
        }

        // Convert to primary precision
        secondaryBorrowedDenominatedInPrimary =
            (secondaryBorrowedDenominatedInPrimary * (10**PRIMARY_DECIMALS)) /
            BalancerUtils.BALANCER_PRECISION;

        return
            primaryBalance.toInt256() -
            secondaryBorrowedDenominatedInPrimary.toInt256();
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
            // @audit when you have a large amount of inputs into a method like this, there is a solidity
            // grammar you can use that works like this, it might help the readability for long parameter
            // lists and ensure that arguments don't get accidentally switched around
            //
            // OracleHelper.getOptimalSecondaryBorrowAmount({
            //     pool: address(BALANCER_POOL_TOKEN),
            //     oracleWindowInSeconds: oracleWindowInSeconds,
            //     ...
            // })
            uint256 optimalSecondaryAmount = OracleHelper
                .getOptimalSecondaryBorrowAmount(
                    address(BALANCER_POOL_TOKEN),
                    vaultSettings.oracleWindowInSeconds,
                    PRIMARY_INDEX,
                    PRIMARY_WEIGHT,
                    SECONDARY_WEIGHT,
                    PRIMARY_DECIMALS,
                    SECONDARY_DECIMALS,
                    deposit
                );

            // Borrow secondary currency from Notional (tokens will be transferred to this contract)
            {
                uint256[2] memory fCashToBorrow;
                uint32[2] memory maxBorrowRate;
                uint32[2] memory minRollLendRate;
                fCashToBorrow[0] = params.secondaryfCashAmount;
                maxBorrowRate[0] = params.secondarySlippageLimit;
                uint256[2] memory tokensTransferred = NOTIONAL.borrowSecondaryCurrencyToVault(
                    account,
                    maturity,
                    fCashToBorrow,
                    maxBorrowRate,
                    minRollLendRate
                );

                borrowedSecondaryAmount = tokensTransferred[0];
            }

            // Require the secondary borrow amount to be within SECONDARY_BORROW_LOWER_LIMIT percent
            // of the optimal amount
            if (
                // @audit rearrange these so that the inequalities are always <= for clarity.
                borrowedSecondaryAmount <
                ((optimalSecondaryAmount * (SECONDARY_BORROW_LOWER_LIMIT)) /
                    100) ||
                borrowedSecondaryAmount >
                (optimalSecondaryAmount * (SECONDARY_BORROW_UPPER_LIMIT)) / 100
            ) {
                revert InvalidSecondaryBorrow(
                    borrowedSecondaryAmount,
                    optimalSecondaryAmount,
                    params.secondaryfCashAmount
                );
            }
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
        // TODO: revert if in settlement window

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
            //prettier-ignore
            (
                uint256 bptHeldInMaturity,
                uint256 totalStrategyTokenSupplyInMaturity
            ) = _getBPTHeldInMaturity(maturity);

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

        //prettier-ignore
        (
            uint256 bptHeldInMaturity,
            uint256 totalStrategyTokenSupplyInMaturity
        ) = _getBPTHeldInMaturity(maturity);

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

        //prettier-ignore
        (
            uint256 bptHeldInMaturity,
            uint256 totalStrategyTokenSupplyInMaturity
        ) = _getBPTHeldInMaturity(maturity);

        strategyTokenAmount =
            (totalStrategyTokenSupplyInMaturity * bptClaim) /
            bptHeldInMaturity;
    }

    function _getBPTHeldInMaturity(uint256 maturity)
        private
        view
        returns (
            uint256 bptHeldInMaturity,
            uint256 totalStrategyTokenSupplyInMaturity
        )
    {
        uint256 totalBPTHeld = _bptHeld();
        totalStrategyTokenSupplyInMaturity = _totalSupplyInMaturity(maturity);
        bptHeldInMaturity =
            (totalBPTHeld * totalStrategyTokenSupplyInMaturity) /
            vaultState.totalStrategyTokenGlobal;
    }

    function _exitPool(
        address account,
        uint256 bptExitAmount,
        uint256 maturity,
        uint256 minPrimary,
        uint256 minSecondary
    ) internal returns (uint256 primaryBalance, uint256 secondaryBalance) {
        uint256 primaryBalanceBefore = _tokenBalance(
            address(_underlyingToken())
        );
        uint256 secondaryBalanceBefore = _tokenBalance(
            address(SECONDARY_TOKEN)
        );

        BalancerUtils.exitPoolExactBPTIn(
            BALANCER_POOL_ID,
            address(_underlyingToken()),
            minPrimary,
            address(SECONDARY_TOKEN),
            minSecondary,
            PRIMARY_INDEX,
            bptExitAmount,
            true // redeem WETH to ETH
        );

        primaryBalance =
            _tokenBalance(address(_underlyingToken())) -
            primaryBalanceBefore;
        secondaryBalance =
            _tokenBalance(address(SECONDARY_TOKEN)) -
            secondaryBalanceBefore;
    }

    /// @notice Callback function for repaying secondary debt
    function _repaySecondaryBorrowCallback(
        address /* secondaryToken */,
        uint256 underlyingRequired,
        bytes calldata data
    ) internal override returns (bytes memory returnData) {
        require(SECONDARY_BORROW_CURRENCY_ID > 0); /// @dev invalid secondary currency

        // secondaryBalance = secondary token amount from BPT redemption
        // prettier-ignore
        (
            RepaySecondaryCallbackParams memory params,
            uint256 secondaryBalance
        ) = abi.decode(data, (RepaySecondaryCallbackParams, uint256));

        Trade memory trade;
        int256 primaryBalanceBefore = _tokenBalance(address(_underlyingToken()))
            .toInt256();

        if (secondaryBalance >= underlyingRequired) {
            // We already have enough to repay secondary debt
            // Update secondary balance before token transfer
            unchecked {
                secondaryBalance -= underlyingRequired;
            }
        } else {
            uint256 secondaryShortfall;
            // Not enough secondary balance to repay secondary debt,
            // sell some primary currency to cover the shortfall
            unchecked {
                secondaryShortfall = underlyingRequired - secondaryBalance;
            }

            trade = Trade(
                TradeType.EXACT_OUT_SINGLE,
                address(_underlyingToken()),
                address(SECONDARY_TOKEN),
                secondaryShortfall,
                TradeHandler.getLimitAmount(
                    address(TRADING_MODULE),
                    uint16(TradeType.EXACT_OUT_SINGLE),
                    address(_underlyingToken()),
                    address(SECONDARY_TOKEN),
                    secondaryShortfall,
                    params.slippageLimit
                ),
                params.deadline, // @audit deadline should always be block.timestamp
                params.exchangeData
            );

            trade.execute(TRADING_MODULE, params.dexId);

            // Setting secondaryBalance to 0 here because it should be
            // equal to underlyingRequired after the trade (validated by the TradingModule)
            // and 0 after the repayment token transfer.
            // Updating it here before the transfer
            secondaryBalance = 0;
        }

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

        int256 primaryBalanceAfter = _tokenBalance(address(_underlyingToken()))
            .toInt256();

        // Return primaryBalanceDiff
        // If primaryBalanceAfter > primaryBalanceBefore, residual secondary currency was
        // sold for primary currency
        // If primaryBalanceBefore > primaryBalanceAfter, primary currency was sold
        // for secondary currency to cover the shortfall
        return abi.encode(primaryBalanceAfter - primaryBalanceBefore);
    }

    function _redeemFromNotional(
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 underlyingAmount) {
        // TODO: revert if in settlement window

        uint256 bptClaim = convertStrategyTokensToBPTClaim(
            strategyTokens,
            maturity
        );

        if (bptClaim > 0) {
            RedeemParams memory params = abi.decode(data, (RedeemParams));

            // Withdraw gauge token from VeBALDelegator
            BOOST_CONTROLLER.withdrawToken(address(LIQUIDITY_GAUGE), bptClaim);

            // Unstake BPT
            LIQUIDITY_GAUGE.withdraw(bptClaim, false);

            // prettier-ignore
            (
                uint256 primaryBalance, 
                uint256 secondaryBalance
            ) = _exitPool(
                account,
                bptClaim,
                maturity,
                params.minPrimary,
                params.minSecondary
            );

            // prettier-ignore
            (
                uint256 debtSharesToRepay, 
                /* uint256 borrowedSecondaryfCashAmount */
            ) = getDebtSharesToRepay(account, maturity, strategyTokens);

            if (debtSharesToRepay > 0) {
                NOTIONAL.repaySecondaryCurrencyFromVault(
                    account,
                    SECONDARY_BORROW_CURRENCY_ID,
                    maturity,
                    debtSharesToRepay,
                    params.secondarySlippageLimit,
                    abi.encode(params.callbackData, secondaryBalance)
                );
            }

            // It's sufficient to return the underlying amount,
            // token transfers are handled in the base strategy
            underlyingAmount = primaryBalance;

            // Update global strategy token balance
            vaultState.totalStrategyTokenGlobal -= strategyTokens;
        }
    }

    function _validateSettlementSlippage(
        bytes memory data,
        uint32 slippageLimit
    ) private pure {
        RedeemParams memory params = abi.decode(data, (RedeemParams));
        RepaySecondaryCallbackParams memory callbackData = abi.decode(
            params.callbackData,
            (RepaySecondaryCallbackParams)
        );
        if (callbackData.slippageLimit > slippageLimit) {
            revert SlippageTooHigh(callbackData.slippageLimit, slippageLimit);
        }
    }

    function _validateSettlementCoolDown(uint32 lastTimestamp, uint32 coolDown)
        private view
    {
        if (lastTimestamp + coolDown > block.timestamp)
            revert InSettlementCoolDown(lastTimestamp, coolDown);
    }

    function settleVault(
        uint256 maturity,
        uint256 bptToSettle,
        bytes calldata data
    ) external {
        // @audit would this code be cleaner and safer if we just split it into three different external methods?
        if (maturity <= block.timestamp) {
            // Vault has reached maturity. settleVault becomes authenticated in this case
            if (msg.sender != NOTIONAL.owner())
                revert NotionalOwnerRequired(msg.sender);
            _validateSettlementCoolDown(
                vaultState.lastPostMaturitySettlementTimestamp,
                vaultSettings.postMaturitySettlementCoolDownInMinutes
            );
            _validateSettlementSlippage(
                data,
                vaultSettings.postMaturitySettlementSlippageLimit
            );

            _normalSettlement(bptToSettle, maturity, data);
        } else {
            if (maturity - SETTLEMENT_PERIOD_IN_SECONDS <= block.timestamp) {
                // In settlement window
                _validateSettlementCoolDown(
                    vaultState.lastSettlementTimestamp,
                    vaultSettings.settlementCoolDownInMinutes
                );
                _validateSettlementSlippage(
                    data,
                    vaultSettings.settlementSlippageLimit
                );

                _normalSettlement(bptToSettle, maturity, data);
            } else {
                // Not in settlement window, check if BPT held is greater than maxBalancerPoolShare * total BPT supply
                // @audit this variable should be emergencyBPTWithdrawThreshold
                uint256 bptTotalSupply = BALANCER_POOL_TOKEN.totalSupply();
                uint256 maxBPTAmount = (bptTotalSupply *
                    vaultSettings.maxBalancerPoolShare) /
                    VAULT_PERCENTAGE_PRECISION;
                uint256 totalBPTHeld = _bptHeld();
                // @audit this error message should be InvalidEmergencySettlement()
                if (totalBPTHeld <= maxBPTAmount)
                    revert NotInSettlementWindow();

                // desiredPoolShare = maxPoolShare * bufferPercentage
                uint256 desiredPoolShare = (vaultSettings.maxBalancerPoolShare *
                    BALANCER_POOL_SHARE_BUFFER) / VAULT_PERCENTAGE_PRECISION;
                uint256 desiredBPTAmount = (bptTotalSupply * desiredPoolShare) /
                    VAULT_PERCENTAGE_PRECISION;

                _emergencySettlement(
                    totalBPTHeld - desiredBPTAmount,
                    maturity,
                    data
                );
            }
        }
    }

    function _normalSettlement(
        uint256 bptToSettle,
        uint256 maturity,
        bytes memory data
    ) private {
        uint256 redeemStrategyTokenAmount = convertBPTClaimToStrategyTokens(
            bptToSettle,
            maturity
        );
        // @audit you decode this twice (already decoded in validateSlippageParams), maybe just
        // pass RedeemParams down
        RedeemParams memory params = abi.decode(data, (RedeemParams));

        // Redeem BPT
        (uint256 primaryBalance, uint256 secondaryBalance) = _exitPool(
            address(this),
            bptToSettle,
            maturity,
            // @audit We need to validate that the spot price is within some band of the
            // oracle price before we exit here, we cannot trust that these minPrimary / minSecondary
            // values are correctly specified
            params.minPrimary,
            params.minSecondary
        );

        uint256 totalPrimary = primarySettlementBalance[maturity] +
            primaryBalance;
        uint256 totalSecondary = secondarySettlementBalance[maturity] +
            secondaryBalance;

        // Get primary and secondary debt amounts from Notional
        // prettier-ignore
        (
            /* int256 assetCashRequiredToSettle */,
            int256 underlyingCashRequiredToSettle
        ) = NOTIONAL.getCashRequiredToSettle(address(this), maturity);

        // prettier-ignore
        (
            uint256 debtSharesToRepay,
            uint256 borrowedSecondaryfCashAmount
        ) = getDebtSharesToRepay(address(this), maturity, redeemStrategyTokenAmount);

        // Convert fCash to secondary currency precision
        borrowedSecondaryfCashAmount =
            (borrowedSecondaryfCashAmount * (10**SECONDARY_DECIMALS)) /
            INTERNAL_PRECISION;

        // If underlyingCashRequiredToSettle is 0 (no debt) or negative (surplus cash)
        // and borrowedSecondaryfCashAmount is also 0, no settlement is required
        if (
            underlyingCashRequiredToSettle <= 0 &&
            borrowedSecondaryfCashAmount == 0
        ) {
            // @audit i think we can move this check higher in the method, we can fail earlier
            revert SettlementNotRequired(); /// @dev no debt
        }

        // Let the token balances accumulate in this contract if we don't have
        // enough to pay off either side
        if (
            totalPrimary.toInt256() < underlyingCashRequiredToSettle &&
            totalSecondary < borrowedSecondaryfCashAmount
        ) {
            primarySettlementBalance[maturity] = totalPrimary;
            secondarySettlementBalance[maturity] = totalSecondary;
            return;
        }
        // @audit for readability i think this should be an if / else condition, the return
        // statement is not easy to see

        // If we get to this point, we have enough to pay off either the primary
        // side or the secondary side
        if (
            _executeSettlement(
                totalPrimary,
                maturity,
                debtSharesToRepay,
                underlyingCashRequiredToSettle,
                params.secondarySlippageLimit,
                abi.encode(params.callbackData, secondaryBalance)
            )
        ) {
            NOTIONAL.settleVault(address(this), maturity);

            emit NormalVaultSettlement(
                maturity,
                bptToSettle,
                redeemStrategyTokenAmount
            );
        }
    }

    function _executeSettlement(
        uint256 primaryAmount,
        uint256 maturity,
        uint256 debtSharesToRepay,
        int256 underlyingCashRequiredToSettle,
        uint32 secondarySlippageLimit,
        bytes memory callbackData
    ) private returns (bool) {
        // We repay the secondary debt first
        // (trading is handled in repaySecondaryCurrencyFromVault)
        if (debtSharesToRepay > 0) {
            bytes memory returnData = NOTIONAL.repaySecondaryCurrencyFromVault(
                address(this),
                SECONDARY_BORROW_CURRENCY_ID,
                maturity,
                debtSharesToRepay,
                secondarySlippageLimit,
                callbackData
            );

            // positive = primaryAmount increased (residual secondary => primary)
            // negative = primaryAmount decreased (primary => secondary shortfall)
            int256 primaryAmountDiff = abi.decode(returnData, (int256));

            // address(this) should have 0 secondary balance at this point
            secondarySettlementBalance[maturity] = 0;
            // @audit there is an edge condition here where the repay secondary currency from
            // vault sells more primary than is available in the current maturity. I'm not sure
            // how this can actually occur in practice but something to be mindful of.
            primaryAmount = (primaryAmount.toInt256() + primaryAmountDiff)
                .toUint256();
        }

        // Secondary debt is paid off, handle potential primary payoff
        // @audit there's a lot of flipping between uint and int here, maybe just convert primaryAmount to
        // int up front and then leave it that way?
        int256 primaryAmountAvailable = primaryAmount.toInt256();
        if (primaryAmountAvailable < underlyingCashRequiredToSettle) {
            // If primaryAmountAvailable < underlyingCashRequiredToSettle,
            // we need to redeem more BPT. So, we update primarySettlementBalance[maturity]
            // and wait for the next settlement call.
            primarySettlementBalance[maturity] = primaryAmount;
            return false;
        }
        // @audit make this an else statement

        // Calculate the amount of surplus cash after primary repayment
        // If underlyingCashRequiredToSettle < 0, that means there is excess
        // cash in the system. We add it to the surplus with the subtraction.
        int256 surplus = primaryAmountAvailable -
            underlyingCashRequiredToSettle;

        // Make sure we are not settling too much because we want
        // to preserve as much BPT as possible
        if (surplus > vaultSettings.maxUnderlyingSurplus.toInt256()) {
            revert RedeemingTooMuch(
                primaryAmountAvailable,
                underlyingCashRequiredToSettle
            );
        }

        // Transfer everything to Notional including the surplus
        _repayPrimaryBorrow(address(NOTIONAL), 0, primaryAmount);

        // address(this) should have 0 primary currency at this point
        primarySettlementBalance[maturity] = 0;

        return true;
    }

    function _emergencySettlement(
        uint256 bptToSettle,
        uint256 maturity,
        bytes calldata data
    ) private {
        uint256 redeemStrategyTokenAmount = convertBPTClaimToStrategyTokens(
            bptToSettle,
            maturity
        );

        int256 expectedUnderlyingRedeemed = convertStrategyToUnderlying(
            address(this),
            redeemStrategyTokenAmount,
            maturity
        );

        // prettier-ignore
        (
            /* int256 assetCashRequiredToSettle */,
            int256 underlyingCashRequiredToSettle
        ) = NOTIONAL.getCashRequiredToSettle(address(this), maturity);

        // @audit i don't see where you actually exit the pool in this method

        // A negative surplus here means the account is insolvent
        // (either expectedUnderlyingRedeemed is negative or
        // expectedUnderlyingRedeemed is less than underlyingCashRequiredToSettle).
        // If that's the case, we should just redeem and repay as much as possible (surplus
        // check is ignored because maxUnderlyingSurplus can never be negative).
        // If underlyingCashRequiredToSettle is negative, that means we already have surplus cash
        // on the Notional side, it will just make the surplus larger and potentially
        // cause it to go over maxUnderlyingSurplus.
        int256 surplus = expectedUnderlyingRedeemed -
            underlyingCashRequiredToSettle;

        // Make sure we not redeeming too much to underlying
        // This allows BPT to be accrued as the profit token.
        if (surplus > vaultSettings.maxUnderlyingSurplus.toInt256()) {
            revert RedeemingTooMuch(
                expectedUnderlyingRedeemed,
                underlyingCashRequiredToSettle
            );
        }

        // prettier-ignore
        (
            int256 assetCashPostRedemption,
            /* int256 underlyingCashPostRedemption */
        ) = NOTIONAL.redeemStrategyTokensToCash(maturity, redeemStrategyTokenAmount, data);

        // Mark the vault as settled
        if (assetCashPostRedemption < 0 && maturity <= block.timestamp) {
            // @audit I would remove this call, emergency settlement should only occur pre-maturity
            // before the settlement period. otherwise we would just go via the normal path.
            NOTIONAL.settleVault(address(this), maturity);
        }

        emit EmergencyVaultSettlement(
            maturity,
            bptToSettle,
            redeemStrategyTokenAmount
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
        if (
            !gaugeRewardTokens[params.primaryTrade.sellToken] &&
            params.primaryTrade.sellToken != address(BAL_TOKEN)
        ) {
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
    function setVaultSettings(StrategyVaultSettings calldata settings)
        external
        onlyNotionalOwner
    {
        _setVaultSettings(settings);
    }

    /** Public view functions */

    function getVaultState() external view returns (StrategyVaultState memory) {
        return vaultState;
    }

    function getVaultSettings()
        external
        view
        returns (StrategyVaultSettings memory)
    {
        return vaultSettings;
    }

    /// @dev Gets the total BPT held across the LIQUIDITY GAUGE, VeBal Delegator and the contract itself
    function _bptHeld() private view returns (uint256) {
        return
            VEBAL_DELEGATOR.getTokenBalance(
                address(LIQUIDITY_GAUGE),
                address(this)
            );
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
        internal
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

            // @audit this variable name shadows a method declaration
            uint256 _totalSupplyInMaturity = _totalSupplyInMaturity(maturity);

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

    function _totalSupplyInMaturity(uint256 maturity)
        private
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

    // Storage gap for future potential upgrades
    uint256[100] private __gap;
}
