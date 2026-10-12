// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {FastLaunchRegistry} from "../src/FastLaunchRegistry.sol";
import {FastLaunchHolderRewards} from "../src/FastLaunchHolderRewards.sol";
import {FastLaunchFactoryCL} from "../src/cl/FastLaunchFactoryCL.sol";
import {FastLaunchLockerCL} from "../src/cl/FastLaunchLockerCL.sol";
import {IV3Factory, IV3Pool, IWrappedNative} from "../src/cl/IV3.sol";

/// Any router: exact-input swap straight on the pool, paying in the callback.
contract SimpleV3Router {
    address private pool;
    address private payer;
    address private tokenIn;

    function swapExactIn(address pool_, address tokenIn_, bool zeroForOne, uint256 amountIn, address recipient)
        external
        returns (uint256 out)
    {
        pool = pool_;
        payer = msg.sender;
        tokenIn = tokenIn_;
        (int256 a0, int256 a1) = IV3Pool(pool_).swap(
            recipient, zeroForOne, int256(amountIn), zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1, ""
        );
        pool = address(0);
        out = uint256(-(zeroForOne ? a1 : a0));
    }

    function _pay(int256 a0, int256 a1) private {
        require(msg.sender == pool, "pool");
        uint256 owed = uint256(a0 > 0 ? a0 : a1);
        IERC20(tokenIn).transferFrom(payer, msg.sender, owed);
    }

    function uniswapV3SwapCallback(int256 a0, int256 a1, bytes calldata) external { _pay(a0, a1); }
    function pancakeV3SwapCallback(int256 a0, int256 a1, bytes calldata) external { _pay(a0, a1); }
}

interface IPancakeSmartRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

