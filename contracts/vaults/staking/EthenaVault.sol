// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import { Constants } from "@contracts/global/Constants.sol";
import { Deployments } from "@deployments/Deployments.sol";
import { BaseStakingVault, DepositParams, RedeemParams } from "./BaseStakingVault.sol";
import {
    sUSDe,
    USDe,
    EthenaCooldownHolder,
    EthenaLib
} from "./protocols/Ethena.sol";
import {WithdrawRequest, SplitWithdrawRequest} from "../common/WithdrawRequestBase.sol";
import {NotionalProxy} from "../common/BaseStrategyVault.sol";
import {
    ITradingModule,
    Trade,
    TradeType
} from "@interfaces/trading/ITradingModule.sol";

/** Borrows a stablecoin and stakes it into sUSDe */
contract EthenaVault is BaseStakingVault {

    /// @notice sUSDe requires a separate contract to hold the tokens during cooldown, this is
    /// the implementation address of the holder that will be cloned.
    address public HOLDER_IMPLEMENTATION;

    constructor(
        address borrowToken
    ) BaseStakingVault(address(sUSDe), borrowToken, address(USDe)) {
        // Addresses in this vault are hardcoded to mainnet
        require(block.chainid == Constants.CHAIN_ID_MAINNET);
    }

    /// @notice Deploys the holder with the address of the proxy
    function _initialize() internal override {
        HOLDER_IMPLEMENTATION = address(new EthenaCooldownHolder(address(this)));
        USDe.approve(address(sUSDe), type(uint256).max);
    }

    function strategy() external override pure returns (bytes4) {
        return bytes4(keccak256("Staking:sUSDe"));
    }

    function _stakeTokens(
        address /* account */,
        uint256 depositUnderlyingExternal,
        uint256 /* maturity */,
        bytes calldata data
    ) internal override returns (uint256 vaultShares) {
        uint256 usdeAmount;

        if (BORROW_TOKEN == address(USDe)) {
            usdeAmount = depositUnderlyingExternal;
        } else {
            // If not borrowing USDe directly, then trade into the position
            DepositParams memory params = abi.decode(data, (DepositParams));

            Trade memory trade = Trade({
                tradeType: TradeType.EXACT_IN_SINGLE,
                sellToken: BORROW_TOKEN,
                buyToken: address(USDe),
                amount: depositUnderlyingExternal,
                limit: params.minPurchaseAmount,
                deadline: block.timestamp,
                exchangeData: params.exchangeData
            });

            // Executes a trade on the given Dex, the vault must have permissions set for
            // each dex and token it wants to sell.
            (/* */, usdeAmount) = _executeTrade(params.dexId, trade);
        }

        uint256 sUSDeMinted = sUSDe.deposit(usdeAmount, address(this));
        vaultShares = sUSDeMinted * uint256(Constants.INTERNAL_TOKEN_PRECISION) /
            uint256(STAKING_PRECISION);
    }

    /// @notice Returns the value of a withdraw request in terms of the borrowed token
    function _getValueOfWithdrawRequest(
       uint256 requestId, uint256 /* totalVaultShares */, uint256 /* stakeAssetPrice */
    ) internal override view returns (uint256) {
        return EthenaLib._getValueOfWithdrawRequest(requestId, BORROW_TOKEN, BORROW_PRECISION);
    }

    function _initiateWithdrawImpl(
        address /* account */, uint256 vaultSharesToRedeem, bool /* isForced */, bytes calldata /* data */
    ) internal override returns (uint256 requestId) {
        uint256 balanceToTransfer = getStakingTokensForVaultShare(vaultSharesToRedeem);
        return EthenaLib._initiateWithdrawImpl(balanceToTransfer, HOLDER_IMPLEMENTATION);
    }

    function _finalizeWithdrawImpl(
        address /* account */, uint256 requestId
    ) internal override returns (uint256 tokensClaimed, bool finalized) {
        return EthenaLib._finalizeWithdrawImpl(requestId);
    }

    function _executeInstantRedemption(
        address /* account */,
        uint256 vaultShares,
        uint256 /* maturity */,
        RedeemParams memory params
    ) internal override returns (uint256 borrowedCurrencyAmount) {
        uint256 sUSDeToSell = getStakingTokensForVaultShare(vaultShares);

        // Selling sUSDe requires special handling since most of the liquidity
        // sits inside a sUSDe/sDAI pool on Curve.
        return EthenaLib._sellStakedUSDe(
            sUSDeToSell, BORROW_TOKEN, params.minPurchaseAmount, params.exchangeData, params.dexId
        );
    }

    function canFinalizeWithdrawRequest(uint256 requestId) public override view returns (bool) {
        return EthenaLib._canFinalizeWithdrawRequest(requestId);
    }

    function _checkReentrancyContext() internal override { /* NO-OP */ }
}