// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

contract MockOracle {
    int256 _answer;
    uint256 _updatedAt;

    function decimals() public pure returns (uint8) { return 18; }
    function setAnswer(int256 answer_) public { _answer = answer_; }
    function setUpdatedAt(uint256 updatedAt_) public { _updatedAt = updatedAt_; }

    function latestRoundData() external view returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    ) {
        roundId = 0;
        startedAt = 0;
        answeredInRound = 0;
        answer = _answer;
        updatedAt = _updatedAt > 0 ? _updatedAt : block.timestamp;
    }
}