// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {Constants} from "@contracts/global/Constants.sol";
import {TypeConvert} from "@contracts/global/TypeConvert.sol";
import {Deployments} from "@deployments/Deployments.sol";
import {
    PendlePrincipalToken,
    WithdrawRequest
} from "./protocols/PendlePrincipalToken.sol";
import {EtherFiLib, weETH, SplitWithdrawRequest} from "./protocols/EtherFi.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract PendlePTEtherFiVault is PendlePrincipalToken, IERC721Receiver {
    using TypeConvert for int256;

    constructor(
        address marketAddress,
        address ptAddress
    ) PendlePrincipalToken(
        marketAddress,
        Constants.ETH_ADDRESS,
        address(weETH),
        Constants.ETH_ADDRESS,
        ptAddress,
        Constants.ETH_ADDRESS
    ) {
        // Addresses in this vault are hardcoded to mainnet
        require(block.chainid == Constants.CHAIN_ID_MAINNET);
    }

    /// @notice this method is needed in order to receive NFT from EtherFi after
    /// withdraw is requested
    function onERC721Received(
        address /* operator */, address /* from */, uint256 /* tokenId */, bytes calldata /* data */
    ) external override pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function strategy() external override pure returns (bytes4) {
        return bytes4(keccak256("Staking:PendlePT:weETH"));
    }

    function _getValueOfWithdrawRequest(
        WithdrawRequest memory w, uint256 weETHPrice
    ) internal override view returns (uint256) {
        return EtherFiLib._getValueOfWithdrawRequest(w, weETHPrice, BORROW_PRECISION);
    }

    /// @notice In a split request, the value is based on the w.vaultShares value so this method is the
    /// same as _getValueOfWithdrawRequest
    function _getValueOfSplitWithdrawRequest(
        WithdrawRequest memory w, SplitWithdrawRequest memory, uint256 weETHPrice
    ) internal override view returns (uint256) {
        return EtherFiLib._getValueOfWithdrawRequest(w, weETHPrice, BORROW_PRECISION);
    }

    function _getValueOfSplitFinalizedWithdrawRequest(
        WithdrawRequest memory w, SplitWithdrawRequest memory s, uint256
    ) internal override view returns (uint256) {
        return EtherFiLib._getValueOfSplitFinalizedWithdrawRequest(w, s, BORROW_TOKEN);
    }

    function _initiateWithdrawImpl(
        address /* account */, uint256 vaultSharesToRedeem, bool /* isForced */
    ) internal override returns (uint256 requestId) {
        uint256 weETHOut = _redeemPT(vaultSharesToRedeem);
        return EtherFiLib._initiateWithdrawImpl(weETHOut);
    }

    function _finalizeWithdrawImpl(
        address /* account */, uint256 requestId
    ) internal override returns (uint256 tokensClaimed, bool finalized) {
        return EtherFiLib._finalizeWithdrawImpl(requestId);
    }

    function canFinalizeWithdrawRequest(uint256 requestId) public override view returns (bool) {
        return EtherFiLib._canFinalizeWithdrawRequest(requestId);
    }
}
