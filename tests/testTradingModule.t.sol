// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

import "@contracts/trading/TradingModule.sol";
import "@contracts/trading/TradeHandler.sol";
import "@interfaces/WETH9.sol";
import "@interfaces/notional/NotionalProxy.sol";
import "@interfaces/notional/IStrategyVault.sol";
import "@interfaces/trading/ITradingModule.sol";
import {IERC20} from "@contracts/utils/TokenUtils.sol";

contract TestTradingModule is Test {
    using TradeHandler for Trade;

    NotionalProxy constant NOTIONAL = NotionalProxy(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    TradingModule constant TRADING_MODULE = TradingModule(0xBf6B9c5608D520469d8c4BD1E24F850497AF0Bb8);

    address internal constant ETH = address(0);
    address internal constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address internal constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address internal constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address internal constant WSTETH = 0x5979D7b546E38E414F7E9822514be443A4800529;
    address internal constant WETH = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address internal constant cbETH = address(0x1DEBd73E752bEaF79865Fd6446b0c970EaE7732f);
    address internal constant rETH = address(0xEC70Dcb4A1EFa46b8F2D97C310C9c4790ba5ffA8);

    string RPC_URL = vm.envString("RPC_URL");
    uint256 FORK_BLOCK = 137439907;
    address owner = 0xE6FB62c2218fd9e3c948f0549A2959B509a293C8;
    mapping(uint256 => address) tokenIndex;
    uint256 maxTokenIndex;

    struct Params {
        DexId dexId;
        Trade t;
        bool shouldRevert;
    }
    Params[] tradeParams;

    // function setUp() public {
    //     vm.createSelectFork(RPC_URL, FORK_BLOCK);
    //     // TEMP: changes to allow for auth revert msg
    //     TradingModule impl = new TradingModule(NOTIONAL, TRADING_MODULE);

    //     vm.prank(owner);
    //     TRADING_MODULE.upgradeTo(address(impl));
    //     tokenIndex[1] = ETH;
    //     tokenIndex[2] = DAI;
    //     tokenIndex[3] = USDC;
    //     tokenIndex[4] = WBTC;
    //     tokenIndex[5] = WSTETH;
    //     tokenIndex[6] = WETH;

    //     maxTokenIndex = 6;

    //     /****** CURVE V2 Trades *****/
    //     tradeParams.push(Params(
    //         DexId.CURVE_V2,
    //         Trade({
    //             tradeType: TradeType.EXACT_IN_SINGLE,
    //             sellToken: ETH,
    //             buyToken: WSTETH,
    //             amount: 1e18,
    //             limit: 0,
    //             deadline: 0,
    //             exchangeData: abi.encode(
    //                 CurveV2Adapter.CurveV2SingleData({ pool: 0x6eB2dc694eB516B16Dc9FBc678C60052BbdD7d80 })
    //             )
    //         }),
    //         false
    //     ));

    //     tradeParams.push(Params(
    //         DexId.CURVE_V2,
    //         Trade({
    //             tradeType: TradeType.EXACT_IN_SINGLE,
    //             sellToken: WSTETH,
    //             buyToken: ETH,
    //             amount: 1e18,
    //             limit: 0,
    //             deadline: 0,
    //             exchangeData: abi.encode(
    //                 CurveV2Adapter.CurveV2SingleData({ pool: 0x6eB2dc694eB516B16Dc9FBc678C60052BbdD7d80 })
    //             )
    //         }),
    //         false
    //     ));

    //     /****** Balancer V2 Trades *****/
    //     tradeParams.push(Params(
    //         DexId.BALANCER_V2,
    //         Trade({
    //             tradeType: TradeType.EXACT_IN_SINGLE,
    //             sellToken: WSTETH,
    //             buyToken: rETH,
    //             amount: 1e18,
    //             limit: 0,
    //             deadline: block.timestamp,
    //             exchangeData: abi.encode(
    //                 BalancerV2Adapter.SingleSwapData({ poolId: 0x4a2f6ae7f3e5d715689530873ec35593dc28951b000000000000000000000481 })
    //             )
    //         }),
    //         false
    //     ));

    //     tradeParams.push(Params(
    //         DexId.BALANCER_V2,
    //         Trade({
    //             tradeType: TradeType.EXACT_IN_SINGLE,
    //             sellToken: cbETH,
    //             buyToken: rETH,
    //             amount: 1e18,
    //             limit: 0,
    //             deadline: block.timestamp,
    //             exchangeData: abi.encode(
    //                 BalancerV2Adapter.SingleSwapData({ poolId: 0x4a2f6ae7f3e5d715689530873ec35593dc28951b000000000000000000000481 })
    //             )
    //         }),
    //         false
    //     ));
    // }

    function assertRelDiff(uint256 a, uint256 b, uint256 rel, uint256 precision, string memory m) internal {
        uint256 d = a > b ? a - b : b - a;
        uint256 r = d * 1e9 / precision;
        assertLe(r, rel, m);
    }

    function executeTrade(
        uint16 dexId,
        Trade memory trade
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        return trade._executeTrade(dexId);
    }

    function executeTradeWithDynamicSlippage(
        uint16 dexId,
        Trade memory trade,
        uint32 dynamicSlippageLimit
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        return trade._executeTradeWithDynamicSlippage(dexId, dynamicSlippageLimit);
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

    function test_oraclePrice(uint256 token1, uint256 token2) public {
        token1 = bound(token1, 1, maxTokenIndex);
        token2 = bound(token2, 1, maxTokenIndex);

        (int256 answerOne, /* int256 decimals */) = TRADING_MODULE.getOraclePrice(
            tokenIndex[token1], tokenIndex[token2]
        );
        (int256 answerTwo, int256 decimals) = TRADING_MODULE.getOraclePrice(
            tokenIndex[token2], tokenIndex[token1]
        );
        
        if (token1 == token2) {
            assertEq(uint256(answerOne), uint256(decimals));
            assertEq(uint256(answerTwo), uint256(decimals));
        }

        assertRelDiff(
            uint256(answerOne),
            uint256(decimals * decimals / answerTwo),
            0.01e5,
            uint256(decimals),
            "Oracle Price"
        );
    }

    function test_ExecuteTrade(uint256 tradeParamIndex) public {
        tradeParamIndex = bound(tradeParamIndex, 0, tradeParams.length - 1);
        Params memory p = tradeParams[tradeParamIndex];
        address sellToken = p.t.sellToken;
        address buyToken = p.t.buyToken;

        if (sellToken == ETH) {
            deal(address(this), p.t.amount);
        } else {
            deal(sellToken, address(this), p.t.amount, true);
        }

        (address spender, /* */, /* */, /* */) = TRADING_MODULE.getExecutionData(
            uint16(p.dexId),
            address(this),
            p.t
        );

        vm.prank(NOTIONAL.owner());
        TRADING_MODULE.setTokenPermissions(
            address(this),
            sellToken,
            ITradingModule.TokenPermissions({
                allowSell: true,
                dexFlags: uint32(1 << uint8(p.dexId)),
                tradeTypeFlags: uint32(1 << uint8(p.t.tradeType))
            })
        );

        if (sellToken != ETH) assertEq(IERC20(sellToken).allowance(address(this), spender), 0);
        if (buyToken != ETH) assertEq(IERC20(buyToken).allowance(address(this), spender), 0);
        uint256 soldBalanceBefore = sellToken == ETH ? 
            address(this).balance :
            IERC20(sellToken).balanceOf(address(this));
        uint256 buyBalanceBefore = buyToken == ETH ?
            address(this).balance :
            IERC20(buyToken).balanceOf(address(this));

        if (p.shouldRevert) vm.expectRevert();
        (uint256 amountSold, uint256 amountBought) = executeTrade(uint16(p.dexId), p.t);

        uint256 soldBalanceAfter = sellToken == ETH ?
            address(this).balance :
            IERC20(sellToken).balanceOf(address(this));
        uint256 buyBalanceAfter = buyToken == ETH ?
            address(this).balance :
            IERC20(buyToken).balanceOf(address(this));

        assertEq(soldBalanceBefore - soldBalanceAfter, amountSold);
        assertEq(buyBalanceAfter - buyBalanceBefore, amountBought);

        if (sellToken != ETH) assertEq(IERC20(sellToken).allowance(address(this), spender), 0);
        if (buyToken != ETH) assertEq(IERC20(buyToken).allowance(address(this), spender), 0);
    }

    function test_ZeroEx_Trading() public {
        vm.createSelectFork(vm.envString("ARBITRUM_RPC_URL"), 235996354);
        // TEMP: changes to allow for auth revert msg
        TradingModule impl = new TradingModule(NOTIONAL, TRADING_MODULE);

        vm.prank(NOTIONAL.owner());
        TRADING_MODULE.upgradeTo(address(impl));

        console.log(address(this));
        Params memory p = Params(
            DexId.ZERO_EX,
            Trade({
                tradeType: TradeType.EXACT_IN_SINGLE,
                sellToken: ETH,
                buyToken: WSTETH,
                amount: 1e18,
                limit: 0,
                deadline: 0,
                exchangeData: bytes(hex"2213bc0b0000000000000000000000002b6625aafc65373e5a82a0349f777fa11f7f04d100000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab100000000000000000000000000000000000000000000000000972c7b7de3db000000000000000000000000002b6625aafc65373e5a82a0349f777fa11f7f04d100000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000f041fff991f0000000000000000000000007fa9385be102ac3eac297483dd6233d62b3e14960000000000000000000000005979d7b546e38e414f7e9822514be443a4800529000000000000000000000000000000000000000000000000007e4c087d4387b900000000000000000000000000000000000000000000000000000000000000a0ea0392e6b1a11a5033b4167000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000002200000000000000000000000000000000000000000000000000000000000000360000000000000000000000000000000000000000000000000000000000000048000000000000000000000000000000000000000000000000000000000000006c000000000000000000000000000000000000000000000000000000000000007e00000000000000000000000000000000000000000000000000000000000000ae00000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000d2000000000000000000000000000000000000000000000000000000000000000c438c9c147000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000ad01c20d5886137e056775af56915de824c8fce5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010438c9c147000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000000000000000000000000000000000000000271000000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab1000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000024d0e30db00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e48d68a1560000000000000000000000002b6625aafc65373e5a82a0349f777fa11f7f04d1000000000000000000000000000000000000000000000000000000000000271000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002c82af49447d8a07e3bd95bd0d56f35241523fbab101000064af88d065e77c8cc2239327c5edb3a432268e5831000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020438c9c147000000000000000000000000af88d065e77c8cc2239327c5edb3a432268e58310000000000000000000000000000000000000000000000000000000000002710000000000000000000000000c873fecbd354f5a56e00e710b90ef4201db2448d000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000124ac3893ba0000000000000000000000000000000000000000000000000000000007e12fea000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000002b6625aafc65373e5a82a0349f777fa11f7f04d100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000066a2a3850000000000000000000000000000000000000000000000000000000000000002000000000000000000000000af88d065e77c8cc2239327c5edb3a432268e5831000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e48d68a1560000000000000000000000002b6625aafc65373e5a82a0349f777fa11f7f04d1000000000000000000000000000000000000000000000000000000000000203900000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002cff970a61a04b1ca14834a43f5de4533ebddb5cc8000001f45979d7b546e38e414f7e9822514be443a480052900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002c438c9c147000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc80000000000000000000000000000000000000000000000000000000000002710000000000000000000000000b4315e873dbcf96ffd0acd8ea43f689d8c20fb30000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000001e42a443fae00000000000000000000000000000000000000000000000000000000016103c2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000002b6625aafc65373e5a82a0349f777fa11f7f04d10000000000000000000000000000000000000000000000000000000066a2a385000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8000000000000000000000000fd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e48d68a1560000000000000000000000002b6625aafc65373e5a82a0349f777fa11f7f04d100000000000000000000000000000000000000000000000000000000000010bd00000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002cfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9000001f42f2a2543b76a4166549f7aab2e75bef0aefc5b0f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e48d68a1560000000000000000000000002b6625aafc65373e5a82a0349f777fa11f7f04d1000000000000000000000000000000000000000000000000000000000000271000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002cfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9010000642f2a2543b76a4166549f7aab2e75bef0aefc5b0f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e48d68a1560000000000000000000000002b6625aafc65373e5a82a0349f777fa11f7f04d1000000000000000000000000000000000000000000000000000000000000271000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002c2f2a2543b76a4166549f7aab2e75bef0aefc5b0f00000bb85979d7b546e38e414f7e9822514be443a480052900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")
            }),
            false
        );

        address sellToken = p.t.sellToken;
        address buyToken = p.t.buyToken;

        if (sellToken == ETH) {
            deal(address(this), p.t.amount);
        } else {
            deal(sellToken, address(this), p.t.amount, true);
        }

        (address spender, /* */, /* */, /* */) = TRADING_MODULE.getExecutionData(
            uint16(p.dexId),
            address(this),
            p.t
        );

        vm.prank(NOTIONAL.owner());
        TRADING_MODULE.setTokenPermissions(
            address(this),
            sellToken,
            ITradingModule.TokenPermissions({
                allowSell: true,
                dexFlags: uint32(1 << uint8(p.dexId)),
                tradeTypeFlags: uint32(1 << uint8(p.t.tradeType))
            })
        );

        if (sellToken != ETH) assertEq(IERC20(sellToken).allowance(address(this), spender), 0);
        if (buyToken != ETH) assertEq(IERC20(buyToken).allowance(address(this), spender), 0);
        uint256 soldBalanceBefore = sellToken == ETH ? 
            address(this).balance :
            IERC20(sellToken).balanceOf(address(this));
        uint256 buyBalanceBefore = buyToken == ETH ?
            address(this).balance :
            IERC20(buyToken).balanceOf(address(this));

        console.log("ETH BALANCE BEFORE", address(this).balance);
        if (p.shouldRevert) vm.expectRevert();
        (uint256 amountSold, uint256 amountBought) = executeTrade(uint16(p.dexId), p.t);

        uint256 soldBalanceAfter = sellToken == ETH ?
            address(this).balance :
            IERC20(sellToken).balanceOf(address(this));
        uint256 buyBalanceAfter = buyToken == ETH ?
            address(this).balance :
            IERC20(buyToken).balanceOf(address(this));

        assertEq(soldBalanceBefore - soldBalanceAfter, amountSold);
        assertEq(buyBalanceAfter - buyBalanceBefore, amountBought);

        if (sellToken != ETH) assertEq(IERC20(sellToken).allowance(address(this), spender), 0);
        if (buyToken != ETH) assertEq(IERC20(buyToken).allowance(address(this), spender), 0);
    }

    receive() payable external {}
}