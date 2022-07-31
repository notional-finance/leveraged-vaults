// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Constants} from "../global/Constants.sol";
import {Errors} from "../global/Errors.sol";
import {SafeInt256} from "../global/SafeInt256.sol";
import {
    AuraDeploymentParams,
    InitParams,
    ReinvestRewardParams,
    StrategyVaultSettings,
    StrategyVaultState,
    PoolContext,
    TwoTokenPoolContext,
    StableOracleContext,
    MetaStable2TokenAuraStrategyContext,
    StrategyContext,
    TwoTokenAuraSettlementContext
} from "./balancer/BalancerVaultTypes.sol";
import {BaseVaultStorage} from "./balancer/BaseVaultStorage.sol";
import {MetaStable2TokenVaultMixin} from "./balancer/mixins/MetaStable2TokenVaultMixin.sol";
import {AuraStakingMixin} from "./balancer/mixins/AuraStakingMixin.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {BalancerUtils} from "./balancer/internal/BalancerUtils.sol";
import {VaultUtils} from "./balancer/internal/VaultUtils.sol";
import {StrategyUtils} from "./balancer/internal/StrategyUtils.sol";
import {TwoTokenAuraStrategyUtils} from "./balancer/internal/TwoTokenAuraStrategyUtils.sol";
import {TwoTokenPoolUtils} from "./balancer/internal/TwoTokenPoolUtils.sol";
import {LibBalancerStorage} from "./balancer/internal/LibBalancerStorage.sol";
import {SecondaryBorrowUtils} from "./balancer/internal/SecondaryBorrowUtils.sol";
import {MetaStable2TokenAuraVaultHelper} from "./balancer/external/MetaStable2TokenAuraVaultHelper.sol";
import {TwoTokenAuraSettlementHelper} from "./balancer/external/TwoTokenAuraSettlementHelper.sol";
import {MetaStable2TokenAuraRewardHelper} from "./balancer/external/MetaStable2TokenAuraRewardHelper.sol";
import {AuraRewardHelperExternal} from "./balancer/external/AuraRewardHelperExternal.sol";

contract MetaStable2TokenAuraVault is
    UUPSUpgradeable,
    BaseVaultStorage,
    MetaStable2TokenVaultMixin,
    AuraStakingMixin
{
    using SafeInt256 for uint256;
    using VaultUtils for StrategyVaultSettings;
    using StrategyUtils for StrategyContext;
    using TwoTokenAuraStrategyUtils for StrategyContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    
    constructor(NotionalProxy notional_, AuraDeploymentParams memory params) 
        BaseVaultStorage(notional_, params.baseParams) 
        MetaStable2TokenVaultMixin(
            params.primaryBorrowCurrencyId,
            params.baseParams.balancerPoolId,
            params.secondaryBorrowCurrencyId
        )
        AuraStakingMixin(params.baseParams.liquidityGauge, params.auraRewardPool)
    {}

    function strategy() external override view returns (bytes4) {
        return bytes4(keccak256("MetaStable2TokenAura"));
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

    function _depositFromNotional(
        address account,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 strategyTokensMinted) {
        // Entering the vault is not allowed within the settlement window
        _revertInSettlementWindow(maturity);
        strategyTokensMinted = MetaStable2TokenAuraVaultHelper.depositFromNotional(
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
            finalPrimaryBalance = MetaStable2TokenAuraVaultHelper.redeemFromNotional(
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

    function convertStrategyToUnderlying(
        address account,
        uint256 strategyTokenAmount,
        uint256 maturity
    ) public view override returns (int256 underlyingValue) {
        MetaStable2TokenAuraStrategyContext memory context = _strategyContext();
        underlyingValue = context.baseStrategy._convertStrategyToUnderlying({
            oracleContext: context.oracleContext.baseOracle,
            poolContext: context.poolContext,
            account: account,
            strategyTokenAmount: strategyTokenAmount,
            maturity: maturity
        });
    }

    function settleVaultNormal(
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external {
        if (maturity <= block.timestamp) {
            revert Errors.PostMaturitySettlement();
        }
        if (block.timestamp < maturity - SETTLEMENT_PERIOD_IN_SECONDS) {
            revert Errors.NotInSettlementWindow();
        }
        TwoTokenAuraSettlementHelper.settleVaultNormal(
            _settlementContext(), maturity, strategyTokensToRedeem, data
        );
    }

    function settleVaultPostMaturity(
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external onlyNotionalOwner {
        if (block.timestamp < maturity) {
            revert Errors.HasNotMatured();
        }
        TwoTokenAuraSettlementHelper.settleVaultPostMaturity(
            _settlementContext(), maturity, strategyTokensToRedeem, data
        );
    }

    function settleVaultEmergency(uint256 maturity, bytes calldata data) external {
        // No need for emergency settlement during the settlement window
        _revertInSettlementWindow(maturity);
        TwoTokenAuraSettlementHelper.settleVaultEmergency(
            _settlementContext(), maturity, data
        );
    }

    function claimRewardTokens() external returns (uint256[] memory claimedBalances) {
        StrategyVaultSettings memory strategyVaultSettings = VaultUtils._getStrategyVaultSettings();
        claimedBalances = AuraRewardHelperExternal.claimRewardTokens(
            _auraStakingContext(), strategyVaultSettings.feePercentage, FEE_RECEIVER
        );
    }

    function reinvestReward(ReinvestRewardParams calldata params) external {
        MetaStable2TokenAuraRewardHelper.reinvestReward(_strategyContext(), params);
    }

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
        MetaStable2TokenAuraStrategyContext memory context = _strategyContext();
        return TwoTokenAuraSettlementContext({
            strategyContext: context.baseStrategy,
            oracleContext: context.oracleContext.baseOracle,
            poolContext: context.poolContext,
            stakingContext: context.stakingContext
        });
    }

    function _strategyContext() private view returns (MetaStable2TokenAuraStrategyContext memory) {
        return MetaStable2TokenAuraStrategyContext({
            poolContext: _twoTokenPoolContext(),
            oracleContext: _stableOracleContext(),
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
    
    function getStrategyContext() external view returns (MetaStable2TokenAuraStrategyContext memory) {
        return _strategyContext();
    }

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

    /// @dev Gets the total BPT held by the aura reward pool
    function _bptHeld() internal view returns (uint256) {
        return AURA_REWARD_POOL.balanceOf(address(this));
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal override onlyNotionalOwner {}
}
