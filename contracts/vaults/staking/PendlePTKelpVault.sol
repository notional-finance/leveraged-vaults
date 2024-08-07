// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {Constants} from "@contracts/global/Constants.sol";
import {TypeConvert} from "@contracts/global/TypeConvert.sol";
import {Deployments} from "@deployments/Deployments.sol";
import {PendlePrincipalToken, WithdrawRequest} from "./protocols/PendlePrincipalToken.sol";
import { KelpLib, KelpCooldownHolder, rsETH, stETH } from "./protocols/Kelp.sol";

contract PendlePTKelpVault is PendlePrincipalToken {
    using TypeConvert for int256;
    address public HOLDER_IMPLEMENTATION;

    constructor(
        address marketAddress,
        address ptAddress
    ) PendlePrincipalToken(
        marketAddress,
        Constants.ETH_ADDRESS,
        address(rsETH),
        Constants.ETH_ADDRESS,
        ptAddress,
        Constants.ETH_ADDRESS
    ) {
        // Addresses in this vault are hardcoded to mainnet
        require(block.chainid == Constants.CHAIN_ID_MAINNET);
    }

    function initialize(
        string memory name,
        uint16 borrowCurrencyId
    ) public override {
        super.initialize(name, borrowCurrencyId);
        HOLDER_IMPLEMENTATION = address(new KelpCooldownHolder(address(this)));
    }

    function strategy() external override pure returns (bytes4) {
        return bytes4(keccak256("Staking:PendlePT:rsETH"));
    }

    /// @notice Returns the value of a withdraw request in terms of the borrowed token
    function _getValueOfWithdrawRequest(
        uint256 requestId, uint256 /* totalVaultShares */, uint256 /* stakeAssetPrice */
    ) internal override view returns (uint256) {
        uint256 tokenOutSY = getTokenOutSYForWithdrawRequest(requestId);
        // NOTE: in this vault the tokenOutSy is known to be stETH.
        (int256 stETHPrice, /* */) = TRADING_MODULE.getOraclePrice(TOKEN_OUT_SY, BORROW_TOKEN);
        return (tokenOutSY * stETHPrice.toUint() * BORROW_PRECISION) /
            (KelpLib.stETH_PRECISION * Constants.EXCHANGE_RATE_PRECISION);
    }

    function _initiateSYWithdraw(
        address /* account */, uint256 amountToWithdraw, bool /* isForced */
    ) internal override returns (uint256 requestId) {
        return KelpLib._initiateWithdrawImpl(amountToWithdraw, HOLDER_IMPLEMENTATION);
    }

    function _finalizeWithdrawImpl(
        address /* account */, uint256 requestId
    ) internal override returns (uint256 tokensClaimed, bool finalized) {
        return KelpLib._finalizeWithdrawImpl(requestId);
    }

    function canFinalizeWithdrawRequest(uint256 requestId) public override view returns (bool) {
        return KelpLib._canFinalizeWithdrawRequest(requestId);
    }

    function canTriggerExtraStep(uint256 requestId) public view returns (bool) {
        return KelpLib._canTriggerExtraStep(requestId);
    }

    function triggerExtraStep(uint256 requestId) external {
        KelpLib._triggerExtraStep(requestId);
    }
}