// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {NotionalProxy} from "@interfaces/notional/NotionalProxy.sol";
import {IStrategyVault} from "@interfaces/notional/IStrategyVault.sol";
import {WETH9} from "@interfaces/WETH9.sol";
import {TokenUtils, IERC20} from "@contracts/utils/TokenUtils.sol";
import {Constants} from "@contracts/global/Constants.sol";
import {
    Token, 
    VaultAccount, 
    BatchLend,
    BalanceActionWithTrades,
    TradeActionType,
    DepositActionType,
    PortfolioAsset
} from "@contracts/global/Types.sol";
import {BoringOwnable} from "./BoringOwnable.sol";
import {Deployments} from "@deployments/Deployments.sol";

abstract contract FlashLiquidatorBase is BoringOwnable {
    using TokenUtils for IERC20;

    uint256 internal constant MAX_CURRENCIES = 3;

    NotionalProxy public immutable NOTIONAL;
    address public immutable FLASH_LENDER;

    enum LiquidationType {
        UNKNOWN,
        DELEVERAGE_VAULT_ACCOUNT,
        LIQUIDATE_CASH_BALANCE,
        DELEVERAGE_VAULT_ACCOUNT_AND_LIQUIDATE_CASH
    }

    struct LiquidationParams {
        LiquidationType liquidationType;
        uint16 currencyId;
        uint16 currencyIndex;
        address account;
        address vault;
        bool useVaultDeleverage;
        bytes actionData;
    }

    error ErrInvalidCurrencyIndex(uint16 index);

    constructor(NotionalProxy notional_, address flashLender_) {
        // Make sure we are using the correct Deployments lib
        uint256 chainId;
        assembly { chainId := chainid() }
        require(Deployments.CHAIN_ID == chainId);

        NOTIONAL = notional_;
        FLASH_LENDER = flashLender_;
        owner = msg.sender;
        uint16 maxCurrencyId = notional_.getMaxCurrencyId();
        uint16[] memory currencies = new uint16[](maxCurrencyId);
        for (uint16 i = 1; i <= maxCurrencyId; i++) currencies[i - 1] = i;
        enableCurrencies(currencies);

        emit OwnershipTransferred(address(0), owner);
    }

    function enableCurrencies(uint16[] memory currencies) public onlyOwner {
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
    ) external returns (uint16 currencyIndex, int256 maxUnderlying) {
        (/* */, int256 accruedFeeInUnderlying) = _settleAccountIfNeeded(account, vault);
        return _getOptimalDeleveragingParams(account, vault, accruedFeeInUnderlying);
    }

    function _settleAccountIfNeeded(
        address account, address vault
    ) private returns (VaultAccount memory vaultAccount, int256 accruedFeeInUnderlying) {
        (vaultAccount, accruedFeeInUnderlying) = NOTIONAL.getVaultAccountWithFeeAccrual(account, vault);

        if (vaultAccount.maturity < block.timestamp) NOTIONAL.settleVaultAccount(account, vault);
    }

    function _getOptimalDeleveragingParams(
        address account, address vault, int256 accruedFeeInUnderlying
    ) private view returns (uint16 currencyIndex, int256 maxUnderlying) {
        (
            /* VaultAccountHealthFactors memory h */,
            int256[3] memory maxLiquidatorDepositUnderlying,
            uint256[3] memory vaultSharesToLiquidator
        ) = NOTIONAL.getVaultAccountHealthFactors(account, vault);

        currencyIndex = vaultSharesToLiquidator[0] < vaultSharesToLiquidator[1] ? 
            (vaultSharesToLiquidator[1] < vaultSharesToLiquidator[2] ? 2 : 1) :
            (vaultSharesToLiquidator[0] < vaultSharesToLiquidator[2] ? 2 : 0); 
        maxUnderlying = maxLiquidatorDepositUnderlying[currencyIndex];

        // If there is an accrued fee, add it to the max underlying to ensure that dust
        // amounts do not cause liquidations to fail.
        if (maxUnderlying > 0) maxUnderlying = maxUnderlying + accruedFeeInUnderlying;
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

    function _deleverageVaultAccount(
        LiquidationParams memory params,
        int256 accruedFeeInUnderlying
    ) private {
        (uint16 currencyIndex, int256 maxUnderlying) = _getOptimalDeleveragingParams(
            params.account, params.vault, accruedFeeInUnderlying
        );
        require(maxUnderlying > 0);

        uint256 vaultSharesFromLiquidation;
        if (params.useVaultDeleverage) {
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
                params.actionData
            );
        }
    }

    function _liquidateCashBalance(
        VaultAccount memory vaultAccount,
        LiquidationParams memory params,
        address asset
    ) private {
        require(vaultAccount.maturity != Constants.PRIME_CASH_VAULT_MATURITY);

        int256 cashBalance;
        if (params.currencyIndex == 0) {
            cashBalance = vaultAccount.tempCashBalance;
        } else if (params.currencyIndex < MAX_CURRENCIES) {
            (/* */, /* */, int256[2] memory accountSecondaryCashHeld) = 
                NOTIONAL.getVaultAccountSecondaryDebt(params.account, params.vault);
            cashBalance = accountSecondaryCashHeld[params.currencyIndex - 1];
        } else {
            revert ErrInvalidCurrencyIndex(params.currencyIndex);
        }

        (int256 fCashDeposit, /* */)  = NOTIONAL.getfCashRequiredToLiquidateCash(
            params.currencyId, vaultAccount.maturity, cashBalance
        );

        _lend(params.currencyId, vaultAccount.maturity, uint256(fCashDeposit), 0, asset);

        if (params.useVaultDeleverage) {
            IStrategyVault(params.vault).liquidateVaultCashBalance(
                params.account,
                params.vault,
                address(this),
                params.currencyIndex,
                fCashDeposit
            );
        } else {
            NOTIONAL.liquidateVaultCashBalance(
                params.account,
                params.vault,
                address(this),
                params.currencyIndex,
                fCashDeposit
            );
        }

        // Withdraw all cash held
        NOTIONAL.withdraw(params.currencyId, type(uint88).max, true);
    }

    function handleLiquidation(uint256 fee, bool repay, bytes memory data) internal {
        require(msg.sender == address(FLASH_LENDER));

        (
            address asset,
            uint256 amount,
            bool withdraw,
            LiquidationParams memory params
        ) = abi.decode(data, (address, uint256, bool, LiquidationParams));

        (
            VaultAccount memory vaultAccount,
            int256 accruedFeeInUnderlying
        ) = _settleAccountIfNeeded(params.account, params.vault);

        if (asset == address(Deployments.WETH)) _unwrapETH(amount);

        if (
            params.liquidationType == LiquidationType.DELEVERAGE_VAULT_ACCOUNT ||
            params.liquidationType == LiquidationType.DELEVERAGE_VAULT_ACCOUNT_AND_LIQUIDATE_CASH
        ) {
            _deleverageVaultAccount(params, accruedFeeInUnderlying);
        }

        if (
            vaultAccount.maturity != Constants.PRIME_CASH_VAULT_MATURITY &&
            (params.liquidationType == LiquidationType.LIQUIDATE_CASH_BALANCE ||
             params.liquidationType == LiquidationType.DELEVERAGE_VAULT_ACCOUNT_AND_LIQUIDATE_CASH)
        ) {
            // Need to re-fetch to get the temp cash balance after liquidation
            vaultAccount = NOTIONAL.getVaultAccount(params.account, params.vault);
            _liquidateCashBalance(vaultAccount, params, asset);
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

    function _lend(
        uint16 currencyId,
        uint256 maturity,
        uint256 fCashAmount,
        uint32 minLendRate,
        address asset
    ) private {
        BalanceActionWithTrades[] memory action = new BalanceActionWithTrades[](1);
        action[0].actionType = DepositActionType.DepositUnderlying;
        // For simplicity just deposit everything at this point.
        action[0].depositActionAmount = currencyId == Constants.ETH_CURRENCY_ID ? 
            address(this).balance : 
            IERC20(asset).balanceOf(address(this));
        action[0].currencyId = currencyId;
        action[0].withdrawEntireCashBalance = true;
        action[0].redeemToUnderlying = true;
        uint256 marketIndex = NOTIONAL.getMarketIndex(currencyId, maturity) + 1;

        action[0].trades = new bytes32[](1);
        action[0].trades[0] = bytes32(
            (uint256(uint8(TradeActionType.Lend)) << 248) |
            (uint256(marketIndex) << 240) |
            (uint256(fCashAmount) << 152) |
            (uint256(minLendRate) << 120)
        );
        
        uint256 msgValue;
        if (currencyId == Constants.ETH_CURRENCY_ID) {
            msgValue = action[0].depositActionAmount;
        }

        NOTIONAL.batchBalanceAndTradeAction{value: msgValue}(address(this), action);
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