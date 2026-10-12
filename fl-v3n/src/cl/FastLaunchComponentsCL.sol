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

import {FastLaunchLockerCL} from "./FastLaunchLockerCL.sol";
import {FastLaunchHolderRewardsETH} from "../FastLaunchHolderRewardsETH.sol";

/// @title Fast Launch by El Trueque
/// @author El Trueque
/// @notice Immutable deployment helper keeps the factory below EIP-170. No delegatecall.
contract FastLaunchComponentsCL {
    address public immutable factory;

    constructor() {
        factory = msg.sender;
    }

    function deploy(
        address pool,
        address token,
        address quote,
        address poolQuote,
        address creator,
        address treasury,
        int24 lower,
        int24 upper,
        uint128 liquidity,
        bool toHolders,
        address snapshotSigner
    ) external returns (address locker, address rewards) {
        require(msg.sender == factory);
        // The pool holds the locked supply: passing it as `manager` excludes it from holder snapshots.
        if (toHolders) rewards = address(new FastLaunchHolderRewardsETH(token, quote, pool, factory, snapshotSigner));
        locker = address(
            new FastLaunchLockerCL(
                pool, token, quote, poolQuote, creator, treasury, lower, upper, liquidity, factory, toHolders ? rewards : creator
            )
        );
        if (toHolders) FastLaunchHolderRewardsETH(payable(rewards)).bindSplitter(locker);
    }
}
