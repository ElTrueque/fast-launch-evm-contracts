// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {FastLaunchRegistry} from "../src/FastLaunchRegistry.sol";
import {FastLaunchFactoryCL} from "../src/cl/FastLaunchFactoryCL.sol";
import {FastLaunchNetQuotes} from "../script/FastLaunchNetQuotes.sol";
import {SimpleV3Router} from "./FastLaunchCL.fork.t.sol";

/// Deploys exactly like script/DeployFastLaunchCLNets.s.sol and exercises every production pair.
abstract contract FastLaunchCLNetBase is Test {
    address payable constant TREASURY = payable(0x1Dd6785c96328FB2d8D312c01611a828E6B208E3);
    address constant HOLDERS_SIGNER = 0x785C44F1428Bf1366127aE68fdD8D0fA22D524ef;
    string constant CID = "bafkreiea44jem3dj4kwh3tef74iwnfwus7lpxsf4qrj2uligiwswqnepji";
    uint256 constant SUPPLY = 1_000_000_000 ether;

    FastLaunchRegistry registry;
    FastLaunchFactoryCL factory;
    SimpleV3Router router;
    address creator = makeAddr("creator");
    address buyer = makeAddr("buyer");

    function _rpc() internal pure virtual returns (string memory);
    function _dex() internal pure virtual returns (FastLaunchFactoryCL.Dex memory, string memory);
    function _entries() internal pure virtual returns (FastLaunchNetQuotes.Entry[] memory);

    function setUp() public {
        vm.createSelectFork(_rpc());
        (FastLaunchFactoryCL.Dex memory d, string memory name) = _dex();
        registry = new FastLaunchRegistry(
            address(this), TREASURY, FastLaunchRegistry.Opening(1, 10000, 10000, 10000, 10000, 200), 0
        );
        factory = new FastLaunchFactoryCL(registry, d, name);
        registry.configureSnapshotSigner(HOLDERS_SIGNER);
        FastLaunchNetQuotes.Entry[] memory e = _entries();
        for (uint256 i; i < e.length; i++) registry.configureQuote(e[i].currency, e[i].q, e[i].source);
        router = new SimpleV3Router();
        vm.deal(creator, 1_000 ether);
        vm.deal(buyer, 1_000 ether);
    }

    function _params(address quote, uint256 valuation, uint256 buy, bytes32 salt, bool holders)
        internal
        view
        returns (FastLaunchFactoryCL.Create memory p, uint256 fee)
    {
        bytes32 digest;
        (,, fee, digest) = registry.configuration(quote);
        p = FastLaunchFactoryCL.Create(
            "Prueba CL", "PCL", CID, quote, valuation, buy, buy > 0 ? 1 : 0, salt, digest, block.timestamp + 600, holders, SUPPLY
        );
    }

    function _entry(string memory symbol) internal pure returns (FastLaunchNetQuotes.Entry memory) {
        FastLaunchNetQuotes.Entry[] memory e = _entries();
        for (uint256 i; i < e.length; i++) if (keccak256(bytes(e[i].symbol)) == keccak256(bytes(symbol))) return e[i];
        revert("moneda no listada");
    }

    function test_registryMatchesTheDeploymentList() public view {
        FastLaunchNetQuotes.Entry[] memory e = _entries();
        for (uint256 i; i < e.length; i++) {
            (FastLaunchRegistry.Quote memory q,,,) = registry.configuration(e[i].currency);
            assertEq(uint8(q.kind), uint8(e[i].q.kind), e[i].symbol);
            assertEq(q.decimals, e[i].q.decimals, e[i].symbol);
            assertEq(q.minValuation, e[i].q.minValuation, e[i].symbol);
            assertEq(q.maxValuation, e[i].q.maxValuation, e[i].symbol);
            assertEq(q.evidenceHash, e[i].q.evidenceHash, e[i].symbol);
            if (e[i].currency != address(0)) assertEq(IERC20Metadata(e[i].currency).decimals(), e[i].q.decimals, e[i].symbol);
        }
    }

    function test_everyPairLaunchesWithChosenSupply() public {
        FastLaunchNetQuotes.Entry[] memory e = _entries();
        for (uint256 i; i < e.length; i++) {
            (FastLaunchFactoryCL.Create memory p, uint256 fee) =
                _params(e[i].currency, uint256(e[i].q.minValuation) * 2, 0, keccak256(abi.encode("p", i)), false);
            vm.prank(creator);
            (address token,) = factory.create{value: fee}(p);
            assertEq(IERC20(token).totalSupply(), SUPPLY, e[i].symbol);
            assertGt(factory.poolAddress(token, e[i].currency).code.length, 0, e[i].symbol);
            (,,,,,,,, uint256 stored) = factory.launches(token);
            assertEq(stored, SUPPLY, e[i].symbol);
        }
    }

    function test_supplyOutsideTheRangeIsRejected() public {
        FastLaunchNetQuotes.Entry[] memory e = _entries();
        (FastLaunchFactoryCL.Create memory p, uint256 fee) =
            _params(e[0].currency, uint256(e[0].q.minValuation) * 2, 0, keccak256("r"), false);
        p.supply = 999 ether;
        vm.prank(creator);
        vm.expectRevert(FastLaunchFactoryCL.InvalidSupply.selector);
        factory.create{value: fee}(p);
        p.supply = 1_000_000_000_000 ether + 1 ether;
        vm.prank(creator);
        vm.expectRevert(FastLaunchFactoryCL.InvalidSupply.selector);
        factory.create{value: fee}(p);
        p.supply = 1_000.5 ether;
        vm.prank(creator);
        vm.expectRevert(FastLaunchFactoryCL.InvalidSupply.selector);
        factory.create{value: fee}(p);
    }

    /// Creator buy with an ERC-20 quote, then a third party buys and sells half back directly on the pool.
    function _launchAndTrade(string memory symbol, uint256 creatorBuy, uint256 amount) internal {
        FastLaunchNetQuotes.Entry memory e = _entry(symbol);
        address quote = e.currency;
        deal(quote, creator, creatorBuy);
        deal(quote, buyer, amount);
        (FastLaunchFactoryCL.Create memory p, uint256 fee) =
            _params(quote, uint256(e.q.minValuation) * 2, creatorBuy, keccak256(abi.encode("t", symbol)), false);
        (uint256 previewed,,,) = factory.previewCreatorBuy(creator, p);
        vm.startPrank(creator);
        IERC20(quote).approve(address(factory), creatorBuy);
        (address token,) = factory.create{value: fee}(p);
        vm.stopPrank();
        assertEq(IERC20(token).balanceOf(creator), previewed, "compra inicial = vista previa");
        assertGt(previewed, 0);
        address pool = factory.poolAddress(token, quote);
        bool quoteIsZero = quote < token;
        vm.startPrank(buyer);
        IERC20(quote).approve(address(router), amount);
        uint256 got = router.swapExactIn(pool, quote, quoteIsZero, amount, buyer);
        assertEq(IERC20(token).balanceOf(buyer), got, "compra de un tercero");
        assertGt(got, 0);
        uint256 half = got / 2;
        uint256 before = IERC20(quote).balanceOf(buyer);
        IERC20(token).approve(address(router), half);
        uint256 back = router.swapExactIn(pool, token, !quoteIsZero, half, buyer);
        vm.stopPrank();
        assertEq(IERC20(quote).balanceOf(buyer) - before, back, "venta devuelve la moneda del par");
        assertGt(back, 0);
    }
}

