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

    Fast Launch by El Trueque  ·  https://el-trueque.com  ·  v1.0.0
    Lanzamientos directos en Uniswap v4 con liquidez bloqueada para siempre.
    X: https://x.com/ElTruequeMarket
    Telegram: https://t.me/eltruequeapp
    Instagram: https://instagram.com/eltruequeapp
*/

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {FastLaunchRegistry} from "./FastLaunchRegistry.sol";

/// @title Fast Launch by El Trueque
/// @author El Trueque
contract FastLaunchHook {
    using PoolIdLibrary for PoolKey;
    uint160 public constant FLAGS = 0x30c0;
    address public immutable manager;
    address public immutable factory;

    struct Guard {
        uint64 launchedAt;
        uint128 bought;
        uint128 cap;
        uint160 initialPrice;
        uint32 durationSeconds;
        uint24 initialFee;
        uint24 normalFee;
        bool token0;
        bool initialized;
    }
    mapping(PoolId => Guard) public guards;
    error Unauthorized();
    error InvalidHookAddress();
    error InvalidPool();
    error OpeningBuyLimit();

    constructor(address manager_, address factory_) {
        if (uint160(address(this)) & 0x3fff != FLAGS) revert InvalidHookAddress();
        manager = manager_;
        factory = factory_;
    }

    function register(PoolKey calldata key, bool token0, uint160 price, FastLaunchRegistry.Opening calldata o)
        external
    {
        if (msg.sender != factory) revert Unauthorized();
        PoolId id = key.toId();
        if (guards[id].initialPrice != 0 || address(key.hooks) != address(this) || key.fee != 0x800000) revert InvalidPool();
        guards[id] = Guard(
            0,
            0,
            uint128(uint256(1_000_000 ether) * o.openingBuyBps / 10000),
            price,
            o.durationSeconds,
            o.initialFee,
            o.normalFee,
            token0,
            false
        );
    }

    function beforeInitialize(address sender, PoolKey calldata key, uint160 price) external returns (bytes4) {
        if (msg.sender != manager || sender != factory) revert Unauthorized();
        Guard storage g = guards[key.toId()];
        if (g.initialPrice != price || g.initialized) revert InvalidPool();
        g.initialized = true;
        g.launchedAt = uint64(block.timestamp);
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(address sender, PoolKey calldata key, uint160, int24) external returns (bytes4) {
        if (msg.sender != manager || sender != factory) revert Unauthorized();
        Guard memory g = guards[key.toId()];
        if (!g.initialized) revert InvalidPool();
        // Only initialization can set the base fee. The opening override is computed, not administrated.
        IPoolManager(manager).updateDynamicLPFee(key, g.normalFee);
        return IHooks.afterInitialize.selector;
    }

    function feeAt(PoolId id) public view returns (uint24) {
        Guard memory g = guards[id];
        if (!g.initialized) revert InvalidPool();
        uint256 age = block.timestamp - g.launchedAt;
        return age >= g.durationSeconds
            ? g.normalFee
            : uint24(g.initialFee - (uint256(g.initialFee - g.normalFee) * age / g.durationSeconds));
    }

    function beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        external
        view
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (msg.sender != manager) revert Unauthorized();
        Guard memory g = guards[key.toId()];
        if (!g.initialized) revert InvalidPool();
        // PoolManager authenticates sender. The factory only swaps in its atomic create callback.
        // No tx.origin, recipient whitelist or user-supplied hookData can grant this exemption.
        uint24 fee = sender == factory || params.zeroForOne == g.token0 ? g.normalFee : feeAt(key.toId());
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | 0x400000);
    }

    function afterSwap(address, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata)
        external
        returns (bytes4, int128)
    {
        if (msg.sender != manager) revert Unauthorized();
        Guard storage g = guards[key.toId()];
        if (!g.initialized) revert InvalidPool();
        if (block.timestamp - g.launchedAt < g.durationSeconds && params.zeroForOne != g.token0) {
            int128 output = g.token0 ? delta.amount0() : delta.amount1();
            if (output < 0) revert InvalidPool();
            uint256 used = g.bought;
            used += uint128(output);
            if (used > g.cap) revert OpeningBuyLimit();
            g.bought = uint128(used);
        }
        return (IHooks.afterSwap.selector, 0);
    }
}
