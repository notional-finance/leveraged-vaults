// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Constants} from "../global/Constants.sol";
import {SafeInt256} from "../global/SafeInt256.sol";
import {
    AuraDeploymentParams,
    InitParams,
    ReinvestRewardParams,
    StrategyVaultSettings,
    StrategyVaultState,
    PoolContext,
    TwoTokenPoolContext,
    WeightedOracleContext,
    Weighted2TokenAuraStrategyContext,
    StrategyContext,
    TwoTokenAuraSettlementContext
} from "./balancer/BalancerVaultTypes.sol";
import {BaseVaultStorage} from "./balancer/BaseVaultStorage.sol";
import {Weighted2TokenVaultMixin} from "./balancer/mixins/Weighted2TokenVaultMixin.sol";
import {AuraStakingMixin} from "./balancer/mixins/AuraStakingMixin.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {BalancerUtils} from "./balancer/internal/BalancerUtils.sol";
import {VaultUtils} from "./balancer/internal/VaultUtils.sol";
import {StrategyUtils} from "./balancer/internal/StrategyUtils.sol";
import {TwoTokenAuraStrategyUtils} from "./balancer/internal/TwoTokenAuraStrategyUtils.sol";
import {TwoTokenPoolUtils} from "./balancer/internal/TwoTokenPoolUtils.sol";
import {LibBalancerStorage} from "./balancer/internal/LibBalancerStorage.sol";
import {SecondaryBorrowUtils} from "./balancer/internal/SecondaryBorrowUtils.sol";
import {SettlementHelper} from "./balancer/internal/SettlementHelper.sol";
import {Weighted2TokenAuraVaultHelper} from "./balancer/external/Weighted2TokenAuraVaultHelper.sol";
import {TwoTokenAuraSettlementHelper} from "./balancer/external/TwoTokenAuraSettlementHelper.sol";
import {Weighted2TokenAuraRewardHelper} from "./balancer/external/Weighted2TokenAuraRewardHelper.sol";
import {AuraRewardHelperExternal} from "./balancer/external/AuraRewardHelperExternal.sol";

