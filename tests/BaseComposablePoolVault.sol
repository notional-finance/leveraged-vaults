// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./BaseAcceptanceTest.sol";
import "../contracts/vaults/BalancerComposableAuraVault.sol";
import "../contracts/vaults/balancer/mixins/AuraStakingMixin.sol";
import "../contracts/vaults/common/SingleSidedLPVaultBase.sol";
import "../contracts/proxy/nProxy.sol";
import "../interfaces/balancer/IBalancerPool.sol";
import "../interfaces/notional/ISingleSidedLPStrategyVault.sol";

abstract contract BaseComposablePoolVault is BaseAcceptanceTest {
    uint16 primaryBorrowCurrency;
    bytes32 balancerPoolId;
    IBalancerPool balancerPool;
    StrategyVaultSettings settings;
    IAuraRewardPool rewardPool;
    uint256 numTokens;

    function deployVault() internal override returns (IStrategyVault) {
        balancerPool = IBalancerPool(rewardPool.asset());
        balancerPoolId = balancerPool.getPoolId();

        IStrategyVault impl = new BalancerComposableAuraVault(
            NOTIONAL, AuraVaultDeploymentParams({
                rewardPool: rewardPool,
                baseParams: DeploymentParams({
                    primaryBorrowCurrencyId: primaryBorrowCurrency,
                    balancerPoolId: balancerPoolId,
                    tradingModule: TRADING_MODULE
                })
            })
        );

        bytes memory initData = abi.encodeWithSelector(
            ISingleSidedLPStrategyVault.initialize.selector, InitParams({
                name: "Vault",
                borrowCurrencyId: primaryBorrowCurrency,
                settings: settings
            })
        );

        vm.prank(NOTIONAL.owner());
        nProxy proxy = new nProxy(address(impl), initData);

        // NOTE: no token permissions set, single sided join by default
        return IStrategyVault(address(proxy));
    }

    function getVaultConfig() internal view override returns (VaultConfigParams memory p) {
        p.flags = ENABLED | ONLY_VAULT_DELEVERAGE | ALLOW_ROLL_POSITION;
        p.borrowCurrencyId = primaryBorrowCurrency;
        p.minAccountBorrowSize = 0.01e8;
        p.minCollateralRatioBPS = 5000;
        p.feeRate5BPS = 5;
        p.liquidationRate = 102;
        p.reserveFeeShare = 80;
        p.maxBorrowMarketIndex = 2;
        p.maxDeleverageCollateralRatioBPS = 7000;
        p.maxRequiredAccountCollateralRatioBPS = 10000;
        p.excessCashLiquidationBonus = 100;
    }

    function getDepositParams(
        uint256 /* depositAmount */,
        uint256 /* maturity */
    ) internal pure override returns (bytes memory) {
        DepositParams memory d;
        d.minPoolClaim = 0;

        return abi.encode(d);
    }

    function getRedeemParams(
        uint256 /* vaultShares */,
        uint256 /* maturity */
    ) internal view override returns (bytes memory) {
        RedeemParams memory d;
        d.minAmounts = new uint256[](numTokens);

        return abi.encode(d);
    }

    function checkInvariants() internal override {
        ISingleSidedLPStrategyVault v = ISingleSidedLPStrategyVault(address(vault));
        ISingleSidedLPStrategyVault.SingleSidedLPStrategyVaultInfo memory s = v.getStrategyVaultInfo();

        assertEq(
            totalVaultSharesAllMaturities,
            s.totalVaultShares,
            "Total Vault Shares"
        );

        assertGe(
            s.totalLPTokens,
            s.totalVaultShares * 1e18 / 1e8,
            "Total LP Tokens"
        );

        // below max pool share
    }
}