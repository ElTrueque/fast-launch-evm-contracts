// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*
    ███████╗██╗
    ██╔════╝██║
    █████╗  ██║
    ██╔══╝  ██║
    ███████╗███████╗
    ╚══════╝╚══════╝

    ████████╗██████╗ ██╗   ██╗███████╗ ██████╗ ██╗   ██╗███████╗
    ╚══██╔══╝██╔══██╗██║   ██║██╔════╝██╔═══██╗██║   ██║██╔════╝
       ██║   ██████╔╝██║   ██║█████╗  ██║   ██║██║   ██║█████╗
       ██║   ██╔══██╗██║   ██║██╔══╝  ██║▄▄ ██║██║   ██║██╔══╝
       ██║   ██║  ██║╚██████╔╝███████╗╚██████╔╝╚██████╔╝███████╗
       ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚══════╝ ╚══▀▀═╝  ╚═════╝ ╚══════╝

    ███████╗ █████╗ ███████╗████████╗
    ██╔════╝██╔══██╗██╔════╝╚══██╔══╝
    █████╗  ███████║███████╗   ██║
    ██╔══╝  ██╔══██║╚════██║   ██║
    ██║     ██║  ██║███████║   ██║
    ╚═╝     ╚═╝  ╚═╝╚══════╝   ╚═╝

    ██╗      █████╗ ██╗   ██╗███╗   ██╗ ██████╗██╗  ██╗
    ██║     ██╔══██╗██║   ██║████╗  ██║██╔════╝██║  ██║
    ██║     ███████║██║   ██║██╔██╗ ██║██║     ███████║
    ██║     ██╔══██║██║   ██║██║╚██╗██║██║     ██╔══██║
    ███████╗██║  ██║╚██████╔╝██║ ╚████║╚██████╗██║  ██║
    ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝╚═╝  ╚═╝

    Fast Launch by El Trueque  ·  https://el-trueque.com  ·  v2.0.0
    Lanzamientos directos en Uniswap v4 con liquidez bloqueada para siempre.
    v2: pools estándar con comisión fija; el hook solo protege la creación.
    X: https://x.com/ElTruequeMarket
    Telegram: https://t.me/eltruequeapp
    Instagram: https://instagram.com/eltruequeapp
*/

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IFastLaunchFeeCredit {
    function claimFees(address recipient) external;
}

