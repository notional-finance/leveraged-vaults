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
        WithdrawRequest memory w, uint256 /* */
    ) internal override view returns (uint256) {
        return KelpLib._getValueOfWithdrawRequest(w, BORROW_TOKEN, BORROW_PRECISION);
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