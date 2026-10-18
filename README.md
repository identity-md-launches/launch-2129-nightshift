# NIGHTSHIFT (SHIFT)

A fixed-supply ERC-20 token for an IdentityMD custom-token launch on Ethereum (chain id 1).

| Property        | Value                                                      |
|-----------------|------------------------------------------------------------|
| Solidity name   | `ShiftToken` (`src/ShiftToken.sol`)                        |
| `name()`        | `NIGHTSHIFT`                                               |
| `symbol()`      | `SHIFT`                                                    |
| `decimals()`    | `18`                                                       |
| Total supply    | 1,000,000,000 SHIFT = `1000000000000000000000000000` minor units |
| Minting         | Once, the whole supply, to `msg.sender`, in the constructor |
| Constructor     | No arguments, no external calls                            |
| Admin functions | None                                                       |

## Behaviour

`ShiftToken` is a self-contained EIP-20 implementation with no dependencies beyond the compiler.

- **Transfers** move exactly the amount requested. There is no fee, burn, tax, reflection or
  blocklist on any path, so every launch flow (factory to distributor, distributor to claimant,
  factory to pool, pool to trader and back) arrives whole.
- **Supply** is a compile-time constant. `totalSupply()` is `pure` and nothing in the contract can
  raise or lower it. There is no `mint`, `burn` or `burnFrom`.
- **Allowances** follow the common convention: `approve` overwrites, `transferFrom` deducts, and an
  allowance of `type(uint256).max` is unlimited and never decremented. A decremented allowance
  emits `Approval` with the new value.
- **Errors** are custom: `ZeroAddress()`, `InsufficientBalance(from, balance, needed)` and
  `InsufficientAllowance(spender, allowance, needed)`. Transfers and approvals to the zero address
  revert; zero-amount transfers succeed and emit.
- **No privileged surface.** There is no owner, pauser, minter, upgrade path, `receive` or
  `fallback`. The runtime contains no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`.

## Deployment parameters

The constructor takes no arguments, so the launch manifest's `constructorArgs` for the token is
empty. The manifest's `token.totalSupply` is `1000000000000000000000000000` and
`token.decimals` is `18`.

On the launch, IdentityMD's `ProjectFactory` deploys the token through `launchCustom`, so the
factory is `msg.sender` of the constructor and receives the whole supply. The factory then pays it
out according to the launch terms: the swarm's ten percent to the launch's MerkleDistributor, the
pool share to the Uniswap v4 pool and the remainder to the requester's economics address. The token
needs no exemptions for any of these because it has no transfer rules.

Launch values decided by the launch itself (not open questions, recorded here for completeness):

- Chain: Ethereum, chain id 1.
- Pair: IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` (18 decimals).
- Pool fee `12500` (1.25%), tick spacing `60`.
- Economics: `poolBps` 8000, `initialMarketCapWei` `20000000000000000000000` IMD,
  `remainderTo` `0x612a9bb008e16ef2d24f41dae9fc661831d93367`.

The manifest (`launch.json`) is written by the manifest step after this work is accepted; it is
intentionally absent from this repository.

### Manual deployment (reviewers only)

`script/DeployShiftToken.s.sol` exposes `deploy()`, which tests call directly, and `run()`, which
wraps it in a broadcast for a reviewer who wants to reproduce the deployment on a local fork.
It reads no environment variables itself. The launch does not use this script.

```sh
forge script script/DeployShiftToken.s.sol --rpc-url <url> --broadcast
```

## After launch

Nothing. The token has no owner-settable values, no setters and no operational duties. Once the
factory has distributed the supply, the contract runs itself forever.

## Assumptions

- The requester asked for a plain token: name, symbol and supply only. No burn, tax, vesting,
  governance or permit was requested, so none is included. Adding one later means a new token.
- The deployer is whoever calls the constructor. On the launch that is the factory; in tests it is
  a probe contract or the test address. The token has no notion of an "owner" after that.
- The EIP-20 approve race (changing a non-zero allowance to another non-zero value) is left as the
  standard describes. Front ends that care should set the allowance to zero first.
- Decimals are fixed at 18 and `totalSupply()` is a constant, so the manifest values above cannot
  drift from the deployed code.

## Operational responsibilities

- **Requester**: the remainder of the supply lands at the economics address. Keep that key safe;
  the contract cannot recover or freeze tokens for anyone.
- **Holders**: tokens sent to the wrong address are gone. The contract refuses transfers to the
  zero address but cannot detect other mistakes.
- **IdentityMD**: deploys through the factory and seeds the pool. No post-launch action on the
  token is required or possible.
- **Explorer verification** after launch is the deployer's open item. Source is compiled with
  `solc 0.8.26`, optimizer on at 200 runs, `evm_version = "cancun"`, `bytecode_hash = "none"` and
  `cbor_metadata = false`, so a verifier must use the same settings.

## Security notes

Checked against the eth-security reference used by this task:

- No reentrancy surface: the contract makes no external calls.
- No oracle, no swapping, no proxy, no delegatecall, no signatures.
- Every state change emits an event (`Transfer`, `Approval`).
- Input validation: zero-address recipients and spenders are rejected; balance and allowance
  bounds are enforced with explicit errors.
- Arithmetic: the only `unchecked` blocks are guarded by a prior comparison and by the fixed supply
  bound.

Tools run: `forge build`, `forge test` (including fuzz tests with the verifier's seed) and
`forge fmt --check`. Slither and Mythril were not available on this machine and did not run.
Passing tests are not an audit; a contract that will hold or route other people's funds should get
an independent adversarial review before release.

## Layout

```
foundry.toml                 compiler pin (0.8.26), bytecode_hash = "none", no ffi, no fs access
remappings.txt               forge-std/ -> lib/forge-std/src/
src/ShiftToken.sol           the token
script/DeployShiftToken.s.sol  reviewable deploy helper
test/ShiftToken.t.sol        unit and fuzz tests for the token
test/DeployShiftToken.t.sol  tests for the deploy helper
lib/forge-std/               vendored forge-std v1.11.0 (plain files, MIT/Apache-2.0)
```

## Running the checks

```sh
forge build
forge test
forge fmt --check
```
