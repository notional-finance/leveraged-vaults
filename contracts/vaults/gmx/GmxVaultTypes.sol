// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {StrategyContext} from "../common/VaultTypes.sol";
import {ITradingModule} from "../../../interfaces/trading/ITradingModule.sol";
import {IGmxExchangeRouter} from "../../../interfaces/gmx/IGmxExchangeRouter.sol";
import {IGmxReader} from "../../../interfaces/gmx/IGmxReader.sol";

struct DeploymentParams {
    uint16 primaryBorrowCurrencyId;
    address collateralToken;
    address gmxRouter;
    address gmxMarket;
    address gmxReader;
    address orderVault;
    ITradingModule tradingModule;
}

struct GmxFundingStrategyContext {
    IGmxExchangeRouter gmxRouter;
    IGmxReader gmxReader;
    address orderVault;
    StrategyContext baseStrategy;
}
