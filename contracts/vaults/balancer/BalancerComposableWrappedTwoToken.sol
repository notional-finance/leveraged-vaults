// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {
    BalancerComposableAuraVault,
    NotionalProxy,
    AuraVaultDeploymentParams,
    BalancerSpotPrice,
    IERC20
} from "./BalancerComposableAuraVault.sol";
import {BalancerV2Adapter} from "@contracts/trading/adapters/BalancerV2Adapter.sol";
import {IAsset} from "@interfaces/balancer/IBalancerVault.sol";
import {DexId, TradeType} from "@interfaces/trading/ITradingModule.sol";
import {Constants} from "@contracts/global/Constants.sol";
import {TradeHandler, Trade} from "@contracts/trading/TradeHandler.sol";

contract BalancerComposableWrappedTwoToken is BalancerComposableAuraVault {
    using TradeHandler for Trade;

    // Set to 50 basis points, if this needs to change then the contract will
    // need to be upgraded.
    uint32 constant DEFAULT_SLIPPAGE_LIMIT = 0.01e8;
    address constant PRIMARY_TOKEN = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant BORROW_TOKEN = address(0);
    int256 constant BORROW_DECIMALS = 1e18;
    int256 constant PRIMARY_DECIMALS = 1e18;
    bytes constant EXCHANGE_DATA = abi.encode(
        BalancerV2Adapter.SingleSwapData(0x1e19cf2d73a72ef1332c882f20534b6519be0276000200000000000000000112)
    );

    function TOKENS() public view override returns (IERC20[] memory, uint8[] memory) {
        IERC20[] memory tokens = new IERC20[](_NUM_TOKENS);
        uint8[] memory decimals = new uint8[](_NUM_TOKENS);

        (tokens[0], decimals[0]) = (IERC20(TOKEN_1), DECIMALS_1);
        (tokens[1], decimals[1]) = (IERC20(TOKEN_2), DECIMALS_2);
        (tokens[2], decimals[2]) = (IERC20(TOKEN_3), DECIMALS_3);

        return (tokens, decimals);
    }

    function ASSETS() internal view override returns (IAsset[] memory) {
        IAsset[] memory assets = new IAsset[](_NUM_TOKENS);
        assets[0] = IAsset(TOKEN_1);
        assets[1] = IAsset(TOKEN_2);
        assets[2] = IAsset(TOKEN_3);
        return assets;
    }

    constructor(
        NotionalProxy notional_,
        AuraVaultDeploymentParams memory params,
        BalancerSpotPrice _spotPrice
    ) BalancerComposableAuraVault(notional_, params, _spotPrice) { }

    function _depositFromNotional(
        address account, uint256 deposit, uint256 maturity, bytes calldata data
    ) internal override returns (uint256 vaultSharesMinted) {

        (/* */, uint256 amountBought) = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: Constants.ETH_ADDRESS,
            buyToken: PRIMARY_TOKEN,
            amount: deposit,
            limit: DEFAULT_SLIPPAGE_LIMIT,
            deadline: block.timestamp,
            exchangeData: EXCHANGE_DATA
        })._executeTradeWithDynamicSlippage(
            uint16(DexId.BALANCER_V2), DEFAULT_SLIPPAGE_LIMIT
        );

        return super._depositFromNotional(account, amountBought, maturity, data);
    }

    function _redeemFromNotional(
        address account, uint256 vaultShares, uint256 maturity, bytes calldata data
    ) internal override returns (uint256 finalPrimaryBalance) {
        uint256 primaryBalance = super._redeemFromNotional(
            account, vaultShares, maturity, data
        );

        (/* */, finalPrimaryBalance) = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: PRIMARY_TOKEN,
            buyToken: BORROW_TOKEN,
            amount: primaryBalance,
            limit: DEFAULT_SLIPPAGE_LIMIT,
            deadline: block.timestamp,
            exchangeData: EXCHANGE_DATA
        })._executeTradeWithDynamicSlippage(
            uint16(DexId.BALANCER_V2), DEFAULT_SLIPPAGE_LIMIT
        );
    }

    function convertStrategyToUnderlying(
        address account, uint256 vaultShares, uint256 maturity
    ) public view override returns (int256 underlyingValue) {
        int256 primaryValue = super.convertStrategyToUnderlying(
            account, vaultShares, maturity
        );

        (int256 rate, int256 rateDecimals) = TRADING_MODULE.getOraclePrice(
            PRIMARY_TOKEN, BORROW_TOKEN
        );

        // Convert this back to the borrow currency, external precision
        return (primaryValue * BORROW_DECIMALS * rate) / (rateDecimals * PRIMARY_DECIMALS);
    }
}