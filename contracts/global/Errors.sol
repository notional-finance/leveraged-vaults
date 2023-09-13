// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.6;

library Errors {
    error InvalidPrice(uint256 oraclePrice, uint256 poolPrice);
    error InvalidEmergencySettlement();
    error HasNotMatured();
    error PostMaturitySettlement();
    error RedeemingTooMuch(
        int256 underlyingRedeemed,
        int256 underlyingCashRequiredToSettle
    );
    error SlippageTooHigh(uint256 slippage, uint32 limit);
    error InSettlementCoolDown(uint32 lastSettlementTimestamp, uint32 coolDownInMinutes);
    /// @notice settleVault called when there is no debt
    error SettlementNotRequired();
    error InvalidRewardToken(address token);
    error InvalidJoinAmounts(uint256 oraclePrice, uint256 maxPrimary, uint256 maxSecondary);
    error PoolShareTooHigh(uint256 totalPoolClaim, uint256 poolClaimThreshold);
    error StakeFailed();
    error UnstakeFailed();
    error InvalidTokenIndex(uint8 tokenIndex);
    error ZeroPoolClaim();
    error ZeroStrategyTokens();
    error VaultLocked();
    error VaultNotLocked();
    error InvalidDexId(uint256 dexId);
}
