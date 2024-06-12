// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseSingleSidedLPVault} from "./BaseSingleSidedLPVault.sol";
import {Deployments} from "@deployments/Deployments.sol";
import {Constants} from "@contracts/global/Constants.sol";
import {VaultConfigParams} from "@contracts/global/Types.sol";
import {VaultRewarderLib} from "@contracts/vaults/common/VaultRewarderLib.sol";
import {VaultRewardState} from "@interfaces/notional/IVaultRewarder.sol";
import {ITradingModule} from "@interfaces/trading/ITradingModule.sol";
import {IERC4626} from "@interfaces/IERC4626.sol";
import {ISingleSidedLPStrategyVault, StrategyVaultSettings} from "@interfaces/notional/ISingleSidedLPStrategyVault.sol";
import {NotionalProxy} from "@interfaces/notional/NotionalProxy.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata as IERC20} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

function min(uint256 a, uint256 b) pure returns (uint256) {
    return a < b ? a : b;
}

abstract contract VaultRewarderTests is BaseSingleSidedLPVault {
    using SafeERC20 for IERC20;
    struct AccountsData {
        address account;
        uint256 initialShare;
        uint256 currentShare;
        uint256 vaultShareSeconds;
        uint256 lastCalculation;
    }

    struct AdditionalRewardToken {
        address token;
        uint128 emissionRatePerYear;
        uint32 endTime;
        uint256 decimals;
    }

    address REWARD;

    AdditionalRewardToken[3] additionalRewardTokens;
    AccountsData[5] private accounts;
    uint256[][5] private totalRewardsPerAccount;
    uint256 private totalAccountsShare;
    uint256 maturity;
    uint256 claimAccountRewardsCall;

    function setUp() public virtual override {
        super.setUp();

        address REWARD_1;
        address REWARD_2;
        maturity = maturities[0];
        if (Deployments.CHAIN_ID == 1) {
            REWARD = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC on mainnet
            REWARD_1 = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
            REWARD_2 = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // Tether

            vm.prank(Deployments.NOTIONAL.owner());
        } else {
            REWARD = 0x019bE259BC299F3F653688c7655C87F998Bc7bC1; // NOTE
            REWARD_1 = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; // DAI
            REWARD_2 = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC

            vm.prank(Deployments.NOTIONAL.owner());
        }
        Deployments.TRADING_MODULE.setMaxOracleFreshness(type(uint32).max);

        additionalRewardTokens[0] = AdditionalRewardToken(REWARD, 1_000_000e8, uint32(block.timestamp + 30 days), 10 ** 8);
        additionalRewardTokens[1] = AdditionalRewardToken(REWARD_1, 1_000e18, uint32(block.timestamp + 10 days), 10 ** 18);
        additionalRewardTokens[2] = AdditionalRewardToken(REWARD_2, 100_000e6, uint32(block.timestamp + 200 days), 10 ** 6);
    }

    function _updateRewardToken(address rewardToken, uint256 index, uint256 emissionRatePerYear, uint256 endTime)
        private
    {
        vm.prank(Deployments.NOTIONAL.owner());
        VaultRewarderLib(address(vault)).updateRewardToken({
            index: index,
            rewardToken: rewardToken,
            emissionRatePerYear: uint128(emissionRatePerYear),
            endTime: uint32(endTime)
        });
    }

    function _depositWithInitialAccounts() private returns (uint256 initialVaultShare) {
        initialVaultShare = totalVaultSharesAllMaturities;
        uint256 totalInitialDeposit = 2 * maxDeposit;

        accounts[0] = AccountsData(makeAddr("account1"), 10, 0, 0, 0);
        accounts[1] = AccountsData(makeAddr("account2"), 40, 0, 0, 0);
        accounts[2] = AccountsData(makeAddr("account3"), 15, 0, 0, 0);
        accounts[3] = AccountsData(makeAddr("account4"), 25, 0, 0, 0);
        accounts[4] = AccountsData(makeAddr("account5"), 5, 0 , 0, 0);

        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i].account;
            uint256 amount = totalInitialDeposit * accounts[i].initialShare / 100;
            uint256 vaultShares = enterVault(account, amount, maturity, getDepositParams(0, 0));
            accounts[i].initialShare = vaultShares;
            accounts[i].currentShare = vaultShares;
            accounts[i].lastCalculation = block.timestamp;
            totalAccountsShare += vaultShares;
        }
    }

    function _addRewardTokensToVault(AdditionalRewardToken[3] memory newRewardTokens) internal {
        AdditionalRewardToken[] memory newRewardTokensDynamic = new AdditionalRewardToken[](newRewardTokens.length);
        for (uint256 i = 0; i < newRewardTokens.length; i++) {
            newRewardTokensDynamic[i] = newRewardTokens[i];
        }
        _addRewardTokensToVault(newRewardTokensDynamic);
    }

    function _addRewardTokensToVault(AdditionalRewardToken[] memory newRewardTokens) internal {
        for (uint256 i = 0; i < newRewardTokens.length; i++) {
            setTokenPermissions(
                address(vault),
                newRewardTokens[i].token,
                ITradingModule.TokenPermissions({allowSell: false, dexFlags: 1, tradeTypeFlags: 1})
            );

            _updateRewardToken(
                newRewardTokens[i].token,
                i,
                newRewardTokens[i].emissionRatePerYear,
                newRewardTokens[i].endTime
            );
        }
    }

    function _convertToDynamic(AdditionalRewardToken[3] memory newRewardTokens) pure internal returns (
        AdditionalRewardToken[] memory newRewardTokensDynamic
    ) {
        newRewardTokensDynamic = new AdditionalRewardToken[](newRewardTokens.length);
        for (uint256 i = 0; i < newRewardTokens.length; i++) {
            newRewardTokensDynamic[i] = newRewardTokens[i];
        }
    }

    function _sendIncentivesToVault(AdditionalRewardToken[3] memory newRewardTokens) internal returns (
        uint256[] memory totalIncentives
    ) {
        AdditionalRewardToken[] memory newRewardTokensDynamic = new AdditionalRewardToken[](newRewardTokens.length);
        for (uint256 i = 0; i < newRewardTokens.length; i++) {
            newRewardTokensDynamic[i] = newRewardTokens[i];
        }
        totalIncentives = _sendIncentivesToVault(newRewardTokensDynamic);
    }

    // calculate totalIncentives that will be emitted for each reward token
    // and send enough funds to vault
    function _sendIncentivesToVault(AdditionalRewardToken[] memory tokens) internal returns (
        uint256[] memory totalIncentives
    ) {
        totalIncentives = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            totalIncentives[i] = (tokens[i].endTime - uint32(block.timestamp))
                * tokens[i].emissionRatePerYear / Constants.YEAR;
            if (totalIncentives[i] > 0) {
                uint256 totalToDeal =
                    totalIncentives[i] + IERC20(tokens[i].token).balanceOf(address(vault));
                deal(tokens[i].token, address(vault), totalToDeal, true);
            }
        }
    }



    function _setForceClaimAfter(uint256 forceClaimAfter) public {
        ISingleSidedLPStrategyVault.SingleSidedLPStrategyVaultInfo memory info =
            ISingleSidedLPStrategyVault(address(vault)).getStrategyVaultInfo();
        (VaultRewardState[] memory r, /* */, /* */) = VaultRewarderLib(address(vault)).getRewardSettings();

        vm.prank(Deployments.NOTIONAL.owner());
        ISingleSidedLPStrategyVault(address(vault)).setStrategyVaultSettings(StrategyVaultSettings({
            deprecated_emergencySettlementSlippageLimitPercent: 0,
            maxPoolShare: uint16(info.maxPoolShare),
            oraclePriceDeviationLimitPercent: uint16(info.oraclePriceDeviationLimitPercent),
            numRewardTokens: uint8(r.length),
            forceClaimAfter: uint32(forceClaimAfter)
        }));
    }

    enum AssertType {
        Gt,
        Eq,
        Ge,
        Lt,
        Le
    }

    function _claimAndAssertNewBal(AssertType assertType, AdditionalRewardToken[3] memory tokens) internal {
        _claimAndAssertNewBal(assertType, _convertToDynamic(tokens));
    }
    function _claimAndAssertNewBal(AssertType assertType, AdditionalRewardToken[] memory tokens) internal {
        for (uint256 i = 0; i < accounts.length; i++) {
            uint256[] memory prevBalances = new uint256[](tokens.length);
            for (uint256 j = 0; j < tokens.length; j++) {
                prevBalances[j] = IERC20(tokens[j].token).balanceOf(accounts[i].account);
            }

            vm.prank(accounts[i].account);
            VaultRewarderLib(address(vault)).claimAccountRewards(accounts[i].account);


            for (uint256 j = 0; j < tokens.length; j++) {
                uint256 newBal = IERC20(tokens[j].token).balanceOf(accounts[i].account);
                if (assertType == AssertType.Gt) {
                    assertGt(newBal, prevBalances[j], "New balance should be greater than previous");
                } else if (assertType == AssertType.Eq) {
                    assertEq(newBal, prevBalances[j], "New balance should be equal previous balance");
                } else {
                    revert("Not implemented");
                }
            }
        }
    }

    function _claimAndAssertNewBalEqExpectedRewardAllowZeroRewards(
        AdditionalRewardToken[3] memory tokens, uint256[] memory totalClaimed, uint256 lastClaimTimestamp, uint256 diff
    ) internal {
        _claimAndAssertNewBalEqExpectedReward(_convertToDynamic(tokens), totalClaimed, lastClaimTimestamp, diff, true);
    }

    function _claimAndAssertNewBalEqExpectedReward(
        AdditionalRewardToken[3] memory tokens, uint256[] memory totalClaimed, uint256 lastClaimTimestamp, uint256 diff
    ) internal {
        _claimAndAssertNewBalEqExpectedReward(_convertToDynamic(tokens), totalClaimed, lastClaimTimestamp, diff, false);
    }

    function _claimAndAssertNewBalEqExpectedReward(
        AdditionalRewardToken[] memory tokens, uint256[] memory totalClaimed, uint256 lastClaimTimestamp, uint256 diff, bool allowZero
    ) internal {
        uint256[][] memory expectedRewardsArray = new uint256[][](accounts.length);
        uint256[][] memory prevBalArray = new uint256[][](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            uint256[] memory expectedRewards = new uint256[](tokens.length);
            uint256[] memory prevBal = new uint256[](tokens.length);
            for (uint256 j = 0; j < tokens.length; j++) {
                uint256 time = min(
                    block.timestamp - lastClaimTimestamp,
                    tokens[j].endTime < lastClaimTimestamp
                        ? 0
                        : tokens[j].endTime - lastClaimTimestamp
                );
                uint256 accountVaultShareSeconds = accounts[i].vaultShareSeconds + accounts[i].currentShare * time;
                if (time == 0) {
                    expectedRewards[j] = 0;
                } else {
                    expectedRewards[j] = time * tokens[j].emissionRatePerYear * accountVaultShareSeconds
                        / (Constants.YEAR * (totalVaultSharesAllMaturities * time));
                }
                if (!allowZero) {
                    assertTrue(expectedRewards[j] != 0, "Expected reward should not be zero");
                }

                prevBal[j] = IERC20(tokens[j].token).balanceOf(accounts[i].account);
            }
            expectedRewardsArray[i] = expectedRewards;
            prevBalArray[i] = prevBal;
        }

        for (uint256 i = 0; i < accounts.length; i++) {
            _claimAccountRewards(i);

            uint256[] memory expectedRewards = expectedRewardsArray[i];
            uint256[] memory prevBal = prevBalArray[i];
            for (uint256 j = 0; j < tokens.length; j++) {
                uint256 newBal = IERC20(tokens[j].token).balanceOf(accounts[i].account);
                assertApproxEqRel(newBal - prevBal[j], expectedRewards[j], diff, "New balance should equal expect rewards");
                totalClaimed[j] += newBal - prevBal[j];
            }
        }
    }

    enum S {
        ENTER_VAULT,
        EXIT_VAULT,
        DELEVERAGE,
        SIMPLE_CLAIM
    }

    function _claimAccountRewards(uint256 i) internal {
        // on each next call change which scenario will be executed for account
        S scenario = S((claimAccountRewardsCall++ + i) % 4);
        // all of the cases will claim reward under the hood
        if (scenario == S.ENTER_VAULT) {
            uint256 vaultShares = enterVault(accounts[i].account, maxDeposit / 10, maturity, getDepositParams(0, 0));
            accounts[i].currentShare += vaultShares;
        } else if (scenario == S.EXIT_VAULT) {
            uint256 vaultShares = accounts[i].currentShare * 5 / 100;
            uint256 lendAmount = uint256(Deployments.NOTIONAL.getVaultAccount(accounts[i].account, address(vault)).accountDebtUnderlying * - 5 / 100);

            vm.prank(accounts[i].account);
            Deployments.NOTIONAL.exitVault(
                accounts[i].account,
                address(vault),
                0x000000000000000000000000000000000000dEaD, // send to zero address so it does not mess up with reward calculation check when lend token and reward token are the same
                vaultShares,
                lendAmount,
                0,
                getRedeemParams(0, 0)
            );
            totalVaultShares[maturity] -= vaultShares;
            totalVaultSharesAllMaturities -= vaultShares;
            accounts[i].currentShare -= vaultShares;
        } else if (scenario == S.DELEVERAGE) {
            uint256 liquidatedVaultShares = _liquidateAccount(accounts[i].account);
            accounts[i].currentShare -= liquidatedVaultShares;
        } else if (scenario == S.SIMPLE_CLAIM) {
            vm.prank(accounts[i].account);
            VaultRewarderLib(address(vault)).claimAccountRewards(accounts[i].account);
        }
        accounts[i].vaultShareSeconds = 0;
        accounts[i].lastCalculation = 0;
    }

    function _liquidateAccount(address account) internal returns (uint256 liquidatedVaultShares) {
        // set vault settings so account can be liquidated
        VaultConfigParams memory newConfig = VaultConfigParams({
            flags: config.flags,
            borrowCurrencyId: config.borrowCurrencyId,
            minAccountBorrowSize: config.minAccountBorrowSize,
            minCollateralRatioBPS: 10000,
            feeRate5BPS: config.feeRate5BPS,
            liquidationRate: config.liquidationRate,
            reserveFeeShare: config.reserveFeeShare,
            maxBorrowMarketIndex: config.maxBorrowMarketIndex,
            maxDeleverageCollateralRatioBPS: 10001,
            secondaryBorrowCurrencies: config.secondaryBorrowCurrencies,
            maxRequiredAccountCollateralRatioBPS: 10101,
            minAccountSecondaryBorrow: config.minAccountSecondaryBorrow,
            excessCashLiquidationBonus: config.excessCashLiquidationBonus
        });
        vm.prank(Deployments.NOTIONAL.owner());
        Deployments.NOTIONAL.updateVault(address(vault), newConfig, getMaxPrimaryBorrow());

        address liquidator = makeAddr("liquidator");
        uint256 value;
        if (isETH) {
            value = 100 ether;
        } else {
            value = 10_000 * 10 ** primaryBorrowToken.decimals();
        }

        dealTokensAndApproveNotional(value, liquidator);
        vm.prank(liquidator);
        (uint256 vaultSharesFromLiquidation,) =
            vault.deleverageAccount{value: isETH ? value : 0 }(account, address(vault), liquidator, 0, int256(value / 1e10));

        // return vault config in previous state
        vm.prank(Deployments.NOTIONAL.owner());
        Deployments.NOTIONAL.updateVault(address(vault), config, getMaxPrimaryBorrow());

        return vaultSharesFromLiquidation;
    }

    function test_VaultRewarder_updateRewardToken_ShouldFailIfNotNotionOwner() public {
        (VaultRewardState[] memory state,,) = VaultRewarderLib(address(vault)).getRewardSettings();
        assertEq(state.length, 0);

        vm.expectRevert();
        VaultRewarderLib(address(vault)).updateRewardToken({
            index: 0,
            rewardToken: REWARD,
            emissionRatePerYear: uint128(100_000e8),
            endTime: uint32(block.timestamp + 30 days)
        });
    }

    function test_VaultRewarder_updateRewardToken_ShouldFailIfUpdatingExistingIndexWithDifferentToken() public {
        (VaultRewardState[] memory state,,) = VaultRewarderLib(address(vault)).getRewardSettings();
        assertEq(state.length, 0);

        vm.prank(Deployments.NOTIONAL.owner());
        VaultRewarderLib(address(vault)).updateRewardToken({
            index: 0,
            rewardToken: REWARD,
            emissionRatePerYear: uint128(100_000e8),
            endTime: uint32(block.timestamp + 30 days)
        });

        vm.expectRevert();
        VaultRewarderLib(address(vault)).updateRewardToken({
            index: 0,
            rewardToken: 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8,
            emissionRatePerYear: uint128(10_000e8),
            endTime: uint32(block.timestamp + 60 days)
        });
    }

    function test_VaultRewarder_updateRewardToken() public {
        (VaultRewardState[] memory state,,) = VaultRewarderLib(address(vault)).getRewardSettings();
        assertEq(state.length, 0);

        vm.prank(Deployments.NOTIONAL.owner());
        _updateRewardToken({
            index: 0,
            rewardToken: REWARD,
            emissionRatePerYear: 100_000e8,
            endTime: uint32(block.timestamp + 30 days)
        });

        (state,,) = VaultRewarderLib(address(vault)).getRewardSettings();
        assertEq(state.length, 1, "1");

        // update reward token that is issue via reward booster
        setTokenPermissions(
            address(vault),
            address(metadata.rewardTokens[0]),
            ITradingModule.TokenPermissions({allowSell: false, dexFlags: 1, tradeTypeFlags: 1})
        );
        vm.prank(Deployments.NOTIONAL.owner());
        _updateRewardToken({
            index: 1,
            rewardToken: address(metadata.rewardTokens[0]),
            emissionRatePerYear: 0,
            endTime: uint32(block.timestamp + 300 days)
        });

        (state,,) = VaultRewarderLib(address(vault)).getRewardSettings();
        assertEq(state.length, 2, "2");
    }

    function test_getAccountRewardClaim_ShouldBeZeroAtStartOfIncentivePeriod() public {
        _depositWithInitialAccounts();
        _updateRewardToken({
            index: 0,
            rewardToken: REWARD,
            emissionRatePerYear: 100_000e8,
            endTime: block.timestamp + 30 days
        });
        for (uint256 i = 0; i < accounts.length; i++) {
            uint256[] memory rewards =
                VaultRewarderLib(address(vault)).getAccountRewardClaim(accounts[i].account, block.timestamp);
            assertTrue(rewards.length != 0, "1");
            for (uint256 j; j < rewards.length; j++) {
                assertEq(rewards[j], 0, "2");
            }
        }
    }

    function testFuzz_getAccountRewardClaim_ShouldNotBeZeroAfterSomeTime(uint32 timeToSkip) public {
        timeToSkip = uint32(bound(timeToSkip, 1 hours, uint256(type(uint32).max / 10)));
        uint256 emissionRatePerYear = 1_000_000e8;
        uint256 endTime = block.timestamp + 30 days;
        _updateRewardToken({index: 0, rewardToken: REWARD, emissionRatePerYear: emissionRatePerYear, endTime: endTime});
        uint40 starTime = uint40(block.timestamp);
        _depositWithInitialAccounts();

        skip(timeToSkip);

        uint256 totalGeneratedIncentive = uint256(min(timeToSkip, endTime - starTime)) * emissionRatePerYear
            * Constants.INCENTIVE_ACCUMULATION_PRECISION / Constants.YEAR;

        for (uint256 i = 0; i < accounts.length; i++) {
            assertEq(VaultRewarderLib(address(vault)).getRewardDebt(REWARD, accounts[i].account), 0, "Debt should be 0");
            uint256 predictedReward = totalGeneratedIncentive * accounts[i].initialShare
                / (Constants.INCENTIVE_ACCUMULATION_PRECISION * totalVaultSharesAllMaturities);
            uint256[] memory rewards =
                VaultRewarderLib(address(vault)).getAccountRewardClaim(accounts[i].account, uint32(block.timestamp));

            assertEq(rewards.length, 1, "One");
            for (uint256 j; j < rewards.length; j++) {
                assertApproxEqRel(
                    rewards[j],
                    predictedReward,
                    1e14, // 0.01 %
                    vm.toString(j)
                );
            }
        }
    }

    function test_claimRewardTokens_ShouldFailIfCalledFromNotional() public {

        vm.prank(address(Deployments.NOTIONAL));
        vm.expectRevert();
        VaultRewarderLib(address(vault)).claimRewardTokens();
    }

    function test_claimRewardTokens_ShouldBeCallableByAnyoneExceptNotional(address caller) public {
        vm.assume(caller != address(Deployments.NOTIONAL));

        vm.prank(caller);
        VaultRewarderLib(address(vault)).claimRewardTokens();

        vm.warp(block.timestamp + 1 days);

        vm.prank(caller);
        VaultRewarderLib(address(vault)).claimRewardTokens();
        vm.prank(caller);
        VaultRewarderLib(address(vault)).claimRewardTokens();
    }

    function test_updateAccountRewards_ShouldBeCallableByNotional() public {
        address account = makeAddr("account");
        vm.prank(address(Deployments.NOTIONAL));
        VaultRewarderLib(address(vault)).updateAccountRewards(account, 1e8, 1e10, true);
    }

    function test_updateAccountRewards_ShouldNotBeCallableByAnyoneExceptNotional(address account) public {
        vm.assume(account != address(Deployments.NOTIONAL));

        vm.prank(account);
        vm.expectRevert();
        VaultRewarderLib(address(vault)).updateAccountRewards(account, 1e8, 1e10, true);
    }

    function _provideLiquidity() internal {
        address liquidityProvider = makeAddr("liquidityProvider");

        vm.prank(Deployments.NOTIONAL.owner());
        Deployments.NOTIONAL.setMaxUnderlyingSupply(config.borrowCurrencyId, 0, 100);


        uint256 decimals = isETH ? 18 : primaryBorrowToken.decimals();
        uint256 deposit = 1000_000 * 10 ** decimals;
        dealTokens(liquidityProvider, deposit);
        vm.startPrank(liquidityProvider);
        if (!isETH) {
            IERC20(address(primaryBorrowToken)).safeApprove(address(Deployments.NOTIONAL), deposit);
        }
        Deployments.NOTIONAL.depositUnderlyingToken{value: isETH ? deposit : 0}(liquidityProvider, config.borrowCurrencyId, deposit);
        vm.stopPrank();
    }

    function test_claimReward_ShouldNotClaimMoreThanTotalIncentives() public {
        vm.skip(_shouldSkip("test_claimReward_ShouldNotClaimMoreThanTotalIncentives"));
        _provideLiquidity();
        uint256 PERCENT_DIFF = 3e15; // 1e18 is 100%
        for (uint256 i = 0; i < additionalRewardTokens.length; i++) {
            _updateRewardToken(
                additionalRewardTokens[i].token,
                i,
                additionalRewardTokens[i].emissionRatePerYear,
                additionalRewardTokens[i].endTime
            );
        }
        _depositWithInitialAccounts();

        uint256[] memory totalIncentives = _sendIncentivesToVault(additionalRewardTokens);

        uint256[] memory totalClaimed = new uint256[](additionalRewardTokens.length);
        uint256 lastClaimTimestamp = block.timestamp;
        uint256 skipTime = 1 days;
        vm.warp(block.timestamp + skipTime);

        _claimAndAssertNewBalEqExpectedReward(additionalRewardTokens, totalClaimed, lastClaimTimestamp, PERCENT_DIFF);
        lastClaimTimestamp = block.timestamp;

        skipTime = 2 weeks;
        vm.warp(block.timestamp + skipTime);

        _claimAndAssertNewBalEqExpectedReward(additionalRewardTokens, totalClaimed, lastClaimTimestamp, PERCENT_DIFF);
        lastClaimTimestamp = block.timestamp;


        skipTime = 20 weeks;
        vm.warp(block.timestamp + skipTime);

        _claimAndAssertNewBalEqExpectedRewardAllowZeroRewards(
            additionalRewardTokens, totalClaimed, lastClaimTimestamp, PERCENT_DIFF
        );

        for (uint256 i = 0; i < additionalRewardTokens.length; i++) {
            assertLe(totalClaimed[i], totalIncentives[i], "Total claimed less than total incentives");
        }
    }

    function test_claimReward_ShouldNotClaimPoolReinvestRewards() public {
        for (uint256 i = 0; i < additionalRewardTokens.length; i++) {
            _updateRewardToken(
                additionalRewardTokens[i].token,
                i,
                additionalRewardTokens[i].emissionRatePerYear,
                additionalRewardTokens[i].endTime
            );
        }
        _depositWithInitialAccounts();

        _sendIncentivesToVault(additionalRewardTokens);


        vm.warp(block.timestamp + 20 days);


        uint256[] memory prevBalances = new uint256[](metadata.rewardTokens.length);
        for (uint256 j = 0; j < metadata.rewardTokens.length; j++) {
            prevBalances[j] = metadata.rewardTokens[j].balanceOf(address(vault));
        }

        for (uint256 i = 0; i < accounts.length; i++) {
            for (uint256 j = 0; j < metadata.rewardTokens.length; j++) {
                assertEq(0, metadata.rewardTokens[j].balanceOf(accounts[i].account));
            }
            vm.prank(accounts[i].account);
            VaultRewarderLib(address(vault)).claimAccountRewards(accounts[i].account);
            for (uint256 j = 0; j < metadata.rewardTokens.length; j++) {
                assertEq(0, metadata.rewardTokens[j].balanceOf(accounts[i].account));
            }
        }

        for (uint256 i = 0; i < accounts.length; i++) {
            for (uint256 j = 0; j < metadata.rewardTokens.length; j++) {
                assertEq(0, metadata.rewardTokens[j].balanceOf(accounts[i].account));
            }
        }

        for (uint256 j = 0; j < metadata.rewardTokens.length; j++) {
            uint256 currentBal = metadata.rewardTokens[j].balanceOf(address(vault));
            assertGt(currentBal, prevBalances[j], "2");
        }

    }

    function test_claimReward_ShouldNotClaimPoolReinvestRewardsEvenIfNoSecondaryIncentives() public {
        _depositWithInitialAccounts();

        vm.warp(block.timestamp + 20 days);

        uint256[] memory prevBalances = new uint256[](metadata.rewardTokens.length);
        for (uint256 j = 0; j < metadata.rewardTokens.length; j++) {
            prevBalances[j] = metadata.rewardTokens[j].balanceOf(address(vault));
        }

        for (uint256 i = 0; i < accounts.length; i++) {
            for (uint256 j = 0; j < metadata.rewardTokens.length; j++) {
                assertEq(0, metadata.rewardTokens[j].balanceOf(accounts[i].account));
            }
            vm.prank(accounts[i].account);
            VaultRewarderLib(address(vault)).claimAccountRewards(accounts[i].account);
            for (uint256 j = 0; j < metadata.rewardTokens.length; j++) {
                assertEq(0, metadata.rewardTokens[j].balanceOf(accounts[i].account));
            }
        }

        for (uint256 i = 0; i < accounts.length; i++) {
            for (uint256 j = 0; j < metadata.rewardTokens.length; j++) {
                assertEq(0, metadata.rewardTokens[j].balanceOf(accounts[i].account));
            }
        }

        for (uint256 j = 0; j < metadata.rewardTokens.length; j++) {
            uint256 currentBal = metadata.rewardTokens[j].balanceOf(address(vault));
            assertGt(currentBal, prevBalances[j], "2");
        }

    }

    function test_claimReward_SecondClaimAtTheSameTimestampShouldClaimZero(uint8 additionalRewTokNum) public {
        additionalRewTokNum = uint8(bound(additionalRewTokNum, 0, metadata.rewardTokens.length));
        AdditionalRewardToken[] memory additionalRewTokens = new AdditionalRewardToken[](additionalRewTokNum);

        // set tokens as secondary reward tokens
        for (uint256 i = 0; i < additionalRewTokNum; i++) {
            uint256 decimals = metadata.rewardTokens[i].decimals();
            additionalRewTokens[i] = AdditionalRewardToken(
                address(metadata.rewardTokens[i]),
                uint128(100_000 * (10 ** decimals)),
                uint32(block.timestamp + 30 days),
                decimals
            );
        }
        _addRewardTokensToVault(additionalRewardTokens);

        // deposit funds to vault with some random accounts
        _depositWithInitialAccounts();


        // track previous vault balance for all reward tokens
        uint256[] memory prevVaultBalances = new uint256[](metadata.rewardTokens.length);
        for (uint256 i = 0; i < metadata.rewardTokens.length; i++) {
            prevVaultBalances[i] = metadata.rewardTokens[i].balanceOf(address(vault));
        }

        _sendIncentivesToVault(additionalRewTokens);

        uint256 skipTime = 10 days;
        vm.warp(block.timestamp + skipTime);
        // first claim for each of the accounts
        for (uint256 i = 0; i < accounts.length; i++) {
            vm.prank(accounts[i].account);
            VaultRewarderLib(address(vault)).claimAccountRewards(accounts[i].account);
        }

        // second claim at the same timestamp should claim 0
        for (uint256 i = 0; i < accounts.length; i++) {
            uint256[] memory prevBal = new uint256[](metadata.rewardTokens.length);
            for (uint256 j = 0; j < metadata.rewardTokens.length; j++) {
                prevBal[j] = metadata.rewardTokens[j].balanceOf(accounts[i].account);
            }

            vm.prank(accounts[i].account);
            VaultRewarderLib(address(vault)).claimAccountRewards(accounts[i].account);


            for (uint256 j = 0; j < metadata.rewardTokens.length; j++) {
                uint256 newBal = metadata.rewardTokens[j].balanceOf(accounts[i].account);
                assertEq(newBal, prevBal[j], "3");
            }
        }
    }

    function test_claimReward_ShouldBeAbleToHaveSecondaryIncentivesOnPoolRewardToken(
        uint8 reinvestToClaimNum, uint8 emissionTokNum, uint256[256] memory emissionRatesList, uint256[256] memory incentivePeriodList
    ) public {
        reinvestToClaimNum = uint8(bound(reinvestToClaimNum, 0, metadata.rewardTokens.length));
        emissionTokNum = uint8(bound(emissionTokNum, 0, additionalRewardTokens.length));
        AdditionalRewardToken[] memory claimableTokensInfo = new AdditionalRewardToken[](reinvestToClaimNum + emissionTokNum);
        for (uint256 i = 0; i < reinvestToClaimNum; i++) {
            uint256 decimals = 10 ** metadata.rewardTokens[i].decimals();

            claimableTokensInfo[i] = AdditionalRewardToken(
                address(metadata.rewardTokens[i]),
                uint128(emissionRatesList[i] == 0 ? 0 : bound(emissionRatesList[i], 10_000 * decimals, 100_000 * decimals)),
                uint32(block.timestamp + bound(incentivePeriodList[i], 7 days, 365 days)),
                decimals
            );
        }
        uint256 nextEmpty = reinvestToClaimNum;
        for (uint256 i = 0; i < emissionTokNum; i++) {
            uint256 decimals = 10 ** IERC20(additionalRewardTokens[i].token).decimals();

            claimableTokensInfo[nextEmpty] = AdditionalRewardToken(
                address(additionalRewardTokens[i].token),
                uint128(bound(emissionRatesList[i], 10_000 * decimals, 100_000 * decimals)),
                uint32(block.timestamp + bound(incentivePeriodList[i], 7 days, 365 days)),
                decimals
            );
            nextEmpty++;
        }
        address[] memory reinvestTokens = new address[](metadata.rewardTokens.length - reinvestToClaimNum);
        {
        uint256 counter;
        for (uint256 i = reinvestToClaimNum; i < metadata.rewardTokens.length; i++) {
            reinvestTokens[counter++] = address(metadata.rewardTokens[i]);
        }
        }
        _addRewardTokensToVault(claimableTokensInfo);

        // deposit funds to vault with some random accounts
        uint256 initialVaultShares = _depositWithInitialAccounts();

        // track previous vault balance for all reward tokens
        uint256[] memory prevVaultBalancesForClaimableTokens = new uint256[](claimableTokensInfo.length);
        for (uint256 i = 0; i < claimableTokensInfo.length; i++) {
            prevVaultBalancesForClaimableTokens[i] = IERC20(claimableTokensInfo[i].token).balanceOf(address(vault));
        }
        uint256[] memory prevVaultBalancesForReinvestTokens = new uint256[](reinvestTokens.length);
        for (uint256 i = 0; i < reinvestTokens.length; i++) {
            prevVaultBalancesForReinvestTokens[i] = IERC20(reinvestTokens[i]).balanceOf(address(vault));
        }

        uint256 starTime = block.timestamp;
        uint256[] memory totalIncentives = _sendIncentivesToVault(claimableTokensInfo);

        // warp some time into the future, initiate claim for each user
        uint256[] memory totalClaims = new uint256[](claimableTokensInfo.length);
        uint256 skipTime = 10 days;
        vm.warp(block.timestamp + skipTime);
        for (uint256 i = 0; i < accounts.length; i++) {
            for (uint256 j = 0; j < claimableTokensInfo.length; j++) {
                // since we used some random accounts, none of them should have any balance at this point
                assertEq(IERC20(claimableTokensInfo[j].token).balanceOf(accounts[i].account), 0, "1");
            }

            vm.prank(accounts[i].account);
            VaultRewarderLib(address(vault)).claimAccountRewards(accounts[i].account);


            for (uint256 j = 0; j < claimableTokensInfo.length; j++) {
                uint256 newBal = IERC20(claimableTokensInfo[j].token).balanceOf(accounts[i].account);
                assertGt(newBal, 0, "2");
                totalClaims[j] += newBal;
            }
        }

        for (uint256 i = 0; i < claimableTokensInfo.length; i++) {
            // rewards via emission and via claim for all other accounts we are not tracking in this test
            // totalClaims[i] = allClaims * accountShares / totalVaultSharesAllMaturities
            // allClaims = totalClaims[i] * totalVaultSharesAllMaturities / accountsShares
            // leftForOtherUsersToClaim = allClaims * initialVaultShares / totalVaultSharesAllMaturities
            // = (totalClaims[i] * totalVaultSharesAllMaturities / accountsShares) *  initialVaultShares / totalVaultSharesAllMaturities
            // = totalClaims[i] * initialVaultShares / (totalVaultSharesAllMaturities - initialVaultShares)
            uint256 predictedBalance;
            {
            // uint256 period = skipTime < (claimableTokensInfo[i].endTime - starTime) ? skipTime : (claimableTokensInfo[i].endTime - starTime);
            uint256 period = min(skipTime, (claimableTokensInfo[i].endTime - starTime));
            uint256 incentivesIssued = period * claimableTokensInfo[i].emissionRatePerYear / Constants.YEAR;
            uint256 incentivesLeft = (totalIncentives[i] - incentivesIssued);
            uint256 leftForOtherUsersToClaim = initialVaultShares * totalClaims[i] / (totalVaultSharesAllMaturities - initialVaultShares);
            predictedBalance = (prevVaultBalancesForClaimableTokens[i] + incentivesLeft + leftForOtherUsersToClaim);
            }
            uint256 currentBalance = IERC20(claimableTokensInfo[i].token).balanceOf(address(vault));

            assertLe(prevVaultBalancesForClaimableTokens[i], currentBalance, "4");

            // increase both sides by totalClaims[i] so that relative difference does not appear large
            // when predictedBalance is 0 or both predictedBalance and currentBalance are small numbers
            assertApproxEqRel(
                predictedBalance + totalClaims[i],
                currentBalance + totalClaims[i],
                6e15, // 0.6 % diff
                "5"
            );
        }
        // check do vault have still enough tokens for reinvestment
        for (uint256 i = 0; i < reinvestTokens.length; i++) {
            // in case when reward token is meant to be reinvested we should observe increased
            // balance on vault since first user claim also triggered vault reward claim
            assertLt(prevVaultBalancesForReinvestTokens[i], IERC20(reinvestTokens[i]).balanceOf(address(vault)), "6");
        }
        // account balance of tokens for reinvestment should be zero
        for (uint256 j = 0; j < accounts.length; j++) {
            for (uint256 i = 0; i < reinvestTokens.length; i++) {
                assertEq(IERC20(reinvestTokens[i]).balanceOf(accounts[j].account), 0, "7");
            }
        }
    }

    function test_claimReward_ShouldBeAbleToManuallyClaimPoolRewardTokens(uint8 manualRewTokNum) public {
        manualRewTokNum = uint8(bound(manualRewTokNum, 0, metadata.rewardTokens.length));
        AdditionalRewardToken[] memory manualClaimRewTokens = new AdditionalRewardToken[](manualRewTokNum);

        for (uint256 i = 0; i < manualClaimRewTokens.length; i++) {
            uint256 decimals = metadata.rewardTokens[i].decimals();
            manualClaimRewTokens[i] = AdditionalRewardToken(
                address(metadata.rewardTokens[i]),
                0,
                0,
                decimals
            );
        }

        _addRewardTokensToVault(manualClaimRewTokens);

        uint256 initialVaultShares = _depositWithInitialAccounts();

        // track previous vault balance for all reward tokens
        uint256[] memory prevVaultBalances = new uint256[](metadata.rewardTokens.length);
        for (uint256 i = 0; i < metadata.rewardTokens.length; i++) {
            prevVaultBalances[i] = metadata.rewardTokens[i].balanceOf(address(vault));
        }

        uint256[] memory totalRewardsReceived = new uint256[](manualClaimRewTokens.length);
        uint256 skipTime = 30 days;
        vm.warp(block.timestamp + skipTime);
        for (uint256 i = 0; i < accounts.length; i++) {
            for (uint256 j = 0; j < metadata.rewardTokens.length; j++) {
                uint256 prevBal = metadata.rewardTokens[j].balanceOf(accounts[i].account);
                assertEq(prevBal, 0, "1");
            }

            vm.prank(accounts[i].account);
            VaultRewarderLib(address(vault)).claimAccountRewards(accounts[i].account);


            for (uint256 j = 0; j < manualRewTokNum; j++) {
                uint256 newBal = IERC20(manualClaimRewTokens[j].token).balanceOf(accounts[i].account);
                totalRewardsReceived[j] += newBal;
                totalRewardsPerAccount[i].push(newBal);
                assertGt(newBal, 0, "2");
            }

            // accounts should not receive anything for each reward tokens meant to be reinvested
            for (uint256 j = manualRewTokNum; j < metadata.rewardTokens.length; j++) {
                uint256 newBal = metadata.rewardTokens[j].balanceOf(accounts[i].account);
                assertEq(newBal, 0, "3");
            }
        }

        // check all accounts received fair share of reward
        for (uint256 i = 0; i < accounts.length; i++) {
            for (uint256 j = 0; j < manualRewTokNum; j++) {
                assertApproxEqAbs(
                    totalRewardsReceived[j] * accounts[i].initialShare / (totalAccountsShare),
                    totalRewardsPerAccount[i][j],
                    2,
                    "4"
                );
            }
        }

        // check do vault have still enough tokens for reinvestment
        for (uint256 i = 0; i < metadata.rewardTokens.length; i++) {
            uint256 currentVaultBalance = metadata.rewardTokens[i].balanceOf(address(vault));
            if (i < manualRewTokNum) {
                uint256 accountsShares = (totalVaultSharesAllMaturities - initialVaultShares);
                // rewards via claim for all other accounts we are not tracking in this test
                uint256 leftForOtherUsersToClaim = initialVaultShares * totalRewardsReceived[i] / accountsShares;
                assertApproxEqRel(
                    (prevVaultBalances[i] + leftForOtherUsersToClaim) / 1e6,
                    currentVaultBalance / 1e6,
                    1e12, // 0.0001 % diff
                    "5"
                );
            } else {
                // in case when reward token is meant to be reinvested we should observe increased
                // balance on vault since first user claim also triggered vault reward claim
                assertLt(prevVaultBalances[i], currentVaultBalance, "6");
            }
        }
    }

    function test_claimReward_UpdateRewardTokenShouldBeAbleToReduceOrIncreaseEmission() public {
        vm.skip(_shouldSkip("test_claimReward_UpdateRewardTokenShouldBeAbleToReduceOrIncreaseEmission"));
        _provideLiquidity();
        uint256 PERCENT_DIFF = 3e15; // 1e18 is 100%
        for (uint256 i = 0; i < additionalRewardTokens.length; i++) {
            _updateRewardToken(
                additionalRewardTokens[i].token,
                i,
                additionalRewardTokens[i].emissionRatePerYear,
                additionalRewardTokens[i].endTime
            );
        }
        _depositWithInitialAccounts();

        uint256 rewardNum = additionalRewardTokens.length;

        _sendIncentivesToVault(additionalRewardTokens);

        uint256[] memory totalClaimed = new uint256[](rewardNum);
        uint256 lastClaimTimestamp = block.timestamp;
        uint256 skipTime = 1 days;
        vm.warp(block.timestamp + skipTime);

        _claimAndAssertNewBalEqExpectedReward(additionalRewardTokens, totalClaimed, lastClaimTimestamp, PERCENT_DIFF);
        lastClaimTimestamp = block.timestamp;

        // turn off emissions
        for (uint256 i = 0; i < additionalRewardTokens.length; i++) {
            _updateRewardToken(additionalRewardTokens[i].token, i, 0, 0);
        }

        skipTime = 2 weeks;
        vm.warp(block.timestamp + skipTime);

        _claimAndAssertNewBal(AssertType.Eq, additionalRewardTokens);

        lastClaimTimestamp = block.timestamp;

        // turn on emissions again
        for (uint256 i = 0; i < additionalRewardTokens.length; i++) {
             additionalRewardTokens[i].emissionRatePerYear = uint128(52 * 10_000 * additionalRewardTokens[i].decimals);
             additionalRewardTokens[i].endTime = uint32(block.timestamp + 1 weeks);
            _updateRewardToken(
                additionalRewardTokens[i].token,
                i,
                additionalRewardTokens[i].emissionRatePerYear,
                additionalRewardTokens[i].endTime
            );
        }
        _sendIncentivesToVault(additionalRewardTokens);

        skipTime = 20 weeks;
        vm.warp(block.timestamp + skipTime);

        _claimAndAssertNewBalEqExpectedReward(additionalRewardTokens, totalClaimed, lastClaimTimestamp, PERCENT_DIFF);
    }

    function test_claimReward_WithChangingForceClaimAfter() public {
        vm.skip(_shouldSkip("test_claimReward_WithChangingForceClaimAfter"));
        uint forceClaimAfter = 10 minutes;
        _setForceClaimAfter(forceClaimAfter);

        AdditionalRewardToken[] memory poolRewardTokens = new AdditionalRewardToken[](metadata.rewardTokens.length);

        for (uint256 i = 0; i < poolRewardTokens.length; i++) {
            uint256 decimals = metadata.rewardTokens[i].decimals();
            poolRewardTokens[i] = AdditionalRewardToken(
                address(metadata.rewardTokens[i]),
                0,
                0,
                decimals
            );
        }

        _addRewardTokensToVault(poolRewardTokens);

        _depositWithInitialAccounts();

        vm.warp(block.timestamp + 2 minutes);
        // should not claim anything after 30 days, since forceClaimAfter is 20 weeks and nobody triggered direct claim
        _claimAndAssertNewBal(AssertType.Eq, poolRewardTokens);

        // trigger direct claim
        VaultRewarderLib(address(vault)).claimRewardTokens();

        // now accounts should have something to claim
        _claimAndAssertNewBal(AssertType.Gt, poolRewardTokens);

        vm.warp(block.timestamp + forceClaimAfter + 1);

        // vault rewards claim should be triggered by the first account that tries to claim
        _claimAndAssertNewBal(AssertType.Gt, poolRewardTokens);

        vm.warp(block.timestamp + 10 minutes);
        // claim should be 0 since force claim will not be triggered
        _claimAndAssertNewBal(AssertType.Eq, poolRewardTokens);

        _setForceClaimAfter(0);

        _claimAndAssertNewBal(AssertType.Gt, poolRewardTokens);
    }
}