/// @title Fast Launch by El Trueque
/// @author El Trueque
/// @notice Holds the holder half of quote fees. No owner, withdrawal or signer replacement.
/// @dev TRUST BOUNDARY: the immutable snapshot signer attests the historical balances,
/// exclusions and proportional calculation. This contract verifies commitments/signatures,
/// NOT historical ERC-20 balances. Incorrect signed lists can misallocate these fee funds.
contract FastLaunchHolderRewards is ReentrancyGuard {
    using SafeERC20 for IERC20;
    uint256 public constant BATCH_SIZE = 100;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address public immutable token;
    address public immutable quote;
    address public immutable manager;
    address public immutable factory;
    address public immutable snapshotSigner;
    address private immutable binder;
    address public splitter;
    uint256 public nextEpoch;
    uint256 public reserved;
    uint256 public lastSnapshot;
    mapping(address => uint256) public credit;

    struct Plan {
        uint256 epoch;
        uint256 snapshotBlock;
        bytes32 snapshotBlockHash;
        uint256 amount;
        uint256 eligibleTokens;
        bytes32 listHash;
        bytes32[] batchHashes;
        string cid;
        uint256 deadline;
    }

    struct Epoch {
        uint256 budget;
        uint256 accounted;
        uint256 batches;
        uint256 paid;
        bytes32 listHash;
    }
    mapping(uint256 => Epoch) public epochs;
    mapping(uint256 => mapping(uint256 => bytes32)) public batchHash;
    mapping(uint256 => mapping(uint256 => bool)) public batchPaid;
    mapping(uint256 => mapping(address => bool)) public recipientPaid;
    error Unauthorized();
    error InvalidPlan();
    error InvalidBatch();
    error PaymentFailed();
    event EpochCommitted(
        uint256 indexed epoch,
        uint256 snapshotBlock,
        bytes32 snapshotBlockHash,
        uint256 amount,
        uint256 eligibleTokens,
        bytes32 listHash,
        string cid
    );
    event BatchPaid(uint256 indexed epoch, uint256 indexed batch, uint256 allocated);
    event EpochCompleted(uint256 indexed epoch, uint256 allocated, uint256 roundingRemainder);
    event HolderPaid(address indexed holder, uint256 amount);
    event PaymentDeferred(address indexed holder, uint256 amount);

    constructor(address t, address q, address m, address f, address signer) {
        if (signer == address(0)) revert InvalidPlan();
        token = t;
        quote = q;
        manager = m;
        factory = f;
        snapshotSigner = signer;
        binder = msg.sender;
    }

    function bindSplitter(address s) external {
        if (msg.sender != binder || splitter != address(0) || s.code.length == 0) revert Unauthorized();
        splitter = s;
    }

    function balance() public view returns (uint256) {
        return quote == address(0) ? address(this).balance : IERC20(quote).balanceOf(address(this));
    }

    function available() external view returns (uint256) {
        return balance() - reserved;
    }

    function excluded(address a) public view returns (bool) {
        return a == address(0) || a == DEAD || a == manager || a == splitter || a == factory || a == address(this);
    }

    /// @notice EIP-191 signMessage of this 32-byte digest. Bound to chain, vault, epoch and full public plan.
    function planDigest(Plan calldata p) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("FastLaunchHolderRewards.v1"),
                block.chainid,
                address(this),
                token,
                quote,
                p.epoch,
                p.snapshotBlock,
                p.snapshotBlockHash,
                p.amount,
                p.eligibleTokens,
                p.listHash,
                keccak256(abi.encode(p.batchHashes)),
                keccak256(bytes(p.cid)),
                p.deadline
            )
        );
    }

    function commitEpoch(Plan calldata p, bytes calldata signature) external nonReentrant {
        uint256 head = block.number;
        if (block.chainid == 4663) {
            (bool ok, bytes memory data) = address(100).staticcall(abi.encodeWithSignature("arbBlockNumber()"));
            if (!ok || data.length != 32) revert InvalidPlan();
            head = abi.decode(data, (uint256));
        }
        if (
            p.epoch != nextEpoch || p.snapshotBlock <= lastSnapshot || p.snapshotBlock >= head
                || p.snapshotBlockHash == 0 || p.amount == 0 || p.amount > balance() - reserved || p.eligibleTokens == 0
                || p.eligibleTokens > 1_000_000 ether || p.listHash == 0 || p.batchHashes.length == 0
                || p.batchHashes.length > 500 || bytes(p.cid).length < 46 || bytes(p.cid).length > 96
                || p.deadline < block.timestamp
        ) revert InvalidPlan();
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", planDigest(p)));
        if (ECDSA.recover(digest, signature) != snapshotSigner) revert Unauthorized();
        for (uint256 i; i < p.batchHashes.length; i++) {
            if (p.batchHashes[i] == 0) revert InvalidPlan();
            batchHash[p.epoch][i] = p.batchHashes[i];
        }
        epochs[p.epoch] = Epoch(p.amount, 0, p.batchHashes.length, 0, p.listHash);
        reserved += p.amount;
        lastSnapshot = p.snapshotBlock;
        nextEpoch++;
        emit EpochCommitted(
            p.epoch, p.snapshotBlock, p.snapshotBlockHash, p.amount, p.eligibleTokens, p.listHash, p.cid
        );
    }

    function payBatch(uint256 epoch, uint256 index, address[] calldata recipients, uint256[] calldata amounts)
        external
        nonReentrant
    {
        Epoch storage e = epochs[epoch];
        uint256 n = recipients.length;
        if (
            index >= e.batches || batchPaid[epoch][index] || n == 0 || n > BATCH_SIZE || n != amounts.length
                || (index + 1 < e.batches && n != BATCH_SIZE)
                || batchHash[epoch][index] != keccak256(abi.encode(epoch, index, recipients, amounts))
        ) revert InvalidBatch();
        batchPaid[epoch][index] = true;
        uint256 sum;
        for (uint256 i; i < n; i++) {
            address h = recipients[i];
            uint256 a = amounts[i];
            if (excluded(h) || recipientPaid[epoch][h] || a == 0) revert InvalidBatch();
            recipientPaid[epoch][h] = true;
            sum += a;
            credit[h] += a;
        }
        e.accounted += sum;
        if (e.accounted > e.budget) revert InvalidBatch();
        e.paid++;
        for (uint256 i; i < n; i++) {
            _attempt(recipients[i]);
        }
        emit BatchPaid(epoch, index, sum);
        if (e.paid == e.batches) {
            uint256 remainder = e.budget - e.accounted;
            reserved -= remainder;
            emit EpochCompleted(epoch, e.accounted, remainder);
        }
    }

    function _attempt(address h) private {
        uint256 n = credit[h];
        if (n == 0) return;
        credit[h] = 0;
        reserved -= n;
        try this.pay{gas: 100000}(h, n) {
            emit HolderPaid(h, n);
        } catch {
            credit[h] = n;
            reserved += n;
            emit PaymentDeferred(h, n);
        }
    }

    /// @notice Anyone can retry a failed payment; its destination can never be changed.
    function retry(address holder) external nonReentrant {
        _attempt(holder);
    }

    function pay(address h, uint256 n) external {
        if (msg.sender != address(this)) revert Unauthorized();
        if (quote == address(0)) {
            (bool ok,) = payable(h).call{value: n}("");
            if (!ok) revert PaymentFailed();
        } else {
            IERC20(quote).safeTransfer(h, n);
        }
    }

    function pullDeferredFees() external nonReentrant {
        IFastLaunchFeeCredit(splitter).claimFees(address(this));
    }

    receive() external payable {
        if (msg.sender != splitter) revert Unauthorized();
    }
}
