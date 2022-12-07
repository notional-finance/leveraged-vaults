// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {
    ThreeTokenPoolContext, 
    TwoTokenPoolContext, 
    BoostedOracleContext,
    UnderlyingPoolContext,
    AuraVaultDeploymentParams,
    Boosted3TokenAuraStrategyContext,
    StrategyContext,
    AuraStakingContext
} from "../BalancerVaultTypes.sol";
import {IERC20} from "../../../../interfaces/IERC20.sol";
import {BalancerConstants} from "../internal/BalancerConstants.sol";
import {IBalancerPool, IBoostedPool, ILinearPool} from "../../../../interfaces/balancer/IBalancerPool.sol";
import {BalancerUtils} from "../internal/pool/BalancerUtils.sol";
import {Deployments} from "../../../global/Deployments.sol";
import {PoolMixin} from "./PoolMixin.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";
import {StableMath} from "../internal/math/StableMath.sol";

abstract contract Boosted3TokenPoolMixin is PoolMixin {

    error InvalidPrimaryToken(address token);

    uint8 internal constant NOT_FOUND = type(uint8).max;

    IERC20 internal immutable PRIMARY_TOKEN;
    IERC20 internal immutable SECONDARY_TOKEN;
    IERC20 internal immutable TERTIARY_TOKEN;
    uint8 internal immutable PRIMARY_INDEX;
    uint8 internal immutable SECONDARY_INDEX;
    uint8 internal immutable TERTIARY_INDEX;
    uint8 internal immutable BPT_INDEX;
    uint8 internal immutable PRIMARY_DECIMALS;
    uint8 internal immutable SECONDARY_DECIMALS;
    uint8 internal immutable TERTIARY_DECIMALS;

    constructor(
        NotionalProxy notional_, 
        AuraVaultDeploymentParams memory params
    ) PoolMixin(notional_, params) {
        address primaryAddress = BalancerUtils.getTokenAddress(
            _getNotionalUnderlyingToken(params.baseParams.primaryBorrowCurrencyId)
        );
        
        // prettier-ignore
        (
            address[] memory tokens,
            /* uint256[] memory balances */,
            /* uint256 lastChangeBlock */
        ) = Deployments.BALANCER_VAULT.getPoolTokens(params.baseParams.balancerPoolId);

        // Boosted pools contain 4 tokens (3 LinearPool LP tokens + 1 BoostedPool LP token)
        require(tokens.length == 4);

        uint8 primaryIndex = NOT_FOUND;
        uint8 secondaryIndex = NOT_FOUND;
        uint8 tertiaryIndex = NOT_FOUND;
        uint8 bptIndex = NOT_FOUND;
        for (uint256 i; i < 4; i++) {
            // Skip pool token
            if (tokens[i] == address(BALANCER_POOL_TOKEN)) {
                bptIndex = uint8(i);
            } else if (ILinearPool(tokens[i]).getMainToken() == primaryAddress) {
                primaryIndex = uint8(i);
            } else {
                if (secondaryIndex == NOT_FOUND) {
                    secondaryIndex = uint8(i);
                } else {
                    tertiaryIndex = uint8(i);
                }
            }
        }

        require(primaryIndex != NOT_FOUND);

        PRIMARY_INDEX = primaryIndex;
        SECONDARY_INDEX = secondaryIndex;
        TERTIARY_INDEX = tertiaryIndex;
        BPT_INDEX = bptIndex;

        PRIMARY_TOKEN = IERC20(tokens[PRIMARY_INDEX]);
        SECONDARY_TOKEN = IERC20(tokens[SECONDARY_INDEX]);
        TERTIARY_TOKEN = IERC20(tokens[TERTIARY_INDEX]);

        uint256 primaryDecimals = IERC20(ILinearPool(address(PRIMARY_TOKEN)).getMainToken()).decimals();

        // Do not allow decimal places greater than 18
        require(primaryDecimals <= 18);
        PRIMARY_DECIMALS = uint8(primaryDecimals);

        // If the SECONDARY_TOKEN is ETH, it will be rewritten as WETH
        uint256 secondaryDecimals = IERC20(ILinearPool(address(SECONDARY_TOKEN)).getMainToken()).decimals();

        // Do not allow decimal places greater than 18
        require(secondaryDecimals <= 18);
        SECONDARY_DECIMALS = uint8(secondaryDecimals);
        
        // If the TERTIARY_TOKEN is ETH, it will be rewritten as WETH
        uint256 tertiaryDecimals = IERC20(ILinearPool(address(TERTIARY_TOKEN)).getMainToken()).decimals();

        // Do not allow decimal places greater than 18
        require(tertiaryDecimals <= 18);
        TERTIARY_DECIMALS = uint8(tertiaryDecimals);
    }

    function _underlyingPoolContext(ILinearPool underlyingPool) private view returns (UnderlyingPoolContext memory) {
        (uint256 lowerTarget, uint256 upperTarget) = underlyingPool.getTargets();
        uint256 mainIndex = underlyingPool.getMainIndex();
        uint256 wrappedIndex = underlyingPool.getWrappedIndex();

        (
            /* address[] memory tokens */,
            uint256[] memory underlyingBalances,
            /* uint256 lastChangeBlock */
        ) = Deployments.BALANCER_VAULT.getPoolTokens(underlyingPool.getPoolId());

        uint256[] memory underlyingScalingFactors = underlyingPool.getScalingFactors();
        // The wrapped token's scaling factor is not constant, but increases over time as the wrapped token increases in
        // value.
        uint256 wrappedScaleFactor = underlyingScalingFactors[mainIndex] * underlyingPool.getWrappedTokenRate() /
            BalancerConstants.BALANCER_PRECISION;

        return UnderlyingPoolContext({
            mainScaleFactor: underlyingScalingFactors[mainIndex],
            mainBalance: underlyingBalances[mainIndex],
            wrappedScaleFactor: wrappedScaleFactor,
            wrappedBalance: underlyingBalances[wrappedIndex],
            virtualSupply: underlyingPool.getVirtualSupply(),
            fee: underlyingPool.getSwapFeePercentage(),
            lowerTarget: lowerTarget,
            upperTarget: upperTarget    
        });
    }

    function _boostedOracleContext(uint256[] memory balances) 
        internal view returns (BoostedOracleContext memory boostedPoolContext) {
        IBoostedPool pool = IBoostedPool(address(BALANCER_POOL_TOKEN));

        (
            uint256 value,
            /* bool isUpdating */,
            uint256 precision
        ) = pool.getAmplificationParameter();
        require(precision == StableMath._AMP_PRECISION);

        boostedPoolContext = BoostedOracleContext({
            ampParam: value,
            bptBalance: balances[BPT_INDEX],
            swapFeePercentage: pool.getSwapFeePercentage(),
            underlyingPools: new UnderlyingPoolContext[](3)
        });

        boostedPoolContext.underlyingPools[0] = _underlyingPoolContext(ILinearPool(address(PRIMARY_TOKEN)));
        boostedPoolContext.underlyingPools[1] = _underlyingPoolContext(ILinearPool(address(SECONDARY_TOKEN)));
        boostedPoolContext.underlyingPools[2] = _underlyingPoolContext(ILinearPool(address(TERTIARY_TOKEN)));
    }

    function _threeTokenPoolContext(uint256[] memory balances, uint256[] memory scalingFactors) 
        internal view returns (ThreeTokenPoolContext memory) {
        return ThreeTokenPoolContext({
            tertiaryToken: address(TERTIARY_TOKEN),
            tertiaryIndex: TERTIARY_INDEX,
            tertiaryDecimals: TERTIARY_DECIMALS,
            tertiaryBalance: balances[TERTIARY_INDEX],
            tertiaryScaleFactor: scalingFactors[TERTIARY_INDEX],
            basePool: TwoTokenPoolContext({
                primaryToken: address(PRIMARY_TOKEN),
                secondaryToken: address(SECONDARY_TOKEN),
                primaryIndex: PRIMARY_INDEX,
                secondaryIndex: SECONDARY_INDEX,
                primaryDecimals: PRIMARY_DECIMALS,
                secondaryDecimals: SECONDARY_DECIMALS,
                primaryBalance: balances[PRIMARY_INDEX],
                secondaryBalance: balances[SECONDARY_INDEX],
                primaryScaleFactor: scalingFactors[PRIMARY_INDEX],
                secondaryScaleFactor: scalingFactors[SECONDARY_INDEX],
                basePool: _poolContext()
            })
        });
    }

    function _strategyContext() internal view returns (Boosted3TokenAuraStrategyContext memory) {
        (uint256[] memory balances, uint256[] memory scalingFactors) = _getBalancesAndScaleFactors();

        BoostedOracleContext memory oracleContext = _boostedOracleContext(balances);

        return Boosted3TokenAuraStrategyContext({
            poolContext: _threeTokenPoolContext(balances, scalingFactors),
            oracleContext: oracleContext,
            stakingContext: _auraStakingContext(),
            baseStrategy: _baseStrategyContext()
        });
    }

    function _getBalancesAndScaleFactors() internal view returns (uint256[] memory balances, uint256[] memory scalingFactors) {
        (
            /* address[] memory tokens */,
            balances,
            /* uint256 lastChangeBlock */
        ) = Deployments.BALANCER_VAULT.getPoolTokens(BALANCER_POOL_ID);

        scalingFactors = IBalancerPool(address(BALANCER_POOL_TOKEN)).getScalingFactors();
    }

    uint256[40] private __gap; // Storage gap for future potential upgrades
}
