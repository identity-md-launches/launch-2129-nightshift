// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title NIGHTSHIFT (SHIFT)
/// @notice A fixed-supply ERC-20. The whole supply of 1,000,000,000 SHIFT (18 decimals) is minted
///         once, to the deployer, in the constructor. There is no owner, no further minting, no
///         pause, no fee, no blocklist and no upgrade path: after deployment the contract has no
///         privileged functions at all.
/// @dev Self-contained ERC-20 (EIP-20) implementation. The contract name is `ShiftToken`; the
///      token's `name()` is "NIGHTSHIFT" and its `symbol()` is "SHIFT". Allowance semantics follow
///      the common convention: an allowance of `type(uint256).max` is treated as unlimited and is
///      not decremented by `transferFrom`.
contract ShiftToken {
    // ------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------

    /// @notice A transfer or approval named the zero address where a real account is required.
    error ZeroAddress();
    /// @notice The sender's balance is smaller than the amount being moved.
    error InsufficientBalance(address from, uint256 balance, uint256 needed);
    /// @notice The spender's allowance is smaller than the amount being moved.
    error InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    // ------------------------------------------------------------------
    // Events (EIP-20)
    // ------------------------------------------------------------------

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // ------------------------------------------------------------------
    // Constants
    // ------------------------------------------------------------------

    /// @notice Token name, as returned by `name()`.
    string public constant NAME = "NIGHTSHIFT";
    /// @notice Token symbol, as returned by `symbol()`.
    string public constant SYMBOL = "SHIFT";
    /// @notice Number of decimals, as returned by `decimals()`.
    uint8 public constant DECIMALS = 18;
    /// @notice The whole supply in minor units: 1,000,000,000 * 10**18. Minted once; never changes.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(DECIMALS);

    // ------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------

    mapping(address account => uint256) private _balances;
    mapping(address owner => mapping(address spender => uint256)) private _allowances;

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------

    /// @notice Mints the whole supply to the deployer (`msg.sender`). On the IdentityMD launch the
    ///         deployer is the ProjectFactory, which pays the supply out: the swarm's share to the
    ///         MerkleDistributor, the pool share to the Uniswap v4 pool and the remainder to the
    ///         requester. The constructor makes no external calls and takes no arguments.
    constructor() {
        _balances[msg.sender] = TOTAL_SUPPLY;
        emit Transfer(address(0), msg.sender, TOTAL_SUPPLY);
    }

    // ------------------------------------------------------------------
    // Metadata
    // ------------------------------------------------------------------

    /// @notice Returns the token name: "NIGHTSHIFT".
    function name() external pure returns (string memory) {
        return NAME;
    }

    /// @notice Returns the token symbol: "SHIFT".
    function symbol() external pure returns (string memory) {
        return SYMBOL;
    }

    /// @notice Returns the number of decimals: 18.
    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------

    /// @notice The total supply. Fixed at `TOTAL_SUPPLY` for the life of the contract.
    function totalSupply() external pure returns (uint256) {
        return TOTAL_SUPPLY;
    }

    /// @notice The balance of `account`.
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /// @notice The amount `spender` may still move from `owner` through `transferFrom`.
    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    // ------------------------------------------------------------------
    // Mutations
    // ------------------------------------------------------------------

    /// @notice Moves `amount` from the caller to `to`.
    /// @dev Reverts with `ZeroAddress` if `to` is the zero address and with `InsufficientBalance`
    ///      if the caller holds less than `amount`. A zero-amount transfer is valid and emits.
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Sets the caller's allowance for `spender` to exactly `amount`.
    /// @dev Reverts with `ZeroAddress` if `spender` is the zero address. Setting an allowance
    ///      while a non-zero one is outstanding is subject to the well-known EIP-20 race; front
    ///      ends that care should set it to zero first.
    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /// @notice Moves `amount` from `from` to `to` using the caller's allowance.
    /// @dev Reverts with `InsufficientAllowance` if the caller's allowance from `from` is smaller
    ///      than `amount`. An allowance of `type(uint256).max` is unlimited and is not reduced.
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    function _transfer(address from, address to, uint256 amount) private {
        if (to == address(0)) revert ZeroAddress();
        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) revert InsufficientBalance(from, fromBalance, amount);
        unchecked {
            // fromBalance >= amount was just checked, and the sum of all balances is TOTAL_SUPPLY,
            // which fits in uint256, so neither line can wrap.
            _balances[from] = fromBalance - amount;
            _balances[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        if (spender == address(0)) revert ZeroAddress();
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) private {
        uint256 current = _allowances[owner][spender];
        if (current == type(uint256).max) return;
        if (current < amount) revert InsufficientAllowance(spender, current, amount);
        unchecked {
            _allowances[owner][spender] = current - amount;
        }
        emit Approval(owner, spender, current - amount);
    }
}
