// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {GmxFundingStrategyContext, DeploymentParams, GmxVaultState} from "./gmx/GmxVaultTypes.sol";
import {
    InitParams, 
    DepositParams, 
    DepositTradeParams, 
    StrategyContext, 
    StrategyVaultSettings
} from "./common/VaultTypes.sol";
import {Errors} from "../global/Errors.sol";
import {TypeConvert} from "../global/TypeConvert.sol";
import {VaultStorage} from "./common/VaultStorage.sol";
import {GmxFundingVaultMixin} from "./gmx/mixins/GmxFundingVaultMixin.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {OrderType} from "../../interfaces/gmx/GmxTypes.sol";
import {IGmxExchangeRouter} from "../../interfaces/gmx/IGmxExchangeRouter.sol";
import {IGmxOrderCallbackReceiver} from "../../interfaces/gmx/IGmxOrderCallbackReceiver.sol";
import {IGmxReader} from "../../interfaces/gmx/IGmxReader.sol";
import {DexId} from "../../interfaces/trading/ITradingModule.sol";
import {StrategyUtils} from "./common/internal/strategy/StrategyUtils.sol";
import {TokenUtils, IERC20} from "../utils/TokenUtils.sol";

contract GmxFundingVault is GmxFundingVaultMixin, IGmxOrderCallbackReceiver {
    using TokenUtils for IERC20;
    using TypeConvert for int256;
    using TypeConvert for uint256;
    using StrategyUtils for StrategyContext;

    // Figure out if GMX precision is really 1e30
    uint256 internal constant GMX_PRECISION = 1e30;

    GmxVaultState internal vaultState;

    constructor(
        NotionalProxy notional_,
        DeploymentParams memory params
    ) GmxFundingVaultMixin(notional_, params) {}

    function strategy() external view override returns (bytes4) {
        return bytes4(keccak256("GmxFundingVault"));
    }

    function initialize(
        InitParams calldata params
    ) external initializer onlyNotionalOwner {
        __INIT_VAULT(params.name, params.borrowCurrencyId);

        IERC20(COLLATERAL_TOKEN).checkApprove(GMX_SPENDER, type(uint256).max);
    }

    function _getAddresses()
        private
        returns (IGmxExchangeRouter.CreateOrderParamsAddresses memory params)
    {
        params.receiver = address(this);
        params.callbackContract = address(this);
        params.market = GMX_MARKET;
        params.initialCollateralToken = COLLATERAL_TOKEN;
    }

    function _getNumbers(
        uint256 positionSize,
        uint256 collateralDelta,
        uint256 executionFee,
        uint256 acceptablePrice
    )
        private
        returns (IGmxExchangeRouter.CreateOrderParamsNumbers memory params)
    {
        params.sizeDeltaUsd = positionSize;
        params.initialCollateralDeltaAmount = collateralDelta;
        params.executionFee = executionFee;
        params.acceptablePrice = acceptablePrice;
    }

    function _getOrderParams(
        uint256 positionSize,
        uint256 collateralDelta,
        uint256 executionFee,
        uint256 acceptablePrice,
        OrderType orderType
    ) private returns (IGmxExchangeRouter.CreateOrderParams memory params) {
        params.addresses = _getAddresses();
        params.numbers = _getNumbers({
            positionSize: positionSize,
            collateralDelta: collateralDelta,
            executionFee: executionFee,
            acceptablePrice: acceptablePrice
        });
        params.orderType = orderType;
        params.isLong = true;
    }

    function _tradePrimaryToCollateral(
        StrategyContext memory strategyContext,
        bytes memory data
    ) internal returns (uint256 primarySold, uint256 secondaryBought) {
        DepositTradeParams memory params = abi.decode(
            data,
            (DepositTradeParams)
        );

        if (DexId(params.tradeParams.dexId) == DexId.ZERO_EX) {
            revert Errors.InvalidDexId(params.tradeParams.dexId);
        }

        (primarySold, secondaryBought) = strategyContext._executeTradeExactIn({
            params: params.tradeParams,
            sellToken: PRIMARY_TOKEN,
            buyToken: COLLATERAL_TOKEN,
            amount: params.tradeAmount,
            useDynamicSlippage: true
        });
    }

    function _deposit(
        GmxFundingStrategyContext memory context,
        uint256 deposit,
        bytes calldata data
    ) internal returns (uint256 vaultSharesMinted) {
        DepositParams memory params = abi.decode(data, (DepositParams));

        // Trade from primaryToken to collateralToken

        uint256 executionFee = 0.5e18; // Is this calculated?

        (/* */, uint256 amountBought) = _tradePrimaryToCollateral(context.baseStrategy, params.tradeData);

        // Market increase
        bytes[] memory data = new bytes[](3);
        uint256 positionSize = amountBought * GMX_PRECISION /
            COLLATERAL_PRECISION;

        data[0] = abi.encodeWithSelector(
            IGmxExchangeRouter.sendWnt.selector,
            ORDER_VAULT,
            executionFee
        );
        data[1] = abi.encodeWithSelector(
            IGmxExchangeRouter.sendTokens.selector,
            COLLATERAL_TOKEN,
            ORDER_VAULT,
            amountBought
        );
        data[2] = abi.encodeWithSelector(
            IGmxExchangeRouter.createOrder.selector,
            _getOrderParams(
                positionSize: positionSize,
                collateralDelta: 0,
                executionFee: executionFee,
                acceptablePrice: params.minPoolClaim,
                orderType: OrderType.MarketIncrease
            )
        );

        bytes[] memory results = GMX_ROUTER.multicall{value: executionFee}(data);

        vaultState.orderHash = abi.decode(results[2], (bytes32));
        vaultState.orderType = OrderType.MarketIncrease

        vaultSharesMinted = StrategyUtils._mintStrategyTokens(
            context.baseStrategy,
            positionSize
        );

        _lockVault();
    }

    function _depositFromNotional(
        address /* account */,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override whenNotLocked returns (uint256 vaultSharesMinted) {
        vaultSharesMinted = _deposit(_strategyContext(), deposit, data);
    }

    function _redeem(
        GmxFundingStrategyContext memory context,
        uint256 vaultShares,
        bytes calldata data
    ) internal returns (uint256 finalPrimaryBalance) {
        uint256 positionSize = context.baseStrategy._convertStrategyTokensToPoolClaim(vaultShares);
        uint256 executionFee = 0.5e18; // Is this calculated?

        // Since our leverage ratio is always 1, collateralDelta is basically positionSize in underlying precision
        uint256 collateralDelta = positionSize * COLLATERAL_PRECISION / GMX_PRECISION;

        bytes[] memory data = new bytes[](2);

        // Market decrease
        data[0] = abi.encodeWithSelector(
            IGmxExchangeRouter.sendWnt.selector,
            ORDER_VAULT,
            executionFee
        );
        data[1] = abi.encodeWithSelector(
            IGmxExchangeRouter.createOrder.selector,
            _getOrderParams(
                positionSize: positionSize,
                collateralDelta: collateralDelta,
                executionFee: executionFee,
                acceptablePrice: params.minPoolClaim,
                orderType: OrderType.MarketDecrease
            )
        );

        bytes[] memory results = GMX_ROUTER.multicall{value: executionFee}(data);

        vaultState.orderHash = abi.decode(results[2], (bytes32));
        vaultState.orderType = OrderType.MarketDecrease;

        finalPrimaryBalance = _convertCollateralToPrimary(collateralDelta);

        _lockVault();
    }

    function _redeemFromNotional(
        address account,
        uint256 vaultShares,
        uint256 maturity,
        bytes calldata data
    ) internal override whenNotLocked returns (uint256 finalPrimaryBalance) {
        finalPrimaryBalance = _redeem(_strategyContext(), vaultShares, data);
    }

    function testGetOrder() external view returns (IGmxReader.OrderProps memory params) {
        GmxFundingStrategyContext memory context = _strategyContext();
        params = context.gmxReader.getOrder(GMX_DATASTORE, vaultState.orderHash);
    }

    function _convertCollateralToPrimary(uint256 collateralBalance) private view returns (uint256) {
        (int256 price, int256 decimals) = context.baseStrategy.tradingModule.getOraclePrice(COLLATERAL_TOKEN, PRIMARY_TOKEN);
        uint256 collateralBalanceInPrimary = collateralBalance * price.toUint() / COLLATERAL_PRECISION;

        return collateralBalanceInPrimary * PRIMARY_PRECISION / decimals.toUint();
    }

    function convertStrategyToUnderlying(
        address account,
        uint256 vaultShares,
        uint256 maturity
    )
        public
        view
        virtual
        override
        returns (int256 underlyingValue)
    {
        GmxFundingStrategyContext memory context = _strategyContext();

        uint256 totalCollateral;

        if (vaultState.orderHash != bytes32(0)) {
            IGmxReader.OrderProps memory params = context.gmxReader.getOrder(GMX_DATASTORE, vaultState.orderHash);
            totalCollateral += _convertCollateralToPrimary(params.numbers.initialCollateralDeltaAmount);
        }
        if (vaultState.positionHash != bytes32(0)) {
            // getPosition
            // use chainlink to fx position collateral amount to primary
            // add to totalCollateral
        }

        underlyingValue = (totalCollateral * vaultShares / context.baseStrategy.vaultState.totalVaultSharesGlobal).toInt();
    }

    /// @notice Updates the vault settings
    /// @param settings vault settings
    function setStrategyVaultSettings(
        StrategyVaultSettings calldata settings
    ) external onlyNotionalOwner {}

    function _strategyContext()
        internal
        view
        returns (GmxFundingStrategyContext memory)
    {
        return
            GmxFundingStrategyContext({
                gmxRouter: GMX_ROUTER,
                gmxReader: GMX_READER,
                orderVault: ORDER_VAULT,
                gmxState: vaultState,
                baseStrategy: StrategyContext({
                    tradingModule: TRADING_MODULE,
                    vaultSettings: VaultStorage.getStrategyVaultSettings(),
                    vaultState: VaultStorage.getStrategyVaultState(),
                    poolClaimPrecision: GMX_PRECISION,
                    canUseStaticSlippage: false
                })
            });
    }

    function getStrategyContext()
        external
        view
        returns (GmxFundingStrategyContext memory)
    {
        return _strategyContext();
    }

    function _checkReentrancyContext() internal override {}

    function getExchangeRate(
        uint256 maturity
    ) external view override returns (int256) {}

    function afterOrderExecution(
        bytes32 key,
        IGmxReader.OrderProps memory order,
        EventLogData memory eventData
    ) external override {
        revert("here");

        _unlockVault();
    }

    function afterOrderCancellation(
        bytes32 key,
        IGmxReader.OrderProps memory order,
        EventLogData memory eventData
    ) external override {
        _unlockVault();
    }

    function afterOrderFrozen(
        bytes32 key,
        IGmxReader.OrderProps memory order,
        EventLogData memory eventData
    ) external override {
        _unlockVault();
    }
}
