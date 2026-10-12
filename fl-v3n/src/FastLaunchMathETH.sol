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

import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Valuation is raw quote units for the whole supply chosen by the creator.
library FastLaunchMathETH {
    uint256 internal constant Q96 = 1 << 96;
    error InvalidPrice();

    struct Range {
        uint160 price;
        int24 tick;
        int24 lower;
        int24 upper;
        uint128 liquidity;
        uint256 tokenUsed;
        uint256 valuation;
    }

    function quote(uint256 valuation, uint256 supply, bool token0, int24 spacing) internal pure returns (Range memory r) {
        if (supply == 0 || valuation == 0 || valuation > type(uint128).max || spacing <= 0 || spacing > 32767) revert InvalidPrice();
        uint256 numerator = token0 ? valuation : supply;
        uint256 denominator = token0 ? supply : valuation;
        // First Q128 then sqrt and Q96. Bounds below avoid overflow/underflow.
        uint256 ratio = FullMath.mulDiv(numerator, 1 << 128, denominator);
        uint256 price = Math.sqrt(ratio) << 32;
        if (price <= TickMath.MIN_SQRT_PRICE || price >= TickMath.MAX_SQRT_PRICE) revert InvalidPrice();
        int24 raw = TickMath.getTickAtSqrtPrice(uint160(price));
        int24 floor = raw / spacing * spacing;
        if (raw < 0 && raw % spacing != 0) floor -= spacing;
        // Round economic launch valuation UP, never grant a price below the request.
        r.tick = floor;
        if (token0 && _valuation(TickMath.getSqrtPriceAtTick(floor), true, supply) < valuation) r.tick += spacing;
        int24 min = TickMath.minUsableTick(spacing);
        int24 max = TickMath.maxUsableTick(spacing);
        if (r.tick <= min || r.tick >= max) revert InvalidPrice();
        r.price = TickMath.getSqrtPriceAtTick(r.tick);
        r.lower = token0 ? r.tick : min;
        r.upper = token0 ? max : r.tick;
        uint160 lo = TickMath.getSqrtPriceAtTick(r.lower);
        uint160 hi = TickMath.getSqrtPriceAtTick(r.upper);
        uint256 l = token0
            ? FullMath.mulDiv(supply, FullMath.mulDiv(lo, hi, Q96), hi - lo)
            : FullMath.mulDiv(supply, Q96, hi - lo);
        if (l == 0 || l > type(uint128).max) revert InvalidPrice();
        r.liquidity = uint128(l);
        r.tokenUsed = token0
            ? SqrtPriceMath.getAmount0Delta(lo, hi, r.liquidity, true)
            : SqrtPriceMath.getAmount1Delta(lo, hi, r.liquidity, true);
        if (r.tokenUsed > supply) revert InvalidPrice();
        // Economic valuation in quote raw units; independent of quote decimals.
        r.valuation = _valuation(r.price, token0, supply);
    }

    function _valuation(uint160 price, bool token0, uint256 supply) private pure returns (uint256) {
        return token0
            ? FullMath.mulDiv(FullMath.mulDiv(supply, price, Q96), price, Q96)
            : FullMath.mulDiv(FullMath.mulDiv(supply, Q96, price), Q96, price);
    }
}
