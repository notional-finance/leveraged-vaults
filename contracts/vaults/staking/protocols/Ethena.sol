// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {Constants} from "@contracts/global/Constants.sol";
import {Deployments} from "@deployments/Deployments.sol";
import {IsUSDe} from "@interfaces/ethena/IsUSDe.sol";
import {IERC20} from "@interfaces/IERC20.sol";
import {IERC4626} from "@interfaces/IERC4626.sol";
import {TypeConvert} from "@contracts/global/TypeConvert.sol";
import {VaultStorage} from "@contracts/vaults/common/VaultStorage.sol";
import {
    WithdrawRequest,
    SplitWithdrawRequest
} from "@contracts/vaults/common/WithdrawRequestBase.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ClonedCoolDownHolder} from "./ClonedCoolDownHolder.sol";
import {CurveV2Adapter} from "@contracts/trading/adapters/CurveV2Adapter.sol";
import {ITradingModule, Trade, DexId, TradeType} from "@interfaces/trading/ITradingModule.sol";
import {TradeHandler} from "@contracts/trading/TradeHandler.sol";

// Mainnet Ethena contract addresses
IsUSDe constant sUSDe = IsUSDe(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
IERC20 constant USDe = IERC20(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3);
// Dai and sDAI are required for trading out of sUSDe
IERC20 constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
IERC4626 constant sDAI = IERC4626(0x83F20F44975D03b1b09e64809B757c47f942BEeA);

contract EthenaCooldownHolder is ClonedCoolDownHolder {

    constructor(address _vault) ClonedCoolDownHolder(_vault) { }

    /// @notice There is no way to stop a cool down
    function _stopCooldown() internal pure override { revert(); }

    function _startCooldown(uint256 cooldownBalance) internal override {
        uint24 duration = sUSDe.cooldownDuration();
        if (duration == 0) {
            // If the cooldown duration is set to zero, can redeem immediately
            sUSDe.redeem(cooldownBalance, address(this), address(this));
        } else {
            // If we execute a second cooldown while one exists, the cooldown end
            // will be pushed further out. This holder should only ever have one
            // cooldown ever.
            require(sUSDe.cooldowns(address(this)).cooldownEnd == 0);
            sUSDe.cooldownShares(cooldownBalance);
        }
    }

    function _finalizeCooldown() internal override returns (uint256 tokensClaimed, bool finalized) {
        uint24 duration = sUSDe.cooldownDuration();
        IsUSDe.UserCooldown memory userCooldown = sUSDe.cooldowns(address(this));

        if (block.timestamp < userCooldown.cooldownEnd && 0 < duration) {
            // Cooldown has not completed, return a false for finalized
            return (0, false);
        }

        uint256 balanceBefore = USDe.balanceOf(address(this));
        // If a cooldown has been initiated, need to call unstake to complete it. If
        // duration was set to zero then the USDe will be on this contract already.
        if (0 < userCooldown.cooldownEnd) sUSDe.unstake(address(this));
        uint256 balanceAfter = USDe.balanceOf(address(this));

        // USDe is immutable. It cannot have a transfer tax and it is ERC20 compliant
        // so we do not need to use the additional protections here.
        tokensClaimed = balanceAfter - balanceBefore;
        USDe.transfer(vault, tokensClaimed);
        finalized = true;
    }
}

library EthenaLib {
    using TradeHandler for Trade;
    using TypeConvert for int256;

    uint256 internal constant USDE_PRECISION = 1e18;

    function _getValueOfWithdrawRequest(
        uint256 requestId,
        address borrowToken,
        uint256 borrowPrecision
    ) internal view returns (uint256) {
        address holder = address(uint160(requestId));
        // This valuation is the amount of USDe the account will receive at cooldown, once
        // a cooldown is initiated the account is no longer receiving sUSDe yield. This balance
        // of USDe is transferred to a Silo contract and guaranteed to be available once the
        // cooldown has passed.
        IsUSDe.UserCooldown memory userCooldown = sUSDe.cooldowns(holder);

        int256 usdeToBorrowRate;
        if (borrowToken == address(USDe)) {
            usdeToBorrowRate = int256(Constants.EXCHANGE_RATE_PRECISION);
        } else {
            // If not borrowing USDe, convert to the borrowed token
            (usdeToBorrowRate, /* */) = Deployments.TRADING_MODULE.getOraclePrice(
                address(USDe), borrowToken
            );
        }

        return (userCooldown.underlyingAmount * usdeToBorrowRate.toUint() * borrowPrecision) /
            (Constants.EXCHANGE_RATE_PRECISION * USDE_PRECISION);
    }

    function _initiateWithdrawImpl(
        uint256 balanceToTransfer,
        address holderImplementation
    ) internal returns (uint256 requestId) {
        EthenaCooldownHolder holder = EthenaCooldownHolder(Clones.clone(holderImplementation));
        sUSDe.transfer(address(holder), balanceToTransfer);
        holder.startCooldown(balanceToTransfer);

        return uint256(uint160(address(holder)));
    }

    function _finalizeWithdrawImpl(
        uint256 requestId
    ) internal returns (uint256 tokensClaimed, bool finalized) {
        EthenaCooldownHolder holder = EthenaCooldownHolder(address(uint160(requestId)));
        (tokensClaimed, finalized) = holder.finalizeCooldown();
    }

    /// @notice The vast majority of the sUSDe liquidity is in an sDAI/sUSDe curve pool.
    /// sDAI has much greater liquidity once it is unwrapped as DAI so that is done manually
    /// in this method.
    function _sellStakedUSDe(
        uint256 sUSDeAmount,
        address borrowToken,
        uint256 minPurchaseAmount,
        bytes memory exchangeData,
        uint16 dexId
    ) internal returns (uint256 borrowedCurrencyAmount) {
        Trade memory sDAITrade = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: address(sUSDe),
            buyToken: address(sDAI),
            amount: sUSDeAmount,
            limit: 0, // NOTE: no slippage guard is set here, it is enforced in the second leg
                      // of the trade.
            deadline: block.timestamp,
            exchangeData: abi.encode(CurveV2Adapter.CurveV2SingleData({
                pool: 0x167478921b907422F8E88B43C4Af2B8BEa278d3A,
                fromIndex: 1, // sUSDe
                toIndex: 0 // sDAI
            }))
        });

        (/* */, uint256 sDAIAmount) = sDAITrade._executeTrade(uint16(DexId.CURVE_V2));

        // Unwraps the sDAI to DAI
        uint256 daiAmount = sDAI.redeem(sDAIAmount, address(this), address(this));
        
        if (borrowToken != address(DAI)) {
            Trade memory trade = Trade({
                tradeType: TradeType.EXACT_IN_SINGLE,
                sellToken: address(DAI),
                buyToken: borrowToken,
                amount: daiAmount,
                limit: minPurchaseAmount,
                deadline: block.timestamp,
                exchangeData: exchangeData
            });

            // Trades the unwrapped DAI back to the given token.
            (/* */, borrowedCurrencyAmount) = trade._executeTrade(dexId);
        } else {
            require(minPurchaseAmount <= daiAmount, "Slippage");
            borrowedCurrencyAmount = daiAmount;
        }
    }

    function _canFinalizeWithdrawRequest(uint256 requestId) internal view returns (bool) {
        uint24 duration = sUSDe.cooldownDuration();
        address holder = address(uint160(requestId));
        // This valuation is the amount of USDe the account will receive at cooldown, once
        // a cooldown is initiated the account is no longer receiving sUSDe yield. This balance
        // of USDe is transferred to a Silo contract and guaranteed to be available once the
        // cooldown has passed.
        IsUSDe.UserCooldown memory userCooldown = sUSDe.cooldowns(holder);
        return (userCooldown.cooldownEnd < block.timestamp || 0 == duration);
    }

}