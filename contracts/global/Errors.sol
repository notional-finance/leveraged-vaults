// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.6;

library Errors {
    error InvalidSpotPrice(uint256 oraclePrice, uint256 spotPrice);
    error NotInSettlementWindow();
    error InvalidEmergencySettlement();
    error HasNotMatured();
    error PostMaturitySettlement();
    error RedeemingTooMuch(
        int256 underlyingRedeemed,
        int256 underlyingCashRequiredToSettle
    );
    error SlippageTooHigh(uint32 slippage, uint32 limit);
    error InSettlementCoolDown(uint32 lastSettlementTimestamp, uint32 coolDownInMinutes);
    /// @notice settleVault called when there is no debt
    error SettlementNotRequired();
    error InvalidRewardToken(address token);
    error InvalidJoinAmounts(uint256 oraclePrice, uint256 maxPrimary, uint256 maxSecondary);
}