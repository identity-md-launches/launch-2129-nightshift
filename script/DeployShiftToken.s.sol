// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {ShiftToken} from "../src/ShiftToken.sol";

/// @title DeployShiftToken
/// @notice Reviewable deployment helper. On the IdentityMD launch the ProjectFactory deploys the
///         token from its bytecode and this script is not used; it exists so a reviewer or a test
///         can reproduce the deployment and check its invariants. `deploy()` has no configuration
///         because the token takes no constructor arguments: whoever calls it receives the supply.
contract DeployShiftToken is Script {
    /// @notice Deploys the token and returns it. Callable directly from tests without broadcast.
    function deploy() public returns (ShiftToken token) {
        token = new ShiftToken();
    }

    /// @notice Broadcast entry point for a manual deployment. Reads nothing from the environment
    ///         beyond what `vm.startBroadcast()` needs (the signer the caller configures).
    function run() external returns (ShiftToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
