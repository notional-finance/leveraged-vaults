// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {Constants} from "@contracts/global/Constants.sol";
import {Deployments} from "@deployments/Deployments.sol";
import {
    PendlePrincipalToken,
    WithdrawRequest
} from "./protocols/PendlePrincipalToken.sol";
import {EtherFiLib, weETH} from "./protocols/EtherFi.sol";

contract PendlePTEtherFiVault is PendlePrincipalToken {
    constructor() PendlePrincipalToken(
        address(0), // market address
        Constants.ETH_ADDRESS,
        address(weETH),
        Constants.ETH_ADDRESS,
        1 hours,
        false,
        address(0),             // PT token address
        Constants.ETH_ADDRESS
    ) {
        // Addresses in this vault are hardcoded to mainnet
        require(block.chainid == Constants.CHAIN_ID_MAINNET);
    }

    function strategy() external override pure returns (bytes4) {
        return bytes4(keccak256("Staking:PendlePT:weETH"));
    }

    function _getValueOfWithdrawRequest(
        WithdrawRequest memory w, uint256 stakeAssetPrice
    ) internal override view returns (uint256 usdEValue) {
        return EtherFiLib._getValueOfWithdrawRequest(
            w, stakeAssetPrice, BORROW_PRECISION, EXCHANGE_RATE_PRECISION
        );
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
}
