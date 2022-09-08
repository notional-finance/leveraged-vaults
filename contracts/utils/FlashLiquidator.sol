// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {IFlashLoanReceiver} from "../../interfaces/aave/IFlashLoanReceiver.sol";
import {IFlashLender} from "../../interfaces/aave/IFlashLender.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {CErc20Interface} from "../../interfaces/compound/CErc20Interface.sol";
import {CEtherInterface} from "../../interfaces/compound/CEtherInterface.sol";
import {WETH9} from "../../interfaces/WETH9.sol";
import {TokenUtils, IERC20} from "../utils/TokenUtils.sol";
import {Constants} from "../global/Constants.sol";
import {Token} from "../global/Types.sol";
import {BoringOwnable} from "./BoringOwnable.sol";
import {Deployments} from "../global/Deployments.sol";

contract FlashLiquidator is BoringOwnable, IFlashLoanReceiver {
    using TokenUtils for IERC20;

    NotionalProxy public immutable NOTIONAL;
    IFlashLender public immutable FLASH_LENDER;
    mapping(address => address) internal underlyingToAsset;

    struct LiquidationParams {
        uint16 currencyId;
        address account;
        address vault;
        bytes redeemData;
    }

    constructor(NotionalProxy notional, IFlashLender flashLender) {
        NOTIONAL = notional;
        FLASH_LENDER = flashLender;
        owner = msg.sender;
        emit OwnershipTransferred(address(0), owner);
    }

    function enableCurrencies(uint16[] calldata currencies) external onlyOwner {
        for (uint256 i; i < currencies.length; i++) {
            (Token memory assetToken, Token memory underlyingToken) = NOTIONAL.getCurrency(currencies[i]);
            IERC20(assetToken.tokenAddress).checkApprove(address(NOTIONAL), type(uint256).max);
            if (underlyingToken.tokenAddress == Constants.ETH_ADDRESS) {
                IERC20(address(Deployments.WETH)).checkApprove(address(FLASH_LENDER), type(uint256).max);
                underlyingToAsset[address(Deployments.WETH)] = assetToken.tokenAddress;
            } else {
                IERC20(underlyingToken.tokenAddress).checkApprove(address(FLASH_LENDER), type(uint256).max);
                IERC20(underlyingToken.tokenAddress).checkApprove(assetToken.tokenAddress, type(uint256).max);
                underlyingToAsset[underlyingToken.tokenAddress] = assetToken.tokenAddress;
            }
        }
    }

    function flashLiquidate(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        bytes calldata params
    ) external onlyOwner {
        FLASH_LENDER.flashLoan(address(this), assets, amounts, modes, address(this), params, 0);
    }

    event Testing(uint256 wethBal, uint256 amount);

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == address(FLASH_LENDER));

        LiquidationParams memory liqParams = abi.decode(params, (LiquidationParams));

        address assetToken = underlyingToAsset[address(assets[0])];

        // Mint CToken
        if (liqParams.currencyId == Constants.ETH_CURRENCY_ID) {
            Deployments.WETH.withdraw(amounts[0]);
            CEtherInterface(assetToken).mint{value: amounts[0]}();
        } else {
            CErc20Interface(assetToken).mint(amounts[0]);
        }

        {
            (
                /* int256 collateralRatio */,
                /* int256 minCollateralRatio */,
                int256 maxLiquidatorDepositAssetCash
            ) = NOTIONAL.getVaultAccountCollateralRatio(liqParams.account, liqParams.vault);
            
            require(maxLiquidatorDepositAssetCash > 0);

            NOTIONAL.deleverageAccount(
                liqParams.account, 
                liqParams.vault, 
                address(this), 
                uint256(maxLiquidatorDepositAssetCash), 
                false, 
                liqParams.redeemData
            );
        }

        // Redeem CToken
        {
            uint256 balance = IERC20(assetToken).balanceOf(address(this));
            if (balance > 0) {
                CErc20Interface(assetToken).redeem(balance);
                if (liqParams.currencyId == Constants.ETH_CURRENCY_ID) {
                    _wrapETH();
                }
            }
        }

        _withdrawToOwner(assets[0], IERC20(assets[0]).balanceOf(address(this)) - amounts[0] - premiums[0]);

        return true;
    }

    function _withdrawToOwner(address token, uint256 amount) private {
        if (amount == type(uint256).max) {
            amount = IERC20(token).balanceOf(address(this));
        }
        if (amount > 0) {
            IERC20(token).checkTransfer(owner, amount);
        }
    }

    function _wrapETH() private {
        Deployments.WETH.deposit{value: address(this).balance}();
    }

    function withdrawToOwner(address token, uint256 amount) external onlyOwner {
        _withdrawToOwner(token, amount);
    }

    function wrapETH() external onlyOwner {
        _wrapETH();
    }

    receive() external payable {} 
}
