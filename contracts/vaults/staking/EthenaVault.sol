// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import { Constants } from "@contracts/global/Constants.sol";
import { Deployments } from "@deployments/Deployments.sol";
import { BaseStakingVault, DepositParams } from "./BaseStakingVault.sol";
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

contract EthenaVault is BaseStakingVault {

    address public HOLDER_IMPLEMENTATION;

    constructor() BaseStakingVault(
        Deployments.NOTIONAL,
        Deployments.TRADING_MODULE,
        address(sUSDe),
        address(USDe)
    ) {
        // Addresses in this vault are hardcoded to mainnet
        require(block.chainid == Constants.CHAIN_ID_MAINNET);
    }

    function initialize(
        string memory name,
        uint16 borrowCurrencyId
    ) public override {
        super.initialize(name, borrowCurrencyId);
        HOLDER_IMPLEMENTATION = address(new EthenaCooldownHolder(address(this)));
    }

    function strategy() external override pure returns (bytes4) {
        return bytes4(keccak256("Staking:Ethena"));
    }

    function _stakeTokens(
        address /* account */,
        uint256 depositUnderlyingExternal,
        uint256 /* maturity */,
        bytes calldata data
    ) internal override returns (uint256 vaultShares) {
        address underlyingToken = address(_underlyingToken());
        uint256 usdeAmount;

        if (underlyingToken == address(USDe)) {
            usdeAmount = depositUnderlyingExternal;
        } else {
            // If not borrowing USDe directly, then trade into the position
            DepositParams memory params = abi.decode(data, (DepositParams));

            Trade memory trade = Trade({
                tradeType: TradeType.EXACT_IN_SINGLE,
                sellToken: underlyingToken,
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
            uint256(BORROW_PRECISION);
    }

    /// @notice This vault will always borrow USDe so the value returned in this method will
    /// always be USDe.
    function _getValueOfWithdrawRequest(
        WithdrawRequest memory w,uint256 stakeAssetPrice
    ) internal override view returns (uint256 usdEValue) {
        return EthenaLib._getValueOfWithdrawRequest(w, stakeAssetPrice);
    }

    function _initiateWithdrawImpl(
        address /* account */, uint256 vaultSharesToRedeem, bool /* isForced */
    ) internal override returns (uint256 requestId) {
        return EthenaLib._initiateWithdrawImpl(
            HOLDER_IMPLEMENTATION, vaultSharesToRedeem, STAKING_PRECISION
        );
    }

    function _finalizeWithdrawImpl(
        address /* account */, uint256 requestId
    ) internal override returns (uint256 tokensClaimed, bool finalized) {
        return EthenaLib._finalizeWithdrawImpl(requestId);
    }

    function _checkReentrancyContext() internal override {
        // NO-OP
    }
}