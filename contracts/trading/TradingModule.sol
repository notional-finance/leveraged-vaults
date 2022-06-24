// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../utils/BoringOwnable.sol";
import "../../interfaces/trading/ITradingModule.sol";
import "../../interfaces/trading/IVaultExchange.sol";
import "../../interfaces/trading/IExchangeAdapter.sol";
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

    // Each exchange adapter returns relevant parameters for a given exchange
    IExchangeAdapter public immutable UNISWAP_V2;
    IExchangeAdapter public immutable UNISWAP_V3;
    IExchangeAdapter public immutable BALANCER_V2;
    IExchangeAdapter public immutable CURVE;
    IExchangeAdapter public immutable ZERO_EX;
    IExchangeAdapter public immutable NOTIONAL_VAULT;

    event PriceOracleUpdated(address token, address oracle);

    constructor(
        IExchangeAdapter _uniswapV2,
        IExchangeAdapter _uniswapV3,
        IExchangeAdapter _balanceV2,
        IExchangeAdapter _curve,
        IExchangeAdapter _zeroEx,
        IExchangeAdapter _notionalVault
    ) initializer {
        UNISWAP_V2 = _uniswapV2;
        UNISWAP_V3 = _uniswapV3;
        BALANCER_V2 = _balanceV2;
        CURVE = _curve;
        ZERO_EX = _zeroEx;
        NOTIONAL_VAULT = _notionalVault;
    }

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

    function _getExchangeAdapter(uint16 dexId) internal view returns (IExchangeAdapter) {
        if (DexId(dexId) == DexId.UNISWAP_V2) {
            return UNISWAP_V2;
        } else if (DexId(dexId) == DexId.UNISWAP_V3) {
            return UNISWAP_V3;
        } else if (DexId(dexId) == DexId.BALANCER_V2) {
            return BALANCER_V2;
        } else if (DexId(dexId) == DexId.CURVE) {
            return CURVE;
        } else if (DexId(dexId) == DexId.ZERO_EX) {
            return ZERO_EX;
        } else if (DexId(dexId) == DexId.NOTIONAL_VAULT) {
            return NOTIONAL_VAULT;
        }

        revert UnknownDEX();
    }

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
        if (trade.buyToken == trade.sellToken) revert SellTokenEqualsBuyToken();
        // TODO: make this all internal
        return _getExchangeAdapter(dexId).getExecutionData(from, trade);
    }

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

        // TODO: this only works if we only list USD oracles....
        answer = (basePrice * quoteDecimals * RATE_DECIMALS) / (quotePrice * baseDecimals);
        decimals = RATE_DECIMALS;
    }

}
