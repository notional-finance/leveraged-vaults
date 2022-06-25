// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.8.11;
pragma abicoder v2;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Token, VaultState, VaultAccount} from "../global/Types.sol";
import {BalancerUtils} from "../utils/BalancerUtils.sol";
import {OracleHelper} from "../utils/OracleHelper.sol";
import {TradeHelper} from "../utils/TradeHelper.sol";
import {BaseStrategyVault} from "./BaseStrategyVault.sol";
import {WETH9} from "../../interfaces/WETH9.sol";
import {IStrategyVault} from "../../interfaces/notional/IStrategyVault.sol";
import {VaultConfig} from "../../interfaces/notional/IVaultController.sol";
import {IBoostController} from "../../interfaces/notional/IBoostController.sol";
import {IVeBalDelegator} from "../../interfaces/notional/IVeBalDelegator.sol";
import {IBalancerVault, IAsset} from "../../interfaces/balancer/IBalancerVault.sol";
import {IBalancerMinter} from "../../interfaces/balancer/IBalancerMinter.sol";
import {ILiquidityGauge} from "../../interfaces/balancer/ILiquidityGauge.sol";
import {IBalancerPool} from "../../interfaces/balancer/IBalancerPool.sol";
import {IPriceOracle} from "../../interfaces/balancer/IPriceOracle.sol";
import {ITradingModule, Trade, TradeType} from "../../interfaces/trading/ITradingModule.sol";
import {TradeHandler} from "../trading/TradeHandler.sol";

