// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployShiftToken} from "../script/DeployShiftToken.s.sol";
import {ShiftToken} from "../src/ShiftToken.sol";

/// @notice Exercises the deploy helper's `deploy()` directly, with no broadcast and no environment.
contract DeployShiftTokenTest is Test {
    function test_deployMintsSupplyToTheScriptAsDeployer() public {
        DeployShiftToken deployer = new DeployShiftToken();
        ShiftToken token = deployer.deploy();
        assertEq(token.name(), "NIGHTSHIFT");
        assertEq(token.symbol(), "SHIFT");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        assertEq(token.balanceOf(address(deployer)), 1_000_000_000 ether);
    }

    function test_everyDeploymentIsIndependent() public {
        DeployShiftToken deployer = new DeployShiftToken();
        ShiftToken a = deployer.deploy();
        ShiftToken b = deployer.deploy();
        assertTrue(address(a) != address(b));
        assertEq(a.totalSupply(), b.totalSupply());
        assertEq(a.balanceOf(address(deployer)), 1_000_000_000 ether);
        assertEq(b.balanceOf(address(deployer)), 1_000_000_000 ether);
    }
}
