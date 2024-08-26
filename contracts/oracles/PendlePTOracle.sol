// SPDX-License-Identifier: BSUL-1.1
pragma solidity 0.8.24;

import {Deployments} from "@deployments/Deployments.sol";
import {TypeConvert} from "@contracts/global/TypeConvert.sol";
import {IPMarket, IPOracle} from "@interfaces/pendle/IPendle.sol";
import "@interfaces/chainlink/AggregatorV2V3Interface.sol";
import "@interfaces/IERC20.sol";

contract PendlePTOracle is AggregatorV2V3Interface {
    using TypeConvert for uint256;

    address public immutable pendleMarket;
    uint32 public immutable twapDuration;
    bool public immutable useSyOracleRate;

    uint8 public override constant decimals = 18;
    uint256 public override constant version = 1;
    int256 public constant rateDecimals = 10**18;

    string public override description;
    // Grace period after a sequencer downtime has occurred
    uint256 public constant SEQUENCER_UPTIME_GRACE_PERIOD = 1 hours;

    AggregatorV2V3Interface public immutable baseToUSDOracle;
    int256 public immutable baseToUSDDecimals;
    int256 public immutable ptDecimals;
    bool public immutable invertBase;
    AggregatorV2V3Interface public immutable sequencerUptimeOracle;
    uint256 public immutable expiry;

    constructor (
        address pendleMarket_,
        AggregatorV2V3Interface baseToUSDOracle_,
        bool invertBase_,
        bool useSyOracleRate_,
        uint32 twapDuration_,
        string memory description_,
        AggregatorV2V3Interface sequencerUptimeOracle_
    ) {
        description = description_;
        pendleMarket = pendleMarket_;
        twapDuration = twapDuration_;
        useSyOracleRate = useSyOracleRate_;

        baseToUSDOracle = baseToUSDOracle_;
        invertBase = invertBase_;
        sequencerUptimeOracle = sequencerUptimeOracle_;

        uint8 _baseDecimals = baseToUSDOracle_.decimals();
        (/* */, address pt, /* */) = IPMarket(pendleMarket_).readTokens();
        uint8 _ptDecimals = IERC20(pt).decimals();

        require(_baseDecimals <= 18);
        require(_ptDecimals <= 18);

        baseToUSDDecimals = int256(10**_baseDecimals);
        ptDecimals = int256(10**_ptDecimals);

        (
            bool increaseCardinalityRequired,
            /* */,
            bool oldestObservationSatisfied
        ) = Deployments.PENDLE_ORACLE.getOracleState(pendleMarket, twapDuration);
        require(!increaseCardinalityRequired && oldestObservationSatisfied, "Oracle Init");

        expiry = IPMarket(pendleMarket).expiry();
    }

    function _checkSequencer() private view {
        // See: https://docs.chain.link/data-feeds/l2-sequencer-feeds/
        if (address(sequencerUptimeOracle) != address(0)) {
            (
                /*uint80 roundID*/,
                int256 answer,
                uint256 startedAt,
                /*uint256 updatedAt*/,
                /*uint80 answeredInRound*/
            ) = sequencerUptimeOracle.latestRoundData();
            require(answer == 0, "Sequencer Down");
            require(SEQUENCER_UPTIME_GRACE_PERIOD < block.timestamp - startedAt, "Sequencer Grace Period");
        }
    }

    function _getPTRate() internal view returns (int256) {
        uint256 ptRate = useSyOracleRate ? 
            Deployments.PENDLE_ORACLE.getPtToSyRate(pendleMarket, twapDuration) :
            Deployments.PENDLE_ORACLE.getPtToAssetRate(pendleMarket, twapDuration);
        return ptRate.toInt();
    }

    function _calculateBaseToQuote() internal view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        _checkSequencer();

        int256 baseToUSD;
        (
            roundId,
            baseToUSD,
            startedAt,
            updatedAt,
            answeredInRound
        ) = baseToUSDOracle.latestRoundData();
        require(baseToUSD > 0, "Chainlink Rate Error");
        // Overflow and div by zero not possible
        if (invertBase) baseToUSD = (baseToUSDDecimals * baseToUSDDecimals) / baseToUSD;

        int256 ptRate = _getPTRate();
        // ptRate is always returned in 1e18 decimals (rateDecimals)
        answer = (ptRate * baseToUSD) / baseToUSDDecimals;
    }

    function latestRoundData() external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return _calculateBaseToQuote();
    }

    function latestAnswer() external view override returns (int256 answer) {
        (/* */, answer, /* */, /* */, /* */) = _calculateBaseToQuote();
    }

    function latestTimestamp() external view override returns (uint256 updatedAt) {
        (/* */, /* */, /* */, updatedAt, /* */) = _calculateBaseToQuote();
    }

    function latestRound() external view override returns (uint256 roundId) {
        (roundId, /* */, /* */, /* */, /* */) = _calculateBaseToQuote();
    }

    function getRoundData(uint80 /* _roundId */) external pure override returns (
        uint80 /* roundId */,
        int256 /* answer */,
        uint256 /* startedAt */,
        uint256 /* updatedAt */,
        uint80 /* answeredInRound */
    ) {
        revert();
    }

    function getAnswer(uint256 /* roundId */) external pure override returns (int256) { revert(); }
    function getTimestamp(uint256 /* roundId */) external pure override returns (uint256) { revert(); }
}