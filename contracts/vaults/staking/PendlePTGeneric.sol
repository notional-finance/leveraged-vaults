// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import { PendlePrincipalToken, WithdrawRequest } from "./protocols/PendlePrincipalToken.sol";

contract PendlePTGeneric is PendlePrincipalToken {

    constructor(
        address market,
        address tokenInSY,
        address tokenOutSY,
        address borrowToken,
        address ptToken,
        address redemptionToken
    ) PendlePrincipalToken(market, tokenInSY, tokenOutSY, borrowToken, ptToken, redemptionToken) {
        // NO-OP
    }

    function strategy() external override pure returns (bytes4) {
        return bytes4(keccak256("Staking:PendlePT:Generic"));
    }

    function _getValueOfWithdrawRequest(
        uint256 /* requestId */, uint256 /* totalVaultShares */, uint256 /* stakeAssetPrice */
    ) internal override view returns (uint256) {
        revert("Unimplemented");
    }

    function _initiateSYWithdraw(
        address /* account */, uint256 /* */, bool /* isForced */
    ) internal pure override returns (uint256) {
        revert("Unimplemented");
    }

    function _finalizeWithdrawImpl(
        address /* */, uint256 /* */
    ) internal pure override returns (uint256, bool) {
        revert("Unimplemented");
    }

    function canFinalizeWithdrawRequest(uint256 /* */) public override pure returns (bool) {
        return false;
    }

}