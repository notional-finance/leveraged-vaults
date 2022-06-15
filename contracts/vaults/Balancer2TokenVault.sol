// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.8.11;
pragma abicoder v2;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Token, VaultState} from "../global/Types.sol";
import {BalancerUtils} from "../utils/BalancerUtils.sol";
import {BaseStrategyVault} from "./BaseStrategyVault.sol";
import {WETH9} from "../../interfaces/WETH9.sol";
import {IStrategyVault} from "../../interfaces/notional/IStrategyVault.sol";
import {VaultConfig} from "../../interfaces/notional/IVaultController.sol";
import {IBoostController} from "../../interfaces/notional/IBoostController.sol";
import {IVeBalDelegator} from "../../interfaces/notional/IVeBalDelegator.sol";
import {IBalancerVault, IAsset} from "../../interfaces/balancer/IBalancerVault.sol";
import {IBalancerMinter} from "../../interfaces/balancer/IBalancerMinter.sol";
import {ILiquidityGauge} from "../../interfaces/balancer/ILiquidityGauge.sol";
import {ITradingModule} from "@notional-trading-module/interfaces/ITradingModule.sol";
import {Trade} from "@notional-trading-module/contracts/Types.sol";
import {TradeHandler} from "@notional-trading-module/contracts/TradeHandler.sol";

