// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {Constants} from "@contracts/global/Constants.sol";
import {Deployments} from "@deployments/Deployments.sol";
import {
    PendlePrincipalToken,
    WithdrawRequest
} from "./protocols/PendlePrincipalToken.sol";
import {
    EthenaLib, EthenaCooldownHolder, sUSDe, USDe
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

    function _getValueOfWithdrawRequest(
        WithdrawRequest memory w, uint256 /* stakeAssetPrice */
    ) internal override view returns (uint256) {
        return EthenaLib._getValueOfWithdrawRequest(w, BORROW_TOKEN, BORROW_PRECISION);
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
}