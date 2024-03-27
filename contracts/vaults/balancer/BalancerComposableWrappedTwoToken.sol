// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

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
import {TokenUtils} from "@contracts/utils/TokenUtils.sol";
import {Constants} from "@contracts/global/Constants.sol";
import {TradeHandler, Trade} from "@contracts/trading/TradeHandler.sol";

contract BalancerComposableWrappedTwoToken is BalancerComposableAuraVault {
    using TradeHandler for Trade;

    /// @notice All initial trades will use this slippage limit, if this needs to change
    /// then the contract must be upgraded
    uint32 immutable DEFAULT_SLIPPAGE_LIMIT;

    /// @notice Only BalancerV2 or CurveV2 are supported as dexes here
    uint16 immutable DEX_ID;
    /// @notice For BalancerV2 this is the balancer pool id, for curve v2 this
    /// is the pool address.
    bytes32 immutable EXCHANGE_DATA;

    int256 immutable BORROW_DECIMALS;
    int256 immutable PRIMARY_DECIMALS;
    address immutable PRIMARY_TOKEN;
    address immutable BORROW_TOKEN;
 
    constructor(
        uint32 _defaultSlippage,
        uint16 _dexId,
        bytes32 exchangeData,
        address _borrowToken,
        NotionalProxy notional,
        AuraVaultDeploymentParams memory params,
        BalancerSpotPrice spotPrice
    ) BalancerComposableAuraVault(notional, params, spotPrice) {
        require(_dexId == uint16(DexId.BALANCER_V2) || _dexId == uint16(DexId.CURVE_V2));
        require(_NUM_TOKENS == 3);

        DEFAULT_SLIPPAGE_LIMIT = _defaultSlippage;
        EXCHANGE_DATA = exchangeData;
        DEX_ID = _dexId;

        (IERC20[] memory tokens, uint8[] memory decimals) = TOKENS();
        PRIMARY_TOKEN = address(tokens[_PRIMARY_INDEX]);
        PRIMARY_DECIMALS = int256(10**decimals[_PRIMARY_INDEX]);

        BORROW_TOKEN = _borrowToken;
        BORROW_DECIMALS = int256(10**TokenUtils.getDecimals(_borrowToken));
    }

    /// @notice strategy identifier
    function strategy() external override pure returns (bytes4) {
        return bytes4(keccak256("BalancerComposableWrappedTwoToken"));
    }

    function TOKENS() public view override returns (IERC20[] memory, uint8[] memory) {
        IERC20[] memory tokens = new IERC20[](3);
        uint8[] memory decimals = new uint8[](3);

        (tokens[0], decimals[0]) = (IERC20(TOKEN_1), DECIMALS_1);
        (tokens[1], decimals[1]) = (IERC20(TOKEN_2), DECIMALS_2);
        (tokens[2], decimals[2]) = (IERC20(TOKEN_3), DECIMALS_3);

        return (tokens, decimals);
    }

    function ASSETS() internal view override returns (IAsset[] memory) {
        IAsset[] memory assets = new IAsset[](3);
        assets[0] = IAsset(TOKEN_1);
        assets[1] = IAsset(TOKEN_2);
        assets[2] = IAsset(TOKEN_3);
        return assets;
    }

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
            exchangeData: abi.encode(BalancerV2Adapter.SingleSwapData(EXCHANGE_DATA))
        })._executeTradeWithDynamicSlippage(
            DEX_ID, DEFAULT_SLIPPAGE_LIMIT
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
            exchangeData: abi.encode(BalancerV2Adapter.SingleSwapData(EXCHANGE_DATA))
        })._executeTradeWithDynamicSlippage(
            DEX_ID, DEFAULT_SLIPPAGE_LIMIT
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