contract Balancer2TokenVault is BaseStrategyVault {
    using TradeHandler for Trade;

    struct InitParams {
        IBalancerVault balancerVault;
        bytes32 balancerPoolId;
        IBoostController boostController;
        ILiquidityGauge liquidityGauge;
        IBalancerMinter balancerMinter;
        IVeBalDelegator veBalDelegator;
        ITradingModule tradingModule;
        WETH9 weth;
        uint256 settlementPeriod; // 1 week settlement
        uint256 maxSettlementPercentage; // 20%
        uint256 settlementCooldown; // 6 hour cooldown
    }

    struct DepositParams {
        uint256 minBPT;
        uint256 secondaryfCashAmount;
        uint32 secondarySlippageLimit;
    }

    struct RedeemParams {
        uint256 minUnderlying;
        uint256 minUnderlyingSecond;
        bool withdrawFromWETH;
    }

    struct SettlementParams {
        uint256 minPrimaryAmount;
        uint256 minSecondaryAmount;
    }

    uint16 internal immutable SECONDARY_BORROW_CURRENCY_ID;
    IBalancerVault public immutable BALANCER_VAULT;
    bytes32 public immutable BALANCER_POOL_ID;
    ERC20 public immutable BALANCER_POOL_TOKEN;
    ERC20 public immutable SECONDARY_TOKEN;
    IBoostController public immutable BOOST_CONTROLLER;
    ILiquidityGauge public immutable LIQUIDITY_GAUGE;
    IBalancerMinter public immutable BALANCER_MINTER;
    IVeBalDelegator public immutable VEBAL_DELEGATOR;
    ERC20 public immutable BAL_TOKEN;
    uint256 public immutable PRIMARY_INDEX;
    WETH9 public immutable WETH;
    uint256 public immutable SETTLEMENT_PERIOD;

    /// @notice account => (maturity => balance)
    mapping(address => mapping(uint256 => uint256))
        private secondaryAmountfCashBorrowed;

    /// @notice Keeps track of the possible gauge reward tokens
    mapping(address => bool) private gaugeRewardTokens;

    constructor(
        address notional_,
        uint16 borrowCurrencyId_,
        bool setApproval,
        bool useUnderlyingToken,
        InitParams memory params
    )
        BaseStrategyVault(
            "Balancer 2-Token Strategy Vault",
            notional_,
            borrowCurrencyId_,
            setApproval,
            useUnderlyingToken
        )
    {
        SECONDARY_BORROW_CURRENCY_ID = _getSecondaryBorrowCurrencyId();
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

        PRIMARY_INDEX = tokens[0] == address(UNDERLYING_TOKEN) ? 1 : 0;
        SECONDARY_TOKEN = SECONDARY_BORROW_CURRENCY_ID > 0
            ? ERC20(_getTokenAddress(SECONDARY_BORROW_CURRENCY_ID))
            : ERC20(tokens[1 - PRIMARY_INDEX]);

        if (SECONDARY_BORROW_CURRENCY_ID > 0) {
            require(address(SECONDARY_TOKEN) == tokens[1 - PRIMARY_INDEX]);
        }

        BOOST_CONTROLLER = params.boostController;
        LIQUIDITY_GAUGE = params.liquidityGauge;
        BALANCER_MINTER = params.balancerMinter;
        BAL_TOKEN = ERC20(BALANCER_MINTER.getBalancerToken());
        VEBAL_DELEGATOR = params.veBalDelegator;

        _balancerInit(params);

        WETH = params.weth;
        SETTLEMENT_PERIOD = params.settlementPeriod;
    }

    function _getTokenAddress(uint16 currencyId) private returns (address) {
        // prettier-ignore
        (
            /* Token memory assetToken */, 
            Token memory underlyingToken
        ) = NOTIONAL.getCurrency(currencyId);
        return underlyingToken.tokenAddress;
    }

    function _getSecondaryBorrowCurrencyId() private returns (uint16) {
        VaultConfig memory vaultConfig = NOTIONAL.getVaultConfig(address(this));
        return vaultConfig.secondaryBorrowCurrencies[0];
    }

    function _balancerInit(InitParams memory params) private {
        address[] memory rewardTokens = VEBAL_DELEGATOR.getGaugeRewardTokens(
            address(LIQUIDITY_GAUGE)
        );
        for (uint256 i; i < rewardTokens.length; i++)
            gaugeRewardTokens[rewardTokens[i]] = true;
    }

    function convertStrategyToUnderlying(
        uint256 strategyTokens,
        uint256 maturity
    ) public view override returns (uint256 underlyingValue) {
        underlyingValue = 0;
    }

    function _joinPool(
        address account,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) private {
        DepositParams memory params = abi.decode(data, (DepositParams));

        uint256 borrowedSecondaryAmount = 0;
        if (SECONDARY_BORROW_CURRENCY_ID > 0) {
            uint256 secondaryOracleBalance = 0;
            uint256 primaryOracleBalance = 1;

            uint256 optimalSecondaryAmount = (deposit *
                secondaryOracleBalance) / primaryOracleBalance;

            // Borrow from Notional (will transfer underlying tokens to you)...this is somewhat annoying because calculating
            // the fCash => cash conversion but we can figure something out. Maybe we have the fcash amount be an input
            // param and then we validate that the tokens returned is within some band to the optimal amount
            borrowedSecondaryAmount = NOTIONAL.borrowSecondaryCurrencyToVault(
                SECONDARY_BORROW_CURRENCY_ID,
                maturity,
                params.secondaryfCashAmount,
                params.secondarySlippageLimit
            );

            //require(borrowedSecondaryAmount +/- optimalSecondaryAmount);

            // Track the amount borrowed per account and maturity on the contract
            secondaryAmountfCashBorrowed[account][
                maturity
            ] += borrowedSecondaryAmount;
        }

        // prettier-ignore
        (
            IAsset[] memory assets,
            uint256[] memory maxAmountsIn
        ) = _getPoolParams(
            BORROW_CURRENCY_ID == 1
                ? address(0)
                : address(UNDERLYING_TOKEN),
            deposit,
            borrowedSecondaryAmount
        );

        uint256 msgValue = assets[PRIMARY_INDEX] == IAsset(address(0))
            ? maxAmountsIn[PRIMARY_INDEX]
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
        address account,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 strategyTokensMinted) {
        // Join pool
        uint256 bptBefore = BALANCER_POOL_TOKEN.balanceOf(address(this));
        _joinPool(account, deposit, maturity, data);
        uint256 bptAfter = BALANCER_POOL_TOKEN.balanceOf(address(this));

        uint256 bptAmount = bptAfter - bptBefore;

        // Stake liquidity
        LIQUIDITY_GAUGE.deposit(bptAmount);

        // Transfer gauge token to VeBALDelegator
        BOOST_CONTROLLER.depositToken(address(LIQUIDITY_GAUGE), bptAmount);

        // Mint strategy tokens
        uint256 bptBalance = _bptHeld();
        uint256 _totalSupply = totalSupply(maturity);
        if (_totalSupply == 0) {
            strategyTokensMinted = bptAmount;
        } else {
            strategyTokensMinted =
                (_totalSupply * bptAmount) /
                (bptBalance - bptAmount);
        }

        // TODO: emit deposit event here
    }

    /// @dev Gets the total BPT held across the LIQUIDITY GAUGE and the contract itself
    function _bptHeld() internal view returns (uint256) {
        return (LIQUIDITY_GAUGE.balanceOf(address(this)) +
            BALANCER_POOL_TOKEN.balanceOf(address(this)));
    }

    function _getPoolParams(
        address primaryAddress,
        uint256 primaryAmount,
        uint256 secondaryAmount
    ) private view returns (IAsset[] memory assets, uint256[] memory amounts) {
        assets = new IAsset[](2);
        assets[PRIMARY_INDEX] = IAsset(primaryAddress);
        assets[1 - PRIMARY_INDEX] = IAsset(address(SECONDARY_TOKEN));

        amounts = new uint256[](2);
        amounts[PRIMARY_INDEX] = primaryAmount;
        amounts[1 - PRIMARY_INDEX] = secondaryAmount;
    }

    /// @notice Returns how many Balancer pool tokens a strategy token amount has a claim on
    function getPoolTokenShare(uint256 strategyTokenAmount, uint256 maturity)
        public
        view
        returns (uint256 bptClaim)
    {
        uint256 _totalSupply = totalSupply(maturity);
        if (_totalSupply == 0) return 0;

        uint256 bptBalance = _bptHeld();

        // BPT and Strategy token are both in 18 decimal precision so no conversion required
        return (bptBalance * strategyTokenAmount) / _totalSupply;
    }

    function _exitPool(
        address account,
        uint256 bptExitAmount,
        uint256 maturity,
        bytes calldata data
    ) internal {
        RedeemParams memory params = abi.decode(data, (RedeemParams));

        // prettier-ignore
        (
            IAsset[] memory assets,
            uint256[] memory minAmountsOut
        ) = _getPoolParams(
            params.withdrawFromWETH ? address(0) : address(WETH),
            params.minUnderlying,
            params.minUnderlyingSecond
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
    }

    function _redeemFromNotional(
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 tokensFromRedeem) {
        tokensFromRedeem = getPoolTokenShare(strategyTokens, maturity);

        if (tokensFromRedeem > 0) {
            // Withdraw gauge token from VeBALDelegator
            BOOST_CONTROLLER.withdrawToken(
                address(LIQUIDITY_GAUGE),
                tokensFromRedeem
            );

            // Unstake BPT
            LIQUIDITY_GAUGE.withdraw(tokensFromRedeem, false);

            uint256 underlyingBefore = BORROW_CURRENCY_ID == 1
                ? msg.sender.balance
                : UNDERLYING_TOKEN.balanceOf(msg.sender);
            uint256 underlyingSecondBefore = SECONDARY_TOKEN.balanceOf(
                msg.sender
            );

            _exitPool(account, tokensFromRedeem, maturity, data);

            uint256 underlyingAfter = BORROW_CURRENCY_ID == 1
                ? msg.sender.balance
                : UNDERLYING_TOKEN.balanceOf(msg.sender);
            uint256 underlyingSecondAfter = SECONDARY_TOKEN.balanceOf(
                msg.sender
            );

            /*emit StrategyTokensRedeemed(
            msg.sender,
            underlyingAfter - underlyingBefore,
            underlyingSecondAfter - underlyingSecondBefore,
            bptExitAmount
            ); */
        }
    }

    function settleVault(
        uint256 maturity,
        uint256 bptToSettle,
        bytes calldata params
    ) external {}

    /// @notice Claim BAL token gauge reward
    /// @return balAmount amount of BAL claimed
    function claimBAL() external returns (uint256) {
        return BOOST_CONTROLLER.claimBAL(address(LIQUIDITY_GAUGE));
    }

    /// @notice Claim other liquidity gauge reward tokens (i.e. LIDO)
    /// @return tokens addresses of reward tokens
    /// @return balancesTransferred amount of tokens claimed
    function claimGaugeTokens()
        external
        returns (address[] memory, uint256[] memory)
    {
        return BOOST_CONTROLLER.claimGaugeTokens(address(LIQUIDITY_GAUGE));
    }

    function executeTrade() external {}

    /** Public view functions */
    function getSecondaryBorrowedAmount(address account, uint256 maturity)
        public
        view
        returns (uint256)
    {
        return secondaryAmountfCashBorrowed[account][maturity];
    }

    function totalSupply(uint256 maturity) public view returns (uint256) {
        VaultState memory vaultState = NOTIONAL.getVaultState(
            address(this),
            maturity
        );
        return vaultState.totalStrategyTokens;
    }
}
