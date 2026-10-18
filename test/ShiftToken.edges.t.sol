// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {ShiftToken} from "../src/ShiftToken.sol";

/// @notice Edge cases the main suite does not pin: zero amounts through `transferFrom`, the
///         boundary allowance values, self-approval, revert atomicity and event exactness.
contract ShiftTokenEdgesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    ShiftToken internal token;
    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public {
        vm.prank(deployer);
        token = new ShiftToken();
        vm.prank(deployer);
        token.transfer(alice, 100 ether);
    }

    function test_transferOneWei() public {
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(alice), 100 ether - 1);
    }

    function test_transferFromZeroAmountWithoutAllowanceSucceeds() public {
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Approval(alice, bob, 0);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, carol, 0);
        assertTrue(token.transferFrom(alice, carol, 0));
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.allowance(alice, bob), 0);
    }

    function test_transferFromExactAllowanceLeavesZero() public {
        vm.prank(alice);
        token.approve(bob, 40 ether);
        vm.prank(bob);
        token.transferFrom(alice, carol, 40 ether);
        assertEq(token.allowance(alice, bob), 0);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ShiftToken.InsufficientAllowance.selector, bob, 0, 1));
        token.transferFrom(alice, carol, 1);
    }

    function test_allowanceOneBelowMaxIsFiniteAndDecrements() public {
        uint256 almost = type(uint256).max - 1;
        vm.prank(alice);
        token.approve(bob, almost);
        vm.prank(bob);
        token.transferFrom(alice, carol, 1 ether);
        assertEq(token.allowance(alice, bob), almost - 1 ether);
    }

    function test_unlimitedAllowanceEmitsNoApprovalOnSpend() public {
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.recordLogs();
        vm.prank(bob);
        token.transferFrom(alice, carol, 1 ether);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "only the Transfer is emitted");
        assertEq(logs[0].topics[0], Transfer.selector);
    }

    function test_unlimitedAllowanceStillBoundByBalance() public {
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(ShiftToken.InsufficientBalance.selector, alice, 100 ether, 100 ether + 1)
        );
        token.transferFrom(alice, carol, 100 ether + 1);
        assertEq(token.allowance(alice, bob), type(uint256).max);
    }

    function test_transferFromSelfRequiresOwnAllowance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ShiftToken.InsufficientAllowance.selector, alice, 0, 1 ether));
        token.transferFrom(alice, bob, 1 ether);

        vm.startPrank(alice);
        token.approve(alice, 1 ether);
        assertTrue(token.transferFrom(alice, bob, 1 ether));
        vm.stopPrank();
        assertEq(token.balanceOf(bob), 1 ether);
        assertEq(token.allowance(alice, alice), 0);
    }

    function test_transferFromOwnerToOwnerKeepsBalanceButSpendsAllowance() public {
        vm.prank(alice);
        token.approve(bob, 10 ether);
        vm.prank(bob);
        token.transferFrom(alice, alice, 10 ether);
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.allowance(alice, bob), 0);
    }

    function test_transferFromZeroAddressOwnerReverts() public {
        // Nobody can hold an allowance from address(0), and address(0) holds nothing.
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ShiftToken.InsufficientAllowance.selector, bob, 0, 1));
        token.transferFrom(address(0), bob, 1);
    }

    function test_transferFromToZeroAddressRevertsAndKeepsAllowance() public {
        vm.prank(alice);
        token.approve(bob, 5 ether);
        vm.prank(bob);
        vm.expectRevert(ShiftToken.ZeroAddress.selector);
        token.transferFrom(alice, address(0), 1 ether);
        assertEq(token.allowance(alice, bob), 5 ether);
        assertEq(token.balanceOf(alice), 100 ether);
    }

    function test_approveMaxThenZero() public {
        vm.startPrank(alice);
        token.approve(bob, type(uint256).max);
        token.approve(bob, 0);
        vm.stopPrank();
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ShiftToken.InsufficientAllowance.selector, bob, 0, 1));
        token.transferFrom(alice, carol, 1);
    }

    function test_returnDataIsAbiEncodedTrue() public {
        vm.prank(alice);
        (bool ok, bytes memory ret) = address(token).call(abi.encodeCall(ShiftToken.transfer, (bob, 1)));
        assertTrue(ok);
        assertEq(ret, abi.encode(true));

        vm.prank(alice);
        (ok, ret) = address(token).call(abi.encodeCall(ShiftToken.approve, (bob, 1)));
        assertTrue(ok);
        assertEq(ret, abi.encode(true));

        vm.prank(bob);
        (ok, ret) = address(token).call(abi.encodeCall(ShiftToken.transferFrom, (alice, carol, 1)));
        assertTrue(ok);
        assertEq(ret, abi.encode(true));
    }

    function test_unknownSelectorReverts() public {
        (bool ok,) = address(token).call(hex"deadbeef");
        assertFalse(ok);
        (ok,) = address(token).call("");
        assertFalse(ok);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveSetsExactly(address owner, address spender, uint256 first, uint256 second) public {
        vm.assume(spender != address(0));
        vm.startPrank(owner);
        token.approve(spender, first);
        token.approve(spender, second);
        vm.stopPrank();
        assertEq(token.allowance(owner, spender), second);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_failedTransferChangesNothing(uint256 amount) public {
        amount = bound(amount, 100 ether + 1, type(uint256).max);
        vm.prank(alice);
        token.approve(bob, 7 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ShiftToken.InsufficientBalance.selector, alice, 100 ether, amount));
        token.transfer(carol, amount);
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.balanceOf(carol), 0);
        assertEq(token.allowance(alice, bob), 7 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromMovesExactlyAndSpendsExactly(uint256 allowed, uint256 amount) public {
        allowed = bound(allowed, 0, type(uint256).max - 1);
        amount = bound(amount, 0, allowed < 100 ether ? allowed : 100 ether);
        vm.prank(alice);
        token.approve(bob, allowed);
        vm.prank(bob);
        token.transferFrom(alice, carol, amount);
        assertEq(token.allowance(alice, bob), allowed - amount);
        assertEq(token.balanceOf(carol), amount);
        assertEq(token.balanceOf(alice), 100 ether - amount);
        assertEq(token.balanceOf(bob), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromBothShortReportsAllowance(uint256 allowed, uint256 amount) public {
        allowed = bound(allowed, 0, 50 ether);
        amount = bound(amount, 100 ether + 1, type(uint256).max - 1);
        vm.prank(alice);
        token.approve(bob, allowed);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ShiftToken.InsufficientAllowance.selector, bob, allowed, amount));
        token.transferFrom(alice, carol, amount);
    }
}
