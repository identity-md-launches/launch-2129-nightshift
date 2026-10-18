// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ShiftToken} from "../src/ShiftToken.sol";

/// @notice Thin deployer so `msg.sender` of the constructor is a contract, as it is on the launch
///         (the ProjectFactory deploys the token and must receive the whole supply).
contract FactoryProbe {
    function deploy() external returns (ShiftToken) {
        return new ShiftToken();
    }

    function send(ShiftToken token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract ShiftTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    FactoryProbe internal factory;
    ShiftToken internal token;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public {
        factory = new FactoryProbe();
        token = factory.deploy();
    }

    // ------------------------------------------------------------------
    // Metadata and supply
    // ------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "NIGHTSHIFT");
        assertEq(token.symbol(), "SHIFT");
        assertEq(token.decimals(), 18);
        assertEq(token.NAME(), "NIGHTSHIFT");
        assertEq(token.SYMBOL(), "SHIFT");
        assertEq(token.DECIMALS(), 18);
    }

    function test_supplyIsOneBillionWithEighteenDecimals() public view {
        assertEq(SUPPLY, 1_000_000_000 * 10 ** 18);
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_constructorEmitsMintTransfer() public {
        FactoryProbe other = new FactoryProbe();
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), address(other), SUPPLY);
        other.deploy();
    }

    function test_deployerIsWhoeverCallsTheConstructor() public {
        vm.prank(alice);
        ShiftToken fresh = new ShiftToken();
        assertEq(fresh.balanceOf(alice), SUPPLY);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    function test_constructorMakesNoExternalCalls() public {
        // A deployment on an empty chain must succeed: nothing to call out to.
        vm.recordLogs();
        ShiftToken fresh = new ShiftToken();
        assertEq(fresh.totalSupply(), SUPPLY);
        assertEq(vm.getRecordedLogs().length, 1, "only the mint Transfer should be emitted");
    }

    // ------------------------------------------------------------------
    // transfer
    // ------------------------------------------------------------------

    function test_transferMovesExactAmount() public {
        assertTrue(factory.send(token, alice, 1_000 ether));
        assertEq(token.balanceOf(alice), 1_000 ether);
        assertEq(token.balanceOf(address(factory)), SUPPLY - 1_000 ether);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, 400 ether);
        assertTrue(token.transfer(bob, 400 ether));

        assertEq(token.balanceOf(alice), 600 ether);
        assertEq(token.balanceOf(bob), 400 ether);
        assertEq(token.totalSupply(), SUPPLY, "transfers never change the supply");
    }

    function test_transferWholeBalance() public {
        factory.send(token, alice, 5 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 5 ether));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 5 ether);
    }

    function test_transferWholeSupplyFromDeployer() public {
        assertTrue(factory.send(token, alice, SUPPLY));
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_transferZeroAmountSucceedsAndEmits() public {
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, 0);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        factory.send(token, alice, 10 ether);
        vm.prank(alice);
        assertTrue(token.transfer(alice, 10 ether));
        assertEq(token.balanceOf(alice), 10 ether);
    }

    function test_transferRevertsOnInsufficientBalance() public {
        factory.send(token, alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ShiftToken.InsufficientBalance.selector, alice, 1 ether, 1 ether + 1));
        token.transfer(bob, 1 ether + 1);
        assertEq(token.balanceOf(alice), 1 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferRevertsFromEmptyAccount() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ShiftToken.InsufficientBalance.selector, bob, 0, 1));
        token.transfer(alice, 1);
    }

    function test_transferRevertsToZeroAddress() public {
        factory.send(token, alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(ShiftToken.ZeroAddress.selector);
        token.transfer(address(0), 1 ether);
        assertEq(token.balanceOf(alice), 1 ether);
    }

    function test_transferRevertsToZeroAddressEvenForZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(ShiftToken.ZeroAddress.selector);
        token.transfer(address(0), 0);
    }

    // ------------------------------------------------------------------
    // approve / allowance / transferFrom
    // ------------------------------------------------------------------

    function test_approveSetsAllowanceAndEmits() public {
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Approval(alice, bob, 7 ether);
        assertTrue(token.approve(bob, 7 ether));
        assertEq(token.allowance(alice, bob), 7 ether);
        assertEq(token.allowance(bob, alice), 0, "allowance is directional");
    }

    function test_approveOverwritesNotAccumulates() public {
        vm.startPrank(alice);
        token.approve(bob, 7 ether);
        token.approve(bob, 3 ether);
        vm.stopPrank();
        assertEq(token.allowance(alice, bob), 3 ether);
    }

    function test_approveZeroClearsAllowance() public {
        vm.startPrank(alice);
        token.approve(bob, 7 ether);
        token.approve(bob, 0);
        vm.stopPrank();
        assertEq(token.allowance(alice, bob), 0);
    }

    function test_approveRevertsForZeroSpender() public {
        vm.prank(alice);
        vm.expectRevert(ShiftToken.ZeroAddress.selector);
        token.approve(address(0), 1);
    }

    function test_approveDoesNotRequireBalance() public {
        vm.prank(carol);
        assertTrue(token.approve(bob, SUPPLY));
        assertEq(token.allowance(carol, bob), SUPPLY);
    }

    function test_transferFromSpendsAllowanceAndMovesTokens() public {
        factory.send(token, alice, 100 ether);
        vm.prank(alice);
        token.approve(bob, 60 ether);

        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Approval(alice, bob, 20 ether);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, carol, 40 ether);
        assertTrue(token.transferFrom(alice, carol, 40 ether));

        assertEq(token.balanceOf(alice), 60 ether);
        assertEq(token.balanceOf(carol), 40 ether);
        assertEq(token.balanceOf(bob), 0, "the spender receives nothing");
        assertEq(token.allowance(alice, bob), 20 ether);
    }

    function test_transferFromToSpender() public {
        factory.send(token, alice, 10 ether);
        vm.prank(alice);
        token.approve(bob, 10 ether);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, bob, 10 ether));
        assertEq(token.balanceOf(bob), 10 ether);
        assertEq(token.allowance(alice, bob), 0);
    }

    function test_transferFromUnlimitedAllowanceIsNotReduced() public {
        factory.send(token, alice, 100 ether);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);

        vm.prank(bob);
        token.transferFrom(alice, carol, 30 ether);
        assertEq(token.allowance(alice, bob), type(uint256).max);
        assertEq(token.balanceOf(carol), 30 ether);
    }

    function test_transferFromRevertsWithoutAllowance() public {
        factory.send(token, alice, 100 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ShiftToken.InsufficientAllowance.selector, bob, 0, 1));
        token.transferFrom(alice, carol, 1);
        assertEq(token.balanceOf(alice), 100 ether);
    }

    function test_transferFromRevertsAboveAllowance() public {
        factory.send(token, alice, 100 ether);
        vm.prank(alice);
        token.approve(bob, 10 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ShiftToken.InsufficientAllowance.selector, bob, 10 ether, 10 ether + 1));
        token.transferFrom(alice, carol, 10 ether + 1);
        assertEq(token.allowance(alice, bob), 10 ether, "a failed spend leaves the allowance intact");
    }

    function test_transferFromRevertsWhenOwnerBalanceTooLow() public {
        factory.send(token, alice, 5 ether);
        vm.prank(alice);
        token.approve(bob, 10 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ShiftToken.InsufficientBalance.selector, alice, 5 ether, 6 ether));
        token.transferFrom(alice, carol, 6 ether);
        assertEq(token.allowance(alice, bob), 10 ether, "the whole call reverts, allowance included");
    }

    function test_transferFromRevertsToZeroAddress() public {
        factory.send(token, alice, 5 ether);
        vm.prank(alice);
        token.approve(bob, 5 ether);
        vm.prank(bob);
        vm.expectRevert(ShiftToken.ZeroAddress.selector);
        token.transferFrom(alice, address(0), 5 ether);
    }

    function test_transferFromCannotMoveTheDeployersSupplyWithoutApproval() public {
        // The address a token would most plausibly trust still cannot move anyone else's balance.
        vm.prank(address(factory));
        vm.expectRevert(abi.encodeWithSelector(ShiftToken.InsufficientAllowance.selector, address(factory), 0, 1));
        token.transferFrom(alice, address(factory), 1);
    }

    // ------------------------------------------------------------------
    // No privileged surface
    // ------------------------------------------------------------------

    function test_noMintPauseBlocklistOrOwnerFunctionsExist() public {
        string[18] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "owner()",
            "transferOwnership(address)",
            "renounceOwnership()",
            "pause()",
            "unpause()",
            "blacklist(address)",
            "setBlacklist(address,bool)",
            "freeze(address)",
            "setTransfersEnabled(bool)",
            "upgradeTo(address)",
            "initialize(address)",
            "setMinter(address)",
            "seize(address)"
        ];
        address[2] memory callers = [address(factory), address(0xBEEF)];
        for (uint256 c; c < callers.length; ++c) {
            for (uint256 i; i < signatures.length; ++i) {
                bytes memory data = abi.encodeWithSignature(signatures[i], address(0xBEEF), type(uint128).max);
                vm.prank(callers[c]);
                (bool ok,) = address(token).call(data);
                assertFalse(ok, signatures[i]);
            }
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0xBEEF)), 0);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
    }

    function test_contractRejectsEther() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok, "no receive or fallback");
        assertEq(address(token).balance, 0);
    }

    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "runtime exceeds EIP-170");
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xF4, "DELEGATECALL");
            assertTrue(op != 0xF2, "CALLCODE");
            assertTrue(op != 0xFF, "SELFDESTRUCT");
        }
    }

    // ------------------------------------------------------------------
    // Fuzz: conservation and bounds
    // ------------------------------------------------------------------

    function testFuzz_transferConservesSupply(address to, uint256 seed, uint256 amount) public {
        vm.assume(to != address(0) && to != address(factory));
        seed = bound(seed, 0, SUPPLY);
        amount = bound(amount, 0, seed);
        factory.send(token, alice, seed);
        vm.assume(to != alice);

        vm.prank(alice);
        assertTrue(token.transfer(to, amount));

        assertEq(token.balanceOf(alice), seed - amount);
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(alice) + token.balanceOf(to) + token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY - 1);
        amount = bound(amount, held + 1, SUPPLY);
        factory.send(token, alice, held);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ShiftToken.InsufficientBalance.selector, alice, held, amount));
        token.transfer(bob, amount);
    }

    function testFuzz_allowanceAccounting(uint256 allowanceAmount, uint256 spend) public {
        allowanceAmount = bound(allowanceAmount, 0, SUPPLY);
        spend = bound(spend, 0, allowanceAmount);
        factory.send(token, alice, SUPPLY);
        vm.prank(alice);
        token.approve(bob, allowanceAmount);

        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, spend));

        uint256 expectedLeft = allowanceAmount == type(uint256).max ? type(uint256).max : allowanceAmount - spend;
        assertEq(token.allowance(alice, bob), expectedLeft);
        assertEq(token.balanceOf(carol), spend);
        assertEq(token.balanceOf(alice), SUPPLY - spend);
    }

    function testFuzz_transferFromAboveAllowanceReverts(uint256 allowanceAmount, uint256 spend) public {
        allowanceAmount = bound(allowanceAmount, 0, SUPPLY - 1);
        spend = bound(spend, allowanceAmount + 1, SUPPLY);
        factory.send(token, alice, SUPPLY);
        vm.prank(alice);
        token.approve(bob, allowanceAmount);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ShiftToken.InsufficientAllowance.selector, bob, allowanceAmount, spend));
        token.transferFrom(alice, carol, spend);
    }

    function testFuzz_supplyNeverChanges(address a, address b, uint256 x, uint256 y) public {
        vm.assume(a != address(0) && b != address(0));
        x = bound(x, 0, SUPPLY);
        y = bound(y, 0, x);
        factory.send(token, a, x);
        vm.prank(a);
        token.transfer(b, y);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
