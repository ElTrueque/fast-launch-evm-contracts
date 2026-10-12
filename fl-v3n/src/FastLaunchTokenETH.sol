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

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Fast Launch by El Trueque
/// @author El Trueque
/// @notice Supply chosen by the creator at launch, minted once. No owner, mint entry point, tax, pause or burn extension.
contract FastLaunchTokenETH is ERC20 {
    string public metadataCID;
    event MetadataCommitted(string cid);

    constructor(string memory name_, string memory symbol_, string memory cid_, uint256 supply_) ERC20(name_, symbol_) {
        metadataCID = cid_;
        _mint(msg.sender, supply_);
        emit MetadataCommitted(cid_);
    }
}