contract FastLaunchCLNetsBNB is FastLaunchCLNetBase {
    function _rpc() internal pure override returns (string memory) {
        return "https://bsc-rpc.publicnode.com";
    }

    function _dex() internal pure override returns (FastLaunchFactoryCL.Dex memory, string memory) {
        return (
            FastLaunchFactoryCL.Dex(
                0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865,
                0x41ff9AA7e16B8B1a8a8dc4f0eFacd93D02d071c9,
                0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c,
                0x6ce8eb472fa82df5469c6ab6d485f17c3ad13c8cd7af59b3d4a8026c5ce0f7e2
            ),
            "PancakeSwap v3"
        );
    }

    function _entries() internal pure override returns (FastLaunchNetQuotes.Entry[] memory) {
        return FastLaunchNetQuotes.bnb();
    }

    function test_tradeWithAsterBtcbGoldSilverAndUsdt() public {
        _launchAndTrade("ASTER", 100 ether, 50 ether);
        _launchAndTrade("BTCB", 0.001 ether, 0.0005 ether);
        _launchAndTrade("GLDon", 0.2 ether, 0.1 ether);
        _launchAndTrade("SLVon", 2 ether, 1 ether);
        _launchAndTrade("USDT", 20 ether, 10 ether);
    }

    function test_holdersModePairedWithAster() public {
        FastLaunchNetQuotes.Entry memory e = _entry("ASTER");
        assertEq(uint8(e.q.kind), uint8(FastLaunchRegistry.Kind.Crypto), "ASTER es cripto");
        (FastLaunchFactoryCL.Create memory p, uint256 fee) =
            _params(e.currency, uint256(e.q.minValuation) * 2, 0, keccak256("h"), true);
        vm.prank(creator);
        (address token,) = factory.create{value: fee}(p);
        (, address quote,,,,,, address rewards,) = factory.launches(token);
        assertEq(quote, e.currency);
        assertTrue(rewards != address(0), "contrato de holders creado");
    }
}

contract FastLaunchCLNetsHyperEVM is FastLaunchCLNetBase {
    function _rpc() internal pure override returns (string memory) {
        return "https://rpc.hyperliquid.xyz/evm";
    }

    function _dex() internal pure override returns (FastLaunchFactoryCL.Dex memory, string memory) {
        return (
            FastLaunchFactoryCL.Dex(
                0xFf7B3e8C00e57ea31477c32A5B52a58Eea47b072,
                0xFf7B3e8C00e57ea31477c32A5B52a58Eea47b072,
                0x5555555555555555555555555555555555555555,
                0x7ef2b01a451cbf890790278981756372e549443802ece149dc0b592cbc114ee9
            ),
            "Project X"
        );
    }

    function _entries() internal pure override returns (FastLaunchNetQuotes.Entry[] memory) {
        return FastLaunchNetQuotes.hyperevm();
    }

    function test_tradeWithUsdc() public {
        _launchAndTrade("USDC", 20e6, 10e6);
    }
}
