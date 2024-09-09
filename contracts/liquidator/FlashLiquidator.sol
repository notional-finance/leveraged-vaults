// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {NotionalProxy} from "@interfaces/notional/NotionalProxy.sol";
import {IStrategyVault} from "@interfaces/notional/IStrategyVault.sol";
import {IERC7399} from "@interfaces/IERC7399.sol";
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

contract FlashLiquidator is BoringOwnable {
    using TokenUtils for IERC20;
    uint16 internal constant ONLY_VAULT_DELEVERAGE = 1 << 5;

    uint256 internal constant MAX_CURRENCIES = 3;

    NotionalProxy public immutable NOTIONAL;

    enum LiquidationType {
        UNKNOWN,
        DELEVERAGE_VAULT_ACCOUNT,
        LIQUIDATE_CASH_BALANCE
    }

    struct LiquidationParams {
        LiquidationType liquidationType;
        address vault;
        address[] accounts;
        bytes redeemData;
        // NOTE: these two are only used for cash liquidation
        uint16 currencyId;
        uint16 currencyIndex;
    }

    error ErrInvalidCurrencyIndex(uint16 index);

    constructor() {
        // Make sure we are using the correct Deployments lib
        uint256 chainId;
        assembly { chainId := chainid() }
        require(Deployments.CHAIN_ID == chainId);

        NOTIONAL = Deployments.NOTIONAL;
        owner = msg.sender;
        uint16 maxCurrencyId = Deployments.NOTIONAL.getMaxCurrencyId();
        uint16[] memory currencies = new uint16[](maxCurrencyId);
        for (uint16 i = 1; i <= maxCurrencyId; i++) currencies[i - 1] = i;
        enableCurrencies(currencies);

        emit OwnershipTransferred(address(0), owner);
    }

    function callback(
        address /* initiator */,
        address paymentReceiver,
        address /* asset */,
        uint256 /* amount */,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes memory) {
        handleLiquidation(fee, paymentReceiver, data);
        return "";
    }

    /// @notice Used for profit estimation off chain
    function estimateProfit(
        address flashLenderWrapper,
        address asset,
        uint256 amount,
        LiquidationParams calldata params
    ) external onlyOwner returns (uint256) {
        uint256 balance = IERC20(asset).balanceOf(address(this));
        _flashLiquidate(flashLenderWrapper, asset, amount, false, params);
        return IERC20(asset).balanceOf(address(this)) - balance;
    }

    function flashLiquidateBatch(
        address[] calldata flashLenderWrapper,
        address[] calldata asset,
        uint256[] calldata amount,
        LiquidationParams[] calldata params
    ) external {
        for (uint256 i; i < asset.length; i++) {
            _flashLiquidate(flashLenderWrapper[i], asset[i], amount[i], true, params[i]);
        }
    }

    /// @notice Primary entry point for the liquidation call
    function flashLiquidate(
        address flashLenderWrapper,
        address asset,
        uint256 amount,
        LiquidationParams calldata params
    ) external {
        _flashLiquidate(flashLenderWrapper, asset, amount, true, params);
    }

    function _flashLiquidate(address flashLender, address asset, uint256 amount, bool withdraw, LiquidationParams calldata params)
        internal
    {
        IERC7399(flashLender).flash(
            address(this), asset, amount, abi.encode(asset, amount, withdraw, params), this.callback
        );
    }

    /// @notice This is the primary entry point after the flash lender transfers the funds
    function handleLiquidation(uint256 fee, address paymentReceiver, bytes memory data) internal {
        (
            address asset,
            uint256 amount,
            bool withdraw,
            LiquidationParams memory params
        ) = abi.decode(data, (address, uint256, bool, LiquidationParams));
        bool isWETH = asset == address(Deployments.WETH);
        bool useVaultDeleverage = (
            NOTIONAL.getVaultConfig(params.vault).flags & ONLY_VAULT_DELEVERAGE == ONLY_VAULT_DELEVERAGE
        );

        // Notional uses ETH internally but flash lenders may send WETH
        if (isWETH) _unwrapETH(amount);

        // Liquidator will liquidate the all the accounts in batch
        uint256 vaultSharesFromLiquidation;
        for (uint256 i; i < params.accounts.length; i++) {
            address account = params.accounts[i];
            (
                VaultAccount memory vaultAccount,
                int256 accruedFeeInUnderlying
            ) = _settleAccountIfNeeded(account, params.vault);

            if (params.liquidationType == LiquidationType.DELEVERAGE_VAULT_ACCOUNT) {
                // Accrue the total vault shares received by deleveraging
                vaultSharesFromLiquidation += _deleverageVaultAccount(
                    account, params.vault, useVaultDeleverage, accruedFeeInUnderlying, isWETH
                );
            } else if (params.liquidationType == LiquidationType.LIQUIDATE_CASH_BALANCE) {
                // NOTE: cannot do batch cash liquidations at this point
                require(params.accounts.length == 1);
                _liquidateCashBalance(vaultAccount, params, asset, useVaultDeleverage);
            }
        }

        // Exit all the vault shares that we've accumulated during liquidation
        if (0 < vaultSharesFromLiquidation) {
            NOTIONAL.exitVault(
                address(this),
                params.vault,
                address(this),
                vaultSharesFromLiquidation,
                0, 0, params.redeemData
            );
        }

        // Rewrap ETH for repayment
        if (isWETH) _wrapETH();

        uint256 currentBalance = IERC20(asset).balanceOf(address(this));
        // force revert if there is no profit
        require(currentBalance > (amount + fee), "Unprofitable Liquidation");

        // Send profits back to the owner
        if (withdraw) {
            _withdrawToOwner(asset, currentBalance - amount - fee);
        }

        // Repay the flash lender
        IERC20(asset).checkTransfer(paymentReceiver, amount + fee);
    }

    /// @notice Used to maintain approvals for various currencies, called initially in the constructor
    function enableCurrencies(uint16[] memory currencies) public onlyOwner {
        for (uint256 i; i < currencies.length; i++) {
            (/* Token memory assetToken */, Token memory underlyingToken) = NOTIONAL.getCurrency(currencies[i]);
            IERC20(underlyingToken.tokenAddress).checkApprove(address(NOTIONAL), type(uint256).max);
        }
    }

    /// @notice Used via static call on the liquidation bot to get parameters for liquidation
    function getOptimalDeleveragingParams(
        address account, address vault
    ) external returns (uint16 currencyIndex, int256 maxUnderlying) {
        (/* */, int256 accruedFeeInUnderlying) = _settleAccountIfNeeded(account, vault);
        return _getOptimalDeleveragingParams(account, vault, accruedFeeInUnderlying);
    }

    /*** INTERNAL METHODS ***/

    function _settleAccountIfNeeded(
        address account, address vault
    ) private returns (VaultAccount memory vaultAccount, int256 accruedFeeInUnderlying) {
        (
            vaultAccount,
            accruedFeeInUnderlying
        ) = NOTIONAL.getVaultAccountWithFeeAccrual(account, vault);

        if (vaultAccount.maturity != 0 && vaultAccount.maturity < block.timestamp) {
            NOTIONAL.settleVaultAccount(account, vault);
        }
    }

    function _getOptimalDeleveragingParams(
        address account,
        address vault,
        int256 accruedFeeInUnderlying
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

    function _deleverageVaultAccount(
        address account,
        address vault,
        bool useVaultDeleverage,
        int256 accruedFeeInUnderlying,
        bool isETH
    ) private returns (uint256 vaultSharesFromLiquidation) {
        (uint16 currencyIndex, int256 maxUnderlying) = _getOptimalDeleveragingParams(
            account, vault, accruedFeeInUnderlying
        );
        // Short circuit accounts where no liquidation is necessary
        if (maxUnderlying == 0) return 0;

        uint256 msgValue = isETH ? uint256(maxUnderlying * 1e10) : 0;
        if (useVaultDeleverage) {
            (
                vaultSharesFromLiquidation, /* */
            ) = IStrategyVault(vault).deleverageAccount{value: msgValue}(
                account, vault, address(this), currencyIndex, maxUnderlying
            );
        } else {
            (
                vaultSharesFromLiquidation, /* */
            ) = NOTIONAL.deleverageAccount{value: msgValue}(
                account, vault, address(this), currencyIndex, maxUnderlying
            );
        }
    }

    function _liquidateCashBalance(
        VaultAccount memory vaultAccount,
        LiquidationParams memory params,
        address asset,
        bool useVaultDeleverage
    ) private {
        require(vaultAccount.maturity != Constants.PRIME_CASH_VAULT_MATURITY);

        int256 cashBalance;
        if (params.currencyIndex == 0) {
            cashBalance = vaultAccount.tempCashBalance;
        } else if (params.currencyIndex < MAX_CURRENCIES) {
            (/* */, /* */, int256[2] memory accountSecondaryCashHeld) = 
                NOTIONAL.getVaultAccountSecondaryDebt(vaultAccount.account, params.vault);
            cashBalance = accountSecondaryCashHeld[params.currencyIndex - 1];
        } else {
            revert ErrInvalidCurrencyIndex(params.currencyIndex);
        }

        (int256 fCashDeposit, /* */)  = NOTIONAL.getfCashRequiredToLiquidateCash(
            params.currencyId, vaultAccount.maturity, cashBalance
        );
        // fCash deposit cannot exceed the account's debt
        int256 maxFCashDeposit = -1 * vaultAccount.accountDebtUnderlying;
        fCashDeposit = maxFCashDeposit < fCashDeposit ?  maxFCashDeposit : fCashDeposit;

        _lend(params.currencyId, vaultAccount.maturity, uint256(fCashDeposit), 0, asset);

        if (useVaultDeleverage) {
            IStrategyVault(params.vault).liquidateVaultCashBalance(
                vaultAccount.account, params.vault, address(this), params.currencyIndex, fCashDeposit
            );
        } else {
            NOTIONAL.liquidateVaultCashBalance(
                vaultAccount.account, params.vault, address(this), params.currencyIndex, fCashDeposit
            );
        }

        // Withdraw all cash held
        NOTIONAL.withdraw(params.currencyId, type(uint88).max, true);
    }

    function _lend(
        uint16 currencyId,
        uint256 maturity,
        uint256 fCashAmount,
        uint32 minLendRate,
        address asset
    ) private {
        // ETH prevents usage of BatchLend here. This also prevents batch cash liquidations
        BalanceActionWithTrades[] memory action = new BalanceActionWithTrades[](1);
        action[0].actionType = DepositActionType.DepositUnderlying;
        action[0].depositActionAmount = currencyId == Constants.ETH_CURRENCY_ID ? 
            address(this).balance : 
            IERC20(asset).balanceOf(address(this));
        action[0].currencyId = currencyId;
        action[0].withdrawEntireCashBalance = true;
        action[0].redeemToUnderlying = true;
        uint256 marketIndex = NOTIONAL.getMarketIndex(maturity, block.timestamp);

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