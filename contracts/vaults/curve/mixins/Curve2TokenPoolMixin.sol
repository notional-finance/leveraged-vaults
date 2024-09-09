// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {TokenUtils, IERC20} from "@contracts/utils/TokenUtils.sol";
import {IERC20} from "@interfaces/IERC20.sol";
import {Deployments} from "@deployments/Deployments.sol";
import {Constants} from "@contracts/global/Constants.sol";
import {TokenUtils} from "@contracts/utils/TokenUtils.sol";
import {SingleSidedLPVaultBase} from "@contracts/vaults/common/SingleSidedLPVaultBase.sol";
import {NotionalProxy} from "@interfaces/notional/NotionalProxy.sol";
import {
    CurveInterface,
    ICurvePool,
    ICurvePoolV1,
    ICurvePoolV2,
    ICurve2TokenPoolV1,
    ICurve2TokenPoolV2,
    ICurveStableSwapNG
} from "@interfaces/curve/ICurvePool.sol";
import {ITradingModule} from "@interfaces/trading/ITradingModule.sol";
import {ICurveGauge} from "@interfaces/curve/ICurveGauge.sol";
import {RewardPoolStorage, RewardPoolType} from "@contracts/vaults/common/VaultStorage.sol";


interface Minter {
    function mint(address gauge) external;
}

struct DeploymentParams {
    uint16 primaryBorrowCurrencyId;
    address pool;
    ITradingModule tradingModule;
    address poolToken;
    address gauge;
    CurveInterface curveInterface;
    address whitelistedReward;
}

