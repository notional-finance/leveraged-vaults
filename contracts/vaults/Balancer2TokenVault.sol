// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;


import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {Token, VaultState, VaultAccount} from "../global/Types.sol";
import {SafeInt256} from "../global/SafeInt256.sol";
import {Constants} from "../global/Constants.sol";

import {TokenUtils} from "../utils/TokenUtils.sol";
import {BaseStrategyVault} from "./BaseStrategyVault.sol";
import {BalancerUtils} from "./balancer/BalancerUtils.sol";
import {RewardHelper} from "./balancer/RewardHelper.sol";
import {SettlementHelper} from "./balancer/SettlementHelper.sol";
import {VaultHelper} from "./balancer/VaultHelper.sol";

import {IERC20} from "../../interfaces/IERC20.sol";
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
import {ITradingModule} from "../../interfaces/trading/ITradingModule.sol";

contract Balancer2TokenVault is
    UUPSUpgradeable,
    Initializable,
    BaseStrategyVault
{
    using TokenUtils for IERC20;
    using SafeInt256 for uint256;
    using SafeInt256 for int256;

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
    error DepositNotAllowedInSettlementWindow();
    error RedeemNotAllowedInSettlementWindow();

    /** Events */
    event StrategyVaultSettingsUpdated(StrategyVaultSettings settings);

    /** Constants */

    uint256 internal constant SECONDARY_BORROW_UPPER_LIMIT = 105;
    uint256 internal constant SECONDARY_BORROW_LOWER_LIMIT = 95;
    uint16 internal constant MAX_SETTLEMENT_COOLDOWN_IN_MINUTES = 24 * 60; // 1 day

    /// @notice Difference between 1e18 and internal precision
    uint256 internal constant INTERNAL_PRECISION_DIFF = 1e10;
    uint256 internal constant INTERNAL_PRECISION = 1e8;

    /** Immutables */
    uint16 internal immutable SECONDARY_BORROW_CURRENCY_ID;
    bytes32 internal immutable BALANCER_POOL_ID;
    IBalancerPool internal immutable BALANCER_POOL_TOKEN;
    IERC20 internal immutable SECONDARY_TOKEN;
    IBoostController internal immutable BOOST_CONTROLLER;
    ILiquidityGauge internal immutable LIQUIDITY_GAUGE;
    IVeBalDelegator internal immutable VEBAL_DELEGATOR;
    IERC20 internal immutable BAL_TOKEN;
    uint8 internal immutable PRIMARY_INDEX;
    uint32 internal immutable SETTLEMENT_PERIOD_IN_SECONDS;
    uint256 internal immutable PRIMARY_WEIGHT;
    uint256 internal immutable SECONDARY_WEIGHT;
    uint8 internal immutable PRIMARY_DECIMALS;
    uint8 internal immutable SECONDARY_DECIMALS;

    StrategyVaultSettings internal vaultSettings;

    StrategyVaultState internal vaultState;

    /// @notice Keeps track of the primary settlement balance maturity => balance
    mapping(uint256 => uint256) internal primarySettlementBalance;

    /// @notice Keeps track of the secondary settlement balance maturity => balance
    mapping(uint256 => uint256) internal secondarySettlementBalance;

    constructor(NotionalProxy notional_, DeploymentParams memory params)
        BaseStrategyVault(notional_, params.tradingModule)
        initializer
    {
        // @audit we should validate in this method that the balancer oracle is enabled otherwise none
        // of the methods will work:
        // https://dev.balancer.fi/references/contracts/apis/pools/weightedpool2tokens#getmiscdata

        SECONDARY_BORROW_CURRENCY_ID = params.secondaryBorrowCurrencyId;
        BALANCER_POOL_ID = params.balancerPoolId;
        {
            (
                address pool, /* */

            ) = BalancerUtils.BALANCER_VAULT.getPool(params.balancerPoolId);
            BALANCER_POOL_TOKEN = IBalancerPool(pool);
        }

        // prettier-ignore
        (
            address[] memory tokens,
            /* uint256[] memory balances */,
            /* uint256 lastChangeBlock */
        ) = BalancerUtils.BALANCER_VAULT.getPoolTokens(BALANCER_POOL_ID);

        // Balancer tokens are sorted by address, so we need to figure out
        // the correct index for the primary token
        PRIMARY_INDEX = tokens[0] ==
            BalancerUtils.tokenAddress(address(_underlyingToken()))
            ? 0
            : 1;
        uint8 secondaryIndex;
        unchecked {
            secondaryIndex = 1 - PRIMARY_INDEX;
        }

        // Since this is always a 2-token vault, SECONDARY_INDEX = 1-PRIMARY_INDEX
        SECONDARY_TOKEN = SECONDARY_BORROW_CURRENCY_ID > 0
            ? IERC20(_getUnderlyingAddress(SECONDARY_BORROW_CURRENCY_ID))
            : IERC20(tokens[secondaryIndex]);

        // Make sure the deployment parameters are correct
        if (
            tokens[PRIMARY_INDEX] !=
            BalancerUtils.tokenAddress(address(_underlyingToken()))
        ) revert InvalidPrimaryToken(tokens[PRIMARY_INDEX]);
        if (
            tokens[secondaryIndex] !=
            BalancerUtils.tokenAddress(address(SECONDARY_TOKEN))
        ) revert InvalidSecondaryToken(tokens[secondaryIndex]);

        uint256 primaryDecimals = address(_underlyingToken()) ==
            Constants.ETH_ADDRESS
            ? 18
            : _underlyingToken().decimals();
        require(primaryDecimals <= type(uint8).max);
        PRIMARY_DECIMALS = uint8(primaryDecimals);

        uint256 secondaryDecimals = address(SECONDARY_TOKEN) ==
            Constants.ETH_ADDRESS
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
        BAL_TOKEN = IERC20(
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
        require(
            settings.balancerOracleWeight <=
                VaultHelper.VAULT_PERCENTAGE_PRECISION
        );
        require(
            settings.maxBalancerPoolShare <=
                VaultHelper.VAULT_PERCENTAGE_PRECISION
        );
        require(
            settings.settlementSlippageLimit <=
                VaultHelper.VAULT_PERCENTAGE_PRECISION
        );
        require(
            settings.postMaturitySettlementSlippageLimit <=
                VaultHelper.VAULT_PERCENTAGE_PRECISION
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

    /// @notice Approve necessary token transfers
    function _approveTokens() private {
        // Approving in external lib to reduce contract size
        // @audit would be nice to move this back into the contract if we have the space
        BalancerUtils.approveBalancerTokens(
            address(BalancerUtils.BALANCER_VAULT),
            _underlyingToken(),
            SECONDARY_TOKEN,
            IERC20(address(BALANCER_POOL_TOKEN)),
            IERC20(address(LIQUIDITY_GAUGE)),
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

        // @audit this pair price is incorrect
        (uint256 primaryBalance, uint256 pairPrice) = BalancerUtils
            .getTimeWeightedPrimaryBalance(
                address(BALANCER_POOL_TOKEN),
                vaultSettings.oracleWindowInSeconds,
                PRIMARY_INDEX,
                PRIMARY_WEIGHT,
                SECONDARY_WEIGHT,
                PRIMARY_DECIMALS,
                bptClaim
            );

        if (SECONDARY_BORROW_CURRENCY_ID == 0) return primaryBalance.toInt();

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
            primaryBalance.toInt() -
            secondaryBorrowedDenominatedInPrimary.toInt();
    }

    function _getVaultContext()
        private
        view
        returns (VaultHelper.VaultContext memory)
    {
        return
            VaultHelper.VaultContext(
                _getPoolContext(),
                VaultHelper.BoostContext(LIQUIDITY_GAUGE, BOOST_CONTROLLER)
            );
    }

    function _getPoolContext()
        private
        view
        returns (VaultHelper.PoolContext memory)
    {
        return
            VaultHelper.PoolContext({
                pool: BALANCER_POOL_TOKEN,
                poolId: BALANCER_POOL_ID,
                primaryToken: address(_underlyingToken()),
                secondaryToken: address(SECONDARY_TOKEN),
                primaryIndex: PRIMARY_INDEX
            });
    }

    function _depositFromNotional(
        address account,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 strategyTokensMinted) {
        if (maturity - SETTLEMENT_PERIOD_IN_SECONDS <= block.timestamp) {
            revert DepositNotAllowedInSettlementWindow();
        }

        VaultHelper.DepositParams memory params = abi.decode(
            data,
            (VaultHelper.DepositParams)
        );

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
            // Optimal secondary amount
            borrowedSecondaryAmount = BalancerUtils
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

            borrowedSecondaryAmount = VaultHelper.borrowSecondaryCurrency(
                account,
                deposit,
                maturity,
                params.secondaryfCashAmount,
                params.secondarySlippageLimit,
                borrowedSecondaryAmount,
                SECONDARY_BORROW_LOWER_LIMIT,
                SECONDARY_BORROW_UPPER_LIMIT
            );
        }

        // prettier-ignore
        (
            uint256 bptHeldInMaturity,
            uint256 totalStrategyTokenSupplyInMaturity
        ) = _getBPTHeldInMaturity(maturity);

        strategyTokensMinted = VaultHelper.depositFromNotional(
            _getVaultContext(),
            account,
            deposit,
            maturity,
            borrowedSecondaryAmount,
            params.minBPT,
            vaultState.totalStrategyTokenGlobal,
            bptHeldInMaturity,
            totalStrategyTokenSupplyInMaturity
        );

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

    /// @notice Callback function for repaying secondary debt
    function _repaySecondaryBorrowCallback(
        address, /* secondaryToken */
        uint256 underlyingRequired,
        bytes calldata data
    ) internal override returns (bytes memory returnData) {
        require(SECONDARY_BORROW_CURRENCY_ID > 0); /// @dev invalid secondary currency
        return
            VaultHelper.handleRepaySecondaryBorrowCallback(
                underlyingRequired,
                data,
                TRADING_MODULE,
                address(_underlyingToken()),
                address(SECONDARY_TOKEN),
                SECONDARY_BORROW_CURRENCY_ID
            );
    }

    function _redeemFromNotional(
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 underlyingAmount) {
        if (maturity - SETTLEMENT_PERIOD_IN_SECONDS <= block.timestamp) {
            revert RedeemNotAllowedInSettlementWindow();
        }

        VaultHelper.RedeemParams memory params = abi.decode(
            data,
            (VaultHelper.RedeemParams)
        );

        uint256 bptClaim = convertStrategyTokensToBPTClaim(
            strategyTokens,
            maturity
        );

        if (bptClaim > 0) {
            // prettier-ignore
            (
                uint256 primaryBalance, 
                uint256 secondaryBalance
            ) = VaultHelper.redeemFromNotional(
                _getVaultContext(),
                bptClaim,
                maturity,
                params
            );

            // prettier-ignore
            (
                uint256 debtSharesToRepay,
                /* uint256 borrowedSecondaryfCashAmount */
            ) = getDebtSharesToRepay(account, maturity, strategyTokens);

            if (debtSharesToRepay > 0) {
                underlyingAmount = VaultHelper.repaySecondaryBorrow(
                    account,
                    SECONDARY_BORROW_CURRENCY_ID,
                    maturity,
                    debtSharesToRepay,
                    params.secondarySlippageLimit,
                    params.callbackData,
                    primaryBalance,
                    secondaryBalance
                );
            } else {
                // No secondary debt
                // Primary repayment is handled in the base strategy
                underlyingAmount = primaryBalance;
            }

            // Update global strategy token balance
            vaultState.totalStrategyTokenGlobal -= strategyTokens;
        }
    }

    function _getNormalSettlementContext(
        uint256 maturity,
        uint256 redeemStrategyTokenAmount,
        uint32 lastSettlementTimestamp,
        uint32 settlementCoolDownInMinutes,
        uint16 settlementSlippageLimit
    ) private returns (SettlementHelper.NormalSettlementContext memory) {
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

        return
            SettlementHelper.NormalSettlementContext({
                maxUnderlyingSurplus: vaultSettings.maxUnderlyingSurplus,
                primarySettlementBalance: primarySettlementBalance[maturity],
                secondarySettlementBalance: secondarySettlementBalance[
                    maturity
                ],
                redeemStrategyTokenAmount: redeemStrategyTokenAmount,
                underlyingCashRequiredToSettle: underlyingCashRequiredToSettle,
                debtSharesToRepay: debtSharesToRepay,
                borrowedSecondaryfCashAmount: borrowedSecondaryfCashAmount,
                settlementPeriodInSeconds: SETTLEMENT_PERIOD_IN_SECONDS,
                lastSettlementTimestamp: lastSettlementTimestamp,
                settlementCoolDownInMinutes: settlementCoolDownInMinutes,
                settlementSlippageLimit: settlementSlippageLimit,
                secondaryBorrowCurrencyId: SECONDARY_BORROW_CURRENCY_ID,
                secondaryDecimals: SECONDARY_DECIMALS,
                poolContext: _getPoolContext()
            });
    }

    function settleVaultPostMaturity(
        uint256 maturity,
        uint256 bptToSettle,
        bytes calldata data
    ) external onlyNotionalOwner {
        uint256 redeemStrategyTokenAmount = convertBPTClaimToStrategyTokens(
            bptToSettle,
            maturity
        );

        // prettier-ignore
        (
            bool settled, 
            uint256 amountToRepay,
            uint256 primaryPostSettlement,
            uint256 secondaryPostSettlement
        ) = SettlementHelper.settleVaultPostMaturity(
            _getNormalSettlementContext(
                maturity,
                redeemStrategyTokenAmount,
                vaultState.lastPostMaturitySettlementTimestamp,
                vaultSettings.postMaturitySettlementCoolDownInMinutes,
                vaultSettings.postMaturitySettlementSlippageLimit
            ),
            maturity,
            bptToSettle,
            data
        );

        primarySettlementBalance[maturity] = primaryPostSettlement;
        secondarySettlementBalance[maturity] = secondaryPostSettlement;

        if (amountToRepay > 0) {
            // Transfer everything to Notional including the surplus
            _repayPrimaryBorrow(address(Constants.NOTIONAL), 0, amountToRepay);
        }

        if (settled) {
            vaultState.lastPostMaturitySettlementTimestamp = uint32(
                block.timestamp
            );

            emit SettlementHelper.NormalVaultSettlement(
                maturity,
                bptToSettle,
                redeemStrategyTokenAmount
            );
        }
    }

    function settleVaultNormal(
        uint256 maturity,
        uint256 bptToSettle,
        bytes calldata data
    ) external {
        uint256 redeemStrategyTokenAmount = convertBPTClaimToStrategyTokens(
            bptToSettle,
            maturity
        );

        // prettier-ignore
        (
            bool settled, 
            uint256 amountToRepay,
            uint256 primaryPostSettlement,
            uint256 secondaryPostSettlement
        ) = SettlementHelper.settleVaultNormal(
            _getNormalSettlementContext(
                maturity,
                redeemStrategyTokenAmount,
                vaultState.lastSettlementTimestamp,
                vaultSettings.settlementCoolDownInMinutes,
                vaultSettings.settlementSlippageLimit
            ),
            maturity,
            bptToSettle,
            data
        );

        primarySettlementBalance[maturity] = primaryPostSettlement;
        secondarySettlementBalance[maturity] = secondaryPostSettlement;

        if (amountToRepay > 0) {
            // Transfer everything to Notional including the surplus
            _repayPrimaryBorrow(address(Constants.NOTIONAL), 0, amountToRepay);
        }

        if (settled) {
            vaultState.lastSettlementTimestamp = uint32(block.timestamp);

            emit SettlementHelper.NormalVaultSettlement(
                maturity,
                bptToSettle,
                redeemStrategyTokenAmount
            );
        }
    }

    function settleVaultEmergency(
        uint256 maturity,
        uint256 bptToSettle,
        bytes calldata data
    ) external {
        uint256 redeemStrategyTokenAmount = convertBPTClaimToStrategyTokens(
            bptToSettle,
            maturity
        );

        int256 expectedUnderlyingRedeemed = convertStrategyToUnderlying(
            address(this),
            redeemStrategyTokenAmount,
            maturity
        );

        SettlementHelper.settleVaultEmergency(
            SettlementHelper.EmergencySettlementContext(
                redeemStrategyTokenAmount,
                expectedUnderlyingRedeemed,
                vaultSettings.maxUnderlyingSurplus,
                BALANCER_POOL_TOKEN.totalSupply(),
                _bptHeld(),
                SETTLEMENT_PERIOD_IN_SECONDS,
                vaultSettings.maxBalancerPoolShare
            ),
            maturity,
            bptToSettle,
            data
        );
    }

    /// @notice Claim BAL token gauge reward
    /// @return balAmount amount of BAL claimed
    function claimBAL() external returns (uint256) {
        // @audit perhaps it would be more efficient to then call executeRewardTrades right after
        // this claim is done inside the same method?
        // @audit part of this BAL that is claimed needs to be donated to the Notional protocol,
        // we should set an percentage and then transfer to the TreasuryManager contract.
        return BOOST_CONTROLLER.claimBAL(LIQUIDITY_GAUGE);
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
        return BOOST_CONTROLLER.claimGaugeTokens(LIQUIDITY_GAUGE);
    }

    /// @notice Sell reward tokens for BPT and reinvest the proceeds
    /// @param params reward reinvestment params
    function reinvestReward(RewardHelper.ReinvestRewardParams calldata params)
        external
    {
        RewardHelper.reinvestReward(
            params,
            RewardHelper.VeBalDelegatorInfo(
                VEBAL_DELEGATOR,
                LIQUIDITY_GAUGE,
                address(BAL_TOKEN)
            ),
            TRADING_MODULE,
            BALANCER_POOL_ID,
            address(_underlyingToken()),
            address(SECONDARY_TOKEN),
            PRIMARY_INDEX
        );
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

            uint256 _totalSupply = _totalSupplyInMaturity(maturity);

            if (account == address(this)) {
                debtSharesToRepay =
                    (totalAccountDebtShares * strategyTokenAmount) /
                    _totalSupply;
                borrowedSecondaryfCashAmount =
                    (totalfCashBorrowed * strategyTokenAmount) /
                    _totalSupply;
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
