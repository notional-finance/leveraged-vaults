// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {
    ConvexVaultDeploymentParams, 
    InitParams, 
    StrategyContext,
    StrategyVaultState,
    Curve2TokenConvexStrategyContext
} from "./curve/CurveVaultTypes.sol";
import {Constants} from "../global/Constants.sol";
import {TypeConvert} from "../global/TypeConvert.sol";
import {Deployments} from "../global/Deployments.sol";
import {TokenUtils, IERC20} from "../utils/TokenUtils.sol";
import {Curve2TokenVaultMixin} from "./curve/mixins/Curve2TokenVaultMixin.sol";
import {CurveVaultStorage} from "./curve/internal/CurveVaultStorage.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {CurveStrategyUtils} from "./curve/internal/strategy/CurveStrategyUtils.sol";
import {ICurve2TokenPool} from "../../interfaces/curve/ICurvePool.sol";

contract Curve2TokenConvexVault is Curve2TokenVaultMixin {
    using TypeConvert for uint256;
    using TypeConvert for int256;
    using TokenUtils for IERC20;
    using CurveVaultStorage for StrategyVaultState;

    constructor(NotionalProxy notional_, ConvexVaultDeploymentParams memory params) Curve2TokenVaultMixin(notional_, params) {
    }

    function strategy() external override view returns (bytes4) {
        return bytes4(keccak256("Curve2TokenConvexVault"));
    }

    function initialize(InitParams calldata params)
        external
        initializer
        onlyNotionalOwner
    {
        __INIT_VAULT(params.name, params.borrowCurrencyId);
        CurveVaultStorage.setStrategyVaultSettings(params.settings);

        if (PRIMARY_TOKEN != Deployments.ALT_ETH_ADDRESS) {
            IERC20(PRIMARY_TOKEN).checkApprove(address(CURVE_POOL), type(uint256).max);
        }
        if (SECONDARY_TOKEN != Deployments.ALT_ETH_ADDRESS) {
            IERC20(SECONDARY_TOKEN).checkApprove(address(CURVE_POOL), type(uint256).max);
        }

        CURVE_POOL_TOKEN.checkApprove(address(CONVEX_BOOSTER), type(uint256).max);
    }

    function _depositFromNotional(
        address /* account */,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 strategyTokensMinted) {
        Curve2TokenConvexStrategyContext memory context = _strategyContext();
        uint256[2] memory amounts;
        uint256 msgValue;
        amounts[PRIMARY_INDEX] = deposit;
        if (PRIMARY_TOKEN == Deployments.ALT_ETH_ADDRESS) {
            msgValue = deposit;
        }
        uint256 poolClaim = ICurve2TokenPool(address(CURVE_POOL)).add_liquidity{value: msgValue}(amounts, 0);
        strategyTokensMinted = CurveStrategyUtils._convertPoolClaimToStrategyTokens(context.baseStrategy, poolClaim);

        bool success = CONVEX_BOOSTER.deposit(CONVEX_POOL_ID, poolClaim, true); // stake = true
        require(success);

        context.baseStrategy.vaultState.totalStrategyTokenGlobal += strategyTokensMinted;
        context.baseStrategy.vaultState.totalPoolClaim += CONVEX_REWARD_POOL.balanceOf(address(this));
        context.baseStrategy.vaultState.setStrategyVaultState();
    }

    function _redeemFromNotional(
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 finalPrimaryBalance) {

    }   

    function convertStrategyToUnderlying(
        address account,
        uint256 strategyTokenAmount,
        uint256 maturity
    ) public view virtual override returns (int256 underlyingValue) {
        // Validate spot price against oracle price
        // Always get spot price as PRIMARY/SECONDARY
        uint256 spotPrice = _getSpotPrice(0);
        (int256 answer, int256 decimals) = TRADING_MODULE.getOraclePrice(
            PRIMARY_TOKEN == Deployments.ALT_ETH_ADDRESS ? Deployments.ETH_ADDRESS : PRIMARY_TOKEN,
            SECONDARY_TOKEN == Deployments.ALT_ETH_ADDRESS ? Deployments.ETH_ADDRESS : SECONDARY_TOKEN
        );
        uint256 oraclePrice = answer.toUint();
        uint256 oraclePrecision = decimals.toUint();

        Curve2TokenConvexStrategyContext memory context = _strategyContext();
        uint256 poolClaim = CurveStrategyUtils._convertStrategyTokensToPoolClaim(context.baseStrategy, strategyTokenAmount);
        uint256 totalSupply = CURVE_POOL_TOKEN.totalSupply();

        // TODO: handle precision
        uint256 primaryPrecision = 10**context.poolContext.primaryDecimals;
        uint256 secondaryPrecision = 10**context.poolContext.secondaryDecimals;
        uint256 primaryAmount = context.poolContext.primaryBalance * poolClaim / totalSupply;
        uint256 secondaryAmount = context.poolContext.secondaryBalance * poolClaim / totalSupply;

        underlyingValue = (primaryAmount + secondaryAmount * oraclePrice / oraclePrecision).toInt();

        underlyingValue = 5e18;
    } 

    function _getSpotPrice(uint256 tokenIndex) internal view returns (uint256 spotPrice) {
        require(tokenIndex < 2);
        if (tokenIndex == 0) {
            spotPrice = CURVE_POOL.get_dy(int8(PRIMARY_INDEX), int8(SECONDARY_INDEX), 10**PRIMARY_DECIMALS);
        } else {
            spotPrice = CURVE_POOL.get_dy(int8(SECONDARY_INDEX), int8(PRIMARY_INDEX), 10**SECONDARY_DECIMALS);
        }
    }

    function getSpotPrice(uint256 tokenIndex) external view returns (uint256 spotPrice) {
        spotPrice = _getSpotPrice(tokenIndex);
    }

    function getStrategyContext() external view returns (Curve2TokenConvexStrategyContext memory) {
        return _strategyContext();
    }
}
