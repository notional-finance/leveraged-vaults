// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {Token, VaultAccount} from "../global/Types.sol";
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
    StrategyVaultState, 
    VeBalDelegatorInfo,
    ReinvestRewardParams,
    DepositParams,
    RedeemParams,
    SecondaryTradeParams
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
        BalancerVaultStorage(notional_, params)
    {}

    function initialize(InitParams calldata params)
        external
        initializer
        onlyNotionalOwner
    {
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
        require(settings.settlementCoolDownInMinutes <= Constants.MAX_SETTLEMENT_COOLDOWN_IN_MINUTES);
        require(settings.postMaturitySettlementCoolDownInMinutes <= Constants.MAX_SETTLEMENT_COOLDOWN_IN_MINUTES);
        require(settings.balancerOracleWeight <= Constants.VAULT_PERCENT_BASIS);
        require(settings.maxBalancerPoolShare <= Constants.VAULT_PERCENT_BASIS);
        require(settings.settlementSlippageLimitBPS <= Constants.VAULT_PERCENT_BASIS);
        require(settings.postMaturitySettlementSlippageLimitBPS <= Constants.VAULT_PERCENT_BASIS);

        vaultSettings.oracleWindowInSeconds = settings.oracleWindowInSeconds;
        vaultSettings.balancerOracleWeight = settings.balancerOracleWeight;
        vaultSettings.maxBalancerPoolShare = settings.maxBalancerPoolShare;
        vaultSettings.maxUnderlyingSurplus = settings.maxUnderlyingSurplus;
        vaultSettings.settlementSlippageLimitBPS = settings
            .settlementSlippageLimitBPS;
        vaultSettings.postMaturitySettlementSlippageLimitBPS = settings
            .postMaturitySettlementSlippageLimitBPS;
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
            _oracleContext(), bptClaim
        );

        // Oracle price for the pair in 18 decimals
        uint256 oraclePairPrice = _getOraclePairPrice();

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
        uint256 primaryPrecision = 10**PRIMARY_DECIMALS;

        uint256 secondaryBorrowedDenominatedInPrimary = (borrowedSecondaryfCashAmount *
                BalancerUtils.BALANCER_PRECISION *
                primaryPrecision) /
                (oraclePairPrice * uint256(Constants.INTERNAL_TOKEN_PRECISION));

        return
            primaryBalance.toInt() -
            secondaryBorrowedDenominatedInPrimary.toInt();
    }

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

    function _depositFromNotional(
        address account,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 strategyTokensMinted) {
        if (maturity - SETTLEMENT_PERIOD_IN_SECONDS <= block.timestamp) {
            revert DepositNotAllowedInSettlementWindow();
        }

        DepositParams memory params = abi.decode(data, (DepositParams));

        // prettier-ignore
        (
            // @audit this number is not correct when rolling since it does not account for
            // tokens rolled into the maturity yet
            uint256 bptHeldInMaturity,
            uint256 totalStrategyTokenSupplyInMaturity
        ) = _getBPTHeldInMaturity(maturity);

        // First borrow any secondary tokens (if required)
        uint256 borrowedSecondaryAmount = _borrowSecondaryCurrency(
            account,
            maturity,
            deposit,
            params
        );

        // Join the balancer pool and stake the tokens for boosting
        uint256 bptMinted = _joinPoolAndStake(
            deposit,
            borrowedSecondaryAmount,
            params.minBPT
        );

        // Calculate strategy token share for this account
        if (vaultState.totalStrategyTokenGlobal == 0) {
            // Strategy tokens are in 8 decimal precision, BPT is in 18. Scale the minted amount down.
            strategyTokensMinted =
                (bptMinted * uint256(Constants.INTERNAL_TOKEN_PRECISION)) /
                BalancerUtils.BALANCER_PRECISION;
        } else {
            // BPT held in maturity is calculated before the new BPT tokens are minted, so this calculation
            // is the tokens minted that will give the account a corresponding share of the new bpt balance held.
            // The precision here will be the same as strategy token supply.
            strategyTokensMinted =
                (bptMinted * totalStrategyTokenSupplyInMaturity) /
                bptHeldInMaturity;
        }

        // Update global supply count
        vaultState.totalStrategyTokenGlobal += strategyTokensMinted;
    }

    function _redeemFromNotional(
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 finalPrimaryBalance) {
        if (maturity - SETTLEMENT_PERIOD_IN_SECONDS <= block.timestamp) {
            revert RedeemNotAllowedInSettlementWindow();
        }

        RedeemParams memory params = abi.decode(data, (RedeemParams));
        uint256 bptClaim = convertStrategyTokensToBPTClaim(strategyTokens, maturity);

        if (bptClaim == 0) return 0;
        // Underlying token balances from exiting the pool
        (uint256 primaryBalance, uint256 secondaryBalance) = BalancerUtils._unstakeAndExitPoolExactBPTIn(
            _poolContext(), _boostContext(), bptClaim, params.minPrimary, params.minSecondary
        );

        if (SECONDARY_BORROW_CURRENCY_ID != 0) {
            // Returns the amount of secondary debt shares that need to be repaid
            (uint256 debtSharesToRepay, /*  */) = getDebtSharesToRepay(
                account, maturity, strategyTokens
            );
            int256 netPrimaryBalance = repaySecondaryBorrow(
                account,
                maturity,
                debtSharesToRepay,
                params,
                secondaryBalance
            );

            // @audit when would this go negative?
            finalPrimaryBalance = (primaryBalance.toInt() + netPrimaryBalance).toUint();
        } else if (secondaryBalance > 0) {
            // If there is no secondary debt, we still need to sell the secondary balance
            // back to the primary token here.
            (SecondaryTradeParams memory tradeParams) = abi.decode(
                params.secondaryTradeParams, (SecondaryTradeParams)
            );
            address primaryToken = address(_underlyingToken());
            uint256 primaryPurchased = sellSecondaryBalance(tradeParams, primaryToken, secondaryBalance);

            finalPrimaryBalance = primaryBalance + primaryPurchased;
        }

        // Update global strategy token balance
        vaultState.totalStrategyTokenGlobal -= strategyTokens;
    }

    /// @notice Settles the vault after maturity
    /// @dev This settlement call is authenticated
    /// @param maturity maturity timestamp
    /// @param bptToSettle the amount of BPT to settle
    /// @param data settlement parameters
    function settleVaultPostMaturity(
        uint256 maturity,
        uint256 bptToSettle,
        bytes calldata data
    ) external onlyNotionalOwner {
        if (block.timestamp < maturity) {
            revert SettlementHelper.HasNotMatured();
        }
        
        RedeemParams memory params = SettlementHelper._decodeParamsAndValidate(
            vaultState.lastPostMaturitySettlementTimestamp,
            vaultSettings.postMaturitySettlementCoolDownInMinutes,
            vaultSettings.postMaturitySettlementSlippageLimitBPS,
            data
        );

        _validateMinExitAmounts(params.minPrimary, params.minSecondary);
        _settleVaultNormal(maturity, bptToSettle, params);
    }

    function settleVaultNormal(
        uint256 maturity,
        uint256 bptToSettle,
        bytes calldata data
    ) external {
        if (maturity <= block.timestamp) {
            revert SettlementHelper.PostMaturitySettlement();
        }
        if (block.timestamp < maturity - SETTLEMENT_PERIOD_IN_SECONDS) {
            revert SettlementHelper.NotInSettlementWindow();
        }

        RedeemParams memory params = SettlementHelper._decodeParamsAndValidate(
            vaultState.lastSettlementTimestamp,
            vaultSettings.settlementCoolDownInMinutes,
            vaultSettings.settlementSlippageLimitBPS,
            data
        );

        _validateMinExitAmounts(params.minPrimary, params.minSecondary);
        _settleVaultNormal(maturity, bptToSettle, params);
    }

    function settleVaultEmergency(uint256 maturity, bytes calldata data)
        external
    {
        if (maturity <= block.timestamp) {
            revert SettlementHelper.PostMaturitySettlement();
        }
        // TODO: is this check necessary?
        if (maturity - SETTLEMENT_PERIOD_IN_SECONDS <= block.timestamp) {
            revert SettlementHelper.InvalidEmergencySettlement();
        }

        // Not in settlement window, check if BPT held is greater than maxBalancerPoolShare * total BPT supply
        uint256 totalBPTSupply = BALANCER_POOL_TOKEN.totalSupply();
        uint256 totalBPTHeld = _bptHeld();
        uint256 emergencyBPTWithdrawThreshold = _bptThreshold(totalBPTSupply);

        if (totalBPTHeld <= emergencyBPTWithdrawThreshold)
            revert SettlementHelper.InvalidEmergencySettlement();

        // prettier-ignore
        (
            // @audit this number is not correct when rolling since it does not account for
            // tokens rolled into the maturity yet
            uint256 bptHeldInMaturity,
            /* uint256 totalStrategyTokenSupplyInMaturity */
        ) = _getBPTHeldInMaturity(maturity);

        uint256 bptToSettle = SettlementHelper
            ._getEmergencySettlementBPTAmount({
                bptTotalSupply: totalBPTSupply,
                maxBalancerPoolShare: vaultSettings.maxBalancerPoolShare,
                totalBPTHeld: totalBPTHeld,
                bptHeldInMaturity: bptHeldInMaturity
            });

        uint256 redeemStrategyTokenAmount = convertBPTClaimToStrategyTokens(
            bptToSettle,
            maturity
        );

        int256 expectedUnderlyingRedeemed = convertStrategyToUnderlying(
            address(this),
            redeemStrategyTokenAmount,
            maturity
        );

        SettlementHelper.settleVaultEmergency({
            maturity: maturity,
            bptToSettle: bptToSettle,
            expectedUnderlyingRedeemed: expectedUnderlyingRedeemed,
            maxUnderlyingSurplus: vaultSettings.maxUnderlyingSurplus,
            redeemStrategyTokenAmount: redeemStrategyTokenAmount,
            data: data
        });
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
    function reinvestReward(ReinvestRewardParams calldata params) external {
        RewardHelper.reinvestReward(
            params,
            VeBalDelegatorInfo(
                LIQUIDITY_GAUGE,
                VEBAL_DELEGATOR,
                address(BAL_TOKEN)
            ),
            TRADING_MODULE,
            _poolContext()
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

    function getVaultSettings() external view returns (StrategyVaultSettings memory) {
        return vaultSettings;
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal override onlyNotionalOwner {}
}
