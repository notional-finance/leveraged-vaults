// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    PoolContext, 
    OracleContext, 
    WeightedOracleContext, 
    TwoTokenPoolContext,
    AuraStakingContext,
    PoolParams
} from "../BalancerVaultTypes.sol";
import {IPriceOracle} from "../../../../interfaces/balancer/IPriceOracle.sol";
import {IBalancerVault, IAsset} from "../../../../interfaces/balancer/IBalancerVault.sol";
import {ITradingModule} from "../../../../interfaces/trading/ITradingModule.sol";
import {Constants} from "../../../global/Constants.sol";
import {WETH9} from "../../../../interfaces/WETH9.sol";
import {TokenUtils, IERC20} from "../../../utils/TokenUtils.sol";

library BalancerUtils {
    using TokenUtils for IERC20;

    WETH9 internal constant WETH =
        WETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IBalancerVault internal constant BALANCER_VAULT =
        IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    uint256 internal constant BALANCER_PRECISION = 1e18;
    uint256 internal constant BALANCER_PRECISION_SQUARED = 1e36;
    uint256 internal constant BALANCER_ORACLE_WEIGHT_PRECISION = 1e8;

    error InvalidTokenIndex(uint256 tokenIndex);

    /// @notice Special handling for ETH because UNDERLYING_TOKEN == address(0)
    /// and Balancer uses WETH
    function getTokenAddress(address token) internal pure returns (address) {
        return token == Constants.ETH_ADDRESS ? address(WETH) : address(token);
    }

    function _getTimeWeightedOraclePrice(
        address pool,
        IPriceOracle.Variable variable,
        uint256 secs
    ) internal view returns (uint256) {
        IPriceOracle.OracleAverageQuery[]
            memory queries = new IPriceOracle.OracleAverageQuery[](1);

        queries[0].variable = variable;
        queries[0].secs = secs;
        queries[0].ago = 0; // now

        // Gets the balancer time weighted average price denominated in the first token
        return IPriceOracle(pool).getTimeWeightedAverage(queries)[0];
    }

    /// @notice Normalizes balances to 1e18 (used by Balancer price oracle functions)
    function _normalizeBalances(
        uint256 primaryBalance,
        uint8 primaryDecimals,
        uint256 secondaryBalance,
        uint8 secondaryDecimals
    ) internal pure returns (uint256 normalizedPrimary, uint256 normalizedSecondary) {
        if (primaryDecimals == 18) {
            normalizedPrimary = primaryBalance;
        } else {
            uint256 decimalAdjust;
            unchecked { 
                decimalAdjust = 10**(18 - primaryDecimals);
            }
            normalizedPrimary = primaryBalance * decimalAdjust;
        }

        if (secondaryDecimals == 18) {
            normalizedSecondary = secondaryBalance;
        } else {
            uint256 decimalAdjust;
            unchecked { 
                decimalAdjust = 10**(18 - secondaryDecimals);
            }
            normalizedSecondary = secondaryBalance * decimalAdjust;
        }
    }

    /// @notice Joins a balancer pool using exact tokens in
    function joinPoolExactTokensIn(
        PoolContext memory context,
        PoolParams memory params,
        uint256 minBPT
    ) internal returns (uint256 bptAmount) {
        // Join pool
        bptAmount = IERC20(address(context.pool)).balanceOf(address(this));
        BALANCER_VAULT.joinPool{value: params.msgValue}(
            context.poolId,
            address(this),
            address(this),
            IBalancerVault.JoinPoolRequest(
                params.assets,
                params.amounts,
                abi.encode(
                    IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                    params.amounts,
                    minBPT // Apply minBPT to prevent front running
                ),
                false // Don't use internal balances
            )
        );
        bptAmount = IERC20(address(context.pool)).balanceOf(address(this)) - bptAmount;
    }

    /// @notice Exits a balancer pool using exact BPT in
    function _exitPoolExactBPTIn(
        PoolContext memory context,
        PoolParams memory params,
        uint256 bptExitAmount
    ) internal returns (uint256[] memory exitBalances) {
        exitBalances = new uint256[](params.assets.length);

        for (uint256 i; i < params.assets.length; i++) {
            exitBalances[i] = TokenUtils.tokenBalance(address(params.assets[i]));
        }

        BALANCER_VAULT.exitPool(
            context.poolId,
            address(this),
            payable(address(this)), // Vault will receive the underlying assets
            IBalancerVault.ExitPoolRequest(
                params.assets,
                params.amounts,
                abi.encode(
                    IBalancerVault.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT,
                    bptExitAmount
                ),
                false // Don't use internal balances
            )
        );

        for (uint256 i; i < params.assets.length; i++) {
            exitBalances[i] = TokenUtils.tokenBalance(address(params.assets[i])) - exitBalances[i];
        }
    }

    function approveBalancerTokens(
        TwoTokenPoolContext memory poolContext,
        AuraStakingContext memory stakingContext
    ) internal {
        IERC20(poolContext.primaryToken).checkApprove(address(BALANCER_VAULT), type(uint256).max);
        IERC20(poolContext.secondaryToken).checkApprove(address(BALANCER_VAULT), type(uint256).max);
        // Allow AURA_BOOSTER to pull BALANCER_POOL_TOKEN
        IERC20(address(poolContext.baseContext.pool))
            .checkApprove(address(stakingContext.auraBooster), type(uint256).max);
    }
}
