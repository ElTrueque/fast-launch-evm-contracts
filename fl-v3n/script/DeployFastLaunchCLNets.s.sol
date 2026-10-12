// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import {FastLaunchRegistry} from "../src/FastLaunchRegistry.sol";
import {FastLaunchFactoryCL} from "../src/cl/FastLaunchFactoryCL.sol";
import {FastLaunchNetQuotes} from "./FastLaunchNetQuotes.sol";

/// Supply-choice Fast Launch on classic concentrated-liquidity pools: PancakeSwap v3 (BNB Chain) and Project X
/// (HyperEVM). Same DEX parameters as the production CL factories 0x3989AE8f...5407 and 0xE2265674...5558,
/// a new registry with the Crypto kind, and every pair from FastLaunchNetQuotes.
contract DeployFastLaunchCLNets is Script {
    address payable constant TREASURY = payable(0x1Dd6785c96328FB2d8D312c01611a828E6B208E3);
    address constant HOLDERS_SIGNER = 0x785C44F1428Bf1366127aE68fdD8D0fA22D524ef;

    function network()
        public
        view
        returns (string memory name, FastLaunchFactoryCL.Dex memory d, FastLaunchNetQuotes.Entry[] memory e)
    {
        if (block.chainid == 56) {
            return (
                "PancakeSwap v3",
                FastLaunchFactoryCL.Dex(
                    0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865,
                    0x41ff9AA7e16B8B1a8a8dc4f0eFacd93D02d071c9,
                    0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c,
                    0x6ce8eb472fa82df5469c6ab6d485f17c3ad13c8cd7af59b3d4a8026c5ce0f7e2
                ),
                FastLaunchNetQuotes.bnb()
            );
        }
        if (block.chainid == 999) {
            return (
                "Project X",
                FastLaunchFactoryCL.Dex(
                    0xFf7B3e8C00e57ea31477c32A5B52a58Eea47b072,
                    0xFf7B3e8C00e57ea31477c32A5B52a58Eea47b072,
                    0x5555555555555555555555555555555555555555,
                    0x7ef2b01a451cbf890790278981756372e549443802ece149dc0b592cbc114ee9
                ),
                FastLaunchNetQuotes.hyperevm()
            );
        }
        revert("Solo BNB Chain (PancakeSwap v3) e HyperEVM (Project X)");
    }

    function run() external {
        (string memory name, FastLaunchFactoryCL.Dex memory d, FastLaunchNetQuotes.Entry[] memory e) = network();
        vm.startBroadcast();
        FastLaunchRegistry r = new FastLaunchRegistry(
            msg.sender, TREASURY, FastLaunchRegistry.Opening(1, 10000, 10000, 10000, 10000, 200), 0
        );
        FastLaunchFactoryCL f = new FastLaunchFactoryCL(r, d, name);
        r.configureSnapshotSigner(HOLDERS_SIGNER);
        for (uint256 i; i < e.length; i++) r.configureQuote(e[i].currency, e[i].q, e[i].source);
        vm.stopBroadcast();
        console2.log("DEX", name);
        console2.log("REGISTRO", address(r));
        console2.log("FABRICA", address(f));
        console2.log("COMPONENTES", address(f.components()));
        console2.log("PARES", e.length);
    }
}
