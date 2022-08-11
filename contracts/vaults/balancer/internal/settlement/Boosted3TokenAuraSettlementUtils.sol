// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    Boosted3TokenAuraStrategyContext, 
    BoostedSettlementData,
    RedeemParams,
    StrategyContext,
    ThreeTokenPoolContext,
    StrategyVaultState
} from "../../BalancerVaultTypes.sol";
import {Constants} from "../../../../global/Constants.sol";
import {SafeInt256} from "../../../../global/SafeInt256.sol";
import {Errors} from "../../../../global/Errors.sol";
import {SettlementUtils} from "./SettlementUtils.sol";
import {StrategyUtils} from "../strategy/StrategyUtils.sol";
import {StableMath} from "../math/StableMath.sol";
import {VaultUtils} from "../VaultUtils.sol";
import {Boosted3TokenPoolUtils} from "../pool/Boosted3TokenPoolUtils.sol";

library Boosted3TokenAuraSettlementUtils {

}
