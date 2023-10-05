// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "../contracts/trading/TradingModule.sol";
import "../contracts/trading/TradeHandler.sol";
import "../interfaces/WETH9.sol";
import "../interfaces/notional/NotionalProxy.sol";
import "../interfaces/notional/IStrategyVault.sol";
import "../interfaces/trading/ITradingModule.sol";
import {IERC20} from "../contracts/utils/TokenUtils.sol";

contract TestTradingModule is Test {
    using TradeHandler for Trade;

    WETH9 constant WETH = WETH9(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    NotionalProxy constant NOTIONAL = NotionalProxy(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    TradingModule constant TRADING_MODULE = TradingModule(0xBf6B9c5608D520469d8c4BD1E24F850497AF0Bb8);

    address internal constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;

    string RPC_URL = vm.envString("RPC_URL");
    uint256 FORK_BLOCK = 137439907;
    address owner = 0xE6FB62c2218fd9e3c948f0549A2959B509a293C8;

    function setUp() public {
        vm.createSelectFork(RPC_URL, FORK_BLOCK);
        // TEMP: changes to allow for auth revert msg
        TradingModule impl = new TradingModule(NOTIONAL, TRADING_MODULE);

        vm.prank(owner);
        TRADING_MODULE.upgradeTo(address(impl));
    }

    function executeTrade(
        uint16 dexId,
        Trade memory trade
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        return trade._executeTrade(dexId, TRADING_MODULE);
    }

    function executeTradeWithDynamicSlippage(
        uint16 dexId,
        Trade memory trade,
        uint32 dynamicSlippageLimit
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        return trade._executeTradeWithDynamicSlippage(dexId, TRADING_MODULE, dynamicSlippageLimit);
    }

    function test_RevertIf_ReinitializeConstructor() public {
        TradingModule impl = TradingModule(
            nProxy(payable(address(TRADING_MODULE))).getImplementation()
        );

        vm.prank(owner);
        vm.expectRevert();
        impl.initialize(100);
    }

    function test_RevertIf_Unauthorized_Initialization() public {
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        TRADING_MODULE.initialize(100);
    }

    function test_RevertIf_Unauthorized_Upgrade() public {
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        TRADING_MODULE.upgradeTo(address(1));
    }

    function test_RevertIf_Unauthorized_MaxOracleFreshness() public {
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        TRADING_MODULE.setMaxOracleFreshness(0);
    }

    function test_RevertIf_Unauthorized_SetPriceOracle() public {
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        TRADING_MODULE.setPriceOracle(address(0), AggregatorV2V3Interface(address(100)));
    }

    function test_RevertIf_Unauthorized_SetTokenPermissions() public {
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        TRADING_MODULE.setTokenPermissions(
            address(NOTIONAL),
            address(0),
            ITradingModule.TokenPermissions({
                allowSell: true,
                dexFlags: 1,
                tradeTypeFlags: 1
            })
        );
    }

    function test_RevertIf_InvalidTokenPermission(
        uint32 dexFlags,
        uint32 tradeTypeFlags
    ) public {
        dexFlags = uint32(bound(dexFlags, 1 << (uint8(DexId.CURVE_V2) + 1), type(uint32).max));
        tradeTypeFlags = uint32(bound(tradeTypeFlags, 1 << (uint8(TradeType.EXACT_OUT_BATCH) + 1), type(uint32).max));

        vm.prank(NOTIONAL.owner());
        vm.expectRevert();
        TRADING_MODULE.setTokenPermissions(
            address(NOTIONAL),
            address(0),
            ITradingModule.TokenPermissions({
                allowSell: true,
                dexFlags: dexFlags,
                tradeTypeFlags: 1
            })
        );

        vm.expectRevert();
        TRADING_MODULE.setTokenPermissions(
            address(NOTIONAL),
            address(0),
            ITradingModule.TokenPermissions({
                allowSell: true,
                dexFlags: 1,
                tradeTypeFlags: tradeTypeFlags
            })
        );
    }

    function test_RevertIf_ExecuteTradeWithoutPermission(
        uint16 dexId,
        uint16 tradeType
    ) public {
        tradeType = uint16(bound(tradeType, 0, 3));
        vm.expectRevert(TradingModule.InsufficientPermissions.selector);
        TRADING_MODULE.executeTrade(
            dexId,
            Trade({
                tradeType: TradeType(tradeType),
                sellToken: address(0),
                buyToken: DAI,
                amount: 1e18,
                limit: 0,
                deadline: 0,
                exchangeData: ""
            })
        );

        vm.expectRevert(TradingModule.InsufficientPermissions.selector);
        TRADING_MODULE.executeTradeWithDynamicSlippage(
            dexId,
            Trade({
                tradeType: TradeType(tradeType),
                sellToken: address(0),
                buyToken: DAI,
                amount: 1e18,
                limit: 0,
                deadline: 0,
                exchangeData: ""
            }),
            0.01e8
        );
    }

    // function test_oraclePrice() {}
    // function test_dynamicLimitAmount() {}

    // function test_Execute_UniswapV3(uint256 tokenInIndex, uint256 tokenOutIndex) {}
    // function test_Execute_BalancerV2(uint256 tokenInIndex, uint256 tokenOutIndex) {}
    // function test_Execute_CurveV2(uint256 tokenInIndex, uint256 tokenOutIndex) {}
    // function test_Execute_ZeroEx(uint256 tokenInIndex, uint256 tokenOutIndex) {}
    // function test_Execute_UniswapV2(uint256 tokenInIndex, uint256 tokenOutIndex) {}
}