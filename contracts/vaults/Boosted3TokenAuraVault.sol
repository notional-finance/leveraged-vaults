// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {Errors} from "../global/Errors.sol";
import {
    AuraVaultDeploymentParams,
    InitParams,
    ReinvestRewardParams,
    StrategyVaultSettings,
    StrategyVaultState,
    PoolContext,
    ThreeTokenPoolContext,
    Boosted3TokenAuraStrategyContext,
    StrategyContext
} from "./balancer/BalancerVaultTypes.sol";
import {BalancerStrategyBase} from "./balancer/BalancerStrategyBase.sol";
import {Boosted3TokenPoolMixin} from "./balancer/mixins/Boosted3TokenPoolMixin.sol";
import {AuraStakingMixin} from "./balancer/mixins/AuraStakingMixin.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {BalancerVaultStorage} from "./balancer/internal/BalancerVaultStorage.sol";
import {StrategyUtils} from "./balancer/internal/strategy/StrategyUtils.sol";
import {Boosted3TokenAuraStrategyUtils} from "./balancer/internal/strategy/Boosted3TokenAuraStrategyUtils.sol";
import {Boosted3TokenPoolUtils} from "./balancer/internal/pool/Boosted3TokenPoolUtils.sol";
import {Boosted3TokenAuraVaultHelper} from "./balancer/external/Boosted3TokenAuraVaultHelper.sol";
import {Boosted3TokenAuraSettlementHelper} from "./balancer/external/Boosted3TokenAuraSettlementHelper.sol";

contract Boosted3TokenAuraVault is
    BalancerStrategyBase,
    Boosted3TokenPoolMixin,
    AuraStakingMixin
{
    using Boosted3TokenPoolUtils for ThreeTokenPoolContext;
    using StrategyUtils for StrategyContext;
    using Boosted3TokenAuraStrategyUtils for StrategyContext;

    constructor(NotionalProxy notional_, AuraVaultDeploymentParams memory params) 
        BalancerStrategyBase(notional_, params.baseParams) 
        Boosted3TokenPoolMixin(
            params.primaryBorrowCurrencyId,
            params.baseParams.balancerPoolId
        )
        AuraStakingMixin(params.baseParams.liquidityGauge, params.auraRewardPool, params.baseParams.feeReceiver)
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
        BalancerVaultStorage.setStrategyVaultSettings(
            params.settings, 
            0, // Max Balancer oracle window size
            0  // Balancer oracle weight
        );

        // @audit why does the auraBooster need approval for all the bal tokens?
        _threeTokenPoolContext()._approveBalancerTokens(address(_auraStakingContext().auraBooster));
    }

    function _depositFromNotional(
        address /* account */,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 strategyTokensMinted) {
        // Entering the vault is not allowed within the settlement window
        // @audit this is true, but is enforced by the Notional side, not necessary here
        _revertInSettlementWindow(maturity);
        // @audit can we bring this back into this contract?
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

        // @audit This is no longer the case with non-secondary token vaults
        // Exiting the vault is not allowed within the settlement window
        if (account != address(this)) {
            _revertInSettlementWindow(maturity);
        }
        // @audit can we bring this back into this contract?
        finalPrimaryBalance = Boosted3TokenAuraVaultHelper.redeemFromNotional(
            _strategyContext(), strategyTokens, maturity, data
        );
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

    function reinvestReward(ReinvestRewardParams calldata params) external {
        Boosted3TokenAuraVaultHelper.reinvestReward(_strategyContext(), params);
    }

    function convertStrategyToUnderlying(
        address account,
        uint256 strategyTokenAmount,
        uint256 maturity
    ) public view override returns (int256 underlyingValue) {
        Boosted3TokenAuraStrategyContext memory context = _strategyContext();
        underlyingValue = context.baseStrategy._convertStrategyToUnderlying({
            oracleContext: context.oracleContext,
            poolContext: context.poolContext,
            strategyTokenAmount: strategyTokenAmount
        });
    }

    /// @notice Updates the vault settings
    /// @param settings vault settings
    function setStrategyVaultSettings(StrategyVaultSettings calldata settings)
        external
        onlyNotionalOwner
    {
        // 3 token vaults do not use the Balancer oracle
        BalancerVaultStorage.setStrategyVaultSettings(
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
                settlementPeriodInSeconds: SETTLEMENT_PERIOD_IN_SECONDS,
                tradingModule: TRADING_MODULE,
                vaultSettings: BalancerVaultStorage.getStrategyVaultSettings(),
                vaultState: BalancerVaultStorage.getStrategyVaultState(),
                feeReceiver: FEE_RECEIVER
            })
        });
    }
    
    function getStrategyContext() external view returns (Boosted3TokenAuraStrategyContext memory) {
        return _strategyContext();
    }
    
    // to get the full _strategyContext() since both of these methods just sit on StrategyUtils
    function convertBPTClaimToStrategyTokens(uint256 bptClaim)
        external view returns (uint256 strategyTokenAmount) {
        return _strategyContext().baseStrategy._convertBPTClaimToStrategyTokens(bptClaim);
    }

    /// @notice Converts strategy tokens to BPT
    function convertStrategyTokensToBPTClaim(uint256 strategyTokenAmount) 
        external view returns (uint256 bptClaim) {
        return _strategyContext().baseStrategy._convertStrategyTokensToBPTClaim(strategyTokenAmount);
    }

    /// @dev Gets the total BPT held by the aura reward pool
    function _bptHeld() internal view returns (uint256) {
        return AURA_REWARD_POOL.balanceOf(address(this));
    }
}
