// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    ThreeTokenPoolContext, 
    TwoTokenPoolContext, 
    BoostedOracleContext, 
    PoolParams
} from "../BalancerVaultTypes.sol";
import {Constants} from "../../../global/Constants.sol";
import {IAsset} from "../../../../interfaces/balancer/IBalancerVault.sol";
import {BalancerUtils} from "./BalancerUtils.sol";
import {ITradingModule} from "../../../../interfaces/trading/ITradingModule.sol";
import {IBoostedPool} from "../../../../interfaces/balancer/IBalancerPool.sol";
import {TokenUtils, IERC20} from "../../../utils/TokenUtils.sol";
import {TwoTokenPoolUtils} from "./TwoTokenPoolUtils.sol";
import {StableMath} from "./StableMath.sol";

library Boosted3TokenPoolUtils {
    using TokenUtils for IERC20;
    using TwoTokenPoolUtils for TwoTokenPoolContext;

    // Preminted BPT is sometimes called Phantom BPT, as the preminted BPT (which is deposited in the Vault as balance of
    // the Pool) doesn't belong to any entity until transferred out of the Pool. The Pool's arithmetic behaves as if it
    // didn't exist, and the BPT total supply is not a useful value: we rely on the 'virtual supply' (how much BPT is
    // actually owned by some entity) instead.
    uint256 private constant _MAX_TOKEN_BALANCE = 2**(112) - 1;

    /// @notice Gets the time-weighted primary token balance for a given bptAmount
    /// @dev Boosted pool can't use the Balancer oracle, using Chainlink instead
    /// @param poolContext pool context variables
    /// @param oracleContext oracle context variables
    /// @param bptAmount amount of balancer pool lp tokens
    /// @return primaryAmount primary token balance
    function _getTimeWeightedPrimaryBalance(
        ThreeTokenPoolContext memory poolContext,
        BoostedOracleContext memory oracleContext,
        uint256 bptAmount
    ) internal view returns (uint256 primaryAmount) {
        // TODO: validate spot prices against oracle prices
        (uint256 virtualSupply, uint256[] memory balances) = 
            _getVirtualSupplyAndBalances(poolContext, oracleContext);

        // NOTE: For Boosted 3 token pools, the LP token (BPT) is just another
        // token in the pool. So, we use _calcTokenOutGivenExactBptIn
        // to value it in terms of the primary currency
        // Use virtual total supply and zero swap fees for joins
        primaryAmount = StableMath._calcTokenOutGivenExactBptIn(
            oracleContext.ampParam, balances, poolContext.basePool.primaryIndex, bptAmount, virtualSupply, 0
        );
    }

    function _getVirtualSupplyAndBalances(
        ThreeTokenPoolContext memory poolContext, 
        BoostedOracleContext memory oracleContext
    ) internal view returns (uint256 virtualSupply, uint256[] memory amountsWithoutBpt) {
        // The initial amount of BPT pre-minted is _MAX_TOKEN_BALANCE and it goes entirely to the pool balance in the
        // vault. So the virtualSupply (the actual supply in circulation) is defined as:
        // virtualSupply = totalSupply() - (_balances[_bptIndex] - _dueProtocolFeeBptAmount)
        //
        // However, since this Pool never mints or burns BPT outside of the initial supply (except in the event of an
        // emergency pause), we can simply use `_MAX_TOKEN_BALANCE` instead of `totalSupply()` and save
        // gas.
        virtualSupply = _MAX_TOKEN_BALANCE - oracleContext.bptBalance + oracleContext.dueProtocolFeeBptAmount;

        amountsWithoutBpt = new uint256[](3);
        amountsWithoutBpt[0] = poolContext.basePool.primaryBalance;
        amountsWithoutBpt[1] = poolContext.basePool.secondaryBalance;
        amountsWithoutBpt[2] = poolContext.tertiaryBalance;
    }

    function _approveBalancerTokens(ThreeTokenPoolContext memory poolContext, address bptSpender) internal {
        poolContext.basePool._approveBalancerTokens(bptSpender);
        IERC20(poolContext.tertiaryToken).checkApprove(address(BalancerUtils.BALANCER_VAULT), type(uint256).max);

        // For boosted pools, the tokens inside pool context are AaveLinearPool tokens.
        // So, we need to approve the _underlyingToken (primary borrow currency) for trading.
        IBoostedPool underlyingPool = IBoostedPool(poolContext.basePool.primaryToken);
        address primaryUnderlyingAddress = BalancerUtils.getTokenAddress(underlyingPool.getMainToken());
        IERC20(primaryUnderlyingAddress).checkApprove(address(BalancerUtils.BALANCER_VAULT), type(uint256).max);
    }
}
