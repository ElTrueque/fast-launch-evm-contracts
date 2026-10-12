// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {FastLaunchFactoryETH} from "../src/FastLaunchFactoryETH.sol";
import {FastLaunchRegistry} from "../src/FastLaunchRegistry.sol";
import {FastLaunchSplitterETH} from "../src/FastLaunchSplitterETH.sol";
import {FastLaunchNetQuotes} from "../script/FastLaunchNetQuotes.sol";

/// Minimal exact-input swapper over the PoolManager, so the tests need no network-specific router.
contract NetSwapper {
    IPoolManager immutable manager;

    constructor(IPoolManager m) {
        manager = m;
    }

    function swap(PoolKey memory key, bool zeroForOne, uint256 amountIn) external payable returns (uint256 out) {
        out = abi.decode(manager.unlock(abi.encode(key, zeroForOne, amountIn, msg.sender)), (uint256));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "solo manager");
        (PoolKey memory key, bool zeroForOne, uint256 amountIn, address user) =
            abi.decode(data, (PoolKey, bool, uint256, address));
        BalanceDelta d = manager.swap(
            key,
            SwapParams(zeroForOne, -int256(amountIn), zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1),
            ""
        );
        int128 a0 = d.amount0();
        int128 a1 = d.amount1();
        _pay(key.currency0, a0, user);
        _pay(key.currency1, a1, user);
        if (a0 > 0) manager.take(key.currency0, user, uint128(a0));
        if (a1 > 0) manager.take(key.currency1, user, uint128(a1));
        return abi.encode(uint256(uint128(zeroForOne ? a1 : a0)));
    }

    function _pay(Currency c, int128 a, address user) private {
        if (a >= 0) return;
        uint256 amount = uint128(-a);
        if (Currency.unwrap(c) == address(0)) {
            manager.settle{value: amount}();
        } else {
            manager.sync(c);
            IERC20(Currency.unwrap(c)).transferFrom(user, address(manager), amount);
            manager.settle();
        }
    }

    receive() external payable {}
}

