// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {BalancerVaultStorage, StrategyVaultState} from "../internal/BalancerVaultStorage.sol";
import {NotionalProxy} from "../../../../interfaces/notional/NotionalProxy.sol";
import {IAuraRewardPool} from "../../../../interfaces/aura/IAuraRewardPool.sol";
import {nProxy} from "../../../proxy/nProxy.sol";
import {VaultState} from "../../../global/Types.sol";
import {TypeConvert} from "../../../global/TypeConvert.sol";

contract MetaStable2TokenPatchFix1 is UUPSUpgradeable {
    using TypeConvert for uint256;

    NotionalProxy public immutable NOTIONAL;
    IAuraRewardPool public immutable AURA_REWARD_POOL;
    address public immutable NEW_IMPL;

    constructor(NotionalProxy notional_, IAuraRewardPool auraPool_, address newImpl_) {
        NOTIONAL = notional_;
        AURA_REWARD_POOL = auraPool_;
        NEW_IMPL = newImpl_;
    }

    function _getStrategyTokenAmount(uint256 maturity)
        private
        view
        returns (uint80)
    {
        VaultState memory state = NOTIONAL.getVaultState(
            address(this),
            maturity
        );
        return state.totalStrategyTokens.toUint80();
    }

    function patch() external {
        require(msg.sender == NOTIONAL.owner());
        uint80 totalStrategyTokens = _getStrategyTokenAmount(1671840000) +
            _getStrategyTokenAmount(1679616000) +
            _getStrategyTokenAmount(1687392000);

        StrategyVaultState memory state = BalancerVaultStorage
            .getStrategyVaultState();
        state.totalBPTHeld = AURA_REWARD_POOL.balanceOf(address(this));
        state.totalStrategyTokenGlobal = totalStrategyTokens;
        BalancerVaultStorage.setStrategyVaultState(state);
        _upgradeTo(NEW_IMPL);
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal override {
        require(msg.sender == NOTIONAL.owner());
    }
}