abstract contract Curve2TokenPoolMixin is SingleSidedLPVaultBase {
    using TokenUtils for IERC20;
    uint256 internal constant _NUM_TOKENS = 2;
    uint256 internal constant CURVE_PRECISION = 1e18;

    address internal immutable CURVE_POOL;
    address internal immutable CURVE_GAUGE;
    IERC20 internal immutable CURVE_POOL_TOKEN;
    CurveInterface internal immutable CURVE_INTERFACE;

    uint8 internal immutable _PRIMARY_INDEX;
    uint8 internal immutable SECONDARY_INDEX;
    address internal immutable TOKEN_1;
    address internal immutable TOKEN_2;
    uint8 internal immutable DECIMALS_1;
    uint8 internal immutable DECIMALS_2;
    uint8 internal immutable PRIMARY_DECIMALS;
    uint8 internal immutable SECONDARY_DECIMALS;

    address immutable WHITELISTED_REWARD;

    function NUM_TOKENS() internal pure override returns (uint256) { return _NUM_TOKENS; }
    function PRIMARY_INDEX() internal view override returns (uint256) { return _PRIMARY_INDEX; }
    function POOL_TOKEN() internal view override returns (IERC20) { return CURVE_POOL_TOKEN; }
    function POOL_PRECISION() internal pure override returns (uint256) { return CURVE_PRECISION; }
    function TOKENS() public view override returns (IERC20[] memory, uint8[] memory) {
        IERC20[] memory tokens = new IERC20[](_NUM_TOKENS);
        uint8[] memory decimals = new uint8[](_NUM_TOKENS);

        (tokens[0], decimals[0]) = (IERC20(TOKEN_1), DECIMALS_1);
        (tokens[1], decimals[1]) = (IERC20(TOKEN_2), DECIMALS_2);

        return (tokens, decimals);
    }

    constructor(
        NotionalProxy notional_,
        DeploymentParams memory params
    ) SingleSidedLPVaultBase(notional_, params.tradingModule) {
        CURVE_POOL = params.pool;
        CURVE_GAUGE = params.gauge;
        CURVE_INTERFACE = params.curveInterface;
        CURVE_POOL_TOKEN = IERC20(params.poolToken);

        address primaryToken = _getNotionalUnderlyingToken(params.primaryBorrowCurrencyId);

        // We interact with curve pools directly so we never pass the token addresses back
        // to the curve pools. The amounts are passed back based on indexes instead. Therefore
        // we can rewrite the token addresses from ALT Eth (0xeeee...) back to (0x0000...) which
        // is used by the vault internally to represent ETH.
        TOKEN_1 = _rewriteAltETH(ICurvePool(CURVE_POOL).coins(0));
        TOKEN_2 = _rewriteAltETH(ICurvePool(CURVE_POOL).coins(1));
        _PRIMARY_INDEX = TOKEN_1 == primaryToken ? 0 : 1;
        SECONDARY_INDEX = 1 - _PRIMARY_INDEX;
        
        DECIMALS_1 = TokenUtils.getDecimals(TOKEN_1);
        DECIMALS_2 = TokenUtils.getDecimals(TOKEN_2);
        PRIMARY_DECIMALS = _PRIMARY_INDEX == 0 ? DECIMALS_1 : DECIMALS_2;
        SECONDARY_DECIMALS = _PRIMARY_INDEX == 0 ? DECIMALS_2 : DECIMALS_1;

        // Allows one of the pool tokens to be whitelisted as a reward token to be re-entered
        // back into the pool to increase LP shares.
        WHITELISTED_REWARD = params.whitelistedReward;
    }

    function _rewriteAltETH(address token) private pure returns (address) {
        return token == address(Deployments.ALT_ETH_ADDRESS) ? Deployments.ETH_ADDRESS : address(token);
    }

    function _checkReentrancyContext() internal override {
        uint256[2] memory minAmounts;
        if (CURVE_INTERFACE == CurveInterface.V1) {
            ICurve2TokenPoolV1(CURVE_POOL).remove_liquidity(0, minAmounts);
        } else if (CURVE_INTERFACE == CurveInterface.StableSwapNG) {
            // Total supply on stable swap has a non-reentrant lock
            ICurveStableSwapNG(CURVE_POOL).totalSupply();
        } else if (CURVE_INTERFACE == CurveInterface.V2) {
            // Curve V2 does a `-1` on the liquidity amount so set the amount removed to 1 to
            // avoid an underflow.
            ICurve2TokenPoolV2(CURVE_POOL).remove_liquidity(1, minAmounts, true, address(this));
        } else {
            revert();
        }
    }

    function _stakeLpTokens(uint256 lpTokens) internal virtual {
        ICurveGauge(CURVE_GAUGE).deposit(lpTokens);
    }

    function _joinPoolAndStake(
        uint256[] memory _amounts, uint256 minPoolClaim
    ) internal override returns (uint256 lpTokens) {
        // Only two tokens are ever allowed in this strategy, remaps the array
        // into a fixed length array here.
        uint256[2] memory amounts;
        amounts[0] = _amounts[0];
        amounts[1] = _amounts[1];

        // Although Curve uses ALT_ETH to represent native ETH, it is rewritten in the Curve2TokenPoolMixin
        // to the Deployments.ETH_ADDRESS which we use internally.
        (IERC20[] memory tokens, /* */) = TOKENS();
        uint256 msgValue;
        if (address(tokens[0]) == Deployments.ETH_ADDRESS) {
            msgValue = amounts[0];
        } else if (address(tokens[1]) == Deployments.ETH_ADDRESS) {
            msgValue = amounts[1];
        }

        // Slightly different method signatures in v1 and v2
        if (CURVE_INTERFACE == CurveInterface.V1) {
            lpTokens = ICurve2TokenPoolV1(CURVE_POOL).add_liquidity{value: msgValue}(
                amounts, minPoolClaim
            );
        } else if (CURVE_INTERFACE == CurveInterface.V2) {
            lpTokens = ICurve2TokenPoolV2(CURVE_POOL).add_liquidity{value: msgValue}(
                amounts, minPoolClaim, 0 < msgValue // use_eth = true if msgValue > 0
            );
        } else if (CURVE_INTERFACE == CurveInterface.StableSwapNG) {
            // StableSwapNG uses dynamic arrays
            lpTokens = ICurveStableSwapNG(CURVE_POOL).add_liquidity{value: msgValue}(
                _amounts, minPoolClaim
            );
        } else {
            revert();
        }

        _stakeLpTokens(lpTokens);
    }

    function _unstakeLpTokens(uint256 poolClaim) internal virtual {
        ICurveGauge(CURVE_GAUGE).withdraw(poolClaim);
    }

    function _unstakeAndExitPool(
        uint256 poolClaim, uint256[] memory _minAmounts, bool isSingleSided
    ) internal override returns (uint256[] memory exitBalances) {
        _unstakeLpTokens(poolClaim);

        exitBalances = new uint256[](2);
        if (isSingleSided) {
            // Redeem single-sided
            if (CURVE_INTERFACE == CurveInterface.V1 || CURVE_INTERFACE == CurveInterface.StableSwapNG) {
                // Method signature is the same for v1 and stable swap ng
                exitBalances[_PRIMARY_INDEX] = ICurve2TokenPoolV1(CURVE_POOL).remove_liquidity_one_coin(
                    poolClaim, int8(_PRIMARY_INDEX), _minAmounts[_PRIMARY_INDEX]
                );
            } else if (CURVE_INTERFACE == CurveInterface.V2) {
                exitBalances[_PRIMARY_INDEX] = ICurve2TokenPoolV2(CURVE_POOL).remove_liquidity_one_coin(
                    // Last two parameters are useEth = true and receiver = this contract
                    poolClaim, _PRIMARY_INDEX, _minAmounts[_PRIMARY_INDEX], true, address(this)
                );
            } else {
                revert();
            }
        } else {
            // Redeem proportionally, min amounts are rewritten to a fixed length array
            uint256[2] memory minAmounts;
            minAmounts[0] = _minAmounts[0];
            minAmounts[1] = _minAmounts[1];

            if (CURVE_INTERFACE == CurveInterface.V1) {
                uint256[2] memory _exitBalances = ICurve2TokenPoolV1(CURVE_POOL).remove_liquidity(poolClaim, minAmounts);
                exitBalances[0] = _exitBalances[0];
                exitBalances[1] = _exitBalances[1];
            } else if (CURVE_INTERFACE == CurveInterface.V2) {
                exitBalances[0] = TokenUtils.tokenBalance(TOKEN_1);
                exitBalances[1] = TokenUtils.tokenBalance(TOKEN_2);
                // Remove liquidity on CurveV2 does not return the exit amounts so we have to measure
                // them before and after.
                ICurve2TokenPoolV2(CURVE_POOL).remove_liquidity(
                    // Last two parameters are useEth = true and receiver = this contract
                    poolClaim, minAmounts, true, address(this)
                );
                exitBalances[0] = TokenUtils.tokenBalance(TOKEN_1) - exitBalances[0];
                exitBalances[1] = TokenUtils.tokenBalance(TOKEN_2) - exitBalances[1];
            } else if (CURVE_INTERFACE == CurveInterface.StableSwapNG) {
                exitBalances = ICurveStableSwapNG(CURVE_POOL).remove_liquidity(poolClaim, _minAmounts);
            } else {
                revert();
            }
        }
    }

    function _checkPriceAndCalculateValue() internal view override returns (uint256 oneLPValueInPrimary) {
        uint256[] memory balances = new uint256[](2);
        balances[0] = ICurvePool(CURVE_POOL).balances(0);
        balances[1] = ICurvePool(CURVE_POOL).balances(1);

        // The primary index spot price is left as zero.
        uint256[] memory spotPrices = new uint256[](2);
        uint256 primaryPrecision = 10 ** PRIMARY_DECIMALS;
        uint256 secondaryPrecision = 10 ** SECONDARY_DECIMALS;

        // `get_dy` returns the price of one unit of the primary token
        // converted to the secondary token. The spot price is in secondary
        // precision and then we convert it to POOL_PRECISION.
        spotPrices[SECONDARY_INDEX] = ICurvePool(CURVE_POOL).get_dy(
            int8(_PRIMARY_INDEX), int8(SECONDARY_INDEX), primaryPrecision
        ) * POOL_PRECISION() / secondaryPrecision;

        return _calculateLPTokenValue(balances, spotPrices);
    }

    function _initialApproveTokens() internal override virtual {
        // If either token is Deployments.ETH_ADDRESS the check approve will short circuit
        IERC20(TOKEN_1).checkApprove(address(CURVE_POOL), type(uint256).max);
        IERC20(TOKEN_2).checkApprove(address(CURVE_POOL), type(uint256).max);
        CURVE_POOL_TOKEN.checkApprove(address(CURVE_GAUGE), type(uint256).max);
    }

    function _isInvalidRewardToken(address token) internal override virtual view returns (bool) {
        if (WHITELISTED_REWARD != address(0) && token == WHITELISTED_REWARD) return false;

        return (
            token == TOKEN_1 ||
            token == TOKEN_2 ||
            token == address(CURVE_GAUGE) ||
            token == address(CURVE_POOL_TOKEN) ||
            token == address(Deployments.ETH_ADDRESS) ||
            token == address(Deployments.WETH)
        );
    }

    function _rewardPoolStorage() internal view override virtual returns (RewardPoolStorage memory r) {
        r.rewardPool = address(0);
        r.poolType = RewardPoolType._UNUSED;
    }
}