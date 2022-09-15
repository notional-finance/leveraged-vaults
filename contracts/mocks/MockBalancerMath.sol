// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {StableMath} from "../vaults/balancer/internal/math/StableMath.sol";

contract MockBalancerMath {
    function calculateInvariant(
        uint256 amplificationParameter,
        uint256[] memory balances,
        bool roundUp
    ) external view returns (uint256) {
        return StableMath._calculateInvariant(amplificationParameter, balances, roundUp);
    }

    function getTokenBalanceGivenInvariantAndAllOtherBalances(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 invariant,
        uint256 tokenIndex
    ) external view returns (uint256) {
        return StableMath._getTokenBalanceGivenInvariantAndAllOtherBalances(
            amplificationParameter, balances, invariant, tokenIndex
        );
    }

    function calcBptOutGivenExactTokensIn(
        uint256 amp,
        uint256[] memory balances,
        uint256[] memory amountsIn,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage,
        uint256 currentInvariant
    ) external view returns (uint256) {
        return StableMath._calcBptOutGivenExactTokensIn(
            amp, balances, amountsIn, bptTotalSupply, swapFeePercentage, currentInvariant
        );
    }
}