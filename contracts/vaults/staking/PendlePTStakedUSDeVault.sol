// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {Constants} from "@contracts/global/Constants.sol";
import {Deployments} from "@deployments/Deployments.sol";
import {PendlePrincipalToken, WithdrawRequest} from "./protocols/PendlePrincipalToken.sol";
import {
    EthenaLib, EthenaCooldownHolder, sUSDe, USDe, SplitWithdrawRequest
} from "./protocols/Ethena.sol";

contract PendlePTStakedUSDeVault is PendlePrincipalToken {
    address public HOLDER_IMPLEMENTATION;

    constructor() PendlePrincipalToken(
        address(0), // market address
        address(USDe),
        address(sUSDe),
        address(USDe),
        address(0),             // PT token address
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
        return bytes4(keccak256("Staking:PendlePT:sUSDe"));
    }

    /// @notice Returns the value of a withdraw request in terms of the borrowed token
    function _getValueOfWithdrawRequest(
        WithdrawRequest memory w, uint256 /* */
    ) internal override view returns (uint256) {
        return EthenaLib._getValueOfWithdrawRequest(w, BORROW_TOKEN, BORROW_PRECISION);
    }

    function _getValueOfSplitWithdrawRequest(
        WithdrawRequest memory w, SplitWithdrawRequest memory s, uint256 /* */
    ) internal override view returns (uint256) {
        return EthenaLib._getValueOfSplitWithdrawRequest(w, s, BORROW_TOKEN, BORROW_PRECISION);
    }

    function _getValueOfSplitFinalizedWithdrawRequest(
        WithdrawRequest memory w, SplitWithdrawRequest memory s, uint256 /* */
    ) internal override view returns (uint256) {
        return EthenaLib._getValueOfSplitFinalizedWithdrawRequest(w, s, BORROW_TOKEN);
    }

    function _initiateWithdrawImpl(
        address /* account */, uint256 vaultSharesToRedeem, bool /* isForced */
    ) internal override returns (uint256 requestId) {
        uint256 sUSDeOut = _redeemPT(vaultSharesToRedeem);
        return EthenaLib._initiateWithdrawImpl(sUSDeOut, HOLDER_IMPLEMENTATION);
    }

    function _finalizeWithdrawImpl(
        address /* account */, uint256 requestId
    ) internal override returns (uint256 tokensClaimed, bool finalized) {
        return EthenaLib._finalizeWithdrawImpl(requestId);
    }

    function canFinalizeWithdrawRequest(uint256 requestId) public override view returns (bool) {
        return EthenaLib._canFinalizeWithdrawRequest(requestId);
    }
}