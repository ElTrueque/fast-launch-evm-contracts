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

    Fast Launch by El Trueque  ·  https://el-trueque.com  ·  v3.0.0-eth
    Lanzamientos directos en Uniswap v4 con liquidez bloqueada para siempre.
    Ethereum: pool estándar de Uniswap v4 sin hook, comisión fija y supply elegido por el creador.
    X: https://x.com/ElTruequeMarket
    Telegram: https://t.me/eltruequeapp
    Instagram: https://instagram.com/eltruequeapp
*/

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {FastLaunchTokenETH} from "./FastLaunchTokenETH.sol";
import {FastLaunchRegistry} from "./FastLaunchRegistry.sol";
import {FastLaunchMathETH} from "./FastLaunchMathETH.sol";
import {FastLaunchSplitterETH} from "./FastLaunchSplitterETH.sol";
import {FastLaunchComponentsETH} from "./FastLaunchComponentsETH.sol";
import {SwapMath} from "@uniswap/v4-core/src/libraries/SwapMath.sol";
import {LiquidityMath} from "@uniswap/v4-core/src/libraries/LiquidityMath.sol";
import {BitMath} from "@uniswap/v4-core/src/libraries/BitMath.sol";

/// @title Fast Launch by El Trueque (Ethereum)
/// @author El Trueque
/// @notice Same launch flow as v2 on a plain Uniswap v4 pool with no hook: static LP fee from the
/// registry, so any router, wallet or aggregator treats it like any other pool. The creator picks the
/// supply. If someone initializes the empty pool first, its price is moved back for free in the same
/// transaction; if anyone placed liquidity there, the launch stops and nothing is spent.
contract FastLaunchFactoryETH is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    IPoolManager public immutable manager;
    FastLaunchRegistry public immutable registry;
    FastLaunchComponentsETH public immutable components;
    uint256 public constant MIN_SUPPLY = 1_000 ether;
    uint256 public constant MAX_SUPPLY = 1_000_000_000_000 ether;
    string public constant VERSION = "3.0.0-eth";

    struct Create {
        string name;
        string symbol;
        string metadataCID;
        address quote;
        uint256 valuation;
        uint256 buyAmount;
        uint256 minTokens;
        bytes32 salt;
        bytes32 configurationHash;
        uint256 deadline;
        bool toHolders;
        uint256 supply;
    }

    struct Launch {
        address creator;
        address quote;
        address splitter;
        PoolId poolId;
        uint256 requestedValuation;
        uint256 effectiveValuation;
        uint256 creatorTokens;
        address holderRewards;
        uint256 supply;
    }
    mapping(address => Launch) public launches;
    address[] public tokens;
    bytes32 private expectedCallback;
    error InvalidConfiguration();
    error InvalidMetadata();
    error IncorrectPayment();
    error NotAllowed();
    error PoolExists();
    error BuyLimit();
    error MinimumOutput();
    error Unauthorized();
    error TransferFailed();
    error InvalidSupply();
    event Launched(
        address indexed token,
        address indexed creator,
        address splitter,
        PoolId poolId,
        address quote,
        uint256 effectiveValuation,
        string metadataCID,
        uint256 supply
    );
    event CreatorPurchase(address indexed token, uint256 quoteSpent, uint256 tokensReceived);
    event FeeDistributionChosen(address indexed token, bool toHolders, address recipient);

    constructor(IPoolManager m, FastLaunchRegistry r) {
        if (address(m).code.length == 0 || address(r).code.length == 0) revert InvalidConfiguration();
        manager = m;
        registry = r;
        components = new FastLaunchComponentsETH();
    }

    function predictToken(address creator, Create calldata p) public view returns (address) {
        bytes32 salt = keccak256(abi.encode(creator, p.salt));
        bytes32 init =
            keccak256(abi.encodePacked(type(FastLaunchTokenETH).creationCode, abi.encode(p.name, p.symbol, p.metadataCID, p.supply)));
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, init)))));
    }

    function preview(address creator, Create calldata p)
        external
        view
        returns (address token, FastLaunchMathETH.Range memory range, PoolKey memory key)
    {
        (FastLaunchRegistry.Quote memory q, FastLaunchRegistry.Opening memory o,,) = registry.configuration(p.quote);
        if (q.kind == FastLaunchRegistry.Kind.Disabled) revert NotAllowed();
        _supply(p.supply);
        token = predictToken(creator, p);
        range = FastLaunchMathETH.quote(p.valuation, p.supply, token < p.quote, o.tickSpacing);
        key = _key(token, p.quote, o.tickSpacing, o.normalFee);
    }

    /// @notice Replays the creator purchase step by step, with the pool's own rounding: one step per tick-bitmap
    /// word, crossing the launch position's two ticks, at the static fee (a pool starts with no protocol fee).
    /// If the empty pool was initialized earlier, the free repricing and that pool's state are replayed too.
    /// The result is what create() delivers when nothing else touches the pool first; create() still checks
    /// minTokens, the cap and the exact payment against the real deltas.
    function previewCreatorBuy(address creator, Create calldata p)
        external
        view
        returns (uint256 tokensOut, uint256 quoteUsed, uint256 quoteFee, uint256 maximumTokens)
    {
        (FastLaunchRegistry.Quote memory q, FastLaunchRegistry.Opening memory o,,) = registry.configuration(p.quote);
        if (q.kind == FastLaunchRegistry.Kind.Disabled || p.buyAmount > uint256(type(int256).max)) {
            revert InvalidConfiguration();
        }
        _supply(p.supply);
        maximumTokens = uint256(o.creatorBuyBps) * p.supply / 10000;
        if (p.buyAmount == 0) return (0, 0, 0, maximumTokens);
        Walk memory w = _previewWalk(creator, p, o);
        return (w.out, p.buyAmount - uint256(-w.remaining), w.fees, maximumTokens);
    }

    function _previewWalk(address creator, Create calldata p, FastLaunchRegistry.Opening memory o)
        private
        view
        returns (Walk memory w)
    {
        address token = predictToken(creator, p);
        bool first = token < p.quote;
        FastLaunchMathETH.Range memory r = FastLaunchMathETH.quote(p.valuation, p.supply, first, o.tickSpacing);
        PoolId id = _key(token, p.quote, o.tickSpacing, o.normalFee).toId();
        Pos memory pos = Pos(r.lower, r.upper, r.liquidity, false);
        w = Walk(r.price, TickMath.getTickAtSqrtPrice(r.price), 0, -int256(p.buyAmount), 0, 0);
        uint24 swapFee = _openingState(w, r.price, first, id, o, pos);
        pos.on = true;
        if (w.tick >= r.lower && w.tick < r.upper) w.liquidity += r.liquidity;
        _walk(w, !first, first ? TickMath.MAX_SQRT_PRICE - 1 : TickMath.MIN_SQRT_PRICE + 1, o.tickSpacing, swapFee, pos, id);
    }

    /// @dev A pool someone initialized earlier is handled like create() does: moving it to the opening price must
    /// cost nothing, or the launch stops; the walk then uses that pool's real ticks, liquidity and protocol fee.
    function _openingState(
        Walk memory w,
        uint160 target,
        bool first,
        PoolId id,
        FastLaunchRegistry.Opening memory o,
        Pos memory pos
    ) private view returns (uint24 swapFee) {
        swapFee = o.normalFee;
        (uint160 existing, int24 existingTick, uint24 protocolFee,) = manager.getSlot0(id);
        if (existing == 0) return swapFee;
        w.tick = existingTick;
        w.liquidity = manager.getLiquidity(id);
        if (existing != target) {
            Walk memory fix = Walk(existing, existingTick, w.liquidity, -1, 0, 0);
            _walk(fix, existing > target, target, o.tickSpacing, o.normalFee, pos, id);
            if (fix.remaining != -1 || fix.out != 0 || fix.price != target) revert PoolExists();
            w.tick = fix.tick;
            w.liquidity = fix.liquidity;
        }
        uint256 pf = first ? protocolFee >> 12 : protocolFee & 0xfff;
        if (pf != 0) swapFee = uint24(pf + o.normalFee - pf * o.normalFee / 1_000_000);
    }

    struct Walk {
        uint160 price;
        int24 tick;
        uint128 liquidity;
        int256 remaining;
        uint256 out;
        uint256 fees;
    }

    /// @dev The launch position, overlaid on the pool's real state once it is seeded.
    struct Pos {
        int24 lower;
        int24 upper;
        uint128 liquidity;
        bool on;
    }

    struct Step {
        uint160 start;
        int24 next;
        bool initialized;
        uint160 nextPrice;
        uint256 amountIn;
        uint256 amountOut;
        uint256 feeAmount;
    }

    /// @dev Same loop as Uniswap v4 Pool.swap for an exact-input swap, reading the pool's own ticks and liquidity.
    function _walk(Walk memory w, bool zeroForOne, uint160 limit, int24 spacing, uint24 fee, Pos memory pos, PoolId id)
        private
        view
    {
        Step memory st;
        while (w.remaining != 0 && w.price != limit) {
            st.start = w.price;
            (st.next, st.initialized) = _nextTick(w.tick, spacing, zeroForOne, pos, id);
            if (st.next <= TickMath.MIN_TICK) st.next = TickMath.MIN_TICK;
            if (st.next >= TickMath.MAX_TICK) st.next = TickMath.MAX_TICK;
            st.nextPrice = TickMath.getSqrtPriceAtTick(st.next);
            (w.price, st.amountIn, st.amountOut, st.feeAmount) = SwapMath.computeSwapStep(
                w.price, SwapMath.getSqrtPriceTarget(zeroForOne, st.nextPrice, limit), w.liquidity, w.remaining, fee
            );
            w.remaining += int256(st.amountIn + st.feeAmount);
            w.out += st.amountOut;
            w.fees += st.feeAmount;
            if (w.price == st.nextPrice) {
                if (st.initialized) {
                    (, int128 net) = manager.getTickLiquidity(id, st.next);
                    if (pos.on) {
                        if (st.next == pos.lower) net += int128(pos.liquidity);
                        else if (st.next == pos.upper) net -= int128(pos.liquidity);
                    }
                    w.liquidity = LiquidityMath.addDelta(w.liquidity, zeroForOne ? -net : net);
                }
                w.tick = zeroForOne ? st.next - 1 : st.next;
            } else if (w.price != st.start) {
                w.tick = TickMath.getTickAtSqrtPrice(w.price);
            }
        }
    }

    /// @dev TickBitmap.nextInitializedTickWithinOneWord on the pool's bitmap plus the launch position's two ticks.
    function _nextTick(int24 tick, int24 spacing, bool lte, Pos memory pos, PoolId id)
        private
        view
        returns (int24 next, bool initialized)
    {
        int24 compressed = tick / spacing;
        if (tick < 0 && tick % spacing != 0) compressed--;
        if (!lte) compressed++;
        int16 wordPos = int16(compressed >> 8);
        uint8 bitPos = uint8(uint24(compressed) & 0xff);
        uint256 word = manager.getTickBitmap(id, wordPos);
        if (pos.on) word |= _bit(pos.lower, spacing, wordPos) | _bit(pos.upper, spacing, wordPos);
        if (lte) {
            uint256 masked = word & (type(uint256).max >> (uint256(type(uint8).max) - bitPos));
            initialized = masked != 0;
            next = initialized
                ? (compressed - int24(uint24(bitPos - BitMath.mostSignificantBit(masked)))) * spacing
                : (compressed - int24(uint24(bitPos))) * spacing;
        } else {
            uint256 masked = word & ~((uint256(1) << bitPos) - 1);
            initialized = masked != 0;
            next = initialized
                ? (compressed + int24(uint24(BitMath.leastSignificantBit(masked) - bitPos))) * spacing
                : (compressed + int24(uint24(type(uint8).max - bitPos))) * spacing;
        }
    }

    function _bit(int24 t, int24 spacing, int16 wordPos) private pure returns (uint256) {
        int24 c = t / spacing;
        return int16(c >> 8) == wordPos ? uint256(1) << (uint24(c) & 0xff) : 0;
    }

    function create(Create calldata p) external payable nonReentrant returns (address token, address splitter) {
        (FastLaunchRegistry.Quote memory q, FastLaunchRegistry.Opening memory o, uint256 fee, bytes32 digest) =
            registry.configuration(p.quote);
        if (q.kind == FastLaunchRegistry.Kind.Disabled) revert NotAllowed();
        if (
            p.deadline < block.timestamp || p.configurationHash != digest || p.valuation < q.minValuation
                || p.valuation > q.maxValuation
        ) revert InvalidConfiguration();
        _metadata(p);
        _supply(p.supply);
        if (msg.value != fee + (p.quote == address(0) ? p.buyAmount : 0)) revert IncorrectPayment();
        if ((p.buyAmount == 0 && p.minTokens != 0) || (p.buyAmount > 0 && p.minTokens == 0)) revert MinimumOutput();
        token =
            address(
            new FastLaunchTokenETH{salt: keccak256(abi.encode(msg.sender, p.salt))}(p.name, p.symbol, p.metadataCID, p.supply)
        );
        FastLaunchMathETH.Range memory r = FastLaunchMathETH.quote(p.valuation, p.supply, token < p.quote, o.tickSpacing);
        if (r.valuation < q.minValuation || r.valuation > q.maxValuation) revert InvalidConfiguration();
        PoolKey memory k = _key(token, p.quote, o.tickSpacing, o.normalFee);
        (uint160 existing,,,) = manager.getSlot0(k.toId());
        if (existing == 0) {
            manager.initialize(k, r.price);
        } else if (existing != r.price) {
            // Without a hook anyone could initialize this key first. The token did not exist before this
            // transaction, so nobody can hold a position that needs it; moving the price of an empty pool
            // costs nothing. Any other liquidity makes the move cost something and the launch reverts.
            bytes memory fix = abi.encode(uint8(1), k, r.price);
            expectedCallback = keccak256(fix);
            manager.unlock(fix);
            expectedCallback = 0;
        }
        address rewards;
        (splitter, rewards) = components.deploy(
            manager,
            k,
            token,
            p.quote,
            msg.sender,
            registry.treasury(),
            r.lower,
            r.upper,
            r.liquidity,
            p.toHolders,
            registry.snapshotSigner()
        );
        IERC20(token).safeTransfer(splitter, p.supply);
        FastLaunchSplitterETH(payable(splitter)).seed();
        uint256 bought;
        if (p.buyAmount > 0) {
            if (p.buyAmount > uint256(type(int256).max)) revert IncorrectPayment();
            if (p.quote != address(0)) {
                uint256 before = IERC20(p.quote).balanceOf(address(this));
                IERC20(p.quote).safeTransferFrom(msg.sender, address(this), p.buyAmount);
                if (IERC20(p.quote).balanceOf(address(this)) != before + p.buyAmount) revert IncorrectPayment();
            }
            bytes memory data =
                abi.encode(
                uint8(2), k, token, p.quote, msg.sender, p.buyAmount, p.minTokens, uint256(o.creatorBuyBps) * p.supply / 10000
            );
            expectedCallback = keccak256(data);
            bought = abi.decode(manager.unlock(data), (uint256));
            expectedCallback = 0;
        }
        launches[token] = Launch(msg.sender, p.quote, splitter, k.toId(), p.valuation, r.valuation, bought, rewards, p.supply);
        tokens.push(token);
        emit FeeDistributionChosen(token, p.toHolders, p.toHolders ? rewards : msg.sender);
        if (fee > 0) {
            (bool ok,) = registry.treasury().call{value: fee}("");
            if (!ok) revert TransferFailed();
        }
        emit Launched(token, msg.sender, splitter, k.toId(), p.quote, r.valuation, p.metadataCID, p.supply);
    }

    /// @dev Static LP fee (registry normalFee, at most 900000 there), no dynamic-fee flag and no hook.
    function _key(address token, address quote, int24 spacing, uint24 fee) private pure returns (PoolKey memory) {
        return PoolKey(
            Currency.wrap(token < quote ? token : quote),
            Currency.wrap(token < quote ? quote : token),
            fee,
            spacing,
            IHooks(address(0))
        );
    }

    function _supply(uint256 supply) private pure {
        if (supply < MIN_SUPPLY || supply > MAX_SUPPLY || supply % 1 ether != 0) revert InvalidSupply();
    }

    function _metadata(Create calldata p) private pure {
        bytes memory c = bytes(p.metadataCID);
        if (
            bytes(p.name).length == 0 || bytes(p.name).length > 64 || bytes(p.symbol).length == 0
                || bytes(p.symbol).length > 16 || c.length < 46 || c.length > 96
        ) revert InvalidMetadata();
        // CID only; never a mutable HTTP URL, path or unescaped document.
        for (uint256 i; i < c.length; i++) {
            if (!((c[i] >= 0x30 && c[i] <= 0x39) || (c[i] >= 0x41 && c[i] <= 0x5a) || (c[i] >= 0x61 && c[i] <= 0x7a))) {
                revert InvalidMetadata();
            }
        }
        if (!((c[0] == 0x51 && c[1] == 0x6d && c.length == 46) || (c[0] == 0x62 && c.length >= 50))) revert InvalidMetadata();
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(manager) || expectedCallback == 0 || keccak256(data) != expectedCallback) {
            revert Unauthorized();
        }
        if (uint8(data[31]) == 1) {
            (, PoolKey memory pk, uint160 target) = abi.decode(data, (uint8, PoolKey, uint160));
            (uint160 current,,,) = manager.getSlot0(pk.toId());
            BalanceDelta moved = manager.swap(pk, SwapParams(current > target, -1, target), "");
            (uint160 fixedPrice,,,) = manager.getSlot0(pk.toId());
            if (moved.amount0() != 0 || moved.amount1() != 0 || fixedPrice != target) revert PoolExists();
            return "";
        }
        (, PoolKey memory k, address t, address q, address buyer, uint256 amount, uint256 minimum, uint256 cap) =
            abi.decode(data, (uint8, PoolKey, address, address, address, uint256, uint256, uint256));
        bool token0 = t < q;
        BalanceDelta d = manager.swap(
            k,
            SwapParams(!token0, -int256(amount), token0 ? TickMath.MAX_SQRT_PRICE - 1 : TickMath.MIN_SQRT_PRICE + 1),
            ""
        );
        int128 output = token0 ? d.amount0() : d.amount1();
        int128 input = token0 ? d.amount1() : d.amount0();
        if (output <= 0 || uint128(output) < minimum) revert MinimumOutput();
        if (uint128(output) > cap) revert BuyLimit();
        // Require full exact-input consumption: no leftovers or silent partial creator buy.
        if (input >= 0 || uint256(-int256(input)) != amount) revert IncorrectPayment();
        if (q == address(0)) {
            manager.settle{value: amount}();
        } else {
            manager.sync(Currency.wrap(q));
            IERC20(q).safeTransfer(address(manager), amount);
            manager.settle();
        }
        manager.take(Currency.wrap(t), buyer, uint128(output));
        emit CreatorPurchase(t, amount, uint128(output));
        return abi.encode(uint256(uint128(output)));
    }

    function launchCount() external view returns (uint256) {
        return tokens.length;
    }
}
