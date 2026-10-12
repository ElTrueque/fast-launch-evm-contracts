// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {FastLaunchRegistry} from "../src/FastLaunchRegistry.sol";
import {FastLaunchFactoryETH} from "../src/FastLaunchFactoryETH.sol";
import {FastLaunchNetQuotes} from "./FastLaunchNetQuotes.sol";

/// Supply-choice Fast Launch (no hook) on Arc and Robinhood Chain (Uniswap v4): new registry with the Crypto kind
/// and 6/8/18-decimal quotes, the unchanged FastLaunchFactoryETH source, and every pair from FastLaunchNetQuotes.
contract DeployFastLaunchNets is Script {
    address payable constant TREASURY = payable(0x1Dd6785c96328FB2d8D312c01611a828E6B208E3);
    address constant HOLDERS_SIGNER = 0x785C44F1428Bf1366127aE68fdD8D0fA22D524ef;

    function network() public view returns (string memory name, address manager, FastLaunchNetQuotes.Entry[] memory e) {
        if (block.chainid == 5042) return ("Arc", 0x8366a39CC670B4001A1121B8F6A443A643e40951, FastLaunchNetQuotes.arc());
        if (block.chainid == 4663) return ("Robinhood Chain", 0x8366a39CC670B4001A1121B8F6A443A643e40951, FastLaunchNetQuotes.robinhood());
        revert("Solo Arc y Robinhood Chain (Uniswap v4); BNB e HyperEVM usan DeployFastLaunchCLNets");
    }

    function run() external {
        (string memory name, address manager, FastLaunchNetQuotes.Entry[] memory e) = network();
        require(manager.code.length > 0, "PoolManager sin codigo");
        vm.startBroadcast();
        FastLaunchRegistry r = new FastLaunchRegistry(
            msg.sender, TREASURY, FastLaunchRegistry.Opening(1, 10000, 10000, 10000, 10000, 200), 0
        );
        FastLaunchFactoryETH f = new FastLaunchFactoryETH(IPoolManager(manager), r);
        r.configureSnapshotSigner(HOLDERS_SIGNER);
        for (uint256 i; i < e.length; i++) r.configureQuote(e[i].currency, e[i].q, e[i].source);
        vm.stopBroadcast();
        console2.log("RED", name);
        console2.log("REGISTRO", address(r));
        console2.log("FABRICA", address(f));
        console2.log("COMPONENTES", address(f.components()));
        console2.log("PARES", e.length);
    }
}
