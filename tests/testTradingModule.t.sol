// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

import "@contracts/trading/TradingModule.sol";
import "@contracts/trading/TradeHandler.sol";
import "@interfaces/WETH9.sol";
import "@interfaces/notional/NotionalProxy.sol";
import "@interfaces/notional/IStrategyVault.sol";
import "@interfaces/trading/ITradingModule.sol";
import "@contracts/trading/adapters/BalancerV2Adapter.sol";
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
    uint256 FORK_BLOCK = 223168067;
    mapping(uint256 => address) tokenIndex;
    uint256 maxTokenIndex;

    struct Params {
        DexId dexId;
        Trade t;
        bool shouldRevert;
    }
    Params[] tradeParams;

    function setUp() public {
        vm.createSelectFork(RPC_URL, FORK_BLOCK);
        // NOTE: always test the latest version
        TradingModule impl = new TradingModule(NOTIONAL, TRADING_MODULE);

        vm.prank(NOTIONAL.owner());
        TRADING_MODULE.upgradeTo(address(impl));
        tokenIndex[1] = ETH;
        tokenIndex[2] = DAI;
        tokenIndex[3] = USDC;
        tokenIndex[4] = WBTC;
        tokenIndex[5] = WSTETH;
        tokenIndex[6] = WETH;

        maxTokenIndex = 6;

        /****** Curve V2 Trades *****/
        tradeParams.push(Params(
            DexId.CURVE_V2,
            Trade({
                tradeType: TradeType.EXACT_IN_SINGLE,
                sellToken: ETH,
                buyToken: WSTETH,
                amount: 1e18,
                limit: 0,
                deadline: 0,
                exchangeData: abi.encode(
                    CurveV2Adapter.CurveV2SingleData({
                        fromIndex: 0,
                        toIndex: 1,
                        pool: 0x6eB2dc694eB516B16Dc9FBc678C60052BbdD7d80
                    })
                )
            }),
            false
        ));

        tradeParams.push(Params(
            DexId.CURVE_V2,
            Trade({
                tradeType: TradeType.EXACT_IN_SINGLE,
                sellToken: WSTETH,
                buyToken: ETH,
                amount: 1e18,
                limit: 0,
                deadline: 0,
                exchangeData: abi.encode(
                    CurveV2Adapter.CurveV2SingleData({ 
                        fromIndex: 1,
                        toIndex: 0,
                        pool: 0x6eB2dc694eB516B16Dc9FBc678C60052BbdD7d80
                    })
                )
            }),
            false
        ));

        /****** Curve V2 Batch Trades *****/

        /****** Balancer V2 Trades *****/
        tradeParams.push(Params(
            DexId.BALANCER_V2,
            Trade({
                tradeType: TradeType.EXACT_IN_SINGLE,
                sellToken: WSTETH,
                buyToken: rETH,
                amount: 1e18,
                limit: 0,
                deadline: block.timestamp,
                exchangeData: abi.encode(
                    BalancerV2Adapter.SingleSwapData({ poolId: 0x4a2f6ae7f3e5d715689530873ec35593dc28951b000000000000000000000481 })
                )
            }),
            false
        ));

        tradeParams.push(Params(
            DexId.BALANCER_V2,
            Trade({
                tradeType: TradeType.EXACT_IN_SINGLE,
                sellToken: cbETH,
                buyToken: rETH,
                amount: 1e18,
                limit: 0,
                deadline: block.timestamp,
                exchangeData: abi.encode(
                    BalancerV2Adapter.SingleSwapData({ poolId: 0x4a2f6ae7f3e5d715689530873ec35593dc28951b000000000000000000000481 })
                )
            }),
            false
        ));

        /****** Balancer V2 Batch Trades *****/
        {
            IBalancerVault.BatchSwapStep[] memory swaps = new IBalancerVault.BatchSwapStep[](2);
            swaps[0] = IBalancerVault.BatchSwapStep({
                // cbETH, wstETH, rETH
                poolId: 0x2d6ced12420a9af5a83765a8c48be2afcd1a8feb000000000000000000000500,
                assetInIndex: 0, // Refers to the assets array
                assetOutIndex: 1,
                amount: 1e18,
                userData: ""
            });
            swaps[1] = IBalancerVault.BatchSwapStep({
                // WETH, rETH
                poolId: 0xd0ec47c54ca5e20aaae4616c25c825c7f48d40690000000000000000000004ef,
                assetInIndex: 1,
                assetOutIndex: 2,
                amount: 0,
                userData: ""
            });
            IAsset[] memory assets = new IAsset[](3);
            assets[0] = IAsset(cbETH);
            assets[1] = IAsset(rETH);
            assets[2] = IAsset(WETH);
            int256[] memory limits = new int256[](3);
            // Specify the max amount into the vault...
            limits[0] = 1e18;

            tradeParams.push(Params(
                DexId.BALANCER_V2,
                Trade({
                    tradeType: TradeType.EXACT_IN_BATCH,
                    sellToken: cbETH,
                    buyToken: WETH,
                    amount: 1e18,
                    limit: 0,
                    deadline: block.timestamp,
                    exchangeData: abi.encode(
                        BalancerV2Adapter.BatchSwapData({
                            swaps: swaps,
                            assets: assets,
                            limits: limits
                        })
                    )
                }),
                false
            ));
        }

        // Batch Given Out
        {
            IBalancerVault.BatchSwapStep[] memory swaps = new IBalancerVault.BatchSwapStep[](2);
            swaps[0] = IBalancerVault.BatchSwapStep({
                // cbETH, wstETH, rETH
                poolId: 0x2d6ced12420a9af5a83765a8c48be2afcd1a8feb000000000000000000000500,
                assetInIndex: 0, // Refers to the assets array
                assetOutIndex: 1,
                // Refers to the amount out in rETH
                amount: 1e18,
                userData: ""
            });
            swaps[1] = IBalancerVault.BatchSwapStep({
                // WETH, rETH
                poolId: 0xd0ec47c54ca5e20aaae4616c25c825c7f48d40690000000000000000000004ef,
                assetInIndex: 1,
                assetOutIndex: 2,
                // Refers to the amount out in WETH
                amount: 1e18,
                userData: ""
            });
            IAsset[] memory assets = new IAsset[](3);
            assets[0] = IAsset(cbETH);
            assets[1] = IAsset(rETH);
            assets[2] = IAsset(WETH);
            int256[] memory limits = new int256[](3);
            // Specify the max amount into the vault...
            limits[0] = 2e18;
            limits[2] = -1e18;

            tradeParams.push(Params(
                DexId.BALANCER_V2,
                Trade({
                    tradeType: TradeType.EXACT_OUT_BATCH,
                    sellToken: cbETH,
                    buyToken: WETH,
                    amount: 1e18,
                    limit: 2e18,
                    deadline: block.timestamp,
                    exchangeData: abi.encode(
                        BalancerV2Adapter.BatchSwapData({
                            swaps: swaps,
                            assets: assets,
                            limits: limits
                        })
                    )
                }),
                false
            ));
        }

        /****** Camelot V3 Trades *****/
        tradeParams.push(Params(
            DexId.CAMELOT_V3,
            Trade({
                tradeType: TradeType.EXACT_IN_SINGLE,
                sellToken: ETH,
                buyToken: USDC,
                amount: 1e18,
                limit: 0,
                deadline: block.timestamp,
                exchangeData: ""
            }),
            false
        ));

        /****** Uni V3 Trades *****/
    }

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

        vm.prank(NOTIONAL.owner());
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
        dexFlags = uint32(bound(dexFlags, 1 << (uint8(DexId.CAMELOT_V3) + 1), type(uint32).max));
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
            deal(address(this), p.t.amount * 2);
        } else {
            deal(sellToken, address(this), p.t.amount * 2, true);
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
        vm.createSelectFork(vm.envString("ARBITRUM_RPC_URL"), 236380392);
        // TEMP: changes to allow for auth revert msg
        TradingModule impl = new TradingModule(NOTIONAL, TRADING_MODULE);

        vm.prank(NOTIONAL.owner());
        TRADING_MODULE.upgradeTo(address(impl));

        // API Query to get the swap data:
        /* https://api.0x.org/swap/allowance-holder/quote?
            chainId=42161&
            buyToken=0x5979D7b546E38E414F7E9822514be443A4800529&
            sellToken=0x82aF49447D8a07e3bd95BD0d56f35241523fBab1&
            sellAmount=1000000000000000000&
            taker=0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496
        */
        Params memory p = Params(
            DexId.ZERO_EX,
            Trade({
                tradeType: TradeType.EXACT_IN_SINGLE,
                sellToken: WETH,
                buyToken: WSTETH,
                amount: 1e18,
                limit: 0,
                deadline: 0,
                exchangeData: bytes(hex"2213bc0b0000000000000000000000002b6625aafc65373e5a82a0349f777fa11f7f04d100000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab10000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000002b6625aafc65373e5a82a0349f777fa11f7f04d100000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000a041fff991f0000000000000000000000007fa9385be102ac3eac297483dd6233d62b3e14960000000000000000000000005979d7b546e38e414f7e9822514be443a48005290000000000000000000000000000000000000000000000000bb12fe30666e08700000000000000000000000000000000000000000000000000000000000000a01731a9f342aa9b6aec2e66f400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000001a00000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000070000000000000000000000000000000000000000000000000000000000000000e4c1fb425e0000000000000000000000002b6625aafc65373e5a82a0349f777fa11f7f04d100000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab10000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000066a41c1c00000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012438c9c14700000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab1000000000000000000000000000000000000000000000000000000000000000f00000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab1000000000000000000000000000000000000000000000000000000000000002400000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000044a9059cbb000000000000000000000000ad01c20d5886137e056775af56915de824c8fce50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003c438c9c14700000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab10000000000000000000000000000000000000000000000000000000000001d4c000000000000000000000000ba12222222228d8ba445958a75a0704d566bf2c800000000000000000000000000000000000000000000000000000000000001c400000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000002e4945bcec90000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000002200000000000000000000000002b6625aafc65373e5a82a0349f777fa11f7f04d100000000000000000000000000000000000000000000000000000000000000000000000000000000000000002b6625aafc65373e5a82a0349f777fa11f7f04d1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002800000000000000000000000000000000000000000000000000000000066a41c1c000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000209791d590788598535278552eecd4b211bfc790cb000000000000000000000498000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000a6489d8442bb00000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab10000000000000000000000005979d7b546e38e414f7e9822514be443a480052900000000000000000000000000000000000000000000000000000000000000027fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020438c9c14700000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab10000000000000000000000000000000000000000000000000000000000002710000000000000000000000000aa23611badafb62d37e7295a682d21960ac85a90000000000000000000000000000000000000000000000000000000000000008400000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000124c04b8d59000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000002b6625aafc65373e5a82a0349f777fa11f7f04d10000000000000000000000000000000000000000000000000000000066a41c1c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002b82af49447d8a07e3bd95bd0d56f35241523fbab10000325979d7b546e38e414f7e9822514be443a4800529000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")
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