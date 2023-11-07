// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {
    ConvexVaultDeploymentParams, 
    Curve2TokenPoolContext,
    Curve2TokenConvexStrategyContext
} from "./curve/CurveVaultTypes.sol";
import {
    StrategyContext,
    StrategyVaultState,
    RedeemParams,
    DepositParams,
    TradeParams
} from "./common/VaultTypes.sol";
import {Constants} from "../global/Constants.sol";
import {VaultEvents} from "./common/VaultEvents.sol";
import {VaultStorage} from "./common/VaultStorage.sol";
import {Errors} from "../global/Errors.sol";
import {Constants} from "../global/Constants.sol";
import {TypeConvert} from "../global/TypeConvert.sol";
import {TokenUtils, IERC20} from "../utils/TokenUtils.sol";
import {ConvexStakingMixin} from "./curve/mixins/ConvexStakingMixin.sol";
import {Curve2TokenPoolUtils} from "./curve/internal/pool/Curve2TokenPoolUtils.sol";
import {Curve2TokenConvexHelper} from "./curve/external/Curve2TokenConvexHelper.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {StrategyUtils} from "./common/internal/strategy/StrategyUtils.sol";

contract Curve2TokenConvexVault is ConvexStakingMixin {
    using TypeConvert for uint256;
    using TypeConvert for int256;
    using TokenUtils for IERC20;
    using VaultStorage for StrategyVaultState;
    using Curve2TokenPoolUtils for Curve2TokenPoolContext;
    using Curve2TokenConvexHelper for Curve2TokenConvexStrategyContext;

    constructor(NotionalProxy notional_, ConvexVaultDeploymentParams memory params) 
        ConvexStakingMixin(notional_, params) {}

    function strategy() external override pure returns (bytes4) {
        return bytes4(keccak256("Curve2TokenConvexVault"));
    }

    function _joinPoolAndStake(
        uint256[] memory amounts, uint256 minPoolClaim
    ) internal override returns (uint256 lpTokens) {
    }

    function _unstakeAndExitPool(
        uint256 poolClaim, uint256[] memory minAmounts, bool isSingleSided
    ) internal override returns (uint256[] memory exitBalances) {

    }

    function _checkPriceAndCalculateValue(uint256 vaultShares) internal view override returns (int256 underlyingValue) {
        Curve2TokenConvexStrategyContext memory context = _strategyContext();
        return context.poolContext._convertStrategyToUnderlying({
            strategyContext: context.baseStrategy,
            vaultShareAmount: vaultShares
        });
    } 

    function _totalPoolSupply() internal view override returns (uint256) {
        return CURVE_POOL_TOKEN.totalSupply();
    }

    function getSpotPrice(uint256 tokenIndex) external view returns (uint256 spotPrice) {
        spotPrice = _strategyContext().poolContext._getSpotPrice(tokenIndex);
    }

    function getStrategyContext() external view returns (Curve2TokenConvexStrategyContext memory) {
        return _strategyContext();
    }
}
