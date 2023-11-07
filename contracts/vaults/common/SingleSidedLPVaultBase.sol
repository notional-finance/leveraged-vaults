// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {BaseStrategyVault} from "../BaseStrategyVault.sol";
import {Errors} from "../../global/Errors.sol";
import {TypeConvert} from "../../global/TypeConvert.sol";
import {VaultEvents} from "./VaultEvents.sol";
import {
    StrategyVaultState,
    StrategyContext,
    SingleSidedRewardTradeParams,
    DepositParams,
    RedeemParams
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
import {ITradingModule} from "../../../interfaces/trading/ITradingModule.sol";

/**
 * Base vault contract that implements common utility functions
 */
abstract contract SingleSidedLPVaultBase is BaseStrategyVault, UUPSUpgradeable, ISingleSidedLPStrategyVault {
    using VaultStorage for StrategyVaultState;
    using StrategyUtils for StrategyContext;

    uint256 internal constant MAX_TOKENS = 5;
    uint8 internal constant NOT_FOUND = type(uint8).max;

    /**
     * These constants are intended to be immutables set by the parent constructor,
     * but this is not easily achievable given how the solidity constructor works.
     */
    function NUM_TOKENS() internal pure virtual returns (uint256);
    function TOKENS() internal pure virtual returns (IERC20[] memory, uint8[] memory decimals);
    function POOL_TOKEN() internal pure virtual returns (IERC20);
    function PRIMARY_INDEX() internal pure virtual returns (uint256);

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
    /// @param data arbitrary data passed to the implementation
    function emergencyExit(
        uint256 claimToExit, bytes calldata data
    ) external override onlyRole(EMERGENCY_EXIT_ROLE) {
        StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
        if (claimToExit == 0) claimToExit = state.totalPoolClaim;

        // TODO: replace this with unstakeAndExitPool
        _emergencyExitPoolClaim(claimToExit, data);

        state.totalPoolClaim = state.totalPoolClaim - claimToExit;
        state.setStrategyVaultState();

        emit VaultEvents.EmergencyExit(claimToExit);
        _lockVault();
    }

    /// @notice Restores withdrawn tokens from emergencyExit back into the vault proportionally.
    /// Unlocks the vault after restoration so that normal functionality is restored.
    /// @param minPoolClaim slippage limit to prevent front running
    /// @param data arbitrary data passed to the implementation
    function restoreVault(
        uint256 minPoolClaim, bytes calldata data
    ) external override whenLocked onlyNotionalOwner {
        StrategyVaultState memory state = VaultStorage.getStrategyVaultState();

        // TODO: replace this joinPoolAndStake
        uint256 poolTokens = _restoreVault(minPoolClaim, data);

        state.totalPoolClaim = state.totalPoolClaim + poolTokens;
        state.setStrategyVaultState(); 

        _unlockVault();
    }

    /// @notice Reverts if the vault is locked during emergency exit.
    function convertStrategyToUnderlying(
        address /* */, uint256 vaultShares, uint256 /* */
    ) public view override whenNotLocked returns (int256 underlyingValue) {
        // Convert the vault shares to pool claims
        // TODO: is it easier to get the value of 1 pool claim token and just multiply here?
        // uint256 poolClaim = _baseStrategyContext()._convertStrategyTokensToPoolClaim(vaultShares);
        return _checkPriceAndCalculateValue(vaultShares);
    }

    function _depositFromNotional(
        address /* account */, uint256 deposit, uint256 /* maturity */, bytes calldata data
    ) internal override whenNotLocked returns (uint256 vaultSharesMinted) {
        StrategyContext memory context = _baseStrategyContext();
        DepositParams memory params = abi.decode(data, (DepositParams));
        uint256[] memory amounts = new uint256[](NUM_TOKENS());
        amounts[PRIMARY_INDEX()] = deposit;

        // XXX: validate and handle deposit trades
        require(params.depositTrades.length == 0);
        uint256 lpTokens = _joinPoolAndStake(amounts, params);

        // Ensure that we do not exceed the max LP pool threshold
        context._checkPoolThreshold(_totalPoolSupply(), lpTokens);
        return context._mintStrategyTokens(lpTokens);
    }

    function _redeemFromNotional(
        address /* account */, uint256 vaultShares, uint256 /* maturity */, bytes calldata data
    ) internal override whenNotLocked returns (uint256 finalPrimaryBalance) {
        StrategyContext memory context = _baseStrategyContext();
        uint256 poolClaim = context._redeemStrategyTokens(vaultShares);
        RedeemParams memory params = abi.decode(data, (RedeemParams));

        bool isSingleSided = params.redemptionTrades.length == 0;
        uint256[] memory exitBalances = _unstakeAndExitPool(poolClaim, params, isSingleSided);
        // XXX: validate and handle exit trades
        require(params.redemptionTrades.length == 0);
    }

    function claimRewardTokens() external override onlyRole(REWARD_REINVESTMENT_ROLE) {
        _claimRewardTokens();
    }

    // function reinvestReward(
    //     SingleSidedRewardTradeParams[] calldata trades,
    //     uint256 minPoolClaim
    // ) external whenNotLocked onlyRole(REWARD_REINVESTMENT_ROLE) returns (
    //     address rewardToken,
    //     uint256 amountSold,
    //     uint256 poolClaimAmount
    // ) {
    //     // TODO: checkPriceLimit
    //     // XXX: validate trades
    //     // XXX: handle deposit trades
    //     // TODO: join pool and stake
    //     // XXX: increase pool claim
    //     // TODO: check pool threshold
    // }

    /// @notice Converts pool claim to strategy tokens
    /// @param poolClaim amount of pool tokens
    /// @return strategyTokenAmount amount of vault shares
    function convertPoolClaimToStrategyTokens(uint256 poolClaim)
        external view returns (uint256 strategyTokenAmount) {
        return _baseStrategyContext()._convertPoolClaimToStrategyTokens(poolClaim);
    }

    /// @notice Converts strategy tokens to pool claim
    /// @param strategyTokenAmount amount of vault shares
    /// @return poolClaim amount of pool tokens
    function convertStrategyTokensToPoolClaim(uint256 strategyTokenAmount) 
        external view returns (uint256 poolClaim) {
        return _baseStrategyContext()._convertStrategyTokensToPoolClaim(strategyTokenAmount);
    }

    /// @notice Called once during initialization to set the initial token approvals.
    function _initialApproveTokens() internal virtual;

    /// @notice Called to exit pool tokens during an emergency
    function _emergencyExitPoolClaim(uint256 claimToExit, bytes calldata data) internal virtual;

    /// @notice Called to restore exited pool tokens after an emergency passes
    function _restoreVault(uint256 minPoolClaim, bytes calldata data) internal virtual returns (uint256 poolTokens);

    /// @notice Called to claim reward tokens
    function _claimRewardTokens() internal virtual;

    function _baseStrategyContext() internal view virtual returns (StrategyContext memory);

    function _checkPriceAndCalculateValue(uint256 vaultShares) internal view virtual returns (int256);

    function _totalPoolSupply() internal view virtual returns (uint256);

    function _joinPoolAndStake(
        uint256[] memory amounts, DepositParams memory params
    ) internal virtual returns (uint256 lpTokens);

    function _unstakeAndExitPool(
        uint256 poolClaim, RedeemParams memory params, bool isEmergencyExit
    ) internal virtual returns (uint256[] memory exitBalances);

    // Storage gap for future potential upgrades
    uint256[100] private __gap;
}