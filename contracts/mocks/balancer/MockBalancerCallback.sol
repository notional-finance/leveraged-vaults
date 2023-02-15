// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Deployments} from "../../global/Deployments.sol";
import {IBalancerVault, IAsset} from "../../../interfaces/balancer/IBalancerVault.sol";
import {IStrategyVault} from "../../../interfaces/notional/IStrategyVault.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {TokenUtils, IERC20} from "../../utils/TokenUtils.sol";

contract MockBalancerCallback {
    using TokenUtils for IERC20;

    NotionalProxy public immutable NOTIONAL;
    address public immutable BALANCER_POOL_TOKEN;
    mapping(address => address) internal underlyingToAsset;
    CallbackParams internal callbackParams;

    event AccountCollateral(
        int256 collateralRatio,
        int256 minCollateralRatio,
        int256 maxLiquidatorDepositAssetCash,
        uint256 vaultSharesToLiquidator
    );
    event AccountDeleveraged(address account);

    struct CallbackParams {
        address account;
        address vault;
        bytes redeemData;
    }

    constructor(NotionalProxy notional_, address balancerPool_) {
        NOTIONAL = notional_;
        BALANCER_POOL_TOKEN = balancerPool_;
    }

    function deleverage(
        uint256 primaryAmount,
        uint256 secondaryAmount,
        CallbackParams calldata params
    ) external {
        IERC20(address(Deployments.WRAPPED_STETH)).checkApprove(address(Deployments.BALANCER_VAULT), type(uint256).max);
        callbackParams = params;

        IAsset[] memory assets = new IAsset[](2);
        assets[1] = IAsset(address(0));
        assets[0] = IAsset(address(Deployments.WRAPPED_STETH));

        uint256[] memory amounts = new uint256[](2);
        // Join with 1 gWei less than msgValue to trigger callback
        amounts[1] = primaryAmount - 1e9;
        amounts[0] = secondaryAmount;

        uint256 msgValue;
        msgValue = primaryAmount;

        Deployments.BALANCER_VAULT.joinPool{value: msgValue}(
            0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080,
            address(this),
            address(this),
            IBalancerVault.JoinPoolRequest(
                assets,
                amounts,
                abi.encode(
                    IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                    amounts,
                    0
                ),
                false // Don't use internal balances
            )
        );
    }

    receive() external payable {
        if (msg.sender == address(Deployments.BALANCER_VAULT)) {
            (
                int256 collateralRatio,
                int256 minCollateralRatio,
                int256 maxLiquidatorDepositAssetCash,
                uint256 vaultSharesToLiquidator
            ) = NOTIONAL.getVaultAccountCollateralRatio(
                callbackParams.account,
                callbackParams.vault
            );

            emit AccountCollateral(collateralRatio, minCollateralRatio, maxLiquidatorDepositAssetCash, vaultSharesToLiquidator);

            IStrategyVault(callbackParams.vault).deleverageAccount(
                callbackParams.account, 
                callbackParams.vault, 
                address(this), 
                uint256(maxLiquidatorDepositAssetCash), 
                true, 
                callbackParams.redeemData
            );

            emit AccountDeleveraged(callbackParams.account);
        }
    } 
}
