// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {GmxFundingStrategyContext} from "./gmx/GmxVaultTypes.sol";
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
import {DeploymentParams} from "./gmx/GmxVaultTypes.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {OrderType} from "../../interfaces/gmx/GmxTypes.sol";
import {IGmxExchangeRouter} from "../../interfaces/gmx/IGmxExchangeRouter.sol";
import {IGmxReader} from "../../interfaces/gmx/IGmxReader.sol";
import {DexId} from "../../interfaces/trading/ITradingModule.sol";
import {StrategyUtils} from "./common/internal/strategy/StrategyUtils.sol";
import {TokenUtils, IERC20} from "../utils/TokenUtils.sol";

struct GmxVaultState {
    bytes32 orderHash;
    bytes32 positionHash;
}

contract GmxFundingVault is GmxFundingVaultMixin {
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
        uint256 executionFee,
        uint256 acceptablePrice
    )
        private
        returns (IGmxExchangeRouter.CreateOrderParamsNumbers memory params)
    {
        params.sizeDeltaUsd = positionSize;
        params.executionFee = executionFee;
        params.acceptablePrice = acceptablePrice;
    }

    function _getOrderParams(
        uint256 positionSize,
        uint256 executionFee,
        uint256 acceptablePrice,
        OrderType orderType
    ) private returns (IGmxExchangeRouter.CreateOrderParams memory params) {
        params.addresses = _getAddresses();
        params.numbers = _getNumbers(
            positionSize,
            executionFee,
            acceptablePrice
        );
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

        uint256 executionFee = 759100000000000; // Is this calculated?
        uint256 amountBought = 66592403;

        //(/* */, amountBought) = _tradePrimaryToCollateral(context.baseStrategy, params.tradeData);

        if (vaultState.positionHash == bytes32(0)) {
            // Create new position
            bytes[] memory data = new bytes[](3);
            uint256 positionSize = (amountBought * GMX_PRECISION) /
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
                    positionSize,
                    executionFee,
                    params.minPoolClaim,
                    OrderType.MarketIncrease
                )
            );

            bytes[] memory results = GMX_ROUTER.multicall{value: executionFee}(data);

            vaultState.orderHash = abi.decode(results[2], (bytes32));

            vaultSharesMinted = StrategyUtils._mintStrategyTokens(
                context.baseStrategy,
                positionSize
            );

            _lockVault();
        } else {
            // Update existing position
        }
    }

    function _depositFromNotional(
        address /* account */,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override whenNotLocked returns (uint256 vaultSharesMinted) {
        vaultSharesMinted = _deposit(_strategyContext(), deposit, data);
    }

    function _redeemFromNotional(
        address account,
        uint256 vaultShares,
        uint256 maturity,
        bytes calldata data
    ) internal override whenNotLocked returns (uint256 finalPrimaryBalance) {}

    function testGetOrder() external view returns (IGmxReader.OrderProps memory params) {
        GmxFundingStrategyContext memory context = _strategyContext();
        params = context.gmxReader.getOrder(GMX_DATASTORE, vaultState.orderHash);
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
            (int256 price, int256 decimals) = context.baseStrategy.tradingModule.getOraclePrice(COLLATERAL_TOKEN, PRIMARY_TOKEN);
            uint256 secondaryBalanceInPrimary = params.numbers.initialCollateralDeltaAmount * price.toUint() / COLLATERAL_PRECISION;

            totalCollateral += secondaryBalanceInPrimary * PRIMARY_PRECISION / decimals.toUint();
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
}