abstract contract FastLaunchCLBase is Test {
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 constant SUPPLY = 1_000_000_000 ether; // supply chosen by the creator, not the old fixed million
    FastLaunchRegistry registry;
    FastLaunchRegistry v1;
    FastLaunchFactoryCL factory;
    address treasury;
    address wrapped;
    address creator = makeAddr("creator");
    address buyer = makeAddr("buyer");
    address attacker = makeAddr("attacker");
    // attacker liquidity callback context
    address private mintToken;

    function _setUp(string memory rpc, address registryV1, FastLaunchFactoryCL.Dex memory d, string memory name) internal {
        vm.createSelectFork(rpc);
        v1 = FastLaunchRegistry(registryV1);
        wrapped = d.wrappedNative;
        treasury = v1.treasury();
        (,, uint24 normalFee,, uint16 creatorBps, int24 spacing) = v1.opening();
        registry = new FastLaunchRegistry(
            address(this), payable(treasury), FastLaunchRegistry.Opening(1, normalFee, normalFee, creatorBps, creatorBps, spacing), v1.creationFee()
        );
        _copy(address(0));
        registry.configureSnapshotSigner(v1.snapshotSigner());
        factory = new FastLaunchFactoryCL(registry, d, name);
        vm.deal(creator, 100 ether);
        vm.deal(buyer, 100 ether);
        vm.deal(attacker, 100 ether);
    }

    function _copy(address c) internal {
        (FastLaunchRegistry.Kind k, uint8 dec, uint128 mn, uint128 mx, bytes32 ev) = v1.quotes(c);
        registry.configureQuote(c, FastLaunchRegistry.Quote(k, dec, mn, mx, ev), "copied from v1 for tests");
    }

    function _params(address quote, uint256 valuation, uint256 buy, bytes32 salt, bool holders)
        internal
        view
        returns (FastLaunchFactoryCL.Create memory p, uint256 fee)
    {
        bytes32 digest;
        (,, fee, digest) = registry.configuration(quote);
        p = FastLaunchFactoryCL.Create(
            "Prueba CL", "PCL", "bafkreiea44jem3dj4kwh3tef74iwnfwus7lpxsf4qrj2uligiwswqnepji", quote, valuation, buy,
            buy > 0 ? 1 : 0, salt, digest, block.timestamp + 600, holders, SUPPLY
        );
    }

    function _nativeValuation() internal view returns (uint256) {
        (,, uint128 mn,,) = registry.quotes(address(0));
        return uint256(mn) * 3;
    }

    function _launchNative(uint256 buy, bytes32 salt, bool holders) internal returns (address token, address locker, address pool) {
        (FastLaunchFactoryCL.Create memory p, uint256 fee) = _params(address(0), _nativeValuation(), buy, salt, holders);
        vm.prank(creator);
        (token, locker) = factory.create{value: fee + buy}(p);
        pool = factory.poolAddress(token, address(0));
    }

    function test_standardPool_creatorBuy_cap() public {
        uint256 buy = 0.01 ether;
        (address token, address locker, address pool) = _launchNative(buy, keccak256("a"), false);
        (,,,, uint256 effective, uint256 creatorTokens,,) = _launch(token);
        assertEq(IV3Factory(factory.dexFactory()).getPool(token, wrapped, 10000), pool, "pool en el DEX oficial, 1%");
        assertTrue(FastLaunchLockerCL(payable(locker)).seeded(), "liquidez bloqueada");
        assertGt(IV3Pool(pool).liquidity(), 0, "liquidez activa tras la compra del creador");
        assertEq(IERC20(token).balanceOf(creator), creatorTokens);
        (,,,, uint16 creatorBps,) = registry.opening();
        assertLe(creatorTokens, SUPPLY * creatorBps / 10000, "tope de compra del creador sobre el supply elegido");
        assertGt(effective, 0);
        assertLt(IERC20(token).balanceOf(locker), 1 ether, "en el locker solo queda polvo");
        console2.log("tokens del creador por 0.01 nativo:", creatorTokens / 1e18);
    }

    function test_creatorBuyCapStillEnforced() public {
        (FastLaunchFactoryCL.Create memory p, uint256 fee) = _params(address(0), _nativeValuation(), 20 ether, keccak256("cap"), false);
        vm.prank(creator);
        vm.expectRevert(FastLaunchFactoryCL.BuyLimit.selector);
        factory.create{value: fee + 20 ether}(p);
    }

    function test_publicBuySell_anyRouter_andFees() public {
        (address token, address locker, address pool) = _launchNative(0.01 ether, keccak256("b"), false);
        SimpleV3Router router = new SimpleV3Router();
        bool wFirst = wrapped < token;
        // compra: 0.2 nativo envuelto, por un router cualquiera
        vm.startPrank(buyer);
        IWrappedNative(wrapped).deposit{value: 0.2 ether}();
        IERC20(wrapped).approve(address(router), 0.2 ether);
        uint256 got = router.swapExactIn(pool, wrapped, wFirst, 0.2 ether, buyer);
        assertEq(IERC20(token).balanceOf(buyer), got);
        // venta de la mitad
        IERC20(token).approve(address(router), got / 2);
        uint256 back = router.swapExactIn(pool, token, !wFirst, got / 2, buyer);
        vm.stopPrank();
        assertGt(back, 0);
        uint256 tb = treasury.balance;
        uint256 cb = creator.balance;
        uint256 db = IERC20(token).balanceOf(DEAD);
        (uint256 qf, uint256 tf) = FastLaunchLockerCL(payable(locker)).collectFees();
        (uint256 lpQuote, uint256 lpToken) = _lpShare(pool, wFirst);
        console2.log("parte de la comision que queda para la liquidez (de 10000), lado par / lado token:", lpQuote, lpToken);
        assertApproxEqRel(qf, (0.01 ether + 0.2 ether) / 100 * lpQuote / 10000, 5e14, "comision de las compras, neta de la parte del protocolo");
        assertApproxEqRel(tf, got / 2 / 100 * lpToken / 10000, 5e14, "comision de la venta en tokens, neta");
        assertEq(treasury.balance - tb, qf / 2, "mitad a la tesoreria, en moneda nativa");
        assertEq(creator.balance - cb, qf / 2, "mitad al creador");
        assertEq(IERC20(token).balanceOf(DEAD) - db, tf, "lado token quemado");
    }

    function test_frontRun_emptyPool_isReset() public {
        (FastLaunchFactoryCL.Create memory p, uint256 fee) = _params(address(0), _nativeValuation(), 0.01 ether, keccak256("c"), false);
        address predicted = factory.predictToken(creator, p);
        vm.startPrank(attacker);
        address pool = IV3Factory(factory.dexFactory()).createPool(predicted, wrapped, 10000);
        IV3Pool(pool).initialize(TickMath.getSqrtPriceAtTick(predicted < wrapped ? int24(-600000) : int24(600000)));
        vm.stopPrank();
        vm.prank(creator);
        vm.expectEmit(true, false, false, false, address(factory));
        emit FastLaunchFactoryCL.PoolPriceReset(pool, 0, 0);
        (address token,) = factory.create{value: fee + 0.01 ether}(p);
        assertEq(token, predicted);
        (,,,,, uint256 creatorTokens,,) = _launch(token);
        assertGt(creatorTokens, 0, "creacion normal pese a la pool preparada");
    }

    function test_frontRun_withForeignLiquidity_reverts() public {
        (FastLaunchFactoryCL.Create memory p, uint256 fee) = _params(address(0), _nativeValuation(), 0, keccak256("d"), false);
        address predicted = factory.predictToken(creator, p);
        bool tokenFirst = predicted < wrapped;
        // precio de arranque del atacante: lejos del objetivo, del lado donde puede poner solo moneda del par
        int24 start = tokenFirst ? int24(400000) : int24(-400000);
        vm.startPrank(attacker);
        address pool = IV3Factory(factory.dexFactory()).createPool(predicted, wrapped, 10000);
        IV3Pool(pool).initialize(TickMath.getSqrtPriceAtTick(start));
        vm.stopPrank();
        // liquidez solo de la moneda del par entre el precio del atacante y el objetivo
        (int24 lo, int24 hi) = tokenFirst ? (int24(200000), int24(300000)) : (int24(-300000), int24(-200000));
        mintToken = wrapped;
        IWrappedNative(wrapped).deposit{value: 5 ether}();
        IV3Pool(pool).mint(address(this), lo, hi, 1e9, "");
        vm.prank(creator);
        vm.expectRevert(FastLaunchFactoryCL.PoolManipulated.selector);
        factory.create{value: fee}(p);
    }

    function test_holdersMode() public {
        (address token,, address pool) = _launchNative(0, keccak256("e"), true);
        (,,,,,,, address rewards,) = factory.launches(token);
        assertTrue(rewards != address(0));
        assertTrue(FastLaunchHolderRewards(payable(rewards)).excluded(pool), "la pool queda fuera de los snapshots");
    }

    /// @dev Share of the swap fee that reaches liquidity providers, in 1/10000, per side.
    /// PancakeSwap v3 packs two 16-bit protocol shares in 1/10000; Uniswap v3 forks use 1/N in 4 bits.
    function _lpShare(address pool, bool wrappedFirst) internal view returns (uint256 quoteSide, uint256 tokenSide) {
        (,,,,, uint32 fp,) = IV3Pool(pool).slot0();
        uint256 p0;
        uint256 p1;
        if (fp > 255) {
            p0 = 10000 - (fp % 65536);
            p1 = 10000 - (fp >> 16);
        } else {
            uint256 d0 = fp % 16;
            uint256 d1 = fp >> 4;
            p0 = d0 == 0 ? 10000 : 10000 - 10000 / d0;
            p1 = d1 == 0 ? 10000 : 10000 - 10000 / d1;
        }
        (quoteSide, tokenSide) = wrappedFirst ? (p0, p1) : (p1, p0);
    }

    function _launch(address token)
        internal
        view
        returns (address c, address q, address s, bytes32 id, uint256 eff, uint256 ct, uint256 req, address hr)
    {
        uint256 supply;
        (c, q, s, id, req, eff, ct, hr, supply) = factory.launches(token);
        require(supply == SUPPLY, "supply guardado");
    }

    function _mintPay(uint256 a0, uint256 a1) internal {
        IERC20(mintToken).transfer(msg.sender, a0 > 0 ? a0 : a1);
    }

    function uniswapV3MintCallback(uint256 a0, uint256 a1, bytes calldata) external { _mintPay(a0, a1); }
    function pancakeV3MintCallback(uint256 a0, uint256 a1, bytes calldata) external { _mintPay(a0, a1); }
}

