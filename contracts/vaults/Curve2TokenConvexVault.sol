// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {
    ConvexVaultDeploymentParams, 
    InitParams, 
    DepositParams,
    ReinvestRewardParams,
    TwoTokenRedeemParams,
    Curve2TokenPoolContext,
    Curve2TokenConvexStrategyContext
} from "./curve/CurveVaultTypes.sol";
import {
    StrategyContext,
    StrategyVaultState
} from "./common/VaultTypes.sol";
import {Constants} from "../global/Constants.sol";
import {TypeConvert} from "../global/TypeConvert.sol";
import {Deployments} from "../global/Deployments.sol";
import {TokenUtils, IERC20} from "../utils/TokenUtils.sol";
import {Curve2TokenVaultMixin} from "./curve/mixins/Curve2TokenVaultMixin.sol";
import {CurveVaultStorage} from "./curve/internal/CurveVaultStorage.sol";
import {Curve2TokenPoolUtils} from "./curve/internal/pool/Curve2TokenPoolUtils.sol";
import {Curve2TokenConvexHelper} from "./curve/external/Curve2TokenConvexHelper.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {StrategyUtils} from "./common/internal/strategy/StrategyUtils.sol";

contract Curve2TokenConvexVault is Curve2TokenVaultMixin {
    using TypeConvert for uint256;
    using TypeConvert for int256;
    using TokenUtils for IERC20;
    using CurveVaultStorage for StrategyVaultState;
    using Curve2TokenPoolUtils for Curve2TokenPoolContext;
    using Curve2TokenConvexHelper for Curve2TokenConvexStrategyContext;

    constructor(NotionalProxy notional_, ConvexVaultDeploymentParams memory params) 
        Curve2TokenVaultMixin(notional_, params) {}

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
        strategyTokensMinted = _strategyContext().deposit(deposit, data);
    }

    function _redeemFromNotional(
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 finalPrimaryBalance) {
        /*Curve2TokenConvexStrategyContext memory context = _strategyContext();
        uint256 poolClaim = StrategyUtils._convertStrategyTokensToPoolClaim(context.baseStrategy, strategyTokens);

        bool success = CONVEX_REWARD_POOL.withdrawAndUnwrap(poolClaim, false); // claim = false
        require(success);

        TwoTokenRedeemParams memory params = abi.decode(data, (TwoTokenRedeemParams));

        if (params.redeemSingleSided) {
            finalPrimaryBalance = ICurve2TokenPool(address(CURVE_POOL)).remove_liquidity_one_coin(
                poolClaim, int8(PRIMARY_INDEX), params.minPrimary
            );
        } else {
            uint256[2] memory minAmounts;
            minAmounts[PRIMARY_INDEX] = params.minPrimary;
            minAmounts[SECONDARY_INDEX] = params.minSecondary;
            ICurve2TokenPool(address(CURVE_POOL)).remove_liquidity(poolClaim, minAmounts);

            // TODO: sell secondary for primary
        }

        context.baseStrategy.vaultState.totalStrategyTokenGlobal -= strategyTokens.toUint80();
        context.baseStrategy.vaultState.totalPoolClaim = CONVEX_REWARD_POOL.balanceOf(address(this));
        context.baseStrategy.vaultState.setStrategyVaultState(); */
    }   

    function reinvestReward(ReinvestRewardParams calldata params) 
        external onlyRole(REWARD_REINVESTMENT_ROLE) {
        
    }

    function convertStrategyToUnderlying(
        address account,
        uint256 strategyTokenAmount,
        uint256 maturity
    ) public view virtual override returns (int256 underlyingValue) {
        Curve2TokenConvexStrategyContext memory context = _strategyContext();
        underlyingValue = context.poolContext._convertStrategyToUnderlying({
            strategyContext: context.baseStrategy,
            strategyTokenAmount: strategyTokenAmount
        });
    } 

    function getSpotPrice(uint256 tokenIndex) external view returns (uint256 spotPrice) {
        Curve2TokenConvexStrategyContext memory context = _strategyContext();
        spotPrice = context.poolContext._getSpotPrice(tokenIndex);
    }

    function getStrategyContext() external view returns (Curve2TokenConvexStrategyContext memory) {
        return _strategyContext();
    }
}
