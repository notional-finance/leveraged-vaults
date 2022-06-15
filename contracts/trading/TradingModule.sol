pragma solidity =0.8.11;

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../utils/BoringOwnable.sol";
import "../../interfaces/trading/ITradingModule.sol";
import "../../interfaces/trading/IVaultExchange.sol";
import "../../interfaces/trading/IExchangeAdapter.sol";
import "../../interfaces/chainlink/AggregatorV2V3Interface.sol";

contract TradingModule is
    BoringOwnable,
    UUPSUpgradeable,
    Initializable,
    ITradingModule
{
    int256 public constant RATE_DECIMALS = 10**18;
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
        owner = address(0);
    }

    mapping(address => address) public priceOracles;

    function initialize(address _owner) external initializer {
        owner = _owner;
        emit OwnershipTransferred(address(0), _owner);
    }

    function _getExchangeAdapater(uint16 dexId)
        internal
        view
        returns (IExchangeAdapter)
    {
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
    }

    function getSpender(uint16 dexId, Trade calldata trade)
        external
        view
        override
        returns (address)
    {
        IExchangeAdapter adapter = _getExchangeAdapater(dexId);

        return adapter.getSpender(trade);
    }

    function getExecutionData(
        uint16 dexId,
        address payable from,
        Trade calldata trade
    )
        external
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        require(trade.buyToken != trade.sellToken, "same token");

        IExchangeAdapter adapter = _getExchangeAdapater(dexId);

        return adapter.getExecutionData(from, trade);
    }

    function setPriceOracle(address token, address oracle)
        external
        override
        onlyOwner
    {
        priceOracles[token] = oracle;
        emit PriceOracleUpdated(token, oracle);
    }

    function getOraclePrice(address baseToken, address quoteToken)
        external
        view
        override
        returns (uint256 answer, uint256 decimals)
    {
        AggregatorV2V3Interface baseOracle = AggregatorV2V3Interface(
            priceOracles[baseToken]
        );
        AggregatorV2V3Interface quoteOracle = AggregatorV2V3Interface(
            priceOracles[quoteToken]
        );

        int256 baseDecimals = int256(10**baseOracle.decimals());
        int256 quoteDecimals = int256(10**quoteOracle.decimals());

        // prettier-ignore
        (
            /* roundId */,
            int256 basePrice,
            /* startedAt */,
            /* updatedAt */,
            /* answeredInRound */
        ) = baseOracle.latestRoundData();
        require(basePrice > 0); /// @dev: Chainlink Rate Error

        // prettier-ignore
        (
            /* roundId */,
            int256 quotePrice,
            /* uint256 startedAt */,
            /* updatedAt */,
            /* answeredInRound */
        ) = quoteOracle.latestRoundData();
        require(quotePrice > 0); /// @dev: Chainlink Rate Error

        answer = uint256(
            (basePrice * quoteDecimals * RATE_DECIMALS) /
                (quotePrice * baseDecimals)
        );
        decimals = uint256(RATE_DECIMALS);
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal override onlyOwner {}
}
