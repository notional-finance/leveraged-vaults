// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {IStrategyVault} from "../../interfaces/notional/IStrategyVault.sol";
import {CErc20Interface} from "../../interfaces/compound/CErc20Interface.sol";
import {CEtherInterface} from "../../interfaces/compound/CEtherInterface.sol";
import {WETH9} from "../../interfaces/WETH9.sol";
import {TokenUtils, IERC20} from "../utils/TokenUtils.sol";
import {Constants} from "../global/Constants.sol";
import {
    Token, 
    VaultAccount, 
    BatchLend,
    BalanceActionWithTrades,
    TradeActionType,
    DepositActionType
} from "../global/Types.sol";
import {BoringOwnable} from "./BoringOwnable.sol";
import {Deployments} from "../global/Deployments.sol";

abstract contract FlashLiquidatorBase is BoringOwnable {
    using TokenUtils for IERC20;

    NotionalProxy public immutable NOTIONAL;
    address public immutable FLASH_LENDER;

    enum LiquidationType {
        UNKNOWN,
        DELEVERAGE_VAULT_ACCOUNT,
        LIQUIDATE_CASH_BALANCE
    }

    struct LiquidationParams {
        LiquidationType liquidationType;
        uint16 currencyId;
        uint16 currencyIndex;
        address account;
        address vault;
        bytes actionData;
    }

    struct DeleverageVaultAccountParams {
        bool useVaultDeleverage;
        bytes redeemData;
    }

    struct LiquidateCashBalanceParams {
        uint16 currencyIndex;
        uint32 minLendRate;
    }

    constructor(NotionalProxy notional_, address flashLender_) {
        NOTIONAL = notional_;
        FLASH_LENDER = flashLender_;
        owner = msg.sender;
        emit OwnershipTransferred(address(0), owner);
    }

    function enableCurrencies(uint16[] calldata currencies) external onlyOwner {
        for (uint256 i; i < currencies.length; i++) {
            (/* Token memory assetToken */, Token memory underlyingToken) = NOTIONAL.getCurrency(currencies[i]);
            if (underlyingToken.tokenAddress == Constants.ETH_ADDRESS) {
                IERC20(address(Deployments.WETH)).checkApprove(address(FLASH_LENDER), type(uint256).max);
            } else {
                IERC20(underlyingToken.tokenAddress).checkApprove(address(FLASH_LENDER), type(uint256).max);
                IERC20(underlyingToken.tokenAddress).checkApprove(address(NOTIONAL), type(uint256).max);
            }
        }
    }

    /// NOTE: use .call from liquidation bot
    function getOptimalDeleveragingParams(
        address account, address vault
    ) external returns (uint16 currencyIndex, int256 maxUnderying) {
        _settleAccountIfNeeded(account, vault);
        return _getOptimalDeleveragingParams(account, vault);
    }

    function _settleAccountIfNeeded(address account, address vault) private returns (VaultAccount memory) {
        VaultAccount memory vaultAccount = NOTIONAL.getVaultAccount(account, vault);

        if (vaultAccount.maturity < block.timestamp) {
            NOTIONAL.settleVaultAccount(account, vault);
        }

        return vaultAccount;
    }

    function _getOptimalDeleveragingParams(
        address account, address vault
    ) private returns (uint16 currencyIndex, int256 maxUnderlying) {
        (
            /* VaultAccountHealthFactors memory h */,
            int256[3] memory maxLiquidatorDepositUnderlying,
            uint256[3] memory vaultSharesToLiquidator
        ) = NOTIONAL.getVaultAccountHealthFactors(account, vault);

        currencyIndex = vaultSharesToLiquidator[0] < vaultSharesToLiquidator[1] ? 
            (vaultSharesToLiquidator[1] < vaultSharesToLiquidator[2] ? 2 : 1) :
            (vaultSharesToLiquidator[0] < vaultSharesToLiquidator[2] ? 2 : 0); 
        maxUnderlying = maxLiquidatorDepositUnderlying[currencyIndex];
    }

    function estimateProfit(
        address asset,
        uint256 amount,
        LiquidationParams calldata params
    ) external onlyOwner returns (uint256) {
        uint256 balance = IERC20(asset).balanceOf(address(this));
        _flashLiquidate(asset, amount, false, params);
        return IERC20(asset).balanceOf(address(this)) - balance;
    }

    function flashLiquidate(
        address asset,
        uint256 amount,
        LiquidationParams calldata params
    ) external {
        _flashLiquidate(asset, amount, true, params);
    }

    function _flashLiquidate(
        address asset,
        uint256 amount,
        bool withdraw,
        LiquidationParams calldata params
    ) internal virtual;

    function _deleverageVaultAccount(LiquidationParams memory params) private {
        (uint16 currencyIndex, int256 maxUnderlying) = _getOptimalDeleveragingParams(params.account, params.vault);
        require(maxUnderlying > 0);

        DeleverageVaultAccountParams memory actionParams = abi.decode(params.actionData, (DeleverageVaultAccountParams));
        uint256 vaultSharesFromLiquidation;
        if (actionParams.useVaultDeleverage) {
            (
                vaultSharesFromLiquidation, /* */ 
            ) = IStrategyVault(params.vault).deleverageAccount{value: address(this).balance}(
                params.account, 
                params.vault, 
                address(this), 
                currencyIndex,
                maxUnderlying
            );
        } else {
            (
                vaultSharesFromLiquidation, /* */ 
            ) = NOTIONAL.deleverageAccount{value: address(this).balance}(
                params.account, 
                params.vault, 
                address(this), 
                currencyIndex,
                maxUnderlying
            );
        }

        if (0 < vaultSharesFromLiquidation) {
            NOTIONAL.exitVault(
                address(this), 
                params.vault, 
                address(this), 
                vaultSharesFromLiquidation,
                0, 
                0, 
                actionParams.redeemData
            );
        }
    }

    function _liquidateCashBalance(VaultAccount memory vaultAccount, LiquidationParams memory params) private {
        LiquidateCashBalanceParams memory actionParams = abi.decode(params.actionData, (LiquidateCashBalanceParams));

        require(vaultAccount.maturity != Constants.PRIME_CASH_VAULT_MATURITY);

        (int256 fCashDeposit, /* */)  = NOTIONAL.getfCashRequiredToLiquidateCash(
            params.currencyId, vaultAccount.maturity, vaultAccount.tempCashBalance
        );

        uint256 fCashAmount = _lend(
            params.currencyId, vaultAccount.maturity, uint256(fCashDeposit), actionParams.minLendRate
        );

        require(fCashAmount <= uint256(type(int256).max));

        NOTIONAL.liquidateVaultCashBalance(
            params.account, 
            params.vault, 
            address(this), 
            actionParams.currencyIndex, 
            int256(fCashAmount)
        );

        // Sell residual fCash
        int256 fCashResidual = NOTIONAL.getfCashNotional(address(this), params.currencyId, vaultAccount.maturity);

        if (0 < fCashResidual) {
            require(fCashResidual <= int256(type(int88).max));
            _sellfCash(params.currencyId, vaultAccount.maturity, uint88(uint256(fCashResidual)));
        } else {
            _withdraw(params);
        }
    }

    function handleLiquidation(uint256 fee, bool repay, bytes memory data) internal {
        require(msg.sender == address(FLASH_LENDER));

        (
            address asset, 
            uint256 amount, 
            bool withdraw,
            LiquidationParams memory params
        ) = abi.decode(data, (address, uint256, bool, LiquidationParams));

        VaultAccount memory vaultAccount = _settleAccountIfNeeded(params.account, params.vault);

        if (asset == address(Deployments.WETH)) {
            _unwrapETH(amount);
        }

        if (params.liquidationType == LiquidationType.DELEVERAGE_VAULT_ACCOUNT) {
            _deleverageVaultAccount(params);
        } else if(params.liquidationType == LiquidationType.LIQUIDATE_CASH_BALANCE) {
            _liquidateCashBalance(vaultAccount, params);
        } else {
            revert();
        }

        if (asset == address(Deployments.WETH)) {
            _wrapETH();
        }

        if (withdraw) {
            _withdrawToOwner(asset, IERC20(asset).balanceOf(address(this)) - amount - fee);
        }

        if (repay) {
            IERC20(asset).transfer(msg.sender, amount + fee);
        }
    }

    function _withdraw(LiquidationParams memory params) private {
        (int256 cashBalance, /* */, /* */) = NOTIONAL.getAccountBalance(params.currencyId, address(this));

        require(0 <= cashBalance && cashBalance <= int256(uint256(type(uint88).max)));

        NOTIONAL.withdraw(params.currencyId, uint88(uint256(cashBalance)), true);
    }

    function _lend(uint16 currencyId, uint256 maturity, uint256 amount, uint32 minLendRate) private returns (uint256) {
        (uint256 fCashAmount, /* */, bytes32 encodedTrade) = NOTIONAL.getfCashLendFromDeposit(
            currencyId,
            amount,
            maturity,
            minLendRate,
            block.timestamp,
            true // useUnderlying is true
        );

        BalanceActionWithTrades[] memory action = new BalanceActionWithTrades[](1);
        action[0].actionType = DepositActionType.DepositUnderlying;
        action[0].depositActionAmount = amount;
        action[0].currencyId = currencyId;
        action[0].withdrawEntireCashBalance = false;
        action[0].redeemToUnderlying = false;

        bytes32[] memory trades = new bytes32[](1);
        
        trades[0] = encodedTrade;
        action[0].trades = trades;

        uint256 msgValue;
        if (currencyId == Constants.ETH_CURRENCY_ID) {
            msgValue = amount;
        }

        NOTIONAL.batchBalanceAndTradeAction{value: msgValue}(address(this), action);

        return fCashAmount;
    }

    function _sellfCash(uint16 currencyId, uint256 maturity, uint88 amount) internal {
        BalanceActionWithTrades[] memory action = new BalanceActionWithTrades[](1);
        action[0].actionType = DepositActionType.None;
        action[0].depositActionAmount = 0;
        action[0].currencyId = currencyId;
        action[0].withdrawEntireCashBalance = true;
        action[0].redeemToUnderlying = true;

        bytes32[] memory trades = new bytes32[](1);

        uint256 marketIndex = NOTIONAL.getMarketIndex(currencyId, block.timestamp);
        
        trades[0] = bytes32(
            (uint256(TradeActionType.Borrow) << 248) |
            (marketIndex << 240) |
            (uint256(amount) << 152)
        );

        action[0].trades = trades;

        NOTIONAL.batchBalanceAndTradeAction(address(this), action);
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

    function _unwrapETH(uint256 amount) private {
        Deployments.WETH.withdraw(amount);
    }

    function withdrawToOwner(address token, uint256 amount) external onlyOwner {
        _withdrawToOwner(token, amount);
    }

    function wrapETH() external onlyOwner {
        _wrapETH();
    }

    receive() external payable {} 
}
