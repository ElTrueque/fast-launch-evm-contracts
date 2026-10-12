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

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title Fast Launch by El Trueque
/// @author El Trueque
/// @notice Administration affects future launches only; it never controls tokens or positions.
contract FastLaunchRegistryB20 is Ownable2Step {
    enum Kind {
        Disabled,
        Native,
        Stablecoin,
        Stock,
        StockPlain
    }

    struct Quote {
        Kind kind;
        uint8 decimals;
        uint128 minValuation;
        uint128 maxValuation;
        bytes32 evidenceHash;
    }

    struct Opening {
        uint32 durationSeconds;
        uint24 initialFee;
        uint24 normalFee;
        uint16 openingBuyBps;
        uint16 creatorBuyBps;
        int24 tickSpacing;
    }
    mapping(address => Quote) public quotes;
    Opening public opening;
    uint256 public creationFee;
    address payable public immutable treasury;
    uint256 public revision;
    address public snapshotSigner;
    error InvalidConfiguration();
    event QuoteConfigured(address indexed quote, Quote configuration, string officialSource, uint256 revision);
    event OpeningConfigured(Opening configuration, uint256 nativeFee, uint256 revision);
    event SnapshotSignerConfigured(address indexed signer, uint256 revision);

    constructor(address admin, address payable treasury_, Opening memory defaults, uint256 fee) Ownable(admin) {
        if (treasury_ == address(0)) revert InvalidConfiguration();
        treasury = treasury_;
        _setOpening(defaults, fee);
    }

    function configureQuote(address currency, Quote calldata q, string calldata officialSource) external onlyOwner {
        if (q.kind == Kind.Disabled) {
            delete quotes[currency];
        } else {
            if (
                q.minValuation == 0 || q.maxValuation <= q.minValuation || q.evidenceHash == bytes32(0)
                    || bytes(officialSource).length == 0
            ) revert InvalidConfiguration();
            if (currency == address(0)) {
                if (q.kind != Kind.Native || q.decimals != 18) revert InvalidConfiguration();
            } else {
                // Base's B20 tokens (Coinbase tokenized stocks) are native precompiles that expose a one-byte 0xEF
                // marker as code and use 8 decimals: the code check stays, 8 decimals is accepted.
                if (
                    q.kind == Kind.Native || currency.code.length == 0 || (q.decimals != 6 && q.decimals != 8 && q.decimals != 18)
                        || IERC20Metadata(currency).decimals() != q.decimals
                ) revert InvalidConfiguration();
                if (q.kind == Kind.Stock) {
                    (bool ok, bytes memory data) = currency.staticcall(abi.encodeWithSignature("uiMultiplier()"));
                    if (
                        (q.decimals != 8 && q.decimals != 18) || !ok || data.length != 32
                            || abi.decode(data, (uint256)) == 0
                    ) {
                        revert InvalidConfiguration();
                    }
                }
            }
            quotes[currency] = q;
        }
        emit QuoteConfigured(currency, q, officialSource, ++revision);
    }

    function configureOpening(Opening calldata o, uint256 fee) external onlyOwner {
        _setOpening(o, fee);
    }

    /// @notice Applies only to new holder-reward vaults; existing vault signers are immutable.
    function configureSnapshotSigner(address signer) external onlyOwner {
        if (signer == address(0)) revert InvalidConfiguration();
        snapshotSigner = signer;
        emit SnapshotSignerConfigured(signer, ++revision);
    }

    function _setOpening(Opening memory o, uint256 fee) private {
        if (
            o.durationSeconds == 0 || o.durationSeconds > 3600 || o.normalFee == 0 || o.initialFee < o.normalFee
                || o.initialFee > 900000 || o.openingBuyBps == 0 || o.openingBuyBps > 10000
                || o.creatorBuyBps > o.openingBuyBps
                || o.tickSpacing <= 0 || o.tickSpacing > 32767
        ) revert InvalidConfiguration();
        opening = o;
        creationFee = fee;
        emit OpeningConfigured(o, fee, ++revision);
    }

    function configuration(address currency) external view returns (Quote memory, Opening memory, uint256, bytes32) {
        return (
            quotes[currency],
            opening,
            creationFee,
            keccak256(
                abi.encode(
                    block.chainid,
                    address(this),
                    currency,
                    quotes[currency],
                    opening,
                    creationFee,
                    treasury,
                    snapshotSigner,
                    revision
                )
            )
        );
    }
}