contract Weighted2TokenAuraVault is 
    UUPSUpgradeable,
    BaseVaultStorage,
    Weighted2TokenVaultMixin,
    AuraStakingMixin 
{
    using SafeInt256 for uint256;
    using VaultUtils for StrategyVaultSettings;
    using StrategyUtils for StrategyContext;
    using TwoTokenAuraStrategyUtils for StrategyContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;

    constructor(NotionalProxy notional_, AuraDeploymentParams memory params)
        BaseVaultStorage(notional_, params.baseParams) 
        Weighted2TokenVaultMixin(
            params.primaryBorrowCurrencyId,
            params.baseParams.balancerPoolId,
            params.secondaryBorrowCurrencyId
        )
        AuraStakingMixin(params.baseParams.liquidityGauge, params.auraRewardPool)
    {}

    function strategy() external override view returns (bytes4) {
        return bytes4(keccak256("Weighted2TokenAuraVault"));
    }

    function initialize(InitParams calldata params)
        external
        initializer
        onlyNotionalOwner
    {
        __INIT_VAULT(params.name, params.borrowCurrencyId);
        VaultUtils._setStrategyVaultSettings(
            params.settings, uint32(MAX_ORACLE_QUERY_WINDOW), Constants.VAULT_PERCENT_BASIS
        );
        _twoTokenPoolContext()._approveBalancerTokens(address(_auraStakingContext().auraBooster));
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
        Weighted2TokenAuraStrategyContext memory context = _strategyContext();
        underlyingValue = context.baseStrategy._convertStrategyToUnderlying({
            oracleContext: context.oracleContext.baseOracle,
            poolContext: context.poolContext,
            account: account,
            strategyTokenAmount: strategyTokenAmount,
            maturity: maturity
        });
    }

    function _depositFromNotional(
        address account,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 strategyTokensMinted) {
        // Entering the vault is not allowed within the settlement window
        _revertInSettlementWindow(maturity);
        strategyTokensMinted = Weighted2TokenAuraVaultHelper.depositFromNotional(
            _strategyContext(), account, deposit, maturity, data
        );
    }

    function _redeemFromNotional(
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 finalPrimaryBalance) {
        require(strategyTokens <= type(uint80).max); /// @dev strategyTokens overflow

        if (account == address(this) && data.length == 32) {
            // Check if this is called from one of the settlement functions
            // data = primaryAmountToRepay (uint256) in this case
            // Token transfers are handled in the base strategy
            (finalPrimaryBalance) = abi.decode(data, (uint256));
        } else {
            // Exiting the vault is not allowed within the settlement window
            _revertInSettlementWindow(maturity);
            finalPrimaryBalance = Weighted2TokenAuraVaultHelper.redeemFromNotional(
                _strategyContext(), account, strategyTokens, maturity, data
            );
        }
    }

    function _repaySecondaryBorrowCallback(
        address, /* secondaryToken */
        uint256 underlyingRequired,
        bytes calldata data
    ) internal override returns (bytes memory returnData) {
        require(SECONDARY_BORROW_CURRENCY_ID != 0); /// @dev invalid secondary currency

        returnData = SecondaryBorrowUtils._handleSecondaryBorrowCallback({
            secondaryBorrowCurrencyId: SECONDARY_BORROW_CURRENCY_ID, 
            tradingModule: TRADING_MODULE,
            primaryToken: address(_underlyingToken()),
            secondaryToken: address(SECONDARY_TOKEN),
            underlyingRequired: underlyingRequired, 
            data: data
        });
    }

    /// @notice Settles the vault after maturity, at this point we assume something has gone wrong
    /// and we allow the owner to take over to ensure that the vault is properly settled. This vault
    /// is presumed to be able to settle fully prior to maturity.
    /// @dev This settlement call is authenticated
    /// @param maturity maturity timestamp
    /// @param strategyTokensToRedeem the amount of strategy tokens to redeem
    /// @param data settlement parameters
    function settleVaultPostMaturity(
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external onlyNotionalOwner {
        if (block.timestamp < maturity) {
            revert SettlementHelper.HasNotMatured();
        }
        TwoTokenAuraSettlementHelper.settleVaultPostMaturity(
            _settlementContext(), maturity, strategyTokensToRedeem, data
        );
    }

    /// @notice Once the settlement window begins, the vault may begin to be settled by anyone
    /// who calls this method with valid parameters. Settlement includes redeeming BPT tokens 
    /// for the two underlying tokens and then trading appropriately until both remaining debts
    /// are repaid. Once the settlement window for a maturity begins, users can no longer enter
    /// or exit the maturity until it has completed settlement.
    /// NOTE: Calling this method is not incentivized.
    /// @param maturity maturity timestamp
    /// @param strategyTokensToRedeem the amount of strategy tokens to redeem
    /// @param data settlement parameters
    function settleVaultNormal(
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external {
        if (maturity <= block.timestamp) {
            revert SettlementHelper.PostMaturitySettlement();
        }
        if (block.timestamp < maturity - SETTLEMENT_PERIOD_IN_SECONDS) {
            revert SettlementHelper.NotInSettlementWindow();
        }
        TwoTokenAuraSettlementHelper.settleVaultNormal(
            _settlementContext(), maturity, strategyTokensToRedeem, data
        );
    }

    /// @notice In the case where the total BPT held by the vault is greater than some threshold
    /// of the total vault supply, we may need to redeem strategy tokens to cash to ensure that
    /// the vault will not run into liquidity issues during settlement.
    function settleVaultEmergency(uint256 maturity, bytes calldata data) external {
        // No need for emergency settlement during the settlement window
        _revertInSettlementWindow(maturity);
        TwoTokenAuraSettlementHelper.settleVaultEmergency(
            _settlementContext(), maturity, data
        );
    }

    /// @notice Claim other liquidity gauge reward tokens (i.e. LIDO)
    function claimRewardTokens() external returns (uint256[] memory claimedBalances) {
        StrategyVaultSettings memory strategyVaultSettings = VaultUtils._getStrategyVaultSettings();
        claimedBalances = AuraRewardHelperExternal.claimRewardTokens(
            _auraStakingContext(), strategyVaultSettings.feePercentage, FEE_RECEIVER
        );
    }

    /// @notice Sell reward tokens for BPT and reinvest the proceeds
    /// @param params reward reinvestment params
    function reinvestReward(ReinvestRewardParams calldata params) external {
        Weighted2TokenAuraRewardHelper.reinvestReward(_strategyContext(), params);
    }

    /** Setters */

    /// @notice Updates the vault settings
    /// @param settings vault settings
    function setStrategyVaultSettings(StrategyVaultSettings calldata settings)
        external
        onlyNotionalOwner
    {
        VaultUtils._setStrategyVaultSettings(
            settings, uint32(MAX_ORACLE_QUERY_WINDOW), Constants.VAULT_PERCENT_BASIS
        );
    }

    function _settlementContext() private view returns (TwoTokenAuraSettlementContext memory) {
        Weighted2TokenAuraStrategyContext memory context = _strategyContext();
        return TwoTokenAuraSettlementContext({
            strategyContext: context.baseStrategy,
            oracleContext: context.oracleContext.baseOracle,
            poolContext: context.poolContext,
            stakingContext: context.stakingContext
        });
    }

    function _strategyContext() internal view returns (Weighted2TokenAuraStrategyContext memory) {
        return Weighted2TokenAuraStrategyContext({
            poolContext: _twoTokenPoolContext(),
            oracleContext: _weightedOracleContext(),
            stakingContext: _auraStakingContext(),
            baseStrategy: StrategyContext({
                totalBPTHeld: _bptHeld(),
                secondaryBorrowCurrencyId: SECONDARY_BORROW_CURRENCY_ID,
                tradingModule: TRADING_MODULE,
                vaultSettings: VaultUtils._getStrategyVaultSettings(),
                vaultState: VaultUtils._getStrategyVaultState()
            })
        });
    }

    /** Public view functions */

    function getDebtSharesToRepay(
        address account, 
        uint256 maturity, 
        uint256 strategyTokenAmount
    ) external view returns (uint256 debtSharesToRepay, uint256 borrowedSecondaryfCashAmount) {
        if (SECONDARY_BORROW_CURRENCY_ID == 0) return (0, 0);
        return SecondaryBorrowUtils._getDebtSharesToRepay(
            SECONDARY_BORROW_CURRENCY_ID, 
            account, 
            maturity, 
            strategyTokenAmount
        );
    }

    function convertBPTClaimToStrategyTokens(uint256 bptClaim, uint256 maturity)
        external view returns (uint256 strategyTokenAmount) {
        return _strategyContext().baseStrategy._convertBPTClaimToStrategyTokens(bptClaim, maturity);
    }

   /// @notice Converts strategy tokens to BPT
    function convertStrategyTokensToBPTClaim(uint256 strategyTokenAmount, uint256 maturity) 
        external view returns (uint256 bptClaim) {
        return _strategyContext().baseStrategy._convertStrategyTokensToBPTClaim(strategyTokenAmount, maturity);
    }

    function getStrategyContext() external view returns (Weighted2TokenAuraStrategyContext memory) {
        return _strategyContext();
    }

    /// @dev Gets the total BPT held by the aura reward pool
    function _bptHeld() internal view returns (uint256) {
        return AURA_REWARD_POOL.balanceOf(address(this));
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal override onlyNotionalOwner {}
}
