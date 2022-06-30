// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {Constants} from "../global/Constants.sol";
import {BalancerV2Adapter} from "./adapters/BalancerV2Adapter.sol";
import {CurveAdapter} from "./adapters/CurveAdapter.sol";
import {UniV2Adapter} from "./adapters/UniV2Adapter.sol";
import {UniV3Adapter} from "./adapters/UniV3Adapter.sol";
import {ZeroExAdapter} from "./adapters/ZeroExAdapter.sol";
import {TradeHandler} from "./TradeHandler.sol";

import {IERC20} from "../utils/TokenUtils.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import "../../interfaces/trading/ITradingModule.sol";
import "../../interfaces/trading/IVaultExchange.sol";
import "../../interfaces/chainlink/AggregatorV2V3Interface.sol";

/// @notice TradingModule is meant to be an upgradeable contract deployed to help Strategy Vaults
/// exchange tokens via multiple DEXes as well as receive price oracle information
contract TradingModule is UUPSUpgradeable, ITradingModule {
    NotionalProxy public immutable NOTIONAL;

    error SellTokenEqualsBuyToken();
    error UnknownDEX();

    struct PriceOracle {
        AggregatorV2V3Interface oracle;
        uint8 rateDecimals;
    }

    uint256 internal constant SLIPPAGE_LIMIT_PRECISION = 1e8;
    int256 internal constant RATE_DECIMALS = 1e18;
    mapping(address => PriceOracle) public priceOracles;

    event PriceOracleUpdated(address token, address oracle);

    constructor(NotionalProxy notional_) { NOTIONAL = notional_; }

    modifier onlyNotionalOwner() {
        require(msg.sender == NOTIONAL.owner());
        _;
    }

    function _authorizeUpgrade(address /* newImplementation */) internal override onlyNotionalOwner { }

    function setPriceOracle(address token, AggregatorV2V3Interface oracle) external override onlyNotionalOwner {
        PriceOracle storage oracleStorage = priceOracles[token];
        oracleStorage.oracle = oracle;
        oracleStorage.rateDecimals = oracle.decimals();

        emit PriceOracleUpdated(token, address(oracle));
    }

    /// @notice Called to receive execution data for vaults that will execute trades without
    /// delegating calls to this contract
    /// @param dexId enum representing the id of the dex
    /// @param from address for the contract executing the trade
    /// @param trade trade object
    /// @return spender the address to approve for the soldToken, will be address(0) if the
    /// send token is ETH and therefore does not require approval
    /// @return target contract to execute the call against
    /// @return msgValue amount of ETH to transfer to the target, if any
    /// @return executionCallData encoded call data for the trade
    function getExecutionData(
        uint16 dexId,
        address from,
        Trade calldata trade
    ) external view override returns (
        address spender,
        address target,
        uint256 msgValue,
        bytes memory executionCallData
    ) {
        return _getExecutionData(dexId, from, trade);
    }

    /// @notice Should be called via delegate call to execute a trade on behalf of the caller.
    /// @param dexId enum representing the id of the dex
    /// @param trade trade object
    /// @return amountSold amount of tokens sold
    /// @return amountBought amount of tokens purchased
    function executeTrade(
        uint16 dexId,
        Trade calldata trade
    ) external override returns (uint256 amountSold, uint256 amountBought) {
        (
            address spender,
            address target,
            uint256 msgValue,
            bytes memory executionData
        ) = _getExecutionData(dexId, address(this), trade);

        return TradeHandler._executeInternal(
            trade, dexId, spender, target, msgValue, executionData
        );
    }

    function _getExecutionData(
        uint16 dexId,
        address from,
        Trade calldata trade
    ) internal view returns (
        address spender,
        address target,
        uint256 msgValue,
        bytes memory executionCallData
    ) {
        if (trade.buyToken == trade.sellToken) revert SellTokenEqualsBuyToken();

        if (DexId(dexId) == DexId.UNISWAP_V2) {
            return UniV2Adapter.getExecutionData(from, trade);
        } else if (DexId(dexId) == DexId.UNISWAP_V3) {
            return UniV3Adapter.getExecutionData(from, trade);
        } else if (DexId(dexId) == DexId.BALANCER_V2) {
            return BalancerV2Adapter.getExecutionData(from, trade);
        } else if (DexId(dexId) == DexId.CURVE) {
            return CurveAdapter.getExecutionData(from, trade);
        } else if (DexId(dexId) == DexId.ZERO_EX) {
            return ZeroExAdapter.getExecutionData(from, trade);
        }

        revert UnknownDEX();
    }

    /// @notice Returns the Chainlink oracle price between the baseToken and the quoteToken, the
    /// Chainlink oracles. The quote currency between the oracles must match or the conversion
    /// in this method does not work. Most Chainlink oracles are baseToken/USD pairs.
    /// @param baseToken address of the first token in the pair, i.e. USDC in USDC/DAI
    /// @param quoteToken address of the second token in the pair, i.e. DAI in USDC/DAI
    /// @return answer exchange rate in rate decimals
    /// @return decimals number of decimals in the rate, currently hardcoded to 1e18
    function getOraclePrice(address baseToken, address quoteToken)
        public view override returns (int256 answer, int256 decimals)
    {
        PriceOracle memory baseOracle = priceOracles[baseToken];
        PriceOracle memory quoteOracle = priceOracles[quoteToken];

        int256 baseDecimals = int256(10**baseOracle.rateDecimals);
        int256 quoteDecimals = int256(10**quoteOracle.rateDecimals);

        (/* */, int256 basePrice, /* */, /* */, /* */) = baseOracle.oracle.latestRoundData();
        require(basePrice > 0); /// @dev: Chainlink Rate Error

        (/* */, int256 quotePrice, /* */, /* */, /* */) = quoteOracle.oracle.latestRoundData();
        require(quotePrice > 0); /// @dev: Chainlink Rate Error

        answer = (basePrice * quoteDecimals * RATE_DECIMALS) / (quotePrice * baseDecimals);
        decimals = RATE_DECIMALS;
    }

    // @audit there should be an internal and external version of this method, the external method should
    // be exposed on the TradingModule directly
    function getLimitAmount(
        uint16 tradeType,
        address sellToken,
        address buyToken,
        uint256 amount,
        uint32 slippageLimit
    ) external view returns (uint256 limitAmount) {
        // prettier-ignore
        (int256 oraclePrice, int256 oracleDecimals) = getOraclePrice(sellToken, buyToken);

        require(oraclePrice >= 0); /// @dev Chainlink rate error
        require(oracleDecimals >= 0); /// @dev Chainlink decimals error

        uint256 sellTokenDecimals = 10 **
            (sellToken == Constants.ETH_ADDRESS ? 18 : IERC20(sellToken).decimals());
        uint256 buyTokenDecimals = 10 **
            (buyToken == Constants.ETH_ADDRESS ? 18 : IERC20(buyToken).decimals());

        // @audit what about EXACT_OUT_BATCH, won't that fall into the wrong else condition?
        if (TradeType(tradeType) == TradeType.EXACT_OUT_SINGLE) {
            // 0 means no slippage limit
            if (slippageLimit == 0) {
                return type(uint256).max;
            }
            // Invert oracle price
            // @audit comment this formula and re-arrange such that division is pushed to the end
            // to the extent possible
            oraclePrice = (oracleDecimals * oracleDecimals) / oraclePrice;
            // For exact out trades, limitAmount is the max amount of sellToken the DEX can
            // pull from the contract
            limitAmount =
                ((uint256(oraclePrice) +
                    ((uint256(oraclePrice) * uint256(slippageLimit)) /
                        SLIPPAGE_LIMIT_PRECISION)) * amount) /
                uint256(oracleDecimals);

            // limitAmount is in buyToken precision after the previous calculation,
            // convert it to sellToken precision
            limitAmount = (limitAmount * sellTokenDecimals) / buyTokenDecimals;
        } else {
            // 0 means no slippage limit
            if (slippageLimit == 0) {
                return 0;
            }
            // For exact in trades, limitAmount is the min amount of buyToken the contract
            // expects from the DEX
            limitAmount =
                ((uint256(oraclePrice) -
                    ((uint256(oraclePrice) * uint256(slippageLimit)) /
                        SLIPPAGE_LIMIT_PRECISION)) * amount) /
                uint256(oracleDecimals);

            // limitAmount is in sellToken precision after the previous calculation,
            // convert it to buyToken precision
            limitAmount = (limitAmount * buyTokenDecimals) / sellTokenDecimals;
        }
    }

}
