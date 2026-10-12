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
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

/// @title Fast Launch by El Trueque
/// @author El Trueque
/// @notice Direct v4 position owned by this immutable, non-upgradeable splitter.
/// No arbitrary calls, LP transfer, approval, principal withdrawal or liquidity decrease.
contract FastLaunchSplitter is ReentrancyGuard {
    using SafeERC20 for IERC20;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    IPoolManager public immutable manager;
    address public immutable factory;
    address public immutable token;
    address public immutable quote;
    address public immutable creator;
    address public immutable feeRecipient;
    address public immutable treasury;
    int24 public immutable lower;
    int24 public immutable upper;
    uint128 public immutable liquidity;
    PoolKey private _key;
    bool public seeded;
    uint8 private callbackMode;
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
        IPoolManager m,
        PoolKey memory k,
        address t,
        address q,
        address c,
        address tr,
        int24 lo,
        int24 hi,
        uint128 l,
        address f,
        address recipient
    ) {
        manager = m;
        _key = k;
        token = t;
        quote = q;
        creator = c;
        feeRecipient = recipient;
        treasury = tr;
        lower = lo;
        upper = hi;
        liquidity = l;
        factory = f;
    }

    function poolKey() external view returns (PoolKey memory) {
        return _key;
    }

    function seed() external nonReentrant {
        if (msg.sender != factory) revert Unauthorized();
        if (seeded) revert AlreadySeeded();
        seeded = true;
        callbackMode = 1;
        manager.unlock("");
        callbackMode = 0;
        lockedDust = IERC20(token).balanceOf(address(this));
        emit LiquidityLocked(liquidity, 1_000_000 ether - lockedDust, lockedDust);
    }

    function collectFees() external nonReentrant returns (uint256 quoteFees, uint256 tokenFees) {
        if (!seeded) revert Unauthorized();
        callbackMode = 2;
        (quoteFees, tokenFees) = abi.decode(manager.unlock(""), (uint256, uint256));
        callbackMode = 0;
        if (tokenFees > 0) {
            deadTokens += tokenFees;
            IERC20(token).safeTransfer(DEAD, tokenFees);
        }
        uint256 total = quoteFees + feeRemainder;
        uint256 half = total / 2;
        feeRemainder = total % 2;
        credit[feeRecipient] += half;
        credit[treasury] += half;
        _attempt(feeRecipient);
        if (feeRecipient != treasury) _attempt(treasury);
        emit FeesCollected(quoteFees, tokenFees);
    }

    function unlockCallback(bytes calldata) external returns (bytes memory) {
        if (msg.sender != address(manager) || callbackMode == 0) revert Unauthorized();
        (BalanceDelta delta,) = manager.modifyLiquidity(
            _key,
            ModifyLiquidityParams(lower, upper, callbackMode == 1 ? int256(uint256(liquidity)) : int256(0), bytes32(0)),
            ""
        );
        bool first = token < quote;
        int128 td = first ? delta.amount0() : delta.amount1();
        int128 qd = first ? delta.amount1() : delta.amount0();
        if (callbackMode == 1) {
            if (td >= 0 || qd != 0) revert InvalidDelta();
            manager.sync(Currency.wrap(token));
            IERC20(token).safeTransfer(address(manager), uint256(-int256(td)));
            manager.settle();
            return "";
        }
        if (td < 0 || qd < 0) revert InvalidDelta();
        if (td > 0) manager.take(Currency.wrap(token), address(this), uint128(td));
        if (qd > 0) manager.take(Currency.wrap(quote), address(this), uint128(qd));
        return abi.encode(uint256(uint128(qd)), uint256(uint128(td)));
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
        if (msg.sender != address(manager)) revert Unauthorized();
    }
}
