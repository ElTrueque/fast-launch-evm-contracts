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

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {SwapMath} from "@uniswap/v4-core/src/libraries/SwapMath.sol";
import {FastLaunchTokenETH} from "../FastLaunchTokenETH.sol";
import {FastLaunchRegistry} from "../FastLaunchRegistry.sol";
import {FastLaunchMathETH} from "../FastLaunchMathETH.sol";
import {FastLaunchLockerCL} from "./FastLaunchLockerCL.sol";
import {FastLaunchComponentsCL} from "./FastLaunchComponentsCL.sol";
import {IV3Factory, IV3Pool, IWrappedNative} from "./IV3.sol";

/// @title Fast Launch by El Trueque (v2, classic concentrated-liquidity pools)
/// @author El Trueque
/// @notice Same launch flow as Fast Launch v1/v2 on a standard PancakeSwap v3 / Project X pool with a
/// static 1% fee. The pool has no hook, so this factory checks that nobody prepared it beforehand.
contract FastLaunchFactoryCL is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Dex {
        address factory;
        address poolDeployer;
        address wrappedNative;
        bytes32 poolInitCodeHash;
    }

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

    /// @dev Same layout as v1/v2. `poolId` holds the pool address, left-padded, for v3 style pools.
    struct Launch {
        address creator;
        address quote;
        address splitter;
        bytes32 poolId;
        uint256 requestedValuation;
        uint256 effectiveValuation;
        uint256 creatorTokens;
        address holderRewards;
        uint256 supply;
    }

    uint24 public constant FEE = 10000;
    uint256 public constant MIN_SUPPLY = 1_000 ether;
    uint256 public constant MAX_SUPPLY = 1_000_000_000_000 ether;
    string public constant VERSION = "3.0.0-cl";
    FastLaunchRegistry public immutable registry;
    FastLaunchComponentsCL public immutable components;
    address public immutable dexFactory;
    address public immutable poolDeployer;
    address public immutable wrappedNative;
    bytes32 public immutable poolInitCodeHash;
    int24 public immutable tickSpacing;
    string public dexName;
    mapping(address => Launch) public launches;
    address[] public tokens;
    address private activePool;
    address private activeToken;
    address private activeQuote;
    uint256 private paymentBudget;

    error InvalidConfiguration();
    error InvalidMetadata();
    error IncorrectPayment();
    error NotAllowed();
    error BuyLimit();
    error MinimumOutput();
    error Unauthorized();
    error TransferFailed();
    error UnexpectedPool();
    error PoolManipulated();
    error InvalidSupply();

    event Launched(
        address indexed token,
        address indexed creator,
        address splitter,
        bytes32 poolId,
        address quote,
        uint256 effectiveValuation,
        string metadataCID,
        uint256 supply
    );
    event CreatorPurchase(address indexed token, uint256 quoteSpent, uint256 tokensReceived);
    event FeeDistributionChosen(address indexed token, bool toHolders, address recipient);
    event PoolPriceReset(address indexed pool, uint160 fromPrice, uint160 toPrice);

    constructor(FastLaunchRegistry r, Dex memory d, string memory name_) {
        if (
            address(r).code.length == 0 || d.factory.code.length == 0 || d.poolDeployer.code.length == 0
                || d.wrappedNative.code.length == 0 || d.poolInitCodeHash == bytes32(0)
        ) revert InvalidConfiguration();
        int24 spacing = IV3Factory(d.factory).feeAmountTickSpacing(FEE);
        if (spacing <= 0 || spacing > 32767) revert InvalidConfiguration();
        // PancakeSwap v3 deploys pools from a separate deployer; Uniswap v3 forks deploy from the factory.
        (bool ok, bytes memory data) = d.factory.staticcall(abi.encodeWithSignature("poolDeployer()"));
        if (ok && data.length == 32) {
            if (abi.decode(data, (address)) != d.poolDeployer) revert InvalidConfiguration();
        } else if (d.poolDeployer != d.factory) {
            revert InvalidConfiguration();
        }
        registry = r;
        dexFactory = d.factory;
        poolDeployer = d.poolDeployer;
        wrappedNative = d.wrappedNative;
        poolInitCodeHash = d.poolInitCodeHash;
        tickSpacing = spacing;
        dexName = name_;
        components = new FastLaunchComponentsCL();
    }

    function predictToken(address creator, Create calldata p) public view returns (address) {
        bytes32 salt = keccak256(abi.encode(creator, p.salt));
        bytes32 init =
            keccak256(abi.encodePacked(type(FastLaunchTokenETH).creationCode, abi.encode(p.name, p.symbol, p.metadataCID, p.supply)));
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, init)))));
    }

    /// @notice Deterministic pool address for a token and a registry quote (address(0) = native coin).
    function poolAddress(address token, address quote) public view returns (address) {
        address pq = quote == address(0) ? wrappedNative : quote;
        (address t0, address t1) = token < pq ? (token, pq) : (pq, token);
        return address(
            uint160(
                uint256(keccak256(abi.encodePacked(hex"ff", poolDeployer, keccak256(abi.encode(t0, t1, FEE)), poolInitCodeHash)))
            )
        );
    }

    function preview(address creator, Create calldata p)
        external
        view
        returns (address token, FastLaunchMathETH.Range memory range, address pool)
    {
        (FastLaunchRegistry.Quote memory q,,,) = registry.configuration(p.quote);
        if (q.kind == FastLaunchRegistry.Kind.Disabled) revert NotAllowed();
        _supply(p.supply);
        token = predictToken(creator, p);
        address pq = p.quote == address(0) ? wrappedNative : p.quote;
        range = FastLaunchMathETH.quote(p.valuation, p.supply, token < pq, tickSpacing);
        pool = poolAddress(token, p.quote);
    }

    /// @notice Exact estimate: the new pool holds only this launch position when the creator buys.
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
        address pq = p.quote == address(0) ? wrappedNative : p.quote;
        bool first = predictToken(creator, p) < pq;
        FastLaunchMathETH.Range memory r = FastLaunchMathETH.quote(p.valuation, p.supply, first, tickSpacing);
        (, uint256 input, uint256 output, uint256 fee) = SwapMath.computeSwapStep(
            r.price, TickMath.getSqrtPriceAtTick(first ? r.upper : r.lower), r.liquidity, -int256(p.buyAmount), FEE
        );
        return (output, input + fee, fee, maximumTokens);
    }

    function create(Create calldata p) external payable nonReentrant returns (address token, address locker) {
        (FastLaunchRegistry.Quote memory q, FastLaunchRegistry.Opening memory o, uint256 fee, bytes32 digest) =
            registry.configuration(p.quote);
        if (q.kind == FastLaunchRegistry.Kind.Disabled) revert NotAllowed();
        if (o.normalFee != FEE || o.tickSpacing != tickSpacing) revert InvalidConfiguration();
        if (
            p.deadline < block.timestamp || p.configurationHash != digest || p.valuation < q.minValuation
                || p.valuation > q.maxValuation
        ) revert InvalidConfiguration();
        _metadata(p);
        _supply(p.supply);
        if (msg.value != fee + (p.quote == address(0) ? p.buyAmount : 0)) revert IncorrectPayment();
        if ((p.buyAmount == 0 && p.minTokens != 0) || (p.buyAmount > 0 && p.minTokens == 0)) revert MinimumOutput();
        token =
            address(new FastLaunchTokenETH{salt: keccak256(abi.encode(msg.sender, p.salt))}(p.name, p.symbol, p.metadataCID, p.supply));
        address pq = p.quote == address(0) ? wrappedNative : p.quote;
        FastLaunchMathETH.Range memory r = FastLaunchMathETH.quote(p.valuation, p.supply, token < pq, tickSpacing);
        if (r.valuation < q.minValuation || r.valuation > q.maxValuation) revert InvalidConfiguration();
        address pool = _preparePool(token, pq, r.price);
        address rewards;
        (locker, rewards) = components.deploy(
            pool, token, p.quote, pq, msg.sender, registry.treasury(), r.lower, r.upper, r.liquidity, p.toHolders,
            registry.snapshotSigner()
        );
        IERC20(token).safeTransfer(locker, p.supply);
        FastLaunchLockerCL(payable(locker)).seed();
        uint256 bought;
        if (p.buyAmount > 0) bought = _creatorBuy(pool, token, pq, p, uint256(o.creatorBuyBps) * p.supply / 10000);
        bytes32 id = bytes32(uint256(uint160(pool)));
        launches[token] = Launch(msg.sender, p.quote, locker, id, p.valuation, r.valuation, bought, rewards, p.supply);
        tokens.push(token);
        emit FeeDistributionChosen(token, p.toHolders, p.toHolders ? rewards : msg.sender);
        if (fee > 0) {
            (bool ok,) = registry.treasury().call{value: fee}("");
            if (!ok) revert TransferFailed();
        }
        emit Launched(token, msg.sender, locker, id, p.quote, r.valuation, p.metadataCID, p.supply);
    }

    /// @dev Anyone can create a v3 pool for an address that has no code yet. If that happened, the price
    /// is moved back for free while the pool is empty; any amount owed means foreign liquidity: revert.
    function _preparePool(address token, address pq, uint160 price) private returns (address pool) {
        pool = IV3Factory(dexFactory).getPool(token, pq, FEE);
        if (pool == address(0)) pool = IV3Factory(dexFactory).createPool(token, pq, FEE);
        if (pool != poolAddress(token, pq == wrappedNative ? address(0) : pq)) revert UnexpectedPool();
        (uint160 current,,,,,,) = IV3Pool(pool).slot0();
        if (current == 0) {
            IV3Pool(pool).initialize(price);
        } else if (current != price) {
            activePool = pool;
            activeToken = token;
            activeQuote = pq;
            paymentBudget = 0;
            IV3Pool(pool).swap(address(this), current > price, 1, price, "");
            activePool = address(0);
            emit PoolPriceReset(pool, current, price);
        }
        (current,,,,,,) = IV3Pool(pool).slot0();
        if (current != price || IV3Pool(pool).liquidity() != 0) revert PoolManipulated();
    }

    function _creatorBuy(address pool, address token, address pq, Create calldata p, uint256 cap)
        private
        returns (uint256 bought)
    {
        if (p.buyAmount > uint256(type(int256).max)) revert IncorrectPayment();
        if (p.quote == address(0)) {
            IWrappedNative(wrappedNative).deposit{value: p.buyAmount}();
        } else {
            uint256 before = IERC20(pq).balanceOf(address(this));
            IERC20(pq).safeTransferFrom(msg.sender, address(this), p.buyAmount);
            if (IERC20(pq).balanceOf(address(this)) != before + p.buyAmount) revert IncorrectPayment();
        }
        bool zeroForOne = pq < token;
        activePool = pool;
        activeToken = token;
        activeQuote = pq;
        paymentBudget = p.buyAmount;
        (int256 a0, int256 a1) = IV3Pool(pool).swap(
            msg.sender,
            zeroForOne,
            int256(p.buyAmount),
            zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1,
            ""
        );
        activePool = address(0);
        paymentBudget = 0;
        int256 paid = zeroForOne ? a0 : a1;
        int256 received = zeroForOne ? a1 : a0;
        // Require full exact-input consumption: no leftovers or silent partial creator buy.
        if (paid != int256(p.buyAmount)) revert IncorrectPayment();
        if (received >= 0 || uint256(-received) < p.minTokens) revert MinimumOutput();
        bought = uint256(-received);
        if (bought > cap) revert BuyLimit();
        emit CreatorPurchase(token, p.buyAmount, bought);
    }

    function _swapCallback(int256 amount0, int256 amount1) private {
        address pool = activePool;
        if (pool == address(0) || msg.sender != pool) revert Unauthorized();
        bool quoteFirst = activeQuote < activeToken;
        int256 owedQuote = quoteFirst ? amount0 : amount1;
        int256 owedToken = quoteFirst ? amount1 : amount0;
        if (owedToken > 0) revert PoolManipulated();
        if (owedQuote > 0) {
            if (uint256(owedQuote) > paymentBudget) revert PoolManipulated();
            paymentBudget -= uint256(owedQuote);
            IERC20(activeQuote).safeTransfer(pool, uint256(owedQuote));
        }
    }

    function pancakeV3SwapCallback(int256 amount0, int256 amount1, bytes calldata) external {
        _swapCallback(amount0, amount1);
    }

    function uniswapV3SwapCallback(int256 amount0, int256 amount1, bytes calldata) external {
        _swapCallback(amount0, amount1);
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

    /// @dev Same rule as FastLaunchFactoryETH: whole tokens from one thousand to one trillion.
    function _supply(uint256 supply) private pure {
        if (supply < MIN_SUPPLY || supply > MAX_SUPPLY || supply % 1 ether != 0) revert InvalidSupply();
    }

    function launchCount() external view returns (uint256) {
        return tokens.length;
    }
}
