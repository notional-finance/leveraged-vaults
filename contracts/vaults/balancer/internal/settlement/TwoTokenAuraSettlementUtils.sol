// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    PoolContext, 
    TwoTokenPoolContext,
    AuraStakingContext,
    StrategyContext,
    OracleContext,
    TwoTokenAuraSettlementContext,
    NormalSettlementData, 
    RedeemParams, 
    SecondaryTradeParams,
    StrategyVaultSettings,
    StrategyVaultState
} from "../../BalancerVaultTypes.sol";
import {BalancerUtils} from "../pool/BalancerUtils.sol";
import {Errors} from "../../../../global/Errors.sol";
import {Constants} from "../../../../global/Constants.sol";
import {SafeInt256} from "../../../../global/SafeInt256.sol";
import {NotionalUtils} from "../../../../utils/NotionalUtils.sol";
import {VaultUtils} from "../VaultUtils.sol";
import {StrategyUtils} from "../strategy/StrategyUtils.sol";
import {SettlementUtils} from "./SettlementUtils.sol";
import {TwoTokenPoolUtils} from "../pool/TwoTokenPoolUtils.sol";
import {TwoTokenAuraStrategyUtils} from "../strategy/TwoTokenAuraStrategyUtils.sol";
import {IERC20} from "../../../../../interfaces/IERC20.sol";
import {ITradingModule} from "../../../../../interfaces/trading/ITradingModule.sol";

library TwoTokenAuraSettlementUtils {
 
}
