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
    v2 CL: pools clásicas de PancakeSwap v3 / Project X, liquidez bloqueada para siempre.
    X: https://x.com/ElTruequeMarket
    Telegram: https://t.me/eltruequeapp
    Instagram: https://instagram.com/eltruequeapp
*/

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IV3Pool, IWrappedNative} from "./IV3.sol";

/// @title Fast Launch by El Trueque · liquidity locker for v3 style pools
/// @author El Trueque
/// @notice Owns one single-sided position directly in the pool, forever. Same economics as the v1 splitter:
/// pair-side fees split 50/50 between the fee recipient (creator or holder vault) and the treasury,
/// token-side fees sent to the dead address. No arbitrary calls, liquidity decrease, transfer or withdrawal.
contract FastLaunchLockerCL is ReentrancyGuard {
    using SafeERC20 for IERC20;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address public immutable pool;
    address public immutable factory;
    address public immutable token;
    /// @notice address(0) for the native coin; fees are then unwrapped and paid in the native coin.
    address public immutable quote;
    /// @notice Asset held by the pool on the pair side: the wrapped native coin or the ERC-20 quote.
    address public immutable poolQuote;
    address public immutable creator;
    address public immutable feeRecipient;
    address public immutable treasury;
    int24 public immutable lower;
    int24 public immutable upper;
    uint128 public immutable liquidity;
    bool public seeded;
    bool private minting;
    uint256 public lockedDust;
    uint256 public deadTokens;
    uint256 public feeRemainder;
    mapping(address => uint256) public credit;
    error Unauthorized();
    error InvalidDelta();
    error AlreadySeeded();
    error PaymentFailed();
    event LiquidityLocked(uint128 liquidity, uint256 tokensInPosition, uint256 permanentlyLockedDust);
    event FeesCollected(uint256 quoteFees, uint256 tokensSentToDead);
    event FeesClaimed(address indexed beneficiary, address indexed recipient, uint256 amount);
    event PaymentDeferred(address indexed beneficiary, uint256 amount);

    constructor(
        address pool_,
        address token_,
        address quote_,
        address poolQuote_,
        address creator_,
        address treasury_,
        int24 lower_,
        int24 upper_,
        uint128 liquidity_,
        address factory_,
        address recipient
    ) {
        pool = pool_;
        token = token_;
        quote = quote_;
        poolQuote = poolQuote_;
        creator = creator_;
        treasury = treasury_;
        lower = lower_;
        upper = upper_;
        liquidity = liquidity_;
        factory = factory_;
        feeRecipient = recipient;
    }

    /// @notice Called once by the factory, after it transfers the whole supply here.
    function seed() external nonReentrant {
        if (msg.sender != factory) revert Unauthorized();
        if (seeded) revert AlreadySeeded();
        seeded = true;
        uint256 received = IERC20(token).balanceOf(address(this));
        minting = true;
        IV3Pool(pool).mint(address(this), lower, upper, liquidity, "");
        minting = false;
        lockedDust = IERC20(token).balanceOf(address(this));
        emit LiquidityLocked(liquidity, received - lockedDust, lockedDust);
    }

    function _mintCallback(uint256 amount0, uint256 amount1) private {
        if (msg.sender != pool || !minting) revert Unauthorized();
        bool first = token < poolQuote;
        // Single-sided position: only the launched token may be owed.
        if ((first ? amount1 : amount0) != 0) revert InvalidDelta();
        IERC20(token).safeTransfer(pool, first ? amount0 : amount1);
    }

    function pancakeV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata) external {
        _mintCallback(amount0, amount1);
    }

    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata) external {
        _mintCallback(amount0, amount1);
    }

    /// @notice Permissionless. Burning zero liquidity only refreshes the fees owed; principal never moves.
    function collectFees() external nonReentrant returns (uint256 quoteFees, uint256 tokenFees) {
        if (!seeded) revert Unauthorized();
        IV3Pool(pool).burn(lower, upper, 0);
        (uint128 c0, uint128 c1) = IV3Pool(pool).collect(address(this), lower, upper, type(uint128).max, type(uint128).max);
        bool first = token < poolQuote;
        tokenFees = first ? c0 : c1;
        quoteFees = first ? c1 : c0;
        if (tokenFees > 0) {
            deadTokens += tokenFees;
            IERC20(token).safeTransfer(DEAD, tokenFees);
        }
        if (quote == address(0) && quoteFees > 0) IWrappedNative(poolQuote).withdraw(quoteFees);
        uint256 total = quoteFees + feeRemainder;
        uint256 half = total / 2;
        feeRemainder = total % 2;
        credit[feeRecipient] += half;
        credit[treasury] += half;
        _attempt(feeRecipient);
        if (feeRecipient != treasury) _attempt(treasury);
        emit FeesCollected(quoteFees, tokenFees);
    }

    function _attempt(address beneficiary) private {
        uint256 n = credit[beneficiary];
        if (n == 0) return;
        credit[beneficiary] = 0;
        try this.pay{gas: 250000}(beneficiary, n) {
            emit FeesClaimed(beneficiary, beneficiary, n);
        } catch {
            credit[beneficiary] = n;
            emit PaymentDeferred(beneficiary, n);
        }
    }

    function pay(address recipient, uint256 n) external {
        if (msg.sender != address(this)) revert Unauthorized();
        if (quote == address(0)) {
            (bool ok,) = payable(recipient).call{value: n}("");
            if (!ok) revert PaymentFailed();
        } else {
            IERC20(quote).safeTransfer(recipient, n);
        }
    }

    function claimFees(address recipient) external nonReentrant {
        if (
            (msg.sender != feeRecipient && msg.sender != treasury) || recipient == address(0)
                || recipient == address(this)
        ) {
            revert Unauthorized();
        }
        uint256 n = credit[msg.sender];
        if (n == 0) revert PaymentFailed();
        credit[msg.sender] = 0;
        this.pay(recipient, n);
        emit FeesClaimed(msg.sender, recipient, n);
    }

    receive() external payable {
        if (msg.sender != poolQuote || quote != address(0)) revert Unauthorized();
    }
}
