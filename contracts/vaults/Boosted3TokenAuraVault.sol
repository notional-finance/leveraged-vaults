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
    ThreeTokenPoolContext,
    Boosted3TokenAuraStrategyContext,
    StrategyContext
} from "./balancer/BalancerVaultTypes.sol";
import {BaseVaultStorage} from "./balancer/BaseVaultStorage.sol";
import {Boosted3TokenPoolMixin} from "./balancer/mixins/Boosted3TokenPoolMixin.sol";
import {AuraStakingMixin} from "./balancer/mixins/AuraStakingMixin.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {BalancerUtils} from "./balancer/internal/BalancerUtils.sol";
import {VaultUtils} from "./balancer/internal/VaultUtils.sol";
import {StrategyUtils} from "./balancer/internal/StrategyUtils.sol";
import {Boosted3TokenAuraStrategyUtils} from "./balancer/internal/Boosted3TokenAuraStrategyUtils.sol";
import {Boosted3TokenPoolUtils} from "./balancer/internal/Boosted3TokenPoolUtils.sol";
import {LibBalancerStorage} from "./balancer/internal/LibBalancerStorage.sol";
import {SecondaryBorrowUtils} from "./balancer/internal/SecondaryBorrowUtils.sol";
import {Boosted3TokenAuraVaultHelper} from "./balancer/external/Boosted3TokenAuraVaultHelper.sol";
import {Boosted3TokenAuraSettlementHelper} from "./balancer/external/Boosted3TokenAuraSettlementHelper.sol";
import {MetaStable2TokenAuraRewardHelper} from "./balancer/external/MetaStable2TokenAuraRewardHelper.sol";
import {AuraRewardHelperExternal} from "./balancer/external/AuraRewardHelperExternal.sol";

contract Boosted3TokenAuraVault is
    UUPSUpgradeable,
    BaseVaultStorage,
    Boosted3TokenPoolMixin,
    AuraStakingMixin
{
    using Boosted3TokenPoolUtils for ThreeTokenPoolContext;
    using StrategyUtils for StrategyContext;
    using Boosted3TokenAuraStrategyUtils for StrategyContext;

    constructor(NotionalProxy notional_, AuraDeploymentParams memory params) 
        BaseVaultStorage(notional_, params.baseParams) 
        Boosted3TokenPoolMixin(
            params.primaryBorrowCurrencyId,
            params.baseParams.balancerPoolId
        )
        AuraStakingMixin(params.baseParams.liquidityGauge, params.auraRewardPool)
    {}

    function strategy() external override view returns (bytes4) {
        return bytes4(keccak256("Boosted3TokenAuraVault"));
    }

    function initialize(InitParams calldata params)
        external
        initializer
        onlyNotionalOwner
    {
        __INIT_VAULT(params.name, params.borrowCurrencyId);
        // 3 token vaults do not use the Balancer oracle
        VaultUtils._setStrategyVaultSettings(
            params.settings, 
            0, // Max Balancer oracle window size
            0  // Balancer oracle weight
        );

        _threeTokenPoolContext()._approveBalancerTokens(address(_auraStakingContext().auraBooster));
    }

    function _depositFromNotional(
        address /* account */,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 strategyTokensMinted) {
        // Entering the vault is not allowed within the settlement window
        _revertInSettlementWindow(maturity);
        strategyTokensMinted = Boosted3TokenAuraVaultHelper.depositFromNotional(
            _strategyContext(), deposit, maturity, data
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
            finalPrimaryBalance = Boosted3TokenAuraVaultHelper.redeemFromNotional(
                _strategyContext(), strategyTokens, maturity, data
            );
        }
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
        Boosted3TokenAuraSettlementHelper.settleVaultNormal(
            _strategyContext(), maturity, strategyTokensToRedeem, data
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
        Boosted3TokenAuraSettlementHelper.settleVaultPostMaturity(
            _strategyContext(), maturity, strategyTokensToRedeem, data
        );
    }

    function settleVaultEmergency(uint256 maturity, bytes calldata data) external {
        // No need for emergency settlement during the settlement window
        _revertInSettlementWindow(maturity);
        Boosted3TokenAuraSettlementHelper.settleVaultEmergency(
            _strategyContext(), maturity, data
        );
    }

    function claimRewardTokens() external returns (uint256[] memory claimedBalances) {
        StrategyVaultSettings memory strategyVaultSettings = VaultUtils._getStrategyVaultSettings();
        claimedBalances = AuraRewardHelperExternal.claimRewardTokens(
            _auraStakingContext(), strategyVaultSettings.feePercentage, FEE_RECEIVER
        );
    }

    function reinvestReward(ReinvestRewardParams calldata params) external {
        //MetaStable2TokenAuraRewardHelper.reinvestReward(_strategyContext(), params);
    }

    function convertStrategyToUnderlying(
        address /* account */,
        uint256 strategyTokenAmount,
        uint256 maturity
    ) public view override returns (int256 underlyingValue) {
        Boosted3TokenAuraStrategyContext memory context = _strategyContext();
        underlyingValue = context.baseStrategy._convertStrategyToUnderlying({
            oracleContext: context.oracleContext,
            poolContext: context.poolContext,
            strategyTokenAmount: strategyTokenAmount,
            maturity: maturity
        });
    }

    /// @notice Updates the vault settings
    /// @param settings vault settings
    function setStrategyVaultSettings(StrategyVaultSettings calldata settings)
        external
        onlyNotionalOwner
    {
        // 3 token vaults do not use the Balancer oracle
        VaultUtils._setStrategyVaultSettings(
            settings, 
            0, // Max Balancer oracle window size
            0  // Balancer oracle weight
        );
    }

    function _strategyContext() private view returns (Boosted3TokenAuraStrategyContext memory) {
        return Boosted3TokenAuraStrategyContext({
            poolContext: _threeTokenPoolContext(),
            oracleContext: _boostedOracleContext(),
            stakingContext: _auraStakingContext(),
            baseStrategy: StrategyContext({
                totalBPTHeld: _bptHeld(),
                secondaryBorrowCurrencyId: 0, // This strategy does not support secondary borrow
                tradingModule: TRADING_MODULE,
                vaultSettings: VaultUtils._getStrategyVaultSettings(),
                vaultState: VaultUtils._getStrategyVaultState()
            })
        });
    }
    
    function getStrategyContext() external view returns (Boosted3TokenAuraStrategyContext memory) {
        return _strategyContext();
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
