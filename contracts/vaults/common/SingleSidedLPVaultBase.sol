// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {BaseStrategyVault} from "../BaseStrategyVault.sol";
import {Errors} from "../../global/Errors.sol";
import {Constants} from "../../global/Constants.sol";
import {TypeConvert} from "../../global/TypeConvert.sol";
import {VaultEvents} from "./VaultEvents.sol";
import {TokenUtils} from "../../utils/TokenUtils.sol";
import {
    StrategyVaultState,
    StrategyContext,
    SingleSidedRewardTradeParams,
    DepositParams,
    DepositTradeParams,
    RedeemParams,
    TradeParams
} from "./VaultTypes.sol";
import {StrategyUtils} from "./internal/strategy/StrategyUtils.sol";
import {VaultStorage} from "./VaultStorage.sol";
import {VaultConstants} from "./VaultConstants.sol";

import {IERC20} from "../../../interfaces/IERC20.sol";
import {
    ISingleSidedLPStrategyVault,
    StrategyVaultSettings,
    InitParams
} from "../../../interfaces/notional/ISingleSidedLPStrategyVault.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {ITradingModule, DexId} from "../../../interfaces/trading/ITradingModule.sol";

/**
 * Base vault contract that implements common utility functions
 */
abstract contract SingleSidedLPVaultBase is BaseStrategyVault, UUPSUpgradeable, ISingleSidedLPStrategyVault {
    using TypeConvert for uint256;
    using VaultStorage for StrategyVaultState;
    using StrategyUtils for StrategyContext;

    uint256 internal constant MAX_TOKENS = 5;
    uint8 internal constant NOT_FOUND = type(uint8).max;

    /**
     * These constants are intended to be immutables set by the parent constructor,
     * but this is not easily achievable given how the solidity constructor works.
     */
    function NUM_TOKENS() internal view virtual returns (uint256);
    function TOKENS() internal view virtual returns (IERC20[] memory, uint8[] memory decimals);
    function POOL_TOKEN() internal view virtual returns (IERC20);
    function PRIMARY_INDEX() internal view virtual returns (uint256);
    function POOL_PRECISION() internal view virtual returns (uint256);

    function getStrategyVaultInfo() public view override returns (SingleSidedLPStrategyVaultInfo memory) {
        StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
        return SingleSidedLPStrategyVaultInfo({
            pool: address(POOL_TOKEN()),
            singleSidedTokenIndex: uint8(PRIMARY_INDEX()),
            totalLPTokens: state.totalPoolClaim,
            totalVaultShares: state.totalVaultSharesGlobal
        });
    }

    constructor(NotionalProxy notional_, ITradingModule tradingModule_)
        BaseStrategyVault(notional_, tradingModule_) {}

    function isLocked() public view returns (bool) {
        StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
        return _hasFlag(state.flags, VaultConstants.FLAG_LOCKED);
    }

    /// @notice Allows the function to execute only when the vault is not locked
    modifier whenNotLocked() {
        if (isLocked()) revert Errors.VaultLocked();
        _;
    }

    /// @notice Allows the function to execute only when the vault is locked
    modifier whenLocked() {
        if (!isLocked()) revert Errors.VaultNotLocked();
        _;
    }

    /// @notice Checks if a flag bit is set
    /// @param flags 32-bit flags
    /// @param flagID flag mask
    /// @return true if the flag is set, false otherwise
    function _hasFlag(uint32 flags, uint32 flagID) private pure returns (bool) {
        return (flags & flagID) == flagID;
    }

    /// @notice Locks the vault, preventing deposits and redemptions
    function _lockVault() internal {
        StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
        // Set locked flag
        state.flags = state.flags | VaultConstants.FLAG_LOCKED;
        VaultStorage.setStrategyVaultState(state);
        emit VaultEvents.VaultLocked();
    }

    /// @notice Unlocks the vault
    function _unlockVault() internal {
        StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
        // Remove locked flag
        state.flags = state.flags & ~VaultConstants.FLAG_LOCKED;
        VaultStorage.setStrategyVaultState(state);
        emit VaultEvents.VaultUnlocked();
    }

    /// @notice Allow Notional owner to upgrade the contract
    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal override onlyNotionalOwner {}

    /// @notice Updates the vault settings
    /// @param settings vault settings
    function setStrategyVaultSettings(StrategyVaultSettings calldata settings) external onlyNotionalOwner {
        // Settings are validated in setStrategyVaultSettings
        VaultStorage.setStrategyVaultSettings(settings);
    }

    /// @notice Initializes the strategy
    /// @param params init parameters
    function initialize(InitParams calldata params) external override initializer onlyNotionalOwner {
        // Initialize the base vault
        __INIT_VAULT(params.name, params.borrowCurrencyId);

        // Settings are validated in setStrategyVaultSettings
        VaultStorage.setStrategyVaultSettings(params.settings);

        _initialApproveTokens();
    }

    /// @notice Allows the emergency exit role to trigger an emergency exit on the vault.
    /// In this situation, the `claimToExit` is withdrawn proportionally to the underlying
    /// tokens and held on the vault. The vault is locked so that no entries, exits or
    /// valuations of vaultShares can be performed.
    /// @param claimToExit if this is set to zero, the entire pool claim is withdrawn
    function emergencyExit(
        uint256 claimToExit, bytes calldata /* data */
    ) external override onlyRole(EMERGENCY_EXIT_ROLE) {
        StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
        if (claimToExit == 0) claimToExit = state.totalPoolClaim;

        // By setting min amounts to zero, we will accept whatever tokens come from the pool
        // in a proportional exit. Front running will not have an effect since no trading will
        // occur during a proportional exit.
        _unstakeAndExitPool(claimToExit, new uint256[](NUM_TOKENS()), true);

        state.totalPoolClaim = state.totalPoolClaim - claimToExit;
        state.setStrategyVaultState();

        emit VaultEvents.EmergencyExit(claimToExit);
        _lockVault();
    }

    /// @notice Restores withdrawn tokens from emergencyExit back into the vault proportionally.
    /// Unlocks the vault after restoration so that normal functionality is restored.
    /// @param minPoolClaim slippage limit to prevent front running
    function restoreVault(
        uint256 minPoolClaim, bytes calldata /* data */
    ) external override whenLocked onlyNotionalOwner {
        StrategyVaultState memory state = VaultStorage.getStrategyVaultState();

        (IERC20[] memory tokens, /* */) = TOKENS();
        uint256[] memory amounts = new uint256[](tokens.length);

        for (uint256 i; i < tokens.length; i++) {
            if (address(tokens[i]) == address(POOL_TOKEN())) continue;
            amounts[i] = TokenUtils.tokenBalance(address(tokens[i]));
        }

        // No trades are specified so this joins proportionally
        uint256 poolTokens = _joinPoolAndStake(amounts, minPoolClaim);

        state.totalPoolClaim = state.totalPoolClaim + poolTokens;
        state.setStrategyVaultState();

        _unlockVault();
    }

    /// @notice Reverts if the vault is locked during emergency exit.
    function convertStrategyToUnderlying(
        address /* */, uint256 vaultShares, uint256 /* */
    ) public view override whenNotLocked returns (int256 underlyingValue) {
        StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
        // Will revert on divide by zero, which is the correct behavior
        uint256 lpTokens = (vaultShares * state.totalPoolClaim) / state.totalVaultSharesGlobal;
        uint256 oneLPValueInPrimary = _checkPriceAndCalculateValue();

        return (oneLPValueInPrimary * lpTokens / POOL_PRECISION()).toInt();
    }

    function _depositFromNotional(
        address /* account */, uint256 deposit, uint256 /* maturity */, bytes calldata data
    ) internal override whenNotLocked returns (uint256 vaultSharesMinted) {
        DepositParams memory params = abi.decode(data, (DepositParams));
        uint256[] memory amounts = new uint256[](NUM_TOKENS());
        amounts[PRIMARY_INDEX()] = deposit;

        if (params.depositTrades.length > 0) {
            amounts = _executeDepositTrades(amounts, params.depositTrades);
        }

        uint256 lpTokens = _joinPoolAndStake(amounts, params.minPoolClaim);
        return _mintVaultShares(lpTokens);
    }

    function _redeemFromNotional(
        address /* account */, uint256 vaultShares, uint256 /* maturity */, bytes calldata data
    ) internal override whenNotLocked returns (uint256 finalPrimaryBalance) {
        uint256 poolClaim = _redeemVaultShares(vaultShares);
        RedeemParams memory params = abi.decode(data, (RedeemParams));

        bool isSingleSided = params.redemptionTrades.length == 0;
        uint256[] memory exitBalances = _unstakeAndExitPool(poolClaim, params.minAmounts, isSingleSided);
        if (!isSingleSided) {
            return _executeRedemptionTrades(exitBalances, params.redemptionTrades);
        } else {
            return exitBalances[PRIMARY_INDEX()];
        }
    }

    function claimRewardTokens() external override onlyRole(REWARD_REINVESTMENT_ROLE) {
        _claimRewardTokens();
    }

    function reinvestReward(
        SingleSidedRewardTradeParams[] calldata trades,
        uint256 minPoolClaim
    ) external whenNotLocked onlyRole(REWARD_REINVESTMENT_ROLE) returns (
        address rewardToken,
        uint256 amountSold,
        uint256 poolClaimAmount
    ) {
        // Will revert if spot prices are not in line with the oracle values
        _checkPriceAndCalculateValue();

        // Require one trade per token, if we do not want to buy any tokens at a
        // given index then the amount should be set to zero.
        require(trades.length == NUM_TOKENS());
        uint256[] memory amounts;
        (rewardToken, amountSold, amounts) = _executeRewardTrades(trades);

        poolClaimAmount = _joinPoolAndStake(amounts, minPoolClaim);

        // TODO: Ensure that we do not exceed the max LP pool threshold
        // context._checkPoolThreshold(_totalPoolSupply(), poolClaimAmount);

        // Increase LP token amount without minting additional vault shares
        StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
        state.totalPoolClaim += poolClaimAmount;
        state.setStrategyVaultState();

        emit VaultEvents.RewardReinvested(rewardToken, amountSold, poolClaimAmount);
    }

    function _executeRewardTrades(SingleSidedRewardTradeParams[] calldata trades) internal returns (
        address rewardToken,
        uint256 amountSold,
        uint256[] memory amounts
    ) {
        // Ensure that we have sufficient permissions to execute reward trades.
        require(_canUseStaticSlippage());

        rewardToken = trades[0].sellToken;
        _validateRewardToken(rewardToken);
        (IERC20[] memory tokens, /* */) = TOKENS();
        amounts = new uint256[](trades.length);

        for (uint256 i; i < trades.length; i++) {
            // All trades must sell the same token.
            require(trades[i].sellToken == rewardToken);
            // Bypass certain invalid trades
            if (trades[i].amount == 0) continue;
            if (trades[i].buyToken == address(POOL_TOKEN())) continue;

            // The reward trade can only purchase tokens that go into the pool
            require(trades[i].buyToken == address(tokens[i]));

            (uint256 sold, uint256 bought) = StrategyUtils._executeTradeWithStaticSlippage(
                TRADING_MODULE, trades[i].tradeParams, rewardToken, trades[i].buyToken, trades[i].amount
            );
            amounts[i] = bought;
            amountSold += sold;
        }
    }

    /// @notice Execute trades from a number of secondary tokens back to the
    /// primary balance for exits.
    function _executeDepositTrades(
        uint256[] memory amounts,
        DepositTradeParams[] memory depositTrades
    ) internal returns (uint256[] memory) {
        (IERC20[] memory tokens, /* */) = TOKENS();
        address primaryToken = address(tokens[PRIMARY_INDEX()]);

        for (uint256 i; i < amounts.length; i++) {
            if (i == PRIMARY_INDEX()) continue;
            DepositTradeParams memory t = depositTrades[i];
            // Do not allow ZERO_EX trading in this method since we cannot validate
            // the arbitrary exchange data.
            if (DexId(t.tradeParams.dexId) == DexId.ZERO_EX) revert Errors.InvalidDexId(uint256(DexId.ZERO_EX));

            (uint256 amountSold, uint256 amountBought) = StrategyUtils._executeDynamicSlippageTradeExactIn(
                TRADING_MODULE, t.tradeParams, primaryToken, address(tokens[i]), t.tradeAmount
            );

            amounts[i] = amountBought;
            amounts[PRIMARY_INDEX()] -= amountSold;
        }

        return amounts;
    }

    function _executeRedemptionTrades(
        uint256[] memory exitBalances,
        TradeParams[] memory redemptionTrades
    ) internal returns (uint256 finalPrimaryBalance) {
        (IERC20[] memory tokens, /* */) = TOKENS();
        address primaryToken = address(tokens[PRIMARY_INDEX()]);

        for (uint256 i; i < exitBalances.length; i++) {
            if (i == PRIMARY_INDEX()) finalPrimaryBalance += exitBalances[i];
            TradeParams memory t = redemptionTrades[i];
            // Do not allow ZERO_EX trading in this method since we cannot validate
            // the arbitrary exchange data.
            if (DexId(t.dexId) == DexId.ZERO_EX) revert Errors.InvalidDexId(uint256(DexId.ZERO_EX));

            if (exitBalances[i] > 0) {
                (/* */, uint256 amountBought) = StrategyUtils._executeDynamicSlippageTradeExactIn(
                    TRADING_MODULE, t, address(tokens[i]), primaryToken, exitBalances[i]
                );

                finalPrimaryBalance += amountBought;
            }
        }
    }

    function _mintVaultShares(uint256 lpTokens) internal returns (uint256 vaultShares) {
        StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
        uint256 maxPoolShare = VaultStorage.getStrategyVaultSettings().maxPoolShare;
        if (state.totalPoolClaim == 0) {
            // Vault Shares are in 8 decimal precision
            vaultShares = (lpTokens * uint256(Constants.INTERNAL_TOKEN_PRECISION)) / POOL_PRECISION();
        } else {
            vaultShares = (lpTokens * state.totalVaultSharesGlobal) / state.totalPoolClaim;
        }

        state.totalPoolClaim += lpTokens;
        state.totalVaultSharesGlobal += vaultShares.toUint80();
        state.setStrategyVaultState();

        uint256 maxSupplyThreshold = (_totalPoolSupply() * maxPoolShare) / VaultConstants.VAULT_PERCENT_BASIS;
        if (maxSupplyThreshold < state.totalPoolClaim)
            revert Errors.PoolShareTooHigh(state.totalPoolClaim, maxSupplyThreshold);
    }

    function _redeemVaultShares(uint256 vaultShares) internal returns (uint256 poolClaim) {
        StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
        // Will revert on divide by zero, which is the correct behavior
        poolClaim = (vaultShares * state.totalPoolClaim) / state.totalVaultSharesGlobal;

        state.totalPoolClaim -= poolClaim;
        // Will revert on underflow if vault shares is greater than total shares global
        state.totalVaultSharesGlobal -= vaultShares.toUint80();
        state.setStrategyVaultState();
    }

    function _totalPoolSupply() internal view virtual returns (uint256) {
        return POOL_TOKEN().totalSupply();
    }

    function _getOraclePairPrice(address base, address quote) internal view returns (uint256) {
        (int256 rate, int256 precision) = TRADING_MODULE.getOraclePrice(base, quote);
        require(rate > 0);
        require(precision > 0);
        return uint256(rate) * POOL_PRECISION() / uint256(precision);
    }

    function _checkPriceAndCalculateValue() internal view virtual returns (uint256 oneLPValueInPrimary);

    function _calculateLPTokenValue(
        uint256[] memory balances,
        uint256[] memory spotPrices
    ) internal view returns (uint256 oneLPValueInPrimary) {
        (IERC20[] memory tokens, uint8[] memory decimals) = TOKENS();
        address primaryToken = address(tokens[PRIMARY_INDEX()]);
        uint256 primaryDecimals = 10 ** decimals[PRIMARY_INDEX()];
        uint256 totalSupply = _totalPoolSupply();
        uint256 limit = VaultStorage.getStrategyVaultSettings().oraclePriceDeviationLimitPercent;

        for (uint256 i; i < tokens.length; i++) {
            // Skip the pool token if it is in the token list (i.e. ComposablePools)
            if (address(tokens[i]) == address(POOL_TOKEN())) continue;
            // This is the claim on the pool balance of 1 LP token.
            uint256 tokenClaim = balances[i] * POOL_PRECISION() / totalSupply;
            if (i == PRIMARY_INDEX()) {
                oneLPValueInPrimary += tokenClaim;
            } else {
                // Convert the token claim to primary using the oracle pair price
                uint256 price = _getOraclePairPrice(primaryToken, address(tokens[i]));
                uint256 lowerLimit = price * (VaultConstants.VAULT_PERCENT_BASIS - limit) / VaultConstants.VAULT_PERCENT_BASIS;
                uint256 upperLimit = price * (VaultConstants.VAULT_PERCENT_BASIS + limit) / VaultConstants.VAULT_PERCENT_BASIS;
                if (spotPrices[i] < lowerLimit || upperLimit < spotPrices[i]) {
                    revert Errors.InvalidPrice(price, spotPrices[i]);
                }

                uint256 secondaryDecimals = 10 ** decimals[i];
                oneLPValueInPrimary += (tokenClaim * price * primaryDecimals) / 
                    (POOL_PRECISION() * secondaryDecimals);
            }
        }
    }

    /// @notice Called once during initialization to set the initial token approvals.
    function _initialApproveTokens() internal virtual;

    /// @notice Called to claim reward tokens
    function _claimRewardTokens() internal virtual;

    function _validateRewardToken(address token) internal view virtual;

    function _joinPoolAndStake(
        uint256[] memory amounts, uint256 minPoolClaim
    ) internal virtual returns (uint256 lpTokens);

    function _unstakeAndExitPool(
        uint256 poolClaim, uint256[] memory minAmounts, bool isSingleSided
    ) internal virtual returns (uint256[] memory exitBalances);

    // Storage gap for future potential upgrades
    uint256[100] private __gap;
}