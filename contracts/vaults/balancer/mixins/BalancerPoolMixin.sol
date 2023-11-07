// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {IERC20} from "../../../../interfaces/IERC20.sol";
import {StrategyContext} from "../../common/VaultTypes.sol";
import {AuraVaultDeploymentParams} from "../BalancerVaultTypes.sol";
import {Deployments} from "../../../global/Deployments.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";
import {IBalancerVault} from "../../../../interfaces/balancer/IBalancerVault.sol";
import {VaultStorage} from "../../common/VaultStorage.sol";
import {BalancerConstants} from "../internal/BalancerConstants.sol";
import {SingleSidedLPVaultBase} from "../../common/SingleSidedLPVaultBase.sol";
import {BalancerUtils} from "../internal/pool/BalancerUtils.sol";
import {TokenUtils} from "../../../utils/TokenUtils.sol";

/**
 * Base class for all Balancer LP strategies
 */
abstract contract BalancerPoolMixin is SingleSidedLPVaultBase {

    bytes32 internal immutable BALANCER_POOL_ID;
    IERC20 internal immutable BALANCER_POOL_TOKEN;

    uint256 internal immutable _NUM_TOKENS;
    uint256 internal immutable _PRIMARY_INDEX;
    uint256 internal immutable BPT_INDEX;

    /// @notice this implementation currently supports up to 5 tokens
    address internal immutable TOKEN_1;
    address internal immutable TOKEN_2;
    address internal immutable TOKEN_3;
    address internal immutable TOKEN_4;
    address internal immutable TOKEN_5;

    uint8 internal immutable DECIMALS_1;
    uint8 internal immutable DECIMALS_2;
    uint8 internal immutable DECIMALS_3;
    uint8 internal immutable DECIMALS_4;
    uint8 internal immutable DECIMALS_5;

    function NUM_TOKENS() internal pure override returns (uint256) { return _NUM_TOKENS; }
    function PRIMARY_INDEX() internal pure override returns (uint256) { return _PRIMARY_INDEX; }
    function POOL_TOKEN() internal pure override returns (IERC20) { return BALANCER_POOL_TOKEN; }
    function TOKENS() internal pure override returns (IERC20[] memory, uint8[] memory) {
        IERC20[] memory tokens = new IERC20[](_NUM_TOKENS);
        uint8[] memory decimals = new uint8[](_NUM_TOKENS);

        if (_NUM_TOKENS > 0) (tokens[0], decimals[0]) = (IERC20(TOKEN_1), DECIMALS_1);
        if (_NUM_TOKENS > 1) (tokens[1], decimals[1]) = (IERC20(TOKEN_2), DECIMALS_2);
        if (_NUM_TOKENS > 2) (tokens[2], decimals[2]) = (IERC20(TOKEN_3), DECIMALS_3);
        if (_NUM_TOKENS > 3) (tokens[3], decimals[3]) = (IERC20(TOKEN_4), DECIMALS_4);
        if (_NUM_TOKENS > 4) (tokens[4], decimals[4]) = (IERC20(TOKEN_5), DECIMALS_5);
    }

    constructor(NotionalProxy notional_, AuraVaultDeploymentParams memory params)
        SingleSidedLPVaultBase(notional_, params.baseParams.tradingModule) {
        // Returns the primary borrowed currency address
        address primaryAddress = _getNotionalUnderlyingToken(params.baseParams.primaryBorrowCurrencyId);
        primaryAddress = BalancerUtils.getTokenAddress(primaryAddress);

        BALANCER_POOL_ID = params.baseParams.balancerPoolId;
        (address pool, /* */) = Deployments.BALANCER_VAULT.getPool(params.baseParams.balancerPoolId);
        BALANCER_POOL_TOKEN = IERC20(pool);

        // Fetch all the token addresses in the pool
        (
            address[] memory tokens,
            /* uint256[] memory balances */,
            /* uint256 lastChangeBlock */
        ) = Deployments.BALANCER_VAULT.getPoolTokens(params.baseParams.balancerPoolId);

        require(tokens.length <= MAX_TOKENS);
        _NUM_TOKENS = uint8(tokens.length);

        TOKEN_1 = _NUM_TOKENS > 0 ? _rewriteWETH(tokens[0]) : address(0);
        TOKEN_2 = _NUM_TOKENS > 1 ? _rewriteWETH(tokens[1]) : address(0);
        TOKEN_3 = _NUM_TOKENS > 2 ? _rewriteWETH(tokens[2]) : address(0);
        TOKEN_4 = _NUM_TOKENS > 3 ? _rewriteWETH(tokens[3]) : address(0);
        TOKEN_5 = _NUM_TOKENS > 4 ? _rewriteWETH(tokens[4]) : address(0);

        DECIMALS_1 = _NUM_TOKENS > 0 ? TokenUtils.getDecimals(TOKEN_1) : 0;
        DECIMALS_2 = _NUM_TOKENS > 1 ? TokenUtils.getDecimals(TOKEN_2) : 0;
        DECIMALS_3 = _NUM_TOKENS > 2 ? TokenUtils.getDecimals(TOKEN_3) : 0;
        DECIMALS_4 = _NUM_TOKENS > 3 ? TokenUtils.getDecimals(TOKEN_4) : 0;
        DECIMALS_5 = _NUM_TOKENS > 4 ? TokenUtils.getDecimals(TOKEN_5) : 0;

        uint8 primaryIndex = NOT_FOUND;
        uint8 bptIndex = NOT_FOUND;
        for (uint8 i; i < tokens.length; i++) {
            if (tokens[i] == primaryAddress)  primaryIndex = i; 
            else if (tokens[i] == address(BALANCER_POOL_TOKEN)) bptIndex = i;
        }

        // Primary Index must exist for all balancer pools, but BPT_INDEX
        // will only exist for ComposableStablePools
        require(primaryIndex != NOT_FOUND);

        _PRIMARY_INDEX = primaryIndex;
        BPT_INDEX = bptIndex;
    }

    function _rewriteWETH(address token) private pure returns (address) {
        return token == address(Deployments.WETH) ? Deployments.ETH_ADDRESS : address(token);
    }

    /// @notice the re-entrancy context is checked during liquidation
    function _checkReentrancyContext() internal override {
        IBalancerVault.UserBalanceOp[] memory noop = new IBalancerVault.UserBalanceOp[](0);
        Deployments.BALANCER_VAULT.manageUserBalance(noop);
    }

    /// @notice returns the base strategy context
    function _baseStrategyContext() internal view override returns (StrategyContext memory) {
        return StrategyContext({
            tradingModule: TRADING_MODULE,
            vaultSettings: VaultStorage.getStrategyVaultSettings(),
            vaultState: VaultStorage.getStrategyVaultState(),
            poolClaimPrecision: BalancerConstants.BALANCER_PRECISION,
            canUseStaticSlippage: _canUseStaticSlippage()
        });
    }

    uint256[40] private __gap; // Storage gap for future potential upgrades
}
