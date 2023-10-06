// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {
    ConvexVaultDeploymentParams, 
    InitParams, 
    Curve2TokenPoolContext,
    Curve2TokenConvexStrategyContext
} from "./curve/CurveVaultTypes.sol";
import {
    StrategyContext,
    StrategyVaultState,
    StrategyVaultSettings,
    RedeemParams,
    DepositParams,
    ReinvestRewardParams
} from "./common/VaultTypes.sol";
import {VaultStorage} from "./common/VaultStorage.sol";
import {Errors} from "../global/Errors.sol";
import {Constants} from "../global/Constants.sol";
import {TypeConvert} from "../global/TypeConvert.sol";
import {Deployments} from "../global/Deployments.sol";
import {TokenUtils, IERC20} from "../utils/TokenUtils.sol";
import {Curve2TokenVaultMixin} from "./curve/mixins/Curve2TokenVaultMixin.sol";
import {Curve2TokenPoolUtils} from "./curve/internal/pool/Curve2TokenPoolUtils.sol";
import {Curve2TokenConvexHelper} from "./curve/external/Curve2TokenConvexHelper.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {StrategyUtils} from "./common/internal/strategy/StrategyUtils.sol";

contract Curve2TokenConvexVault is Curve2TokenVaultMixin {
    using TypeConvert for uint256;
    using TypeConvert for int256;
    using TokenUtils for IERC20;
    using VaultStorage for StrategyVaultState;
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
        VaultStorage.setStrategyVaultSettings(params.settings);

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
        finalPrimaryBalance = _strategyContext().redeem(strategyTokens, data);
    }   

    function emergencyExit(bytes calldata data) 
        external onlyRole(EMERGENCY_SETTLEMENT_ROLE) {
        Curve2TokenConvexHelper.emergencyExit(_strategyContext(), data);
        _lockVault();
    }

    function restoreVault(uint256 minPoolClaim) external whenLocked onlyNotionalOwner {
        Curve2TokenConvexStrategyContext memory context = _strategyContext();

        uint256 poolClaimAmount = context.poolContext._joinPoolAndStake({
            strategyContext: context.baseStrategy,
            stakingContext: context.stakingContext,
            primaryAmount: TokenUtils.tokenBalance(PRIMARY_TOKEN),
            secondaryAmount: TokenUtils.tokenBalance(SECONDARY_TOKEN),
            minPoolClaim: minPoolClaim
        });

        context.baseStrategy.vaultState.totalPoolClaim += poolClaimAmount;
        context.baseStrategy.vaultState.setStrategyVaultState(); 

        _unlockVault();
    }

    function reinvestReward(ReinvestRewardParams calldata params) 
        external whenNotLocked onlyRole(REWARD_REINVESTMENT_ROLE) returns (
            address rewardToken,
            uint256 amountSold,
            uint256 poolClaimAmount
    ) {
        return Curve2TokenConvexHelper.reinvestReward(_strategyContext(), params);        
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
        spotPrice = _strategyContext().poolContext._getSpotPrice(tokenIndex);
    }

    function getStrategyContext() external view returns (Curve2TokenConvexStrategyContext memory) {
        return _strategyContext();
    }

    /// @notice Updates the vault settings
    /// @param settings vault settings
    function setStrategyVaultSettings(StrategyVaultSettings calldata settings)
        external
        onlyNotionalOwner
    {
        VaultStorage.setStrategyVaultSettings(settings);
    }
}
