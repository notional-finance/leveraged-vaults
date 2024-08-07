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

    uint256 internal constant WETH_PRECISION = 1e18;

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
        uint256 requestId, uint256 /* totalVaultShares */, uint256 /* stakeAssetPrice */
    ) internal override view returns (uint256) {
        uint256 tokenOutSY = getTokenOutSYForWithdrawRequest(requestId);
        // NOTE: in this vault the tokenOutSy is known to be weETH.
        (int256 weETHPrice, /* */) = TRADING_MODULE.getOraclePrice(TOKEN_OUT_SY, BORROW_TOKEN);
        return (tokenOutSY * weETHPrice.toUint() * BORROW_PRECISION) /
            (WETH_PRECISION * Constants.EXCHANGE_RATE_PRECISION);
    }

    function _initiateSYWithdraw(
        address /* account */, uint256 weETHOut, bool /* isForced */
    ) internal override returns (uint256 requestId) {
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
