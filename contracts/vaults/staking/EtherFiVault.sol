// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import { Constants } from "../../global/Constants.sol";
import { Deployments } from "@deployments/Deployments.sol";
import { 
    BaseStakingVault,
    RedeemParams
} from "./BaseStakingVault.sol";
import { 
    WithdrawRequest,
    SplitWithdrawRequest
} from "../common/WithdrawRequestBase.sol";
import { 
    IERC20,
    NotionalProxy
} from "../common/BaseStrategyVault.sol";
import {
    ITradingModule,
    Trade,
    TradeType
} from "../../../interfaces/trading/ITradingModule.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface IeETH is IERC20 { }

interface IweETH is IERC20 {
    function wrap(uint256 eETHDeposit) external returns (uint256 weETHMinted);
    function unwrap(uint256 weETHDeposit) external returns (uint256 eETHMinted);
}

interface ILiquidityPool {
    function deposit() external payable returns (uint256 eETHMinted);
    function requestWithdraw(address requester, uint256 eETHAmount) external returns (uint256 requestId);
}

interface IWithdrawRequestNFT {
    function ownerOf(uint256 requestId) external view returns (address);
    function isFinalized(uint256 requestId) external view returns (bool);
    function getClaimableAmount(uint256 requestId) external view returns (uint256);
    function claimWithdraw(uint256 requestId) external;
    function finalizeRequests(uint256 requestId) external;
}

contract EtherFiVault is BaseStakingVault, IERC721Receiver {
    IweETH public constant weETH = IweETH(0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee);
    IeETH internal constant eETH = IeETH(0x35fA164735182de50811E8e2E824cFb9B6118ac2);
    ILiquidityPool internal constant LiquidityPool = ILiquidityPool(0x308861A430be4cce5502d0A12724771Fc6DaF216);
    IWithdrawRequestNFT public constant WithdrawRequestNFT =
        IWithdrawRequestNFT(0x7d5706f6ef3F89B3951E23e557CDFBC3239D4E2c);

    constructor(
        NotionalProxy notional_,
        ITradingModule tradingModule_
    ) BaseStakingVault(
        notional_,
        tradingModule_,
        address(weETH),
        Constants.ETH_ADDRESS
    ) { }

    function _initialize() internal override {
        // Required for minting weETH
        eETH.approve(address(weETH), type(uint256).max);
    }

    function strategy() external override pure returns (bytes4) {
        return bytes4(keccak256("Staking:EtherFi"));
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
        uint256 eETHMinted = LiquidityPool.deposit{value: depositUnderlyingExternal}();
        uint256 weETHReceived = weETH.wrap(eETHMinted);
        vaultShares = weETHReceived * uint256(Constants.INTERNAL_TOKEN_PRECISION) /
            uint256(BORROW_PRECISION);
    }

    function _initiateWithdrawImpl(
        address /* account */, uint256 vaultSharesToRedeem, bool /* isForced */
    ) internal override returns (uint256 requestId) {
        uint256 weETHToUnwrap = vaultSharesToRedeem * BORROW_PRECISION /
            uint256(Constants.INTERNAL_TOKEN_PRECISION);
        uint256 eETHReceived = weETH.unwrap(weETHToUnwrap);

        eETH.approve(address(LiquidityPool), eETHReceived);
        return LiquidityPool.requestWithdraw(address(this), eETHReceived);
    }

    function _getValueOfWithdrawRequest(
        WithdrawRequest memory w,
        uint256 weETHPrice
    ) internal override view returns (uint256 ethValue) {
        if (w.requestId == 0) return 0;

        if (w.hasSplit) {
            SplitWithdrawRequest memory s = getSplitWithdrawRequest(w.requestId);
            // Check if the withdraw request has been claimed if the
            // request has been split, the value is the share of the ETH
            // claimed with no discount b/c the ETH is already held in the
            // vault contract.
            if (WithdrawRequestNFT.ownerOf(w.requestId) == address(0)) {
                return (s.totalWithdraw * w.vaultShares) / s.totalVaultShares;
            } else {
                return (w.vaultShares * weETHPrice * BORROW_PRECISION) /
                    (s.totalVaultShares * EXCHANGE_RATE_PRECISION);
            }
        }

        return (w.vaultShares * weETHPrice * BORROW_PRECISION) /
            (uint256(Constants.INTERNAL_TOKEN_PRECISION) * EXCHANGE_RATE_PRECISION);
    }

    function _finalizeWithdrawImpl(
        address /* account */,
        uint256 requestId
    ) internal override returns (uint256 tokensClaimed, bool finalized) {
        finalized = (
            WithdrawRequestNFT.isFinalized(requestId) &&
            WithdrawRequestNFT.ownerOf(requestId) != address(0)
        );

        if (finalized) {
            uint256 balanceBefore = address(this).balance;
            WithdrawRequestNFT.claimWithdraw(requestId);
            tokensClaimed = address(this).balance - balanceBefore;
        }
    }

    function _checkReentrancyContext() internal override {
        // NO-OP
    }
}