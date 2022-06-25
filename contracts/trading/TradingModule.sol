// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../utils/BoringOwnable.sol";

import "./adapters/BalancerV2Adapter.sol";
import "./adapters/CurveAdapter.sol";
import "./adapters/UniV2Adapter.sol";
import "./adapters/UniV3Adapter.sol";
import "./adapters/ZeroExAdapter.sol";
import "./TradeHandler.sol";

import "../../interfaces/trading/ITradingModule.sol";
import "../../interfaces/trading/IVaultExchange.sol";
import "../../interfaces/chainlink/AggregatorV2V3Interface.sol";

/// @notice TradingModule is meant to be an upgradeable contract deployed to help Strategy Vaults
/// exchange tokens via multiple DEXes as well as receive price oracle information
contract TradingModule is BoringOwnable, UUPSUpgradeable, Initializable, ITradingModule {
    error SellTokenEqualsBuyToken();
    error UnknownDEX();

    struct PriceOracle {
        AggregatorV2V3Interface oracle;
        uint8 rateDecimals;
    }

    int256 internal constant RATE_DECIMALS = 1e18;
    mapping(address => PriceOracle) public priceOracles;

    event PriceOracleUpdated(address token, address oracle);

    constructor() initializer { }

    function initialize(address _owner) external initializer {
        owner = _owner;
        emit OwnershipTransferred(address(0), _owner);
    }

    function _authorizeUpgrade(address /* newImplementation */) internal override onlyOwner {}

    function setPriceOracle(address token, AggregatorV2V3Interface oracle) external override onlyOwner {
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
    ) external returns (uint256 amountSold, uint256 amountBought) {
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
        external view override returns (int256 answer, int256 decimals)
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

}
