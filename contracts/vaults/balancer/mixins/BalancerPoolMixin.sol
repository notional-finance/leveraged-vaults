// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {IERC20} from "@interfaces/IERC20.sol";
import {Deployments} from "@deployments/Deployments.sol";
import {NotionalProxy} from "@interfaces/notional/NotionalProxy.sol";
import {IBalancerVault, IAsset} from "@interfaces/balancer/IBalancerVault.sol";
import {IBalancerPool} from "@interfaces/balancer/IBalancerPool.sol";
import {SingleSidedLPVaultBase} from "../../common/SingleSidedLPVaultBase.sol";
import {TokenUtils} from "@contracts/utils/TokenUtils.sol";
import {ITradingModule} from "@interfaces/trading/ITradingModule.sol";

/// @notice Deployment parameters
struct DeploymentParams {
    /// @notice primary currency id
    uint16 primaryBorrowCurrencyId;
    /// @notice balancer pool ID
    bytes32 balancerPoolId;
    /// @notice trading module proxy
    ITradingModule tradingModule;
}

/** Base class for all Balancer LP strategies */
abstract contract BalancerPoolMixin is SingleSidedLPVaultBase {

    uint256 internal constant BALANCER_PRECISION = 1e18;

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

    function NUM_TOKENS() internal view override returns (uint256) { return _NUM_TOKENS; }
    function PRIMARY_INDEX() internal view override returns (uint256) { return _PRIMARY_INDEX; }
    function POOL_TOKEN() internal view override returns (IERC20) { return BALANCER_POOL_TOKEN; }
    function POOL_PRECISION() internal pure override returns (uint256) { return BALANCER_PRECISION; }
    function TOKENS() public view virtual override returns (IERC20[] memory, uint8[] memory) {
        IERC20[] memory tokens = new IERC20[](_NUM_TOKENS);
        uint8[] memory decimals = new uint8[](_NUM_TOKENS);

        if (_NUM_TOKENS > 0) (tokens[0], decimals[0]) = (IERC20(TOKEN_1), DECIMALS_1);
        if (_NUM_TOKENS > 1) (tokens[1], decimals[1]) = (IERC20(TOKEN_2), DECIMALS_2);
        if (_NUM_TOKENS > 2) (tokens[2], decimals[2]) = (IERC20(TOKEN_3), DECIMALS_3);
        if (_NUM_TOKENS > 3) (tokens[3], decimals[3]) = (IERC20(TOKEN_4), DECIMALS_4);
        if (_NUM_TOKENS > 4) (tokens[4], decimals[4]) = (IERC20(TOKEN_5), DECIMALS_5);

        return (tokens, decimals);
    }

    /// @notice Used to get type compatibility with the Balancer join and exit methods.
    function ASSETS() internal virtual view returns (IAsset[] memory) {
        IAsset[] memory assets = new IAsset[](_NUM_TOKENS);
        if (_NUM_TOKENS > 0) assets[0] = IAsset(TOKEN_1);
        if (_NUM_TOKENS > 1) assets[1] = IAsset(TOKEN_2);
        if (_NUM_TOKENS > 2) assets[2] = IAsset(TOKEN_3);
        if (_NUM_TOKENS > 3) assets[3] = IAsset(TOKEN_4);
        if (_NUM_TOKENS > 4) assets[4] = IAsset(TOKEN_5);
        return assets;
    }

    constructor(NotionalProxy notional_, DeploymentParams memory params)
        SingleSidedLPVaultBase(notional_, params.tradingModule) {

        BALANCER_POOL_ID = params.balancerPoolId;
        (address pool, /* */) = Deployments.BALANCER_VAULT.getPool(params.balancerPoolId);
        BALANCER_POOL_TOKEN = IERC20(pool);

        // Fetch all the token addresses in the pool
        (
            address[] memory tokens,
            /* uint256[] memory balances */,
            /* uint256 lastChangeBlock */
        ) = Deployments.BALANCER_VAULT.getPoolTokens(params.balancerPoolId);

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

        // Returns the primary borrowed currency address
        address primaryAddress = _getNotionalUnderlyingToken(params.primaryBorrowCurrencyId);
        if (primaryAddress == Deployments.ETH_ADDRESS) {
            // Balancer uses WETH when calling `getPoolTokens` so rewrite it here to
            // when we match on the primary index later.
            primaryAddress = address(Deployments.WETH);
        }

        uint8 primaryIndex = NOT_FOUND;
        uint8 bptIndex = NOT_FOUND;
        for (uint8 i; i < tokens.length; i++) {
            if (tokens[i] == primaryAddress) primaryIndex = i; 
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

    // Checks if a token in the pool is a BPT. Used in cases where a BPT is one of the
    // tokens within the pool (not the self BPT in the case of the Composable Stable Pool).
    function _isBPT(address token) internal view returns (bool) {
        // Need to check for zero address since this breaks the try / catch
        if (token == address(0)) return false;

        try IBalancerPool(token).getPoolId() returns (bytes32 /* poolId */) {
            return true;
        } catch {
            return false;
        }
    }

    /// @notice the re-entrancy context is checked during liquidation to prevent read-only
    /// reentrancy on all balancer pools.
    function _checkReentrancyContext() internal override {
        IBalancerVault.UserBalanceOp[] memory noop = new IBalancerVault.UserBalanceOp[](0);
        Deployments.BALANCER_VAULT.manageUserBalance(noop);
    }

    /// @notice Joins a balancer pool using the supplied amounts of tokens
    function _joinPoolExactTokensIn(
        uint256[] memory amounts,
        bytes memory customData
    ) internal returns (uint256 bptAmount) {
        uint256 msgValue;
        IAsset[] memory assets = ASSETS();
        require(assets.length == amounts.length);
        for (uint256 i; i < assets.length; i++) {
            // Sets the msgValue of transferring ETH
            if (address(assets[i]) == Deployments.ETH_ADDRESS) {
                msgValue = amounts[i];
                break;
            }
        }

        bptAmount = BALANCER_POOL_TOKEN.balanceOf(address(this));
        Deployments.BALANCER_VAULT.joinPool{value: msgValue}(
            BALANCER_POOL_ID,
            address(this), // sender
            address(this), //  Vault will receive the pool tokens
            IBalancerVault.JoinPoolRequest(
                ASSETS(),
                amounts,
                customData,
                false // Don't use internal balances
            )
        );

        // Calculate the amount of BPT minted
        bptAmount = BALANCER_POOL_TOKEN.balanceOf(address(this)) - bptAmount;
    }

    /// @notice Exits a balancer pool using exact BPT in
    function _exitPoolExactBPTIn(
        uint256[] memory amounts,
        bytes memory customData
    ) internal returns (uint256[] memory exitBalances) {
        // For composable pools, the asset array includes the BPT token (i.e. poolToken). The balance
        // will decrease in an exit while all of the other balances increase, causing a subtraction
        // underflow in the final loop. For that reason, exit balances are not calculated of the poolToken
        // is included in the array of assets.
        exitBalances = new uint256[](_NUM_TOKENS);
        IAsset[] memory assets = ASSETS();

        for (uint256 i; i < _NUM_TOKENS; i++) {
            if (address(assets[i]) == address(BALANCER_POOL_TOKEN)) continue;
            exitBalances[i] = TokenUtils.tokenBalance(address(assets[i]));
        }

        Deployments.BALANCER_VAULT.exitPool(
            BALANCER_POOL_ID,
            address(this), // sender
            payable(address(this)), // Vault will receive the underlying assets
            IBalancerVault.ExitPoolRequest(
                assets,
                amounts,
                customData,
                false // Don't use internal balances
            )
        );

        // Calculate the amounts of underlying tokens after the exit
        for (uint256 i; i < _NUM_TOKENS; i++) {
            if (address(assets[i]) == address(BALANCER_POOL_TOKEN)) continue;
            uint256 balanceAfter = TokenUtils.tokenBalance(address(assets[i]));
            exitBalances[i] = balanceAfter - exitBalances[i];
        }
    }

    uint256[40] private __gap; // Storage gap for future potential upgrades
}