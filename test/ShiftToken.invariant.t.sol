// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ShiftToken} from "../src/ShiftToken.sol";

/// @notice Drives the token with random transfers, approvals and spends across a fixed set of
///         actors (the deployer included). It keeps an independent model of every balance and
///         allowance, predicts whether each call should succeed, and checks that a call that
///         reverts leaves all state exactly as it was.
contract ShiftTokenHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    ShiftToken public immutable token;
    address[] public actors;

    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public calls;
    uint256 public successes;
    uint256 public expectedReverts;
    uint256 public ghostMoved;

    constructor(ShiftToken token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
        ghostBalance[actors_[0]] = SUPPLY;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /// @dev Amounts are drawn mostly within the sender's reach, but sometimes beyond it so the
    ///      failure paths are exercised as well.
    function _amount(uint256 raw, uint256 reach) internal pure returns (uint256) {
        uint256 mode = raw % 8;
        if (mode == 0) return 0;
        if (mode == 1) return reach;
        if (mode == 2) return reach + 1 + (raw >> 8) % 1e18;
        if (mode == 3) return type(uint256).max;
        return reach == 0 ? 0 : bound(raw >> 8, 0, reach);
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        calls++;
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = _amount(rawAmount, ghostBalance[from]);
        bool shouldPass = amount <= ghostBalance[from];

        vm.prank(from);
        try token.transfer(to, amount) returns (bool ok) {
            assertTrue(shouldPass, "transfer succeeded above balance");
            assertTrue(ok, "transfer returned false");
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
            ghostMoved += amount;
            successes++;
        } catch (bytes memory reason) {
            assertFalse(shouldPass, "transfer reverted within balance");
            assertEq(
                reason,
                abi.encodeWithSelector(ShiftToken.InsufficientBalance.selector, from, ghostBalance[from], amount)
            );
            expectedReverts++;
        }
    }

    function transferToZero(uint256 fromSeed, uint256 rawAmount) external {
        calls++;
        address from = _actor(fromSeed);
        uint256 amount = _amount(rawAmount, ghostBalance[from]);
        vm.prank(from);
        try token.transfer(address(0), amount) {
            fail("transfer to the zero address succeeded");
        } catch (bytes memory reason) {
            assertEq(reason, abi.encodeWithSelector(ShiftToken.ZeroAddress.selector));
            expectedReverts++;
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount) external {
        calls++;
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 mode = rawAmount % 4;
        uint256 amount = mode == 0 ? 0 : mode == 1 ? type(uint256).max : bound(rawAmount >> 2, 0, SUPPLY * 2);

        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "approve returned false");
        ghostAllowance[owner][spender] = amount;
        successes++;
    }

    function transferFrom(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 rawAmount) external {
        calls++;
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[owner][spender];
        uint256 held = ghostBalance[owner];
        uint256 amount = _amount(rawAmount, allowed < held ? allowed : held);

        bool allowanceOk = allowed == type(uint256).max || amount <= allowed;
        bool balanceOk = amount <= held;

        vm.prank(spender);
        try token.transferFrom(owner, to, amount) returns (bool ok) {
            assertTrue(allowanceOk && balanceOk, "transferFrom succeeded without cover");
            assertTrue(ok, "transferFrom returned false");
            if (allowed != type(uint256).max) ghostAllowance[owner][spender] = allowed - amount;
            ghostBalance[owner] -= amount;
            ghostBalance[to] += amount;
            ghostMoved += amount;
            successes++;
        } catch (bytes memory reason) {
            assertFalse(allowanceOk && balanceOk, "transferFrom reverted with cover");
            // The allowance is checked first, so it names the error when both fall short.
            bytes memory expected = !allowanceOk
                ? abi.encodeWithSelector(ShiftToken.InsufficientAllowance.selector, spender, allowed, amount)
                : abi.encodeWithSelector(ShiftToken.InsufficientBalance.selector, owner, held, amount);
            assertEq(reason, expected);
            expectedReverts++;
        }
    }

    /// @dev A stranger outside the actor set tries to spend from an actor. It never has an
    ///      allowance, so anything but a zero-amount call must revert.
    function strangerTransferFrom(uint256 ownerSeed, uint256 rawAmount, address stranger) external {
        calls++;
        for (uint256 i; i < actors.length; ++i) {
            if (stranger == actors[i]) return;
        }
        address owner = _actor(ownerSeed);
        uint256 amount = bound(rawAmount, 1, type(uint256).max);
        vm.prank(stranger);
        try token.transferFrom(owner, stranger, amount) {
            fail("a stranger moved a holder's tokens");
        } catch (bytes memory reason) {
            assertEq(reason, abi.encodeWithSelector(ShiftToken.InsufficientAllowance.selector, stranger, 0, amount));
            expectedReverts++;
        }
    }
}

contract ShiftTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    ShiftToken internal token;
    ShiftTokenHandler internal handler;
    address[] internal actors;

    function setUp() public {
        address deployer = makeAddr("deployer");
        vm.prank(deployer);
        token = new ShiftToken();

        actors.push(deployer);
        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("carol"));
        actors.push(makeAddr("dave"));

        handler = new ShiftTokenHandler(token, actors);

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = ShiftTokenHandler.transfer.selector;
        selectors[1] = ShiftTokenHandler.transferToZero.selector;
        selectors[2] = ShiftTokenHandler.approve.selector;
        selectors[3] = ShiftTokenHandler.transferFrom.selector;
        selectors[4] = ShiftTokenHandler.strangerTransferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_totalSupplyIsFixed() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, SUPPLY, "tokens appeared or vanished");
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_balancesMatchModel() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.ghostBalance(actors[i]));
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_allowancesMatchModel() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.ghostAllowance(actors[i], actors[j]));
            }
        }
    }

    /// @dev Guards against a vacuous campaign: each sequence must actually have driven the token.
    function afterInvariant() public view {
        assertGt(handler.calls(), 0, "the handler was never called");
        assertLe(handler.successes() + handler.expectedReverts(), handler.calls());
    }
}
