// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.8.11;
pragma abicoder v2;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Token, VaultState, VaultAccount} from "../global/Types.sol";
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
import {IBalancerPool} from "../../interfaces/balancer/IBalancerPool.sol";
import {IPriceOracle} from "../../interfaces/balancer/IPriceOracle.sol";
import {ITradingModule, Trade} from "../../interfaces/trading/ITradingModule.sol";
import {TradeHandler} from "../trading/TradeHandler.sol";

contract Balancer2TokenVault is
    UUPSUpgradeable,
    Initializable,
    BaseStrategyVault
{
    using TradeHandler for Trade;
    using SafeERC20 for ERC20;

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

    struct DepositParams {
        uint256 minBPT;
        uint256 secondaryfCashAmount;
        uint32 secondarySlippageLimit;
    }

    struct RedeemParams {
        uint256 minUnderlying;
        bool withdrawFromWETH;
        uint256 secondaryfCashAmount;
        uint32 secondarySlippageLimit;
    }

    struct SettlementParams {
        uint256 minPrimaryAmount;
        uint256 minSecondaryAmount;
    }

    struct RepaySecondaryCallbackParams {
        uint256 borrowedSecondaryAmount;
    }

    /** Errors */
    error InvalidPrimaryToken(address token);
    error InvalidSecondaryToken(address token);
    error InvalidTokenIndex(uint256 tokenIndex);

    /** Events */
    event OracleWindowUpdated(uint256 oldWindow, uint256 newWindow);
    event SettlementPercentageUpdated(
        uint256 oldPercentage,
        uint256 newPercentage
    );
    event SettlementCoolDownUpdated(uint256 oldCoolDown, uint256 newCoolDown);

    /** Constants */

    uint256 internal constant SECONDARY_BORROW_UPPER_LIMIT = 105;
    uint256 internal constant SECONDARY_BORROW_LOWER_LIMIT = 95;
    uint256 internal constant MAX_SETTLEMENT_PERCENTAGE = 1e8; // 100%
    uint256 internal constant MAX_SETTLEMENT_COOLDOWN = 24 * 3600; // 1 day

    /** Immutables */
    uint16 public immutable SECONDARY_BORROW_CURRENCY_ID;
    IBalancerVault public immutable BALANCER_VAULT;
    bytes32 public immutable BALANCER_POOL_ID;
    IBalancerPool public immutable BALANCER_POOL_TOKEN;
    ERC20 public immutable SECONDARY_TOKEN;
    IBoostController public immutable BOOST_CONTROLLER;
    ILiquidityGauge public immutable LIQUIDITY_GAUGE;
    IVeBalDelegator public immutable VEBAL_DELEGATOR;
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

    /// @notice Balancer oracle window in seconds
    uint256 public oracleWindowInSeconds;

    /// @notice Total number of strategy tokens across all maturities
    uint256 public totalStrategyTokenGlobal;

    uint256 public settlementPercentage;

    uint256 public settlementCoolDown;

    constructor(
        address notional_,
        uint16 borrowCurrencyId_,
        bool setApproval,
        bool useUnderlyingToken,
        DeploymentParams memory params
    )
        BaseStrategyVault(
            "Balancer 2-Token Strategy Vault",
            notional_,
            borrowCurrencyId_,
            setApproval,
            useUnderlyingToken
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
        PRIMARY_INDEX = tokens[0] == _primaryAddress() ? 0 : 1;

        // Since this is always a 2-token vault, SECONDARY_INDEX = 1-PRIMARY_INDEX
        SECONDARY_TOKEN = SECONDARY_BORROW_CURRENCY_ID > 0
            ? ERC20(_getTokenAddress(SECONDARY_BORROW_CURRENCY_ID))
            : ERC20(tokens[1 - PRIMARY_INDEX]);

        // Make sure the deployment parameters are correct
        if (tokens[PRIMARY_INDEX] != _primaryAddress())
            revert InvalidPrimaryToken(tokens[PRIMARY_INDEX]);
        if (SECONDARY_BORROW_CURRENCY_ID > 0) {
            if (tokens[1 - PRIMARY_INDEX] != _secondaryAddress())
                revert InvalidSecondaryToken(tokens[1 - PRIMARY_INDEX]);
        }

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
        SETTLEMENT_PERIOD = params.settlementPeriod;
    }

    function initialize(
        uint256 _oracleWindowInSeconds,
        uint256 _settlementPercentage,
        uint256 _settlementCooldown
    ) external initializer onlyNotionalOwner {
        oracleWindowInSeconds = _oracleWindowInSeconds;
        settlementPercentage = _settlementPercentage;
        settlementCoolDown = _settlementCooldown;
        _initRewardTokenList();
        _approveTokens();
    }

    /// @notice special handling for ETH because UNDERLYING_TOKEN == address(0))
    /// and Balancer uses WETH
    function _primaryAddress() private returns (address) {
        return
            BORROW_CURRENCY_ID == 1 ? address(WETH) : address(UNDERLYING_TOKEN);
    }

    /// @notice special handling for ETH because SECONDARY_TOKEN == address(0))
    /// and Balancer uses WETH
    function _secondaryAddress() private returns (address) {
        if (SECONDARY_BORROW_CURRENCY_ID > 0) {
            return
                SECONDARY_BORROW_CURRENCY_ID == 1
                    ? address(WETH)
                    : address(SECONDARY_TOKEN);
        }
        return address(0);
    }

    function _getTokenAddress(uint16 currencyId) private returns (address) {
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
        // Allow Balancer vault to pull UNDERLYING_TOKEN
        if (address(UNDERLYING_TOKEN) != address(0)) {
            UNDERLYING_TOKEN.safeApprove(
                address(BALANCER_VAULT),
                type(uint256).max
            );
        }
        // Allow balancer vault to pull SECONDARY_TOKEN
        if (address(SECONDARY_TOKEN) != address(0)) {
            SECONDARY_TOKEN.safeApprove(
                address(BALANCER_VAULT),
                type(uint256).max
            );
        }
        // Allow LIQUIDITY_GAUGE to pull BALANCER_POOL_TOKEN
        ERC20(address(BALANCER_POOL_TOKEN)).safeApprove(
            address(LIQUIDITY_GAUGE),
            type(uint256).max
        );
        // Allow VEBAL_DELEGATOR to pull LIQUIDITY_GAUGE tokens
        ERC20(address(LIQUIDITY_GAUGE)).safeApprove(
            address(VEBAL_DELEGATOR),
            type(uint256).max
        );
    }

    /// @notice Converts strategy tokens to underlyingValue
    /// @dev Secondary token value is converted to its primary token equivalent value
    /// using the Balancer time-weighted price oracle
    /// @param strategyTokenAmount strategy token amount
    /// @param maturity maturity timestamp
    /// @return underlyingValue underlying (primary token) value of the strategy tokens
    function convertStrategyToUnderlying(
        uint256 strategyTokenAmount,
        uint256 maturity
    ) public view override returns (uint256 underlyingValue) {
        uint256 bptClaim = getStrategyTokenClaim(strategyTokenAmount, maturity);
        return getTimeWeightedPrimaryBalance(bptClaim);
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

    /// @notice Returns how many Balancer pool tokens a strategy token amount has a claim on
    function getStrategyTokenClaim(
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

    function _exitPool(
        address account,
        uint256 bptExitAmount,
        uint256 maturity,
        uint256 borrowedSecondaryAmount,
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
            borrowedSecondaryAmount
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
        if (borrowedSecondaryAmount > 0) {
            NOTIONAL.repaySecondaryCurrencyFromVault(
                SECONDARY_BORROW_CURRENCY_ID,
                maturity,
                params.secondaryfCashAmount,
                params.secondarySlippageLimit,
                abi.encode(borrowedSecondaryAmount)
            );
        }
    }

    /// @notice Callback function for repaying secondary debt
    function _repaySecondaryBorrowCallback(
        uint256 assetCashRequired,
        bytes calldata data
    ) internal override returns (bytes memory returnData) {
        require(msg.sender == address(NOTIONAL)); /// @dev invalid caller
        require(SECONDARY_BORROW_CURRENCY_ID > 0); /// @dev invalid secondary currency
        RepaySecondaryCallbackParams memory params = abi.decode(
            data,
            (RepaySecondaryCallbackParams)
        );

        // Require the secondary borrow amount to be within SECONDARY_BORROW_LOWER_LIMIT percent
        // of the optimal amount
        require(
            assetCashRequired >=
                ((params.borrowedSecondaryAmount *
                    (SECONDARY_BORROW_LOWER_LIMIT)) / 100) &&
                assetCashRequired <=
                (params.borrowedSecondaryAmount *
                    (SECONDARY_BORROW_UPPER_LIMIT)) /
                    100,
            "invalid secondary amount"
        );

        if (SECONDARY_BORROW_CURRENCY_ID == 1) {
            payable(address(NOTIONAL)).transfer(assetCashRequired);
        } else {
            SECONDARY_TOKEN.safeTransfer(address(NOTIONAL), assetCashRequired);
        }
    }

    function _redeemFromNotional(
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 tokensFromRedeem) {
        tokensFromRedeem = getStrategyTokenClaim(strategyTokens, maturity);

        if (tokensFromRedeem > 0) {
            // Withdraw gauge token from VeBALDelegator
            BOOST_CONTROLLER.withdrawToken(
                address(LIQUIDITY_GAUGE),
                tokensFromRedeem
            );

            // Unstake BPT
            LIQUIDITY_GAUGE.withdraw(tokensFromRedeem, false);

            // Calculate the amount of secondary tokens to repay
            uint256 borrowedSecondaryAmount = 0;
            if (SECONDARY_BORROW_CURRENCY_ID > 0) {
                uint256 accountTotal = getStrategyTokenBalance(account);
                if (accountTotal > 0) {
                    borrowedSecondaryAmount =
                        (secondaryAmountfCashBorrowed[account][maturity] *
                            strategyTokens) /
                        accountTotal;
                }
            }

            _exitPool(
                account,
                tokensFromRedeem,
                maturity,
                borrowedSecondaryAmount,
                data
            );
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

    /// @notice Updates the settlement percentage
    /// @dev This value determines the max value per settlement trade
    /// @param newSettlementPercentage 1e8 = 100%
    function setSettlementPercentage(uint256 newSettlementPercentage)
        external
        onlyNotionalOwner
    {
        require(newSettlementPercentage <= MAX_SETTLEMENT_PERCENTAGE);
        emit SettlementPercentageUpdated(
            settlementPercentage,
            newSettlementPercentage
        );
        settlementPercentage = newSettlementPercentage;
    }

    /// @notice Updates the settlement cool down
    /// @dev Time limit between settlement trades
    /// @param newSettlementCoolDown settlement cool down in seconds
    function setSettlementCoolDown(uint256 newSettlementCoolDown)
        external
        onlyNotionalOwner
    {
        require(newSettlementCoolDown <= MAX_SETTLEMENT_COOLDOWN);
        emit SettlementCoolDownUpdated(
            settlementCoolDown,
            newSettlementCoolDown
        );
        settlementCoolDown = newSettlementCoolDown;
    }

    /** Public view functions */

    function getTokenDecimals(uint256 tokenIndex)
        public
        view
        returns (uint256)
    {
        if (tokenIndex == PRIMARY_INDEX) {
            return
                address(UNDERLYING_TOKEN) == address(0)
                    ? 18
                    : UNDERLYING_TOKEN.decimals();
        } else if (tokenIndex == (1 - PRIMARY_INDEX)) {
            if (SECONDARY_BORROW_CURRENCY_ID == 0) return 0;

            return
                address(SECONDARY_TOKEN) == address(0)
                    ? 18
                    : SECONDARY_TOKEN.decimals();
        }

        revert InvalidTokenIndex(tokenIndex);
    }

    /// @notice Gets the time-weighted primary token balance for a given bptAmount
    /// @dev Balancer pool needs to be fully initialized with at least 1024 trades
    /// @param bptAmount BPT amount
    /// @return primaryBalance primary token balance
    function getTimeWeightedPrimaryBalance(uint256 bptAmount)
        public
        view
        returns (uint256)
    {
        // Gets the BPT token price
        uint256 bptPrice = BalancerUtils.getTimeWeightedOraclePrice(
            address(BALANCER_POOL_TOKEN),
            IPriceOracle.Variable.BPT_PRICE,
            uint256(oracleWindowInSeconds)
        );

        // The first token in the BPT pool is the primary token.
        // Since bptPrice is always denominated in the first token,
        // Both bptPrice and bptAmount are in 1e18
        // underlyingValue = bptPrice * bptAmount / 1e18
        if (PRIMARY_INDEX == 0) {
            uint256 primaryAmount = (bptPrice * bptAmount) / 1e18;

            // Normalize precision to primary precision
            uint256 primaryDecimals = getTokenDecimals(PRIMARY_INDEX);
            return (primaryAmount * primaryDecimals) / 1e18;
        }

        // The second token in the BPT pool is the primary token.
        // In this case, we need to convert secondaryTokenValue
        // to underlyingValue using the pairPrice.
        // Both bptPrice and bptAmount are in 1e18
        uint256 secondaryAmount = (bptPrice * bptAmount) / 1e18;

        // Gets the pair price
        uint256 pairPrice = BalancerUtils.getTimeWeightedOraclePrice(
            address(BALANCER_POOL_TOKEN),
            IPriceOracle.Variable.PAIR_PRICE,
            uint256(oracleWindowInSeconds)
        );

        // PairPrice =  (SecondaryAmount / SecondaryWeight) / (PrimaryAmount / PrimaryWeight)
        // (SecondaryAmount / SecondaryWeight) / PairPrice = (PrimaryAmount / PrimaryWeight)
        // PrimaryAmount = (SecondaryAmount / SecondaryWeight) / PairPrice * PrimaryWeight

        // Calculate weighted secondary amount
        secondaryAmount = ((secondaryAmount * 1e18) / SECONDARY_WEIGHT);

        // Calculate primary amount using pair price
        uint256 primaryAmount = ((secondaryAmount * 1e18) / pairPrice);

        // Calculate secondary amount (precision is still 1e18)
        primaryAmount = (primaryAmount * PRIMARY_WEIGHT) / 1e18;

        // Normalize precision to secondary precision (Balancer uses 1e18)
        uint256 primaryDecimals = getTokenDecimals(PRIMARY_INDEX);
        return (primaryAmount * 10**primaryDecimals) / 1e18;
    }

    /// @notice Gets the current spot price with a given token index
    /// @param tokenIndex 0 = PRIMARY_TOKEN, 1 = SECONDARY_TOKEN
    /// @return spotPrice token spot price
    function getSpotPrice(uint256 tokenIndex) public view returns (uint256) {
        // prettier-ignore
        (
            /* address[] memory tokens */,
            uint256[] memory balances,
            /* uint256 lastChangeBlock */
        ) = BALANCER_VAULT.getPoolTokens(BALANCER_POOL_ID);

        uint256 primaryDecimals = getTokenDecimals(PRIMARY_INDEX);
        uint256 secondaryDecimals = getTokenDecimals(1 - PRIMARY_INDEX);

        // Make everything 1e18
        uint256 primaryBalance = balances[PRIMARY_INDEX] *
            10**(18 - primaryDecimals);
        uint256 secondaryBalance = balances[1 - PRIMARY_INDEX] *
            10**(18 - secondaryDecimals);

        // First we multiply everything by 1e18 for the weight division (weights are in 1e18),
        // then we multiply the numerator by 1e18 to to preserve enough precision for the division
        if (tokenIndex == PRIMARY_INDEX) {
            // PrimarySpotPrice = (SecondaryBalance / SecondaryWeight * 1e18) / (PrimaryBalance / PrimaryWeight)
            return
                (((secondaryBalance * 1e18) / SECONDARY_WEIGHT) * 1e18) /
                ((primaryBalance * 1e18) / PRIMARY_WEIGHT);
        } else if (tokenIndex == (1 - PRIMARY_INDEX)) {
            // SecondarySpotPrice = (PrimaryBalance / PrimaryWeight * 1e18) / (SecondaryBalance / SecondaryWeight)
            return
                (((primaryBalance * 1e18) / PRIMARY_WEIGHT) * 1e18) /
                ((secondaryBalance * 1e18) / SECONDARY_WEIGHT);
        }

        revert InvalidTokenIndex(tokenIndex);
    }

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
        uint256 primaryDecimals = getTokenDecimals(PRIMARY_INDEX);
        secondaryAmount =
            (secondaryAmount * 10**SECONDARY_TOKEN.decimals()) /
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

    function getSecondaryBorrowedAmount(address account, uint256 maturity)
        public
        view
        returns (uint256)
    {
        return secondaryAmountfCashBorrowed[account][maturity];
    }

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
