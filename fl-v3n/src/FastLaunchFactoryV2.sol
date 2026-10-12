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
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {FastLaunchToken} from "./FastLaunchToken.sol";
import {FastLaunchRegistry} from "./FastLaunchRegistry.sol";
import {FastLaunchGuardHook} from "./FastLaunchGuardHook.sol";
import {FastLaunchMath} from "./FastLaunchMath.sol";
import {FastLaunchSplitter} from "./FastLaunchSplitter.sol";
import {FastLaunchComponents} from "./FastLaunchComponents.sol";
import {SwapMath} from "@uniswap/v4-core/src/libraries/SwapMath.sol";

/// @title Fast Launch by El Trueque (v2)
/// @author El Trueque
/// @notice Same launch flow as v1, on a standard Uniswap v4 pool: static LP fee from the registry
/// (normalFee) and a hook that only guards initialization. No opening fee, so routers and wallets
/// can treat the pool like any other. The creator buy cap is still enforced here, in the callback.
contract FastLaunchFactoryV2 is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    IPoolManager public immutable manager;
    FastLaunchRegistry public immutable registry;
    FastLaunchGuardHook public immutable hook;
    FastLaunchComponents public immutable components;
    uint256 public constant SUPPLY = 1_000_000 ether;
    string public constant VERSION = "2.0.0";

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
    event Launched(
        address indexed token,
        address indexed creator,
        address splitter,
        PoolId poolId,
        address quote,
        uint256 effectiveValuation,
        string metadataCID
    );
    event CreatorPurchase(address indexed token, uint256 quoteSpent, uint256 tokensReceived);
    event FeeDistributionChosen(address indexed token, bool toHolders, address recipient);

    constructor(IPoolManager m, FastLaunchRegistry r, bytes32 hookSalt) {
        if (address(m).code.length == 0 || address(r).code.length == 0) revert InvalidConfiguration();
        manager = m;
        registry = r;
        hook = new FastLaunchGuardHook{salt: hookSalt}(address(m), address(this));
        components = new FastLaunchComponents();
    }

    function predictToken(address creator, Create calldata p) public view returns (address) {
        bytes32 salt = keccak256(abi.encode(creator, p.salt));
        bytes32 init =
            keccak256(abi.encodePacked(type(FastLaunchToken).creationCode, abi.encode(p.name, p.symbol, p.metadataCID)));
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, init)))));
    }

    function preview(address creator, Create calldata p)
        external
        view
        returns (address token, FastLaunchMath.Range memory range, PoolKey memory key)
    {
        (FastLaunchRegistry.Quote memory q, FastLaunchRegistry.Opening memory o,,) = registry.configuration(p.quote);
        if (q.kind == FastLaunchRegistry.Kind.Disabled) revert NotAllowed();
        token = predictToken(creator, p);
        range = FastLaunchMath.quote(p.valuation, token < p.quote, o.tickSpacing);
        key = _key(token, p.quote, o.tickSpacing, o.normalFee);
    }

    /// @notice Exact opening swap estimate: new pool has no protocol fee, no other LP or prior swaps.
    /// Initialization, seeding and creator purchase are atomic. Execution still checks actual deltas.
    function previewCreatorBuy(address creator, Create calldata p)
        external
        view
        returns (uint256 tokensOut, uint256 quoteUsed, uint256 quoteFee, uint256 maximumTokens)
    {
        (FastLaunchRegistry.Quote memory q, FastLaunchRegistry.Opening memory o,,) = registry.configuration(p.quote);
        if (q.kind == FastLaunchRegistry.Kind.Disabled || p.buyAmount > uint256(type(int256).max)) {
            revert InvalidConfiguration();
        }
        maximumTokens = uint256(o.creatorBuyBps) * SUPPLY / 10000;
        if (p.buyAmount == 0) return (0, 0, 0, maximumTokens);
        bool first = predictToken(creator, p) < p.quote;
        FastLaunchMath.Range memory r = FastLaunchMath.quote(p.valuation, first, o.tickSpacing);
        (, uint256 input, uint256 output, uint256 fee) = SwapMath.computeSwapStep(
            r.price,
            TickMath.getSqrtPriceAtTick(first ? r.upper : r.lower),
            r.liquidity,
            -int256(p.buyAmount),
            o.normalFee
        );
        return (output, input + fee, fee, maximumTokens);
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
        if (msg.value != fee + (p.quote == address(0) ? p.buyAmount : 0)) revert IncorrectPayment();
        if ((p.buyAmount == 0 && p.minTokens != 0) || (p.buyAmount > 0 && p.minTokens == 0)) revert MinimumOutput();
        token =
            address(
            new FastLaunchToken{salt: keccak256(abi.encode(msg.sender, p.salt))}(p.name, p.symbol, p.metadataCID)
        );
        FastLaunchMath.Range memory r = FastLaunchMath.quote(p.valuation, token < p.quote, o.tickSpacing);
        if (r.valuation < q.minValuation || r.valuation > q.maxValuation) revert InvalidConfiguration();
        PoolKey memory k = _key(token, p.quote, o.tickSpacing, o.normalFee);
        (uint160 existing,,,) = manager.getSlot0(k.toId());
        if (existing != 0) revert PoolExists();
        manager.initialize(k, r.price);
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
        IERC20(token).safeTransfer(splitter, SUPPLY);
        FastLaunchSplitter(payable(splitter)).seed();
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
                k, token, p.quote, msg.sender, p.buyAmount, p.minTokens, uint256(o.creatorBuyBps) * SUPPLY / 10000
            );
            expectedCallback = keccak256(data);
            bought = abi.decode(manager.unlock(data), (uint256));
            expectedCallback = 0;
        }
        launches[token] = Launch(msg.sender, p.quote, splitter, k.toId(), p.valuation, r.valuation, bought, rewards);
        tokens.push(token);
        emit FeeDistributionChosen(token, p.toHolders, p.toHolders ? rewards : msg.sender);
        if (fee > 0) {
            (bool ok,) = registry.treasury().call{value: fee}("");
            if (!ok) revert TransferFailed();
        }
        emit Launched(token, msg.sender, splitter, k.toId(), p.quote, r.valuation, p.metadataCID);
    }

    /// @dev Static LP fee (registry normalFee, at most 900000 there): no dynamic-fee flag, no swap hook.
    function _key(address token, address quote, int24 spacing, uint24 fee) private view returns (PoolKey memory) {
        return PoolKey(
            Currency.wrap(token < quote ? token : quote),
            Currency.wrap(token < quote ? quote : token),
            fee,
            spacing,
            IHooks(address(hook))
        );
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
        (PoolKey memory k, address t, address q, address buyer, uint256 amount, uint256 minimum, uint256 cap) =
            abi.decode(data, (PoolKey, address, address, address, uint256, uint256, uint256));
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