abstract contract FastLaunchNetBase is Test {
    address payable constant TREASURY = payable(0x1Dd6785c96328FB2d8D312c01611a828E6B208E3);
    address constant HOLDERS_SIGNER = 0x785C44F1428Bf1366127aE68fdD8D0fA22D524ef;
    string constant CID = "bafkreiea44jem3dj4kwh3tef74iwnfwus7lpxsf4qrj2uligiwswqnepji";
    uint256 constant SUPPLY = 1_000_000_000 ether; // a chosen supply, not the old fixed million

    FastLaunchRegistry registry;
    FastLaunchFactoryETH factory;
    NetSwapper swapper;
    address creator = makeAddr("creator");
    address buyer = makeAddr("buyer");

    function _rpc() internal pure virtual returns (string memory);
    function _manager() internal pure virtual returns (address);
    function _entries() internal pure virtual returns (FastLaunchNetQuotes.Entry[] memory);

    function setUp() public {
        vm.createSelectFork(_rpc());
        assertGt(_manager().code.length, 0, "PoolManager con codigo");
        // Same steps as script/DeployFastLaunchNets.s.sol.
        registry = new FastLaunchRegistry(
            address(this), TREASURY, FastLaunchRegistry.Opening(1, 10000, 10000, 10000, 10000, 200), 0
        );
        factory = new FastLaunchFactoryETH(IPoolManager(_manager()), registry);
        registry.configureSnapshotSigner(HOLDERS_SIGNER);
        FastLaunchNetQuotes.Entry[] memory e = _entries();
        for (uint256 i; i < e.length; i++) registry.configureQuote(e[i].currency, e[i].q, e[i].source);
        swapper = new NetSwapper(IPoolManager(_manager()));
        vm.deal(creator, 1_000 ether);
        vm.deal(buyer, 1_000 ether);
    }

    function _params(address quote, uint256 valuation, uint256 buyAmount, bytes32 salt, bool toHolders)
        internal
        view
        returns (FastLaunchFactoryETH.Create memory p, uint256 fee)
    {
        bytes32 digest;
        (,, fee, digest) = registry.configuration(quote);
        p = FastLaunchFactoryETH.Create({
            name: "Prueba Red",
            symbol: "PRED",
            metadataCID: CID,
            quote: quote,
            valuation: valuation,
            buyAmount: buyAmount,
            minTokens: buyAmount > 0 ? 1 : 0,
            salt: salt,
            configurationHash: digest,
            deadline: block.timestamp + 600,
            toHolders: toHolders,
            supply: SUPPLY
        });
    }

    function _entry(string memory symbol) internal pure returns (FastLaunchNetQuotes.Entry memory) {
        FastLaunchNetQuotes.Entry[] memory e = _entries();
        for (uint256 i; i < e.length; i++) {
            if (keccak256(bytes(e[i].symbol)) == keccak256(bytes(symbol))) return e[i];
        }
        revert("moneda no listada");
    }

    /// Creates a launch with a creator buy, then a third party buys with `amount` of the quote and sells half back.
    function _launchAndTrade(string memory symbol, uint256 creatorBuy, uint256 amount) internal {
        FastLaunchNetQuotes.Entry memory e = _entry(symbol);
        address quote = e.currency;
        bool native = quote == address(0);
        if (!native) {
            deal(quote, creator, creatorBuy);
            deal(quote, buyer, amount);
        }
        (FastLaunchFactoryETH.Create memory p, uint256 fee) =
            _params(quote, uint256(e.q.minValuation) * 2, creatorBuy, keccak256(abi.encode("t", symbol)), false);
        (uint256 previewed,,,) = factory.previewCreatorBuy(creator, p);
        vm.startPrank(creator);
        if (!native) IERC20(quote).approve(address(factory), creatorBuy);
        (address token, address s) = factory.create{value: fee + (native ? creatorBuy : 0)}(p);
        vm.stopPrank();
        assertEq(IERC20(token).totalSupply(), SUPPLY, "supply elegido");
        assertEq(IERC20(token).balanceOf(creator), previewed, "compra inicial = vista previa");
        assertGt(previewed, 0, "compra inicial con tokens");
        PoolKey memory k = FastLaunchSplitterETH(payable(s)).poolKey();
        assertEq(address(k.hooks), address(0), "pool sin hook");
        bool quoteIsZero = Currency.unwrap(k.currency0) == quote;
        vm.startPrank(buyer);
        if (!native) IERC20(quote).approve(address(swapper), amount);
        uint256 got = swapper.swap{value: native ? amount : 0}(k, quoteIsZero, amount);
        assertEq(IERC20(token).balanceOf(buyer), got, "compra de un tercero");
        assertGt(got, 0);
        uint256 half = got / 2;
        uint256 before = native ? buyer.balance : IERC20(quote).balanceOf(buyer);
        IERC20(token).approve(address(swapper), half);
        uint256 back = swapper.swap(k, !quoteIsZero, half);
        vm.stopPrank();
        uint256 afterBalance = native ? buyer.balance : IERC20(quote).balanceOf(buyer);
        assertEq(afterBalance - before, back, "venta devuelve la moneda del par");
        assertGt(back, 0);
    }

    // ---------- the deployed list ----------

    function test_registryMatchesTheDeploymentList() public view {
        FastLaunchNetQuotes.Entry[] memory e = _entries();
        for (uint256 i; i < e.length; i++) {
            (FastLaunchRegistry.Quote memory q,,,) = registry.configuration(e[i].currency);
            assertEq(uint8(q.kind), uint8(e[i].q.kind), e[i].symbol);
            assertEq(q.decimals, e[i].q.decimals, e[i].symbol);
            assertEq(q.minValuation, e[i].q.minValuation, e[i].symbol);
            assertEq(q.maxValuation, e[i].q.maxValuation, e[i].symbol);
            assertEq(q.evidenceHash, e[i].q.evidenceHash, e[i].symbol);
            if (e[i].currency != address(0)) {
                assertEq(IERC20Metadata(e[i].currency).decimals(), e[i].q.decimals, e[i].symbol);
            }
        }
    }

    function test_everyPairLaunchesWithChosenSupply() public {
        FastLaunchNetQuotes.Entry[] memory e = _entries();
        for (uint256 i; i < e.length; i++) {
            (FastLaunchFactoryETH.Create memory p, uint256 fee) =
                _params(e[i].currency, uint256(e[i].q.minValuation) * 2, 0, keccak256(abi.encode("p", i)), false);
            vm.prank(creator);
            (address token, address s) = factory.create{value: fee}(p);
            assertEq(IERC20(token).totalSupply(), SUPPLY, e[i].symbol);
            assertEq(address(FastLaunchSplitterETH(payable(s)).poolKey().hooks), address(0), e[i].symbol);
        }
    }

    // ---------- registry rules ----------

    function test_registryRejectsInvalidQuotes() public {
        FastLaunchRegistry.Quote memory q =
            FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Crypto, 18, 1 ether, 10 ether, keccak256("x"));
        // Crypto is never the native currency.
        vm.expectRevert();
        registry.configureQuote(address(0), q, "https://example.org");
        // A Crypto quote needs a contract.
        vm.expectRevert();
        registry.configureQuote(makeAddr("eoa"), q, "https://example.org");
        // Missing evidence, empty source and inverted bounds are refused.
        FastLaunchNetQuotes.Entry[] memory e = _entries();
        address erc20;
        for (uint256 i; i < e.length; i++) if (e[i].currency != address(0)) { erc20 = e[i].currency; break; }
        uint8 d = IERC20Metadata(erc20).decimals();
        vm.expectRevert();
        registry.configureQuote(erc20, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Crypto, d, 1, 2, bytes32(0)), "https://example.org");
        vm.expectRevert();
        registry.configureQuote(erc20, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Crypto, d, 1, 2, keccak256("x")), "");
        vm.expectRevert();
        registry.configureQuote(erc20, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Crypto, d, 2, 1, keccak256("x")), "https://example.org");
        // Declared decimals must match the token.
        vm.expectRevert();
        registry.configureQuote(erc20, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Crypto, d == 18 ? 6 : 18, 1, 2, keccak256("x")), "https://example.org");
        // Only the owner configures.
        vm.prank(buyer);
        vm.expectRevert();
        registry.configureQuote(erc20, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Crypto, d, 1, 2, keccak256("x")), "https://example.org");
    }
}

contract FastLaunchNetsArc is FastLaunchNetBase {
    function _rpc() internal pure override returns (string memory) {
        return "https://rpc.mainnet.arc.io";
    }

    function _manager() internal pure override returns (address) {
        return 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    }

    function _entries() internal pure override returns (FastLaunchNetQuotes.Entry[] memory) {
        return FastLaunchNetQuotes.arc();
    }
}

contract FastLaunchNetsRobinhood is FastLaunchNetBase {
    function _rpc() internal pure override returns (string memory) {
        return "https://rpc.mainnet.chain.robinhood.com";
    }

    function _manager() internal pure override returns (address) {
        return 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    }

    function _entries() internal pure override returns (FastLaunchNetQuotes.Entry[] memory) {
        return FastLaunchNetQuotes.robinhood();
    }

    function test_tradeWithEthAndUsdg() public {
        _launchAndTrade("ETH", 0.01 ether, 0.005 ether);
        _launchAndTrade("USDG", 20e6, 10e6);
    }

    function test_tradeWithGoldAndSilver() public {
        _launchAndTrade("GLD", 0.2 ether, 0.1 ether);
        _launchAndTrade("SLV", 2 ether, 1 ether);
    }
}
