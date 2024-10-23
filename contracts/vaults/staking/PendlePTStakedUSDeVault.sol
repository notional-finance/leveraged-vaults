// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {Constants} from "@contracts/global/Constants.sol";
import {Deployments} from "@deployments/Deployments.sol";
import {PendlePrincipalToken, WithdrawRequest, RedeemParams} from "./protocols/PendlePrincipalToken.sol";
import {
    EthenaLib, EthenaCooldownHolder, sUSDe, USDe, SplitWithdrawRequest
} from "./protocols/Ethena.sol";

contract PendlePTStakedUSDeVault is PendlePrincipalToken {
    address public HOLDER_IMPLEMENTATION;

    constructor(
        address marketAddress,
        address ptAddress,
        address borrowToken
    ) PendlePrincipalToken(
        marketAddress,
        address(USDe),
        address(sUSDe),
        borrowToken,
        ptAddress,
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

    function _executeInstantRedemption(
        address /* account */,
        uint256 vaultShares,
        uint256 /* maturity */,
        RedeemParams memory params
    ) internal override returns (uint256 borrowedCurrencyAmount) {
        uint256 sUSDeToSell = _redeemPT(vaultShares);

        // Selling sUSDe requires special handling since most of the liquidity
        // sits inside a sUSDe/sDAI pool on Curve.
        return EthenaLib._sellStakedUSDe(
            sUSDeToSell, BORROW_TOKEN, params.minPurchaseAmount, params.exchangeData, params.dexId
        );
    }

    /// @notice Returns the value of a withdraw request in terms of the borrowed token
    function _getValueOfWithdrawRequest(
        uint256 requestId, uint256 /* totalVaultShares */, uint256 /* stakeAssetPrice */
    ) internal override view returns (uint256) {
        // NOTE: This withdraw valuation is not based on the vault shares value so we do not
        // need to use the PendlePT metadata conversion.
        return EthenaLib._getValueOfWithdrawRequest(requestId, BORROW_TOKEN, BORROW_PRECISION);
    }

    function _initiateSYWithdraw(
        address /* account */, uint256 sUSDeOut, bool /* isForced */
    ) internal override returns (uint256 requestId) {
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