// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {AggregatorV2V3Interface} from "../../../interfaces/chainlink/AggregatorV2V3Interface.sol";
import {IPriceOracle} from "../../../interfaces/balancer/IPriceOracle.sol";
import {NotionalProxy} from "../../../interfaces/notional/NotionalProxy.sol";
import {TypeConvert} from "../../global/TypeConvert.sol";

contract BalancerPoolChainlinkAdapter is AggregatorV2V3Interface {
    using TypeConvert for uint256;

    event OracleWindowUpdated(uint256 oldWindow, uint256 newWindow);

    NotionalProxy public immutable NOTIONAL;
    bool public immutable MUST_INVERT;
    address public immutable BALANCER_POOL;

    uint8 public override constant decimals = 18;
    uint256 public override constant version = 1;

    string public override description;
    uint256 public oracleWindowInSeconds;

    constructor(
        NotionalProxy notional_,
        address balancerPool_, 
        string memory description_, 
        uint256 oracleWindowInSeconds_,
        bool mustInvert_
    ) {
        NOTIONAL = notional_;
        BALANCER_POOL = balancerPool_;
        MUST_INVERT = mustInvert_;
        description = description_;
        oracleWindowInSeconds = oracleWindowInSeconds_;
    }

    function setOracleWindow(uint256 oracleWindowInSeconds_) external {
        require(msg.sender == NOTIONAL.owner());
        emit OracleWindowUpdated(oracleWindowInSeconds, oracleWindowInSeconds_);
        oracleWindowInSeconds = oracleWindowInSeconds_;
    }

    function _calculateAnswer() internal view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        startedAt = block.timestamp;
        updatedAt = block.timestamp;

        IPriceOracle.OracleAverageQuery[]
            memory queries = new IPriceOracle.OracleAverageQuery[](1);

        queries[0].variable = IPriceOracle.Variable.PAIR_PRICE;
        queries[0].secs = oracleWindowInSeconds;
        queries[0].ago = 0; // now

        uint256 value = IPriceOracle(BALANCER_POOL).getTimeWeightedAverage(queries)[0];

        if (MUST_INVERT) {
            value = 10 ** (decimals * 2) / value;
        }

        answer = value.toInt();
    }

    function latestRoundData() external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return _calculateAnswer();
    }

    function latestAnswer() external view override returns (int256 answer) {
        (/* */, answer, /* */, /* */, /* */) = _calculateAnswer();
    }

    function latestTimestamp() external view override returns (uint256 updatedAt) {
        (/* */, /* */, /* */, updatedAt, /* */) = _calculateAnswer();
    }

    function latestRound() external view override returns (uint256 roundId) {
        (roundId, /* */, /* */, /* */, /* */) = _calculateAnswer();
    }

    function getRoundData(uint80 _roundId) external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        revert();
    }

    function getAnswer(uint256 roundId) external view override returns (int256) { revert(); }
    function getTimestamp(uint256 roundId) external view override returns (uint256) { revert(); }
}