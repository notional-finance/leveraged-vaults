// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {IFlashLoanRecipient} from "../../interfaces/balancer/IFlashLoanRecipient.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {CErc20Interface} from "../../interfaces/compound/CErc20Interface.sol";
import {CEtherInterface} from "../../interfaces/compound/CEtherInterface.sol";
import {WETH9} from "../../interfaces/WETH9.sol";
import {TokenUtils, IERC20} from "../utils/TokenUtils.sol";
import {Constants} from "../global/Constants.sol";
import {Token} from "../global/Types.sol";
import {BoringOwnable} from "./BoringOwnable.sol";
import {Deployments} from "../global/Deployments.sol";

contract FlashLiquidator is BoringOwnable, IFlashLoanRecipient {
    using TokenUtils for IERC20;

    NotionalProxy public immutable NOTIONAL;
    mapping(address => address) internal underlyingToAsset;

    struct LiquidationParams {
        uint16 currencyId;
        address account;
        address vault;
        bytes redeemData;
    }

    constructor(NotionalProxy notional) {
        NOTIONAL = notional;
        owner = msg.sender;
        emit OwnershipTransferred(address(0), owner);
    }

    function enableCurrencies(uint16[] calldata currencies) external onlyOwner {
        for (uint256 i; i < currencies.length; i++) {
            (Token memory assetToken, Token memory underlyingToken) = NOTIONAL.getCurrency(currencies[i]);
            IERC20(assetToken.tokenAddress).checkApprove(address(NOTIONAL), type(uint256).max);
            if (underlyingToken.tokenAddress == Constants.ETH_ADDRESS) {
                IERC20(address(Deployments.WETH)).checkApprove(address(Deployments.BALANCER_VAULT), type(uint256).max);
                underlyingToAsset[address(Deployments.WETH)] = assetToken.tokenAddress;
            } else {
                IERC20(underlyingToken.tokenAddress).checkApprove(address(Deployments.BALANCER_VAULT), type(uint256).max);
                IERC20(underlyingToken.tokenAddress).checkApprove(assetToken.tokenAddress, type(uint256).max);
                underlyingToAsset[underlyingToken.tokenAddress] = assetToken.tokenAddress;
            }
        }
    }

    function flashLiquidate(
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes calldata userData
    ) external onlyOwner {
        Deployments.BALANCER_VAULT.flashLoan(address(this), tokens, amounts, userData);
    }

    function receiveFlashLoan(
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes calldata userData
    ) external {
        require(msg.sender == address(Deployments.BALANCER_VAULT));

        LiquidationParams memory params = abi.decode(userData, (LiquidationParams));

        address assetToken = underlyingToAsset[address(tokens[0])];

        // Mint CToken
        if (params.currencyId == Constants.ETH_CURRENCY_ID) {
            Deployments.WETH.withdraw(amounts[0]);
            CEtherInterface(assetToken).mint{value: amounts[0]}();
        } else {
            CErc20Interface(assetToken).mint(amounts[0]);
        }

        (
            /* int256 collateralRatio */,
            /* int256 minCollateralRatio */,
            int256 maxLiquidatorDepositAssetCash
        ) = NOTIONAL.getVaultAccountCollateralRatio(params.account, params.vault);
        
        require(maxLiquidatorDepositAssetCash > 0);

        NOTIONAL.deleverageAccount(
            params.account, 
            params.vault, 
            address(this), 
            uint256(maxLiquidatorDepositAssetCash), 
            false, 
            params.redeemData
        );

        // Redeem CToken
        uint256 balance = IERC20(assetToken).balanceOf(address(this));
        if (balance > 0) {
            CErc20Interface(assetToken).redeem(balance);
            if (params.currencyId == Constants.ETH_CURRENCY_ID) {
                Deployments.WETH.deposit{value: address(this).balance}();
            }
        }
    }    
}
