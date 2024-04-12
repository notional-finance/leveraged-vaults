// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import { Constants } from "../../global/Constants.sol";
import { Deployments } from "@deployments/Deployments.sol";
import { BaseStakingVault, DepositParams } from "./BaseStakingVault.sol";
import { ClonedCoolDownHolder } from "./ClonedCoolDownHolder.sol";
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
} from "@interfaces/trading/ITradingModule.sol";
import { IERC4626 } from "@interfaces/IERC4626.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

interface IsUSDe is IERC4626, IERC20 {
    struct UserCooldown {
        uint104 cooldownEnd;
        uint152 underlyingAmount;
    }

    function cooldownDuration() external returns (uint24);
    function cooldowns(address account) external view returns (UserCooldown memory);
    function cooldownShares(uint256 shares) external returns (uint256 assets);
    function unstake(address receiver) external;
}

IsUSDe constant sUSDe = IsUSDe(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
IERC20 constant USDe = IERC20(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3);

contract EthenaCooldownHolder is ClonedCoolDownHolder {

    constructor(address _vault) ClonedCoolDownHolder(_vault) { }

    /// @notice There is no way to stop a cool down
    function _stopCooldown() internal pure override { revert(); }

    function _startCooldown() internal override {
        uint24 duration = sUSDe.cooldownDuration();
        uint256 balance = sUSDe.balanceOf(address(this));
        if (duration == 0) {
            // If the cooldown duration is set to zero, can redeem immediately
            sUSDe.redeem(balance, address(this), address(this));
        } else {
            // If we execute a second cooldown while one exists, the cooldown end
            // will be pushed further out. This holder should only ever have one
            // cooldown ever.
            require(sUSDe.cooldowns(address(this)).cooldownEnd == 0);
            sUSDe.cooldownShares(balance);
        }
    }

    function _finalizeCooldown() internal override returns (uint256 tokensClaimed, bool finalized) {
        uint24 duration = sUSDe.cooldownDuration();
        IsUSDe.UserCooldown memory userCooldown = sUSDe.cooldowns(address(this));

        if (block.timestamp < userCooldown.cooldownEnd && 0 < duration) {
            // Do not revert if the cooldown has not completed, will return a false
            // for the finalized state.
            return (0, false);
        }

        // If a cooldown has been initiated, need to call unstake to complete it. If
        // duration was set to zero then the USDe will be on this contract already.
        if (0 < userCooldown.cooldownEnd) {
            sUSDe.unstake(address(this));
        }

        // USDe is immutable. It cannot have a transfer tax and it is ERC20 compliant
        // so we do not need to use the additional protections here.
        tokensClaimed = USDe.balanceOf(address(this));
        USDe.transfer(vault, tokensClaimed);
        finalized = true;
    }
}

contract EthenaVault is BaseStakingVault {

    address public HOLDER_IMPLEMENTATION;

    constructor(
        NotionalProxy notional_,
        ITradingModule tradingModule_
    ) BaseStakingVault(notional_, tradingModule_, address(sUSDe), address(USDe)) { }

    function initialize(
        string memory name,
        uint16 borrowCurrencyId
    ) public override {
        super.initialize(name, borrowCurrencyId);
        HOLDER_IMPLEMENTATION = address(new EthenaCooldownHolder(address(this)));
    }

    function strategy() external override pure returns (bytes4) {
        return bytes4(keccak256("Staking:Ethena"));
    }

    function _stakeTokens(
        address /* account */,
        uint256 depositUnderlyingExternal,
        uint256 /* maturity */,
        bytes calldata data
    ) internal override returns (uint256 vaultShares) {
        address underlyingToken = address(_underlyingToken());
        uint256 usdeAmount;

        if (underlyingToken == address(USDe)) {
            usdeAmount = depositUnderlyingExternal;
        } else {
            // If not borrowing USDe directly, then trade into the position
            DepositParams memory params = abi.decode(data, (DepositParams));

            Trade memory trade = Trade({
                tradeType: TradeType.EXACT_IN_SINGLE,
                sellToken: underlyingToken,
                buyToken: address(USDe),
                amount: depositUnderlyingExternal,
                limit: params.minPurchaseAmount,
                deadline: block.timestamp,
                exchangeData: params.exchangeData
            });

            // Executes a trade on the given Dex, the vault must have permissions set for
            // each dex and token it wants to sell.
            (/* */, usdeAmount) = _executeTrade(params.dexId, trade);
        }

        uint256 sUSDeMinted = sUSDe.deposit(usdeAmount, address(this));
        vaultShares = sUSDeMinted * uint256(Constants.INTERNAL_TOKEN_PRECISION) /
            uint256(BORROW_PRECISION);
    }

    /// @notice This vault will always borrow USDe so the value returned in this method will
    /// always be USDe.
    function _getValueOfWithdrawRequest(
        WithdrawRequest memory w,
        uint256 /* stakeAssetPrice */
    ) internal override view returns (uint256 usdEValue) {
        if (w.hasSplit) {
            SplitWithdrawRequest memory s = getSplitWithdrawRequest(w.requestId);
            if (s.finalized) {
                // totalWithdraw is a USDe amount
                return (s.totalWithdraw * w.vaultShares) / s.totalVaultShares;
            }
        }

        address holder = address(uint160(w.requestId));
        // This valuation is the amount of USDe the account will receive at cooldown, once
        // a cooldown is initiated the account is no longer receiving sUSDe yield. This balance
        // of USDe is transferred to a Silo contract and guaranteed to be available once the
        // cooldown has passed.
        IsUSDe.UserCooldown memory userCooldown = sUSDe.cooldowns(holder);

        return userCooldown.underlyingAmount;
        /*
        // This is the current valuation of sUSDe at the current market price. If the cooldown
        // time window is extended, the price of sUSDe may drop relative to the price of USDe
        // which would reflect the current market expectation around redeeming sUSDe.
        uint256 valuation = (w.vaultShares * stakeAssetPrice * STAKING_PRECISION) /
            (uint256(Constants.INTERNAL_TOKEN_PRECISION) * 1e18);

        return SafeUint256.min(userCooldown.underlyingAmount, valuation);
        */
    }

    function _initiateWithdrawImpl(
        address /* account */, uint256 vaultSharesToRedeem, bool /* isForced */
    ) internal override returns (uint256 requestId) {
        EthenaCooldownHolder holder = EthenaCooldownHolder(Clones.clone(HOLDER_IMPLEMENTATION));
        uint256 balanceToTransfer = vaultSharesToRedeem * STAKING_PRECISION / uint256(Constants.INTERNAL_TOKEN_PRECISION);
        sUSDe.transfer(address(holder), balanceToTransfer);
        holder.startCooldown();

        return uint256(uint160(address(holder)));
    }

    function _finalizeWithdrawImpl(
        address /* account */,
        uint256 requestId
    ) internal override returns (uint256 tokensClaimed, bool finalized) {
        EthenaCooldownHolder holder = EthenaCooldownHolder(address(uint160(requestId)));
        (tokensClaimed, finalized) = holder.finalizeCooldown();
    }

    function _checkReentrancyContext() internal override {
        // NO-OP
    }
}