// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import {Constants} from "@contracts/global/Constants.sol";
import {Deployments} from "@deployments/Deployments.sol";
import {BaseStakingVault, RedeemParams} from "./BaseStakingVault.sol";
import {WithdrawRequest, SplitWithdrawRequest} from "../common/WithdrawRequestBase.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {EtherFiLib, weETH, eETH, LiquidityPool} from "./protocols/EtherFi.sol";

/** Borrows ETH or an LST and stakes the tokens in EtherFi */
contract EtherFiVault is BaseStakingVault, IERC721Receiver {

    constructor(address borrowToken) BaseStakingVault(address(weETH), borrowToken, Constants.ETH_ADDRESS) {
        // Addresses in this vault are hardcoded to mainnet
        require(block.chainid == Constants.CHAIN_ID_MAINNET);
    }

    function _initialize() internal override {
        // Required for minting weETH
        eETH.approve(address(weETH), type(uint256).max);
    }

    function strategy() external override pure returns (bytes4) {
        return bytes4(keccak256("Staking:weETH"));
    }

    /// @notice this method is needed in order to receive NFT from EtherFi after
    /// withdraw is requested
    function onERC721Received(
        address /* operator */, address /* from */, uint256 /* tokenId */, bytes calldata /* data */
    ) external override pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function _stakeTokens(
        address /* account */,
        uint256 depositUnderlyingExternal,
        uint256 /* maturity */,
        bytes calldata /* data */
    ) internal override returns (uint256 vaultShares) {
        uint256 eEthBalBefore = eETH.balanceOf(address(this));
        LiquidityPool.deposit{value: depositUnderlyingExternal}();
        uint256 eETHMinted = eETH.balanceOf(address(this)) - eEthBalBefore;
        uint256 weETHReceived = weETH.wrap(eETHMinted);
        vaultShares = weETHReceived * uint256(Constants.INTERNAL_TOKEN_PRECISION) / STAKING_PRECISION;
    }

    function _initiateWithdrawImpl(
        address /* account */, uint256 vaultSharesToRedeem, bool /* isForced */, bytes calldata /* data */
    ) internal override returns (uint256 requestId) {
        uint256 weETHToUnwrap = getStakingTokensForVaultShare(vaultSharesToRedeem);
        return EtherFiLib._initiateWithdrawImpl(weETHToUnwrap);
    }

    function _getValueOfWithdrawRequest(
        uint256 /* requestId */, uint256 totalVaultShares, uint256 weETHPrice
    ) internal override view returns (uint256) {
        return EtherFiLib._getValueOfWithdrawRequest(totalVaultShares, weETHPrice, BORROW_PRECISION);
    }

    function _finalizeWithdrawImpl( address /* */, uint256 requestId) internal override returns (uint256, bool) {
        return EtherFiLib._finalizeWithdrawImpl(requestId);
    }

    function canFinalizeWithdrawRequest(uint256 requestId) public override view returns (bool) {
        return EtherFiLib._canFinalizeWithdrawRequest(requestId);
    }

    function _checkReentrancyContext() internal override {
        // NO-OP
    }
}