// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {Token, VaultState, VaultAccount} from "../global/Types.sol";
import {SafeInt256} from "../global/SafeInt256.sol";
import {Constants} from "../global/Constants.sol";

import {TokenUtils} from "../utils/TokenUtils.sol";
import {BalancerUtils} from "./balancer/BalancerUtils.sol";
import {BalancerVaultStorage} from "./balancer/BalancerVaultStorage.sol";
import {RewardHelper} from "./balancer/RewardHelper.sol";
import {SettlementHelper} from "./balancer/SettlementHelper.sol";
import {VaultHelper} from "./balancer/VaultHelper.sol";
import {
    DeploymentParams,
    InitParams,
    StrategyVaultSettings,
    StrategyVaultState
} from "./balancer/BalancerVaultTypes.sol";

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

contract Balancer2TokenVault is UUPSUpgradeable, Initializable, VaultHelper {
    using TokenUtils for IERC20;
    using SafeInt256 for uint256;
    using SafeInt256 for int256;

    /** Errors */
    error NotionalOwnerRequired(address sender);
    error DepositNotAllowedInSettlementWindow();
    error RedeemNotAllowedInSettlementWindow();

    /** Events */
    event StrategyVaultSettingsUpdated(StrategyVaultSettings settings);

    constructor(NotionalProxy notional_, DeploymentParams memory params)
        BalancerVaultStorage(notional_, params) { }

    function initialize(InitParams calldata params) external initializer onlyNotionalOwner {
        __INIT_VAULT(params.name, params.borrowCurrencyId);
        _setVaultSettings(params.settings);

        BalancerUtils.approveBalancerTokens(
            address(BalancerUtils.BALANCER_VAULT),
            _underlyingToken(),
            SECONDARY_TOKEN,
            IERC20(address(BALANCER_POOL_TOKEN)),
            IERC20(address(LIQUIDITY_GAUGE)),
            address(VEBAL_DELEGATOR)
        );
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
                VAULT_PERCENTAGE_PRECISION
        );
        require(
            settings.maxBalancerPoolShare <=
                VAULT_PERCENTAGE_PRECISION
        );
        require(
            settings.settlementSlippageLimit <=
                VAULT_PERCENTAGE_PRECISION
        );
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

        uint256 primaryBalance = BalancerUtils.getTimeWeightedPrimaryBalance(
            address(BALANCER_POOL_TOKEN),
            vaultSettings.oracleWindowInSeconds,
            PRIMARY_INDEX,
            PRIMARY_WEIGHT,
            SECONDARY_WEIGHT,
            PRIMARY_DECIMALS,
            bptClaim
        );
        
        // Oracle price for the pair in 18 decimals
        uint256 oraclePairPrice = BalancerUtils.getOraclePairPrice(
            address(BALANCER_POOL_TOKEN),
            PRIMARY_INDEX,
            vaultSettings.oracleWindowInSeconds,
            vaultSettings.balancerOracleWeight,
            address(_underlyingToken()),
            address(SECONDARY_TOKEN),
            TRADING_MODULE
        );

        if (SECONDARY_BORROW_CURRENCY_ID == 0) return primaryBalance.toInt();

        // prettier-ignore
        (
            /* uint256 debtShares */,
            uint256 borrowedSecondaryfCashAmount
        ) = getDebtSharesToRepay(account, maturity, strategyTokenAmount);

        // Do not discount secondary fCash amount to present value so that we do not introduce
        // interest rate risk in this calculation. fCash is always in 8 decimal precision, the
        // oraclePairPrice is always in 18 decimal precision and we want our result denominated
        // in the primary token precision.
        // primaryTokenValue = (fCash * rateDecimals * primaryDecimals) / (rate * 1e8)
        uint256 primaryPrecision = 10 ** PRIMARY_DECIMALS;

        uint256 secondaryBorrowedDenominatedInPrimary = 
            (borrowedSecondaryfCashAmount * BalancerUtils.BALANCER_PRECISION * primaryPrecision)
                / (oraclePairPrice * uint256(Constants.INTERNAL_TOKEN_PRECISION));

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

        // prettier-ignore
        (
            // @audit this number is not correct when rolling since it does not account for
            // tokens rolled into the maturity yet
            uint256 bptHeldInMaturity,
            uint256 totalStrategyTokenSupplyInMaturity
        ) = _getBPTHeldInMaturity(maturity);

        // First borrow any secondary tokens (if required)
        uint256 borrowedSecondaryAmount = _borrowSecondaryCurrency(
            account, maturity, deposit, params
        );

        // Join the balancer pool and stake the tokens for boosting
        uint256 bptMinted = _joinPoolAndStake(deposit, borrowedSecondaryAmount, params.minBPT);

        // Calculate strategy token share for this account
        if (vaultState.totalStrategyTokenGlobal == 0) {
            // Strategy tokens are in 8 decimal precision, BPT is in 18. Scale the minted amount down.
            strategyTokensMinted = (bptMinted * uint256(Constants.INTERNAL_TOKEN_PRECISION))
                / BalancerUtils.BALANCER_PRECISION;
        } else {
            // BPT held in maturity is calculated before the new BPT tokens are minted, so this calculation
            // is the tokens minted that will give the account a corresponding share of the new bpt balance held.
            // The precision here will be the same as strategy token supply.
            strategyTokensMinted = (bptMinted * totalStrategyTokenSupplyInMaturity) / bptHeldInMaturity;
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

}
