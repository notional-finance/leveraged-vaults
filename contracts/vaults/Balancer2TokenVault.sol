// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.8.11;
pragma abicoder v2;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Token} from "../global/Types.sol";
import {BalancerUtils} from "../utils/BalancerUtils.sol";
import {BaseStrategyVault} from "./BaseStrategyVault.sol";
import {IStrategyVault} from "../../interfaces/notional/IStrategyVault.sol";
import {IBoostController} from "../../interfaces/notional/IBoostController.sol";
import {IBalancerVault} from "../../interfaces/balancer/IBalancerVault.sol";
import {IBalancerMinter} from "../../interfaces/balancer/IBalancerMinter.sol";
import {ILiquidityGauge} from "../../interfaces/balancer/ILiquidityGauge.sol";
import {ITradingModule} from "@notional-trading-module/interfaces/ITradingModule.sol";

struct Balancer2TokenVaultParams {
    IBalancerVault balancerVault;
    bytes32 balancerPoolId;
    IBoostController boostController;
    ILiquidityGauge liquidityGauge;
    IBalancerMinter balancerMinter;
    address veBalDelegator;
    ITradingModule tradingModule;
}

contract Balancer2TokenVault is BaseStrategyVault {
    IBalancerVault public immutable BALANCER_VAULT;
    bytes32 public immutable BALANCER_POOL_ID;
    ERC20 public immutable UNDERLYING_SECOND;
    IBoostController public immutable BOOST_CONTROLLER;
    ILiquidityGauge public immutable LIQUIDITY_GAUGE;
    IBalancerMinter public immutable BALANCER_MINTER;
    address public immutable VEBAL_DELEGATOR;

    constructor(
        string memory name_,
        string memory symbol_,
        address notional_,
        uint16 borrowCurrencyId_,
        bool setApproval,
        bool useUnderlyingToken,
        Balancer2TokenVaultParams memory params
    )
        BaseStrategyVault(
            name_,
            symbol_,
            notional_,
            borrowCurrencyId_,
            setApproval,
            useUnderlyingToken
        )
    {
        BALANCER_VAULT = params.balancerVault;
        BALANCER_POOL_ID = params.balancerPoolId;

        // prettier-ignore
        (
            address[] memory tokens,
            /* uint256[] memory balances */,
            /* uint256 lastChangeBlock */
        ) = BALANCER_VAULT.getPoolTokens(BALANCER_POOL_ID);

        require(
            address(UNDERLYING_TOKEN) == tokens[0] ||
                address(UNDERLYING_TOKEN) == tokens[1]
        );

        UNDERLYING_SECOND = tokens[0] == address(UNDERLYING_TOKEN)
            ? ERC20(tokens[1])
            : ERC20(tokens[0]);

        BOOST_CONTROLLER = params.boostController;
        LIQUIDITY_GAUGE = params.liquidityGauge;
        BALANCER_MINTER = params.balancerMinter;
        VEBAL_DELEGATOR = params.veBalDelegator;
    }

    function canSettleMaturity(uint256 maturity)
        external
        view
        override
        returns (bool)
    {
        return false;
    }

    function convertStrategyToUnderlying(uint256 strategyTokens)
        public
        view
        override
        returns (uint256 underlyingValue)
    {
        underlyingValue = 0;
    }

    function isInSettlement() external view override returns (bool) {
        return false;
    }

    function _depositFromNotional(
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 strategyTokensMinted) {
        // Join pool

        // Stake liquidity -> gaugeToken

        // BOOST_CONTROLLER.depositToken(gaugeToken, amount);

        strategyTokensMinted = 0;
    }

    function _redeemFromNotional(
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 tokensFromRedeem) {
        tokensFromRedeem = 0;
    }
}
