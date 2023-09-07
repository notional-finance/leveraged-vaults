// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {
    UnderlyingPoolContext,
    AuraVaultDeploymentParams,
    BalancerComposablePoolContext,
    BalancerComposableAuraStrategyContext,
    AuraStakingContext
} from "../BalancerVaultTypes.sol";
import {
    StrategyContext, 
    ComposablePoolContext
} from "../../common/VaultTypes.sol";
import {Constants} from "../../../global/Constants.sol";
import {TypeConvert} from "../../../global/TypeConvert.sol";
import {IERC20} from "../../../../interfaces/IERC20.sol";
import {ISingleSidedLPStrategyVault} from "../../../../interfaces/notional/IStrategyVault.sol";
import {BalancerConstants} from "../internal/BalancerConstants.sol";
import {IBalancerPool, IBoostedPool, ILinearPool} from "../../../../interfaces/balancer/IBalancerPool.sol";
import {BalancerUtils} from "../internal/pool/BalancerUtils.sol";
import {Deployments} from "../../../global/Deployments.sol";
import {BalancerPoolMixin} from "./BalancerPoolMixin.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";
import {StableMath} from "../internal/math/StableMath.sol";

abstract contract Balancer3TokenPoolMixin is BalancerPoolMixin, ISingleSidedLPStrategyVault {
    using TypeConvert for uint256;

    error InvalidPrimaryToken(address token);

    uint8 internal constant NOT_FOUND = type(uint8).max;

    address internal immutable PRIMARY_TOKEN;
    address internal immutable SECONDARY_TOKEN;
    address internal immutable TERTIARY_TOKEN;
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
    ) BalancerPoolMixin(notional_, params) {
        address primaryAddress = BalancerUtils.getTokenAddress(
            _getNotionalUnderlyingToken(params.baseParams.primaryBorrowCurrencyId)
        );
        
        if (address(notional_) != address(0)) {
            revert("here");
        }

        // prettier-ignore
        (
            address[] memory tokens,
            /* uint256[] memory balances */,
            /* uint256 lastChangeBlock */
        ) = Deployments.BALANCER_VAULT.getPoolTokens(params.baseParams.balancerPoolId);

        // Boosted pools contain 4 tokens (3 tokens + 1 LP token)
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

        PRIMARY_TOKEN = tokens[PRIMARY_INDEX];
        SECONDARY_TOKEN = tokens[SECONDARY_INDEX];
        TERTIARY_TOKEN = tokens[TERTIARY_INDEX];

        uint256 primaryDecimals = IERC20(ILinearPool(PRIMARY_TOKEN).getMainToken()).decimals();

        // Do not allow decimal places greater than 18
        require(primaryDecimals <= 18);
        PRIMARY_DECIMALS = uint8(primaryDecimals);

        // If the SECONDARY_TOKEN is ETH, it will be rewritten as WETH
        uint256 secondaryDecimals = IERC20(ILinearPool(SECONDARY_TOKEN).getMainToken()).decimals();

        // Do not allow decimal places greater than 18
        require(secondaryDecimals <= 18);
        SECONDARY_DECIMALS = uint8(secondaryDecimals);
        
        // If the TERTIARY_TOKEN is ETH, it will be rewritten as WETH
        uint256 tertiaryDecimals = IERC20(ILinearPool(TERTIARY_TOKEN).getMainToken()).decimals();

        // Do not allow decimal places greater than 18
        require(tertiaryDecimals <= 18);
        TERTIARY_DECIMALS = uint8(tertiaryDecimals);
    }

    function _composablePoolContext() 
        internal view returns (BalancerComposablePoolContext memory) {
        address[] memory tokens = new address[](3);
        uint8[] memory indices = new uint8[](3);
        uint256[] memory balances = new uint256[](3);

        indices[0] = PRIMARY_INDEX;
        indices[1] = SECONDARY_INDEX;
        indices[2] = TERTIARY_INDEX;

        return BalancerComposablePoolContext({
            basePool: ComposablePoolContext({
                tokens: tokens,
                indices: indices,
                balances: balances,
                poolToken: BALANCER_POOL_TOKEN
            }),
            poolId: BALANCER_POOL_ID
        });
    }

    function _strategyContext() internal view returns (BalancerComposableAuraStrategyContext memory) {
        return BalancerComposableAuraStrategyContext({
            poolContext: _composablePoolContext(),
            stakingContext: _auraStakingContext(),
            baseStrategy: _baseStrategyContext()
        });
    }

    function getExchangeRate(uint256 /* maturity */) public view override returns (int256) {
    }

    function getStrategyVaultInfo() public view override returns (SingleSidedLPStrategyVaultInfo memory) {
        StrategyContext memory context = _baseStrategyContext();
        return SingleSidedLPStrategyVaultInfo({
            pool: address(BALANCER_POOL_TOKEN),
            singleSidedTokenIndex: PRIMARY_INDEX,
            totalLPTokens: context.vaultState.totalPoolClaim,
            totalVaultShares: context.vaultState.totalVaultSharesGlobal
        });
    }

    uint256[40] private __gap; // Storage gap for future potential upgrades
}