contract Balancer2TokenVault is
    UUPSUpgradeable,
    Initializable,
    BaseStrategyVault
{
    using TradeHandler for Trade;
    using SafeERC20 for ERC20;
    using SafeCast for uint256;

    struct DeploymentParams {
        uint16 secondaryBorrowCurrencyId;
        WETH9 weth;
        IBalancerVault balancerVault;
        bytes32 balancerPoolId;
        IBoostController boostController;
        ILiquidityGauge liquidityGauge;
        ITradingModule tradingModule;
        uint256 settlementPeriod;
    }

    struct InitParams {
        uint32 oracleWindowInSeconds;
        uint32 settlementCooldownInSeconds;
        uint32 balancerOracleWeight;
        uint32 maxBalancerPoolShare;
        uint256 maxUnderylingSurplus;
        uint32 settlementSlippageLimit;
        uint32 emergencySettlementSlippageLimit;
        uint32 settlementCoolDownInSeconds;
        uint32 emergencySettlementCoolDownInSeconds;
    }

    struct DepositParams {
        uint256 minBPT;
        uint256 secondaryfCashAmount;
        uint32 secondarySlippageLimit;
    }

    struct RedeemParams {
        uint32 secondarySlippageLimit;
        uint256 minPrimary;
        uint256 minSecondary;
        bool withdrawFromWETH;
        bytes callbackData;
    }

    struct RepaySecondaryCallbackParams {
        uint16 dexId;
        uint32 slippageLimit;
        uint256 deadline;
        bytes exchangeData;
    }

    struct RewardTokenTradeParams {
        uint16 primaryTradeDexId;
        Trade primaryTrade;
        uint16 secondaryTradeDexId;
        Trade secondaryTrade;
    }

    struct ReinvestRewardParams {
        bytes tradeData;
        uint256 minBPT;
    }

    /** Errors */
    error InvalidPrimaryToken(address token);
    error InvalidSecondaryToken(address token);
    error NotionalOwnerRequired(address sender);
    error NotInSettlementWindow();
    error RedeemingTooMuch(
        int256 underlyingRedeemed,
        int256 underlyingCashRequiredToSettle
    );
    error SlippageTooHigh(uint32 slippage, uint32 limit);
    error InSettlementCoolDown(uint32 lastTimestamp, uint32 coolDown);

    /** Events */
    event OracleWindowUpdated(uint256 oldWindow, uint256 newWindow);
    event SettlementCoolDownUpdated(uint32 oldCoolDown, uint32 newCoolDown);
    event EmergencySettlementCoolDownUpdated(
        uint32 oldCoolDown,
        uint32 newCoolDown
    );
    event BalancerOracleWeightUpdated(uint32 oldWeight, uint32 newWeight);
    event MaxBalancerPoolShareUpdated(uint32 oldShare, uint32 newShare);
    event MaxUnderlyingSurplusUpdated(uint256 oldSurplus, uint256 newSurplus);
    event SettlementSlippageLimitUpdated(uint32 oldLimit, uint32 newLimit);
    event EmergencySettlementSlippageLimitUpdated(
        uint32 oldLimit,
        uint32 newLimit
    );

    /// @notice Emitted when a vault is settled
    /// @param assetTokenProfits total amount of profit to vault account holders, if this is negative
    /// than there is a shortfall that must be covered by the protocol
    /// @param underlyingTokenProfits same as assetTokenProfits but denominated in underlying
    event VaultSettled(
        uint256 maturity,
        int256 assetTokenProfits,
        int256 underlyingTokenProfits
    );

    /** Constants */

    uint256 internal constant SECONDARY_BORROW_UPPER_LIMIT = 105;
    uint256 internal constant SECONDARY_BORROW_LOWER_LIMIT = 95;
    uint32 internal constant MAX_SETTLEMENT_COOLDOWN = 24 * 3600; // 1 day
    uint32 internal constant MAX_ORACLE_WEIGHT = 1e8; // 100%
    uint32 internal constant MAX_SLIPPAGE_LIMIT = 1e8; // 100%
    uint32 internal constant MAX_BALANCER_POOL_SHARE = 1e8; // 100%
    uint32 internal constant BALANCER_POOL_SHARE_BUFFER = 8e7; // 80%

    /** Immutables */
    uint16 public immutable SECONDARY_BORROW_CURRENCY_ID;
    IBalancerVault public immutable BALANCER_VAULT;
    bytes32 public immutable BALANCER_POOL_ID;
    IBalancerPool public immutable BALANCER_POOL_TOKEN;
    ERC20 public immutable SECONDARY_TOKEN;
    IBoostController public immutable BOOST_CONTROLLER;
    ILiquidityGauge public immutable LIQUIDITY_GAUGE;
    IVeBalDelegator public immutable VEBAL_DELEGATOR;
    ITradingModule public immutable TRADING_MODULE;
    ERC20 public immutable BAL_TOKEN;
    uint256 public immutable PRIMARY_INDEX;
    WETH9 public immutable WETH;
    uint256 public immutable SETTLEMENT_PERIOD;
    uint256 public immutable PRIMARY_WEIGHT;
    uint256 public immutable SECONDARY_WEIGHT;

    /// @notice account => (maturity => balance)
    mapping(address => mapping(uint256 => uint256))
        private secondaryAmountfCashBorrowed;

    /// @notice Keeps track of the possible gauge reward tokens
    mapping(address => bool) private gaugeRewardTokens;

    /// @notice Total number of strategy tokens across all maturities
    uint256 public totalStrategyTokenGlobal;

    /// @notice Balancer oracle window in seconds
    uint256 public oracleWindowInSeconds;

    uint256 public maxUnderylingSurplus;

    uint32 public maxBalancerPoolShare;

    /// @notice Slippage limit for normal settlement
    uint32 public settlementSlippageLimit;

    /// @notice Slippage limit for emergency settlement (vault owns too much of the Balancer pool)
    uint32 public emergencySettlementSlippageLimit;

    uint32 public balancerOracleWeight;

    /// @notice Cool down in seconds for normal settlement
    uint32 public settlementCoolDownInSeconds;

    /// @notice Cool down in seconds for emergency settlement
    uint32 public emergencySettlementCoolDownInSeconds;

    uint32 public lastSettlementTimestamp;

    uint32 public lastEmergencySettlementTimestamp;

    constructor(
        address notional_,
        uint16 borrowCurrencyId_,
        DeploymentParams memory params
    )
        BaseStrategyVault(
            "Balancer 2-Token Strategy Vault",
            notional_,
            borrowCurrencyId_
        )
        initializer
    {
        SECONDARY_BORROW_CURRENCY_ID = params.secondaryBorrowCurrencyId;
        WETH = params.weth;
        BALANCER_VAULT = params.balancerVault;
        BALANCER_POOL_ID = params.balancerPoolId;
        BALANCER_POOL_TOKEN = IBalancerPool(
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

        // Balancer tokens are sorted by address, so we need to figure out
        // the correct index for the primary token
        PRIMARY_INDEX = tokens[0] == _tokenAddress(address(UNDERLYING_TOKEN))
            ? 0
            : 1;

        // Since this is always a 2-token vault, SECONDARY_INDEX = 1-PRIMARY_INDEX
        SECONDARY_TOKEN = SECONDARY_BORROW_CURRENCY_ID > 0
            ? ERC20(_getUnderlyingAddress(SECONDARY_BORROW_CURRENCY_ID))
            : ERC20(tokens[1 - PRIMARY_INDEX]);

        // Make sure the deployment parameters are correct
        if (tokens[PRIMARY_INDEX] != _tokenAddress(address(UNDERLYING_TOKEN)))
            revert InvalidPrimaryToken(tokens[PRIMARY_INDEX]);
        if (
            tokens[1 - PRIMARY_INDEX] != _tokenAddress(address(SECONDARY_TOKEN))
        ) revert InvalidSecondaryToken(tokens[1 - PRIMARY_INDEX]);

        uint256[] memory weights = BALANCER_POOL_TOKEN.getNormalizedWeights();

        PRIMARY_WEIGHT = weights[PRIMARY_INDEX];
        SECONDARY_WEIGHT = weights[1 - PRIMARY_INDEX];

        BOOST_CONTROLLER = params.boostController;
        LIQUIDITY_GAUGE = params.liquidityGauge;
        VEBAL_DELEGATOR = IVeBalDelegator(BOOST_CONTROLLER.VEBAL_DELEGATOR());
        BAL_TOKEN = ERC20(
            IBalancerMinter(VEBAL_DELEGATOR.BALANCER_MINTER())
                .getBalancerToken()
        );
        TRADING_MODULE = params.tradingModule;
        SETTLEMENT_PERIOD = params.settlementPeriod;
    }

    function initialize(InitParams calldata params)
        external
        initializer
        onlyNotionalOwner
    {
        oracleWindowInSeconds = params.oracleWindowInSeconds;
        settlementCoolDownInSeconds = params.settlementCooldownInSeconds;
        balancerOracleWeight = params.balancerOracleWeight;
        maxBalancerPoolShare = params.maxBalancerPoolShare;
        maxUnderylingSurplus = params.maxUnderylingSurplus;
        settlementSlippageLimit = params.settlementSlippageLimit;
        emergencySettlementSlippageLimit = params
            .emergencySettlementSlippageLimit;
        settlementCoolDownInSeconds = params.settlementCoolDownInSeconds;
        emergencySettlementCoolDownInSeconds = params
            .emergencySettlementCoolDownInSeconds;
        _initRewardTokenList();
        _approveTokens();
    }

    /// @notice Special handling for ETH because UNDERLYING_TOKEN == address(0)
    /// and Balancer uses WETH
    function _tokenAddress(address token) private view returns (address) {
        return token == address(0) ? address(WETH) : address(token);
    }

    function _tokenBalance(address token) private view returns (uint256) {
        return
            token == address(0)
                ? address(this).balance
                : ERC20(token).balanceOf(address(this));
    }

    /// @notice Gets the underlying token address by currency ID
    function _getUnderlyingAddress(uint16 currencyId)
        private
        view
        returns (address)
    {
        // prettier-ignore
        (
            /* Token memory assetToken */, 
            Token memory underlyingToken
        ) = NOTIONAL.getCurrency(currencyId);
        return underlyingToken.tokenAddress;
    }

    /// @notice This list is used to validate trades
    function _initRewardTokenList() private {
        if (address(LIQUIDITY_GAUGE) != address(0)) {
            address[] memory rewardTokens = VEBAL_DELEGATOR
                .getGaugeRewardTokens(address(LIQUIDITY_GAUGE));
            for (uint256 i; i < rewardTokens.length; i++)
                gaugeRewardTokens[rewardTokens[i]] = true;
        }
    }

    /// @notice Approve necessary token transfers
    function _approveTokens() private {
        // Approving in external lib to reduce contract size
        TradeHelper.approveTokens(
            address(BALANCER_VAULT),
            address(UNDERLYING_TOKEN),
            address(SECONDARY_TOKEN),
            address(BALANCER_POOL_TOKEN),
            address(LIQUIDITY_GAUGE),
            address(VEBAL_DELEGATOR)
        );
    }

    /// @notice Converts strategy tokens to underlyingValue
    /// @dev Secondary token value is converted to its primary token equivalent value
    /// using the Balancer time-weighted price oracle
    /// @param strategyTokenAmount strategy token amount
    /// @param maturity maturity timestamp
    /// @return underlyingValue underlying (primary token) value of the strategy tokens
    function convertStrategyToUnderlying(
        address account,
        uint256 strategyTokenAmount,
        uint256 maturity
    ) public view override returns (int256 underlyingValue) {
        uint256 bptClaim = convertStrategyTokensToBPTClaim(
            strategyTokenAmount,
            maturity
        );

        uint256 primaryBalance = OracleHelper.getTimeWeightedPrimaryBalance(
            address(BALANCER_POOL_TOKEN),
            oracleWindowInSeconds,
            PRIMARY_INDEX,
            PRIMARY_WEIGHT,
            SECONDARY_WEIGHT,
            address(UNDERLYING_TOKEN) == address(0)
                ? 18
                : UNDERLYING_TOKEN.decimals(),
            bptClaim
        );

        if (SECONDARY_BORROW_CURRENCY_ID == 0) return primaryBalance.toInt256();

        // Get the amount of secondary fCash borrowed
        // We directly use the fCash amount instead of converting to underyling
        // as an approximation with built-in interest and haircut parameters
        uint256 borrowedSecondaryfCashAmount = getSecondaryBorrowedfCashAmount(
            account,
            maturity,
            strategyTokenAmount
        );

        uint256 pairPrice = OracleHelper.getPairPrice(
            address(BALANCER_POOL_TOKEN),
            address(BALANCER_VAULT),
            BALANCER_POOL_ID,
            address(TRADING_MODULE),
            oracleWindowInSeconds,
            balancerOracleWeight
        );

        uint256 borrowedPrimaryAmount = 0;
        if (PRIMARY_INDEX == 0) {
            borrowedPrimaryAmount =
                (borrowedSecondaryfCashAmount * 1e18) /
                pairPrice;
        } else {
            borrowedPrimaryAmount =
                (borrowedSecondaryfCashAmount * pairPrice) /
                1e18;
        }

        return primaryBalance.toInt256() - borrowedPrimaryAmount.toInt256();
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
            uint256 optimalSecondaryAmount = getOptimalSecondaryBorrowAmount(
                deposit
            );

            // Borrow secondary currency from Notional (tokens will be transferred to this contract)
            borrowedSecondaryAmount = NOTIONAL.borrowSecondaryCurrencyToVault(
                SECONDARY_BORROW_CURRENCY_ID,
                maturity,
                params.secondaryfCashAmount,
                params.secondarySlippageLimit
            );

            // Require the secondary borrow amount to be within SECONDARY_BORROW_LOWER_LIMIT percent
            // of the optimal amount
            require(
                borrowedSecondaryAmount >=
                    ((optimalSecondaryAmount * (SECONDARY_BORROW_LOWER_LIMIT)) /
                        100) &&
                    borrowedSecondaryAmount <=
                    (optimalSecondaryAmount * (SECONDARY_BORROW_UPPER_LIMIT)) /
                        100,
                "invalid secondary amount"
            );

            // Track the amount borrowed per account and maturity on the contract
            secondaryAmountfCashBorrowed[account][maturity] += params
                .secondaryfCashAmount;
        }

        // prettier-ignore
        (
            IAsset[] memory assets,
            uint256[] memory maxAmountsIn
        ) = _getPoolParams(
            address(UNDERLYING_TOKEN),
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
        if (totalStrategyTokenGlobal == 0) {
            strategyTokensMinted = bptAmount;
        } else {
            uint256 totalBPTHeld = bptHeld();
            uint256 totalStrategyTokenSupplyInMaturity = totalSupply(maturity);
            uint256 bptHeldInMaturity = (totalBPTHeld *
                totalStrategyTokenSupplyInMaturity) / totalStrategyTokenGlobal;
            strategyTokensMinted =
                (totalStrategyTokenSupplyInMaturity * bptAmount) /
                (bptHeldInMaturity - bptAmount);
        }

        // Update global supply count
        totalStrategyTokenGlobal += strategyTokensMinted;
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

    /// @notice Converts strategy tokens to BPT
    function convertStrategyTokensToBPTClaim(
        uint256 strategyTokenAmount,
        uint256 maturity
    ) public view returns (uint256 bptClaim) {
        if (totalStrategyTokenGlobal == 0) return strategyTokenAmount;

        uint256 totalBPTHeld = bptHeld();
        uint256 totalStrategyTokenSupplyInMaturity = totalSupply(maturity);
        uint256 bptHeldInMaturity = (totalBPTHeld *
            totalStrategyTokenSupplyInMaturity) / totalStrategyTokenGlobal;
        bptClaim =
            (bptHeldInMaturity * strategyTokenAmount) /
            totalStrategyTokenSupplyInMaturity;
    }

    /// @notice Converts BPT to strategy tokens
    function convertBPTClaimToStrategyTokens(uint256 bptClaim, uint256 maturity)
        public
        view
        returns (uint256 strategyTokenAmount)
    {
        if (totalStrategyTokenGlobal == 0) return bptClaim;

        uint256 totalBPTHeld = bptHeld();
        uint256 totalStrategyTokenSupplyInMaturity = totalSupply(maturity);
        uint256 bptHeldInMaturity = (totalBPTHeld *
            totalStrategyTokenSupplyInMaturity) / totalStrategyTokenGlobal;
        strategyTokenAmount =
            (totalStrategyTokenSupplyInMaturity * bptClaim) /
            bptHeldInMaturity;
    }

    function _exitPool(
        address account,
        uint256 bptExitAmount,
        uint256 maturity,
        uint256 borrowedSecondaryfCashAmount,
        bytes calldata data
    ) internal {
        RedeemParams memory params = abi.decode(data, (RedeemParams));

        // prettier-ignore
        (
            IAsset[] memory assets,
            uint256[] memory minAmountsOut
        ) = _getPoolParams(
            params.withdrawFromWETH ? address(0) : address(WETH),
            params.minPrimary,
            params.minSecondary
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

        // Repay secondary debt
        if (borrowedSecondaryfCashAmount > 0) {
            NOTIONAL.repaySecondaryCurrencyFromVault(
                SECONDARY_BORROW_CURRENCY_ID,
                maturity,
                borrowedSecondaryfCashAmount,
                params.secondarySlippageLimit,
                params.callbackData
            );
        }
    }

    /// @notice Callback function for repaying secondary debt
    function _repaySecondaryBorrowCallback(
        uint256 underlyingRequired,
        bytes calldata data
    ) internal override returns (bytes memory returnData) {
        require(msg.sender == address(NOTIONAL)); /// @dev invalid caller
        require(SECONDARY_BORROW_CURRENCY_ID > 0); /// @dev invalid secondary currency
        RepaySecondaryCallbackParams memory params = abi.decode(
            data,
            (RepaySecondaryCallbackParams)
        );

        uint256 secondaryBalance = _tokenBalance(address(SECONDARY_TOKEN));
        Trade memory trade;

        if (secondaryBalance < underlyingRequired) {
            // Not enough secondary balance to repay debt, sell some primary currency
            trade = Trade(
                uint16(TradeType.EXACT_OUT_SINGLE),
                address(UNDERLYING_TOKEN),
                address(SECONDARY_TOKEN),
                underlyingRequired - secondaryBalance,
                TradeHelper.getLimitAmount(
                    address(TRADING_MODULE),
                    uint16(TradeType.EXACT_OUT_SINGLE),
                    address(UNDERLYING_TOKEN),
                    address(SECONDARY_TOKEN),
                    underlyingRequired - secondaryBalance,
                    params.slippageLimit
                ),
                params.deadline,
                params.exchangeData
            );

            trade.execute(TRADING_MODULE, params.dexId, WETH);
        }

        // Update balance before transfer
        secondaryBalance -= underlyingRequired;

        // Transfer required secondary balance to Notional
        if (SECONDARY_BORROW_CURRENCY_ID == 1) {
            payable(address(NOTIONAL)).transfer(underlyingRequired);
        } else {
            SECONDARY_TOKEN.safeTransfer(address(NOTIONAL), underlyingRequired);
        }

        if (secondaryBalance > 0) {
            // Sell residual secondary balance
            trade = Trade(
                uint16(TradeType.EXACT_IN_SINGLE),
                address(SECONDARY_TOKEN),
                address(UNDERLYING_TOKEN),
                secondaryBalance,
                TradeHelper.getLimitAmount(
                    address(TRADING_MODULE),
                    uint16(TradeType.EXACT_OUT_SINGLE),
                    address(SECONDARY_TOKEN),
                    address(UNDERLYING_TOKEN),
                    secondaryBalance,
                    params.slippageLimit
                ),
                params.deadline,
                params.exchangeData
            );

            trade.execute(TRADING_MODULE, params.dexId, WETH);
        }
    }

    function _redeemFromNotional(
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 tokensFromRedeem) {
        tokensFromRedeem = convertStrategyTokensToBPTClaim(
            strategyTokens,
            maturity
        );

        if (tokensFromRedeem > 0) {
            // Withdraw gauge token from VeBALDelegator
            BOOST_CONTROLLER.withdrawToken(
                address(LIQUIDITY_GAUGE),
                tokensFromRedeem
            );

            // Unstake BPT
            LIQUIDITY_GAUGE.withdraw(tokensFromRedeem, false);

            // Calculate the amount of secondary tokens to repay
            uint256 borrowedSecondaryfCashAmount = getSecondaryBorrowedfCashAmount(
                    account,
                    maturity,
                    strategyTokens
                );

            _exitPool(
                account,
                tokensFromRedeem,
                maturity,
                borrowedSecondaryfCashAmount,
                data
            );
        }
    }

    function _validateSettlementSlippage(
        bytes memory data,
        uint32 slippageLimit
    ) private {
        RedeemParams memory params = abi.decode(data, (RedeemParams));
        RepaySecondaryCallbackParams memory callbackParams = abi.decode(
            params.callbackData,
            (RepaySecondaryCallbackParams)
        );
        if (callbackParams.slippageLimit > slippageLimit) {
            revert SlippageTooHigh(callbackParams.slippageLimit, slippageLimit);
        }
    }

    function _validateSettlementCoolDown(uint32 lastTimestamp, uint32 coolDown)
        private
    {
        if (lastTimestamp + coolDown > block.timestamp)
            revert InSettlementCoolDown(lastTimestamp, coolDown);
    }

    function settleVault(
        uint256 maturity,
        uint256 bptToSettle,
        bytes calldata data
    ) external {
        uint256 redeemAmount = 0;
        if (maturity <= block.timestamp) {
            // Vault has reached maturity. settleVault becomes authenticated in this case
            if (msg.sender != NOTIONAL.owner())
                revert NotionalOwnerRequired(msg.sender);
            _validateSettlementCoolDown(
                lastEmergencySettlementTimestamp,
                emergencySettlementCoolDownInSeconds
            );
            _validateSettlementSlippage(data, emergencySettlementSlippageLimit);
        } else {
            if (maturity - SETTLEMENT_PERIOD <= block.timestamp) {
                // In settlement window
                _validateSettlementCoolDown(
                    lastSettlementTimestamp,
                    settlementCoolDownInSeconds
                );
                _validateSettlementSlippage(data, settlementSlippageLimit);
            } else {
                // Not in settlement window, check if BPT held is greater than maxBalancerPoolShare * total BPT supply
                uint256 maxBPTAmount = (BALANCER_POOL_TOKEN.totalSupply() *
                    maxBalancerPoolShare) / 1e8;
                uint256 _bptHeld = bptHeld();
                if (_bptHeld <= maxBPTAmount) revert NotInSettlementWindow();

                // desiredPoolShare = maxPoolShare * bufferPercentage
                uint256 desiredPoolShare = (maxBalancerPoolShare *
                    BALANCER_POOL_SHARE_BUFFER) / 1e8;
                uint256 desiredBPTAmount = (BALANCER_POOL_TOKEN.totalSupply() *
                    desiredPoolShare) / 1e8;
                redeemAmount = convertBPTClaimToStrategyTokens(
                    _bptHeld - desiredBPTAmount,
                    maturity
                );
            }
        }

        int256 underlyingRedeemed = convertStrategyToUnderlying(
            address(this),
            redeemAmount,
            maturity
        );

        // prettier-ignore
        (
            int256 assetCashRequiredToSettle,
            int256 underlyingCashRequiredToSettle
        ) = NOTIONAL.getCashRequiredToSettle(address(this), maturity);

        // Make sure we not redeeming too much to underlying
        // This allows BPT to be accrued as the profit token.
        if (
            underlyingRedeemed - underlyingCashRequiredToSettle >
            int256(maxUnderylingSurplus)
        ) {
            revert RedeemingTooMuch(
                underlyingRedeemed,
                underlyingCashRequiredToSettle
            );
        }

        // prettier-ignore
        (
            int256 assetCashProfit,
            int256 underlyingCashProfit
        ) = NOTIONAL.redeemStrategyTokensToCash(maturity, redeemAmount, data);

        // Profits are the surplus in cash after the tokens have been settled, this is the negation of
        // what is returned from the method above
        emit VaultSettled(
            maturity,
            -1 * assetCashProfit,
            -1 * underlyingCashProfit
        );
    }

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

    function _executeRewardTrades(bytes memory data)
        private
        returns (uint256 primaryAmount, uint256 secondaryAmount)
    {
        RewardTokenTradeParams memory params = abi.decode(
            data,
            (RewardTokenTradeParams)
        );

        // Validate trades
        if (!gaugeRewardTokens[params.primaryTrade.sellToken]) {
            revert InvalidPrimaryToken(params.primaryTrade.sellToken);
        }
        if (params.primaryTrade.sellToken != params.secondaryTrade.sellToken) {
            revert InvalidSecondaryToken(params.secondaryTrade.sellToken);
        }
        if (
            params.primaryTrade.buyToken !=
            _tokenAddress(address(UNDERLYING_TOKEN))
        ) {
            revert InvalidPrimaryToken(params.primaryTrade.buyToken);
        }
        if (
            params.secondaryTrade.buyToken !=
            _tokenAddress(address(SECONDARY_TOKEN))
        ) {
            revert InvalidSecondaryToken(params.secondaryTrade.buyToken);
        }

        // TODO: validate prices
        // TODO: make sure spot is close to pairPrice

        uint256 primaryAmountBefore = _tokenBalance(address(UNDERLYING_TOKEN));
        params.primaryTrade.execute(
            TRADING_MODULE,
            params.primaryTradeDexId,
            WETH
        );
        primaryAmount =
            _tokenBalance(address(UNDERLYING_TOKEN)) -
            primaryAmountBefore;

        uint256 secondaryAmountBefore = _tokenBalance(address(SECONDARY_TOKEN));
        params.secondaryTrade.execute(
            TRADING_MODULE,
            params.secondaryTradeDexId,
            WETH
        );
        secondaryAmount =
            _tokenBalance(address(SECONDARY_TOKEN)) -
            secondaryAmountBefore;
    }

    /// @notice Sell reward tokens for BPT and reinvest the proceeds
    /// @param params reward reinvestment params
    function reinvestReward(ReinvestRewardParams calldata params) external {
        // Decode trades in another function to avoid the stack too deep error
        (uint256 primaryAmount, uint256 secondaryAmount) = _executeRewardTrades(
            params.tradeData
        );

        // prettier-ignore
        (
            IAsset[] memory assets,
            uint256[] memory maxAmountsIn
        ) = _getPoolParams(
            address(UNDERLYING_TOKEN),
            primaryAmount,
            secondaryAmount
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

        // TODO: emit event here
    }

    /** Setters */

    /// @notice Updates the oracle window
    /// @param newOracleWindowInSeconds new oracle window in seconds
    function setOracleWindow(uint256 newOracleWindowInSeconds)
        external
        onlyNotionalOwner
    {
        require(
            newOracleWindowInSeconds <=
                IPriceOracle(address(BALANCER_POOL_TOKEN))
                    .getLargestSafeQueryWindow()
        );
        emit OracleWindowUpdated(
            oracleWindowInSeconds,
            newOracleWindowInSeconds
        );
        oracleWindowInSeconds = newOracleWindowInSeconds;
    }

    /// @notice Updates the settlement cool down
    /// @dev Time limit between settlement trades
    /// @param newSettlementCoolDownInSeconds settlement cool down in seconds
    function setSettlementCoolDown(uint32 newSettlementCoolDownInSeconds)
        external
        onlyNotionalOwner
    {
        require(newSettlementCoolDownInSeconds <= MAX_SETTLEMENT_COOLDOWN);
        emit SettlementCoolDownUpdated(
            settlementCoolDownInSeconds,
            newSettlementCoolDownInSeconds
        );
        settlementCoolDownInSeconds = newSettlementCoolDownInSeconds;
    }

    function setEmergencySettlementCoolDown(
        uint32 newEmergencySettlementCoolDownInSeconds
    ) external onlyNotionalOwner {
        require(
            newEmergencySettlementCoolDownInSeconds <= MAX_SETTLEMENT_COOLDOWN
        );
        emit EmergencySettlementCoolDownUpdated(
            emergencySettlementCoolDownInSeconds,
            newEmergencySettlementCoolDownInSeconds
        );
        emergencySettlementCoolDownInSeconds = newEmergencySettlementCoolDownInSeconds;
    }

    /// @notice Updates the Balancer oracle weight. This value determines
    /// the amount of weight given to the Balancer oracle vs Chainlink
    /// @dev 1e8 = 100%
    /// @param newBalancerOracleWeight new Balancer oracle weight
    function setBalancerOracleWeight(uint32 newBalancerOracleWeight)
        external
        onlyNotionalOwner
    {
        require(newBalancerOracleWeight <= MAX_ORACLE_WEIGHT);
        emit BalancerOracleWeightUpdated(
            balancerOracleWeight,
            newBalancerOracleWeight
        );
        balancerOracleWeight = newBalancerOracleWeight;
    }

    function setMaxBalancerPoolShare(uint32 newMaxBalancerPoolShare)
        external
        onlyNotionalOwner
    {
        require(newMaxBalancerPoolShare <= MAX_BALANCER_POOL_SHARE);
        emit MaxBalancerPoolShareUpdated(
            maxBalancerPoolShare,
            newMaxBalancerPoolShare
        );
        maxBalancerPoolShare = newMaxBalancerPoolShare;
    }

    function setMaxUnderylingSurplus(uint256 newMaxUnderlyingSurplus)
        external
        onlyNotionalOwner
    {
        emit MaxUnderlyingSurplusUpdated(
            maxUnderylingSurplus,
            newMaxUnderlyingSurplus
        );
        maxUnderylingSurplus = newMaxUnderlyingSurplus;
    }

    function setSettlementSlippageLimit(uint32 newSettlementSlippageLimit)
        external
        onlyNotionalOwner
    {
        require(newSettlementSlippageLimit <= MAX_SLIPPAGE_LIMIT);
        emit SettlementSlippageLimitUpdated(
            settlementSlippageLimit,
            newSettlementSlippageLimit
        );
        settlementSlippageLimit = newSettlementSlippageLimit;
    }

    function setEmergencySettlementSlippageLimit(
        uint32 newEmergencySettlementSlippageLimit
    ) external onlyNotionalOwner {
        require(newEmergencySettlementSlippageLimit <= MAX_SLIPPAGE_LIMIT);
        emit EmergencySettlementSlippageLimitUpdated(
            emergencySettlementSlippageLimit,
            newEmergencySettlementSlippageLimit
        );
        emergencySettlementSlippageLimit = newEmergencySettlementSlippageLimit;
    }

    /** Public view functions */

    /// @notice Calculates the optimal secondary borrow amount using the
    /// Balancer time-weighted oracle price
    /// @dev Balancer pool needs to be fully initialized with at least 1024 trades
    /// @param primaryAmount primary borrow amount
    /// @return secondaryAmount optimal secondary borrow amount
    function getOptimalSecondaryBorrowAmount(uint256 primaryAmount)
        public
        view
        returns (uint256 secondaryAmount)
    {
        // Gets the PAIR price
        uint256 pairPrice = BalancerUtils.getTimeWeightedOraclePrice(
            address(BALANCER_POOL_TOKEN),
            IPriceOracle.Variable.PAIR_PRICE,
            oracleWindowInSeconds
        );

        // Calculate weighted primary amount
        primaryAmount = ((primaryAmount * 1e18) / PRIMARY_WEIGHT);

        // Calculate price adjusted primary amount, price is always in 1e18
        // Since price is always expressed as the price of the second token in units of the
        // first token, we need to invert the math if the second token is the primary token
        if (PRIMARY_INDEX == 0) {
            // PairPrice = (PrimaryAmount / PrimaryWeight) / (SecondaryAmount / SecondaryWeight)
            // SecondaryAmount = (PrimaryAmount / PrimaryWeight) / PairPrice * SecondaryWeight
            primaryAmount = ((primaryAmount * 1e18) / pairPrice);
        } else {
            // PairPrice = (SecondaryAmount / SecondaryWeight) / (PrimaryAmount / PrimaryWeight)
            // SecondaryAmount = (PrimaryAmount / PrimaryWeight) * PairPrice * SecondaryWeight
            primaryAmount = ((primaryAmount * pairPrice) / 1e18);
        }

        // Calculate secondary amount (precision is still 1e18)
        secondaryAmount = (primaryAmount * SECONDARY_WEIGHT) / 1e18;

        // Normalize precision to secondary precision
        uint256 primaryDecimals = address(UNDERLYING_TOKEN) == address(0)
            ? 18
            : UNDERLYING_TOKEN.decimals();
        uint256 secondaryDecimals = address(UNDERLYING_TOKEN) == address(0)
            ? 18
            : SECONDARY_TOKEN.decimals();

        secondaryAmount =
            (secondaryAmount * 10**secondaryDecimals) /
            10**primaryDecimals;
    }

    /// @dev Gets the total BPT held across the LIQUIDITY GAUGE, VeBal Delegator and the contract itself
    function bptHeld() public view returns (uint256) {
        return (LIQUIDITY_GAUGE.balanceOf(address(this)) +
            BALANCER_POOL_TOKEN.balanceOf(address(this)) +
            VEBAL_DELEGATOR.getTokenBalance(
                address(LIQUIDITY_GAUGE),
                address(this)
            ));
    }

    /// @notice Gets the amount of secondary fCash borrowed
    /// @param account account address
    /// @param maturity maturity timestamp
    /// @param strategyTokenAmount amount of strategy tokens
    /// @return borrowedSecondaryfCashAmount amount of secondary fCash borrowed
    function getSecondaryBorrowedfCashAmount(
        address account,
        uint256 maturity,
        uint256 strategyTokenAmount
    ) public view returns (uint256 borrowedSecondaryfCashAmount) {
        if (SECONDARY_BORROW_CURRENCY_ID > 0) {
            // Return total second currency borrowed if account is the vault address
            if (account == address(this))
                return
                    NOTIONAL.getSecondaryBorrow(
                        address(this),
                        SECONDARY_BORROW_CURRENCY_ID,
                        maturity
                    );
            uint256 accountTotal = getStrategyTokenBalance(account);
            if (accountTotal > 0) {
                borrowedSecondaryfCashAmount =
                    (secondaryAmountfCashBorrowed[account][maturity] *
                        strategyTokenAmount) /
                    accountTotal;
            }
        }
    }

    /// @notice Gets the total number of strategy tokens owned by the given account
    /// @param account account address
    function getStrategyTokenBalance(address account)
        public
        view
        returns (uint256)
    {
        VaultAccount memory vaultAccount = NOTIONAL.getVaultAccount(
            account,
            address(this)
        );
        return vaultAccount.vaultShares;
    }

    function totalSupply(uint256 maturity) public view returns (uint256) {
        VaultState memory vaultState = NOTIONAL.getVaultState(
            address(this),
            maturity
        );
        return vaultState.totalStrategyTokens;
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal override onlyNotionalOwner {}
}
