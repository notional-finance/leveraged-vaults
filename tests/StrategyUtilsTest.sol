pragma solidity 0.8.15;

import "forge-std/Test.sol";
import {StrategyContext} from "../contracts/vaults/balancer/BalancerVaultTypes.sol";
import {StrategyUtils} from "../contracts/vaults/balancer/internal/strategy/StrategyUtils.sol";

contract StrategyUtilsTest is Test {
    function setUp() public {
        
    }
    
    function testConvertStrategyTokensToBPTClaim() public {
        StrategyContext memory context;
        context.totalBPTHeld = 10e18;
        context.vaultState.totalStrategyTokenGlobal = 10e8;
        uint256 strategyTokenAmount = 1e8;
        uint256 bptClaim = StrategyUtils._convertStrategyTokensToBPTClaim(context, strategyTokenAmount);

        assertEq(bptClaim, 2e18);
    }
}