contract FastLaunchCLBnbForkTest is FastLaunchCLBase {
    address constant SMART_ROUTER = 0x13f4EA83D0bd40E75C8222255bc855a974568Dd4;
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address constant NVDAB = 0x02Fca66C1D1aFB4E2A7884261eB00F63598a7436;

    function setUp() public {
        _setUp(
            "https://bsc-dataseed.bnbchain.org",
            0x2191167456C36c4AD9C01Fe0583547F2880cC4De,
            FastLaunchFactoryCL.Dex(
                0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865,
                0x41ff9AA7e16B8B1a8a8dc4f0eFacd93D02d071c9,
                0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c,
                0x6ce8eb472fa82df5469c6ab6d485f17c3ad13c8cd7af59b3d4a8026c5ce0f7e2
            ),
            "PancakeSwap v3"
        );
        _copy(USDT);
        registry.configureQuote(
            NVDAB,
            FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 1 ether, 1000 ether, keccak256("test")),
            "bStocks test"
        );
    }

    function test_buyThroughPancakeSmartRouter() public {
        (address token,,) = _launchNative(0.01 ether, keccak256("f"), false);
        vm.prank(buyer);
        uint256 out = IPancakeSmartRouter(SMART_ROUTER).exactInputSingle{value: 0.05 ether}(
            IPancakeSmartRouter.ExactInputSingleParams(wrapped, token, 10000, buyer, 0.05 ether, 1, 0)
        );
        assertGt(out, 0);
        assertEq(IERC20(token).balanceOf(buyer), out, "compra por el router oficial de PancakeSwap");
    }

    function test_usdtPair_withCreatorBuy() public {
        (,, uint128 mn,,) = registry.quotes(USDT);
        deal(USDT, creator, 10 ether);
        (FastLaunchFactoryCL.Create memory p, uint256 fee) = _params(USDT, uint256(mn) * 3, 1 ether, keccak256("g"), false);
        vm.startPrank(creator);
        IERC20(USDT).approve(address(factory), 1 ether);
        (address token,) = factory.create{value: fee}(p);
        vm.stopPrank();
        assertGt(IERC20(token).balanceOf(creator), 0);
        assertTrue(factory.poolAddress(token, USDT).code.length > 0);
    }

    function test_bStockPair() public {
        (FastLaunchFactoryCL.Create memory p, uint256 fee) = _params(NVDAB, 10 ether, 0, keccak256("h"), false);
        vm.prank(creator);
        (address token,) = factory.create{value: fee}(p);
        address pool = factory.poolAddress(token, NVDAB);
        assertEq(IV3Factory(factory.dexFactory()).getPool(token, NVDAB, 10000), pool, "pool token/NVDAB en PancakeSwap v3");
    }
}

contract FastLaunchCLHyperForkTest is FastLaunchCLBase {
    function setUp() public {
        _setUp(
            "https://rpc.hyperliquid.xyz/evm",
            0x08A79b47812d1b38308bb10EA664d6d408e5E9c1,
            FastLaunchFactoryCL.Dex(
                0xFf7B3e8C00e57ea31477c32A5B52a58Eea47b072,
                0xFf7B3e8C00e57ea31477c32A5B52a58Eea47b072,
                0x5555555555555555555555555555555555555555,
                0x7ef2b01a451cbf890790278981756372e549443802ece149dc0b592cbc114ee9
            ),
            "Project X"
        );
    }
}
