// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.8.11;
pragma abicoder v2;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Token} from "../global/Types.sol";
import {BalancerUtils} from "../utils/BalancerUtils.sol";
import {BaseStrategyVault} from "./BaseStrategyVault.sol";
import {WETH9} from "../../interfaces/WETH9.sol";
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
    WETH9 weth;
}

struct Balancer2TokenVaultDepositParams {
    uint256 minBPT;
}

struct Balancer2TokenVaultRedeemParams {
    uint256 minUnderlying;
    uint256 minUnderlyingSecond;
    bool withdrawFromWETH;
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
    WETH9 public immutable WETH;

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
        WETH = params.weth;
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

        // prettier-ignore
        (
            IAsset[] memory assets,
            uint256[] memory maxAmountsIn
        ) = _getPoolParams(
            BORROW_CURRENCY_ID == 1
                ? address(0)
                : address(UNDERLYING_TOKEN),
            deposit,
            0
        );

        uint256 msgValue = assets[UNDERLYING_INDEX] == IAsset(address(0))
            ? maxAmountsIn[UNDERLYING_INDEX]
            : 0;

        // Join pool
        BALANCER_VAULT.joinPool{value: msgValue}(
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
        if (_totalSupply == 0) {
            strategyTokensMinted = bptAmount;
        } else {
            strategyTokensMinted =
                (_totalSupply * bptAmount) /
                (bptBalance - bptAmount);
        }

        // Handles event emission, balance update and total supply update
        super._mint(msg.sender, strategyTokensMinted);

        // TODO: emit deposit event here
    }

    /// @dev Gets the total BPT held across the LIQUIDITY GAUGE and the contract itself
    function _bptHeld() internal view returns (uint256) {
        return (LIQUIDITY_GAUGE.balanceOf(address(this)) +
            BALANCER_POOL_TOKEN.balanceOf(address(this)));
    }

    function _getPoolParams(
        address underlying,
        uint256 underlyingAmount,
        uint256 underlyingSecondAmount
    ) private view returns (IAsset[] memory assets, uint256[] memory amounts) {
        assets = new IAsset[](2);
        assets[UNDERLYING_INDEX] = IAsset(underlying);
        assets[1 - UNDERLYING_INDEX] = IAsset(address(UNDERLYING_SECOND));

        amounts = new uint256[](2);
        amounts[UNDERLYING_INDEX] = underlyingAmount;
        amounts[1 - UNDERLYING_INDEX] = underlyingSecondAmount;
    }

    /// @notice Returns how many Balancer pool tokens a strategy token amount has a claim on
    function getPoolTokenShare(uint256 strategyTokenAmount)
        public
        view
        returns (uint256 bptClaim)
    {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) return 0;

        uint256 bptBalance = _bptHeld();

        // BPT and Strategy token are both in 18 decimal precision so no conversion required
        return (bptBalance * strategyTokenAmount) / _totalSupply;
    }

    function _exitPool(uint256 bptExitAmount, bytes calldata data) internal {
        Balancer2TokenVaultRedeemParams memory params = abi.decode(
            data,
            (Balancer2TokenVaultRedeemParams)
        );

        // prettier-ignore
        (
            IAsset[] memory assets,
            uint256[] memory minAmountsOut
        ) = _getPoolParams(
            params.withdrawFromWETH ? address(0) : address(WETH),
            params.minUnderlying,
            params.minUnderlyingSecond
        );

        uint256 underlyingBefore = BORROW_CURRENCY_ID == 1
            ? msg.sender.balance
            : UNDERLYING_TOKEN.balanceOf(msg.sender);
        uint256 underlyingSecondBefore = UNDERLYING_SECOND.balanceOf(
            msg.sender
        );

        BALANCER_VAULT.exitPool(
            BALANCER_POOL_ID,
            address(this),
            payable(msg.sender), // Owner will receive the underlying assets
            IBalancerVault.ExitPoolRequest(
                assets,
                minAmountsOut,
                abi.encode(
                    IBalancerVault.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT,
                    bptExitAmount
                ),
                false // Don't use internal balances
            )
        );

        uint256 underlyingAfter = BORROW_CURRENCY_ID == 1
            ? msg.sender.balance
            : UNDERLYING_TOKEN.balanceOf(msg.sender);
        uint256 underlyingSecondAfter = UNDERLYING_SECOND.balanceOf(msg.sender);

        /*emit StrategyTokensRedeemed(
            msg.sender,
            underlyingAfter - underlyingBefore,
            underlyingSecondAfter - underlyingSecondBefore,
            bptExitAmount
        ); */
    }

    function _redeemFromNotional(
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 tokensFromRedeem) {
        tokensFromRedeem = getPoolTokenShare(strategyTokens);

        // Handles event emission, balance update and total supply update
        _burn(msg.sender, strategyTokens);

        if (tokensFromRedeem > 0) {
            // Withdraw gauge token from VeBALDelegator
            BOOST_CONTROLLER.withdrawToken(
                address(LIQUIDITY_GAUGE),
                tokensFromRedeem
            );

            // Unstake BPT
            LIQUIDITY_GAUGE.withdraw(tokensFromRedeem, false);

            _exitPool(tokensFromRedeem, data);
        }
    }
}
