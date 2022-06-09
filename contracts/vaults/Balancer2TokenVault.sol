// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.8.11;
pragma abicoder v2;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Token} from "../global/Types.sol";
import {BalancerUtils} from "../utils/BalancerUtils.sol";
import {BaseStrategyVault} from "./BaseStrategyVault.sol";
import {IStrategyVault} from "../../interfaces/notional/IStrategyVault.sol";
import {IBoostController} from "../../interfaces/notional/IBoostController.sol";
import {IBalancerVault, IAsset} from "../../interfaces/balancer/IBalancerVault.sol";
import {IBalancerMinter} from "../../interfaces/balancer/IBalancerMinter.sol";
import {ILiquidityGauge} from "../../interfaces/balancer/ILiquidityGauge.sol";
import {ITradingModule} from "@notional-trading-module/interfaces/ITradingModule.sol";
import {Trade} from "@notional-trading-module/contracts/Types.sol";
import {TradeHandler} from "@notional-trading-module/contracts/TradeHandler.sol";

struct Balancer2TokenVaultParams {
    IBalancerVault balancerVault;
    bytes32 balancerPoolId;
    IBoostController boostController;
    ILiquidityGauge liquidityGauge;
    IBalancerMinter balancerMinter;
    address veBalDelegator;
    ITradingModule tradingModule;
}

struct Balancer2TokenVaultDepositParams {
    uint256 minBPT;
}

contract Balancer2TokenVault is BaseStrategyVault {
    using TradeHandler for Trade;

    IBalancerVault public immutable BALANCER_VAULT;
    bytes32 public immutable BALANCER_POOL_ID;
    ERC20 public immutable BALANCER_POOL_TOKEN;
    ERC20 public immutable UNDERLYING_SECOND;
    IBoostController public immutable BOOST_CONTROLLER;
    ILiquidityGauge public immutable LIQUIDITY_GAUGE;
    IBalancerMinter public immutable BALANCER_MINTER;
    address public immutable VEBAL_DELEGATOR;
    uint256 public immutable UNDERLYING_INDEX;

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
        BALANCER_POOL_TOKEN = ERC20(
            BalancerUtils.getPoolAddress(
                params.balancerVault,
                params.balancerPoolId
            )
        );

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

        UNDERLYING_INDEX = tokens[0] == address(UNDERLYING_TOKEN) ? 1 : 0;
        UNDERLYING_SECOND = ERC20(tokens[1 - UNDERLYING_INDEX]);

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

    function _joinPool(uint256 deposit, bytes calldata data) private {
        Balancer2TokenVaultDepositParams memory params = abi.decode(
            data,
            (Balancer2TokenVaultDepositParams)
        );

        (
            IAsset[] memory assets,
            uint256[] memory maxAmountsIn
        ) = _getPoolParams(deposit);

        // Join pool
        BALANCER_VAULT.joinPool(
            BALANCER_POOL_ID,
            address(this),
            address(this),
            IBalancerVault.JoinPoolRequest(
                assets,
                maxAmountsIn,
                abi.encode(
                    IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                    maxAmountsIn,
                    params.minBPT // Apply minBPT to prevent front running
                ),
                false // Don't use internal balances
            )
        );
    }

    function _depositFromNotional(
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 strategyTokensMinted) {
        // Join pool
        uint256 bptBefore = BALANCER_POOL_TOKEN.balanceOf(address(this));
        _joinPool(deposit, data);
        uint256 bptAfter = BALANCER_POOL_TOKEN.balanceOf(address(this));

        uint256 bptAmount = bptAfter - bptBefore;

        // Stake liquidity
        LIQUIDITY_GAUGE.deposit(bptAmount);

        // Transfer gauge token to VeBALDelegator
        BOOST_CONTROLLER.depositToken(address(LIQUIDITY_GAUGE), bptAmount);

        // Mint strategy tokens
        uint256 bptBalance = _bptHeld();
        uint256 _totalSupply = totalSupply();
        uint256 strategyTokensMinted;
        if (_totalSupply == 0) {
            strategyTokensMinted = bptAmount;
        } else {
            strategyTokensMinted =
                (_totalSupply * bptAmount) /
                (bptBalance - bptAmount);
        }

        // Handles event emission, balance update and total supply update
        super._mint(msg.sender, strategyTokensMinted);
    }

    /// @dev Gets the total BPT held across the LIQUIDITY GAUGE and the contract itself
    function _bptHeld() internal view returns (uint256) {
        return (LIQUIDITY_GAUGE.balanceOf(address(this)) +
            BALANCER_POOL_TOKEN.balanceOf(address(this)));
    }

    function _getPoolParams(uint256 amount)
        private
        view
        returns (IAsset[] memory, uint256[] memory)
    {
        IAsset[] memory assets = new IAsset[](2);
        assets[UNDERLYING_INDEX] = BORROW_CURRENCY_ID == 1
            ? IAsset(address(0))
            : IAsset(address(UNDERLYING_TOKEN));
        assets[1 - UNDERLYING_INDEX] = IAsset(address(UNDERLYING_SECOND));

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[UNDERLYING_INDEX] = amount;
        maxAmountsIn[1 - UNDERLYING_INDEX] = 0;

        return (assets, maxAmountsIn);
    }

    function _redeemFromNotional(
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 tokensFromRedeem) {
        tokensFromRedeem = 0;
    }
}
