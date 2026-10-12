// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FastLaunchRegistry} from "../src/FastLaunchRegistry.sol";

/// Pair currencies for the supply-choice factories (12/10/2026). Existing pairs copy, unchanged, the on-chain
/// configuration of each network's registry IN PRODUCTION (kind, decimals, min/max valuation, evidence hash) and the
/// official source the website shows for it. New BNB pairs follow the Ethereum deployment convention.
/// Production registries: BNB 0x24A7FB8b683884543f6e2ca3E12E33C3b6865B1E (PancakeSwap v3), HyperEVM
/// 0x4c6a32C6B8c719a66a96B385074B04C3F5A0d14B (Project X), Arc 0xB9A0588B9E6CC963a58BC54854BA2b1C8be391Ea and
/// Robinhood 0xbFb2F411B8fA72E97975f1592D2b6548F84dba0E (Uniswap v4).
library FastLaunchNetQuotes {
    struct Entry {
        address currency;
        FastLaunchRegistry.Quote q;
        string source;
        string symbol;
    }

    function bnb() internal pure returns (Entry[] memory e) {
        e = new Entry[](20);
        e[0] = Entry(0x0000000000000000000000000000000000000000, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Native, 18, 1304903828587833077, 130490382858783307670, 0xba31135375ae2565f7cf52af9f602f2cf0f89d76913e08fabfdd3c73277f172e), "https://docs.bnbchain.org/", "BNB");
        e[1] = Entry(0x55d398326f99059fF775485246999027B3197955, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stablecoin, 18, 1000000000000000000000, 100000000000000000000000, 0xeff6d0001302278bb18f2edf038ead6cf2902fd338c8eebb79f30e17a3387ed1), "https://www.binance.com/en/collateral-btokens", "USDT");
        e[2] = Entry(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stablecoin, 18, 1000000000000000000000, 100000000000000000000000, 0x85d259598054ca92229016171b82d838365b9f4e43b19cae3e38c1cece5cd2b0), "https://www.binance.com/en/collateral-btokens", "USDC");
        e[3] = Entry(0x02Fca66C1D1aFB4E2A7884261eB00F63598a7436, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 4142150000000000000, 414215000000000000000, 0xe1598971ef47f7d643153266059469e31b498fec0a224c920db3c7c2abb33666), "https://www.bnbchain.org/en/blog/introducing-bstocks-on-bnb-chain-trade-24-7-with-zero-fees-deploy-across-defi-protocols-with-full-self-custody", "NVDAB");
        e[4] = Entry(0x205812CdBed920aFf76C6580abD681a46D11efc7, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 1316370000000000000, 131637000000000000000, 0xe15e87a232ac04ead0a629c4ae666886f62771724a71d8467b96d7fcf94755c5), "https://www.bnbchain.org/en/blog/introducing-bstocks-on-bnb-chain-trade-24-7-with-zero-fees-deploy-across-defi-protocols-with-full-self-custody", "QQQB");
        e[5] = Entry(0x5b1910eAaD6450E50f816082Aa078C41F10C292f, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 2615190000000000000, 261519000000000000000, 0x27150a6e421406f933c4f950cd1bfe6564d00e148c16ae4a306fcc9606a5a3cc), "https://www.bnbchain.org/en/blog/introducing-bstocks-on-bnb-chain-trade-24-7-with-zero-fees-deploy-across-defi-protocols-with-full-self-custody", "TSLAB");
        e[6] = Entry(0x431a3BEE82E2ca41e49895CbECE5bB0F76A89b7A, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 2998860000000000000, 299886000000000000000, 0xf5dd15e6e185818b71275a04aaf4d37a2416a5e12b16a8a6d5b1592ab8ed76d1), "https://www.bnbchain.org/en/blog/introducing-bstocks-on-bnb-chain-trade-24-7-with-zero-fees-deploy-across-defi-protocols-with-full-self-custody", "AAPLB");
        e[7] = Entry(0x3F53De71c126BdaBAe20f9cD64848d317f6C3238, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 2872750000000000000, 287275000000000000000, 0x1a2acbe2c2f52cced54de4bee18e4c9eb9d1fa153d5983174905079b787157e6), "https://www.bnbchain.org/en/blog/introducing-bstocks-on-bnb-chain-trade-24-7-with-zero-fees-deploy-across-defi-protocols-with-full-self-custody", "GOOGLB");
        e[8] = Entry(0x80f3D493EBCe97e343c53D29a137942416B4ffC0, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 11845500000000000000, 1184550000000000000000, 0xfa5af564faba04799c85b88a915a74051217c1fcf5550e7eb083df224d54de7e), "https://www.bnbchain.org/en/blog/introducing-bstocks-on-bnb-chain-trade-24-7-with-zero-fees-deploy-across-defi-protocols-with-full-self-custody", "CRCLB");
        e[9] = Entry(0x7138b48df7D98D7e3cc221BfE7192D0a178182D8, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 1283570000000000000, 128357000000000000000, 0xc7a1d8104f5a8e677ec740a3902750dc9667c9db008942ff7b869107657a516a), "https://www.bnbchain.org/en/blog/introducing-bstocks-on-bnb-chain-trade-24-7-with-zero-fees-deploy-across-defi-protocols-with-full-self-custody", "SPYB");
        e[10] = Entry(0xE87afb3076AeB0f9B14E368DE8145ae6a2826A14, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 5999880000000000000, 599988000000000000000, 0xd150735649bb744d8925bf3bccb0e5e2da7a309fd1e0e7798d61e23830f5000b), "https://www.bnbchain.org/en/blog/introducing-bstocks-on-bnb-chain-trade-24-7-with-zero-fees-deploy-across-defi-protocols-with-full-self-custody", "MSTRB");
        e[11] = Entry(0x80106cb3EAD06659A5ad19DF39D9b4733863B9b0, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 1888390000000000000, 188839000000000000000, 0xe93a9bee791cafffa2e4e394b024c749213eedfab5a72d5a71b86f67f1b90f7f), "https://www.bnbchain.org/en/blog/introducing-bstocks-on-bnb-chain-trade-24-7-with-zero-fees-deploy-across-defi-protocols-with-full-self-custody", "MSFTB");
        e[12] = Entry(0xA394dCEa3fd3847fD793afBFd163E2e3858B7c65, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 8669260000000000000, 866926000000000000000, 0x4d070f3b08c7b5b00451c9ea9943dbf7ffafaff4af76ece43e7276d4738558e0), "https://www.bnbchain.org/en/blog/introducing-bstocks-on-bnb-chain-trade-24-7-with-zero-fees-deploy-across-defi-protocols-with-full-self-custody", "HOODB");
        e[13] = Entry(0x1a4b499833A79A09ad7Cf1D42D7DacF71e92eb00, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 3951360000000000000, 395136000000000000000, 0xe07dcfea8f6cbf048f90f06edcba8099903ef999bf79a648bdc52a844e45158d), "https://www.bnbchain.org/en/blog/introducing-bstocks-on-bnb-chain-trade-24-7-with-zero-fees-deploy-across-defi-protocols-with-full-self-custody", "AMZNB");
        e[14] = Entry(0x3eE4dF61bd4F867E349BEaE8bFE07bc31b4850fb, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 585247000000000000, 58524700000000000000, 0xac0269f4e21423441cc822d40f0bc5d76267f3ad92bfd332ba9182657fda29a3), "https://www.bnbchain.org/en/blog/introducing-bstocks-on-bnb-chain-trade-24-7-with-zero-fees-deploy-across-defi-protocols-with-full-self-custody", "SNDKB");
        e[15] = Entry(0x7425889FE94F9d693E8daefE88BCCed6AcFEf4c0, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 1340780000000000000, 134078000000000000000, 0x47fae0c6b95c0c1ab0cc79b30fb7cf498a303f71097501ce5ac4b0c4fd7ce47d), "https://www.bnbchain.org/en/blog/introducing-bstocks-on-bnb-chain-trade-24-7-with-zero-fees-deploy-across-defi-protocols-with-full-self-custody", "METAB");
        e[16] = Entry(0x000Ae314E2A2172a039B26378814C252734f556A, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Crypto, 18, 1396000000000000000000, 139626000000000000000000, 0x2090f4bca502929aa12390df9488adf2cb7ab00024dab0e75cbb359cce01f2c6), "https://www.asterdex.com/en", "ASTER");
        e[17] = Entry(0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Crypto, 18, 11900000000000000, 1190000000000000000, 0x153e0c1b4bd86b0f5cf9f34a72eae04db6a8ac143793d0dd860b995caa356019), "https://www.binance.com/en/collateral-btokens", "BTCB");
        e[18] = Entry(0xfA9a1E901085e269f6D428F79Cd5252d8b919344, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.StockPlain, 18, 2590000000000000000, 259280000000000000000, 0xb8a23f400c759e068087c90adf0bbf3b1346c8fa6c1226ccaa9784ad705980cb), "https://github.com/ondoprotocol/ondo-global-markets-token-list/blob/main/tokenlist.json", "GLDon");
        e[19] = Entry(0x8b872732b07be325a8803CDB480D9d20B6f8d11B, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.StockPlain, 18, 18070000000000000000, 1807330000000000000000, 0x5a32aea70e82c1521e653519587044929b0307a43ab015d1b9090a587e50c468), "https://github.com/ondoprotocol/ondo-global-markets-token-list/blob/main/tokenlist.json", "SLVon");
    }

    function hyperevm() internal pure returns (Entry[] memory e) {
        e = new Entry[](3);
        e[0] = Entry(0x0000000000000000000000000000000000000000, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Native, 18, 11316697787585582528, 1131669778758558252701, 0xfc1347a5fdb3737f8dd8bf27f91cd8785cdd2a4ececedbfa9abd1196e16794db), "https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm", "HYPE");
        e[1] = Entry(0xb88339CB7199b77E23DB6E890353E22632Ba630f, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stablecoin, 6, 1000000000, 100000000000, 0x7f3343de5067b9b532eb0f9747108c6815e19406042f57613093eb70a88dd429), "https://developers.circle.com/stablecoins/usdc-contract-addresses", "USDC");
        e[2] = Entry(0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stablecoin, 6, 1000000000, 100000000000, 0x69e3d735e850bc8b6f4c8d7910e0c1c9f85e8764b2bb6385ab88b33d9d3c1c0d), "https://docs.usdt0.to/technical-documentation/deployments", "USDT0");
    }

    function arc() internal pure returns (Entry[] memory e) {
        e = new Entry[](1);
        e[0] = Entry(0x3600000000000000000000000000000000000000, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stablecoin, 6, 1000000000, 100000000000, 0xb2880f5dfdb41033b5bea5196cf77b0adb22a42fb3562d647a8a03a5ea2c6717), "https://docs.arc.network/arc/references/contract-addresses", "USDC");
    }

    function robinhood() internal pure returns (Entry[] memory e) {
        e = new Entry[](14);
        e[0] = Entry(0x0000000000000000000000000000000000000000, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Native, 18, 373398354433452012, 37339835443345201177, 0x5aaf07cb03453826427e9aa81ef9bbdb0e623ade2e3c2a4e794f4eef539d6792), "https://docs.robinhood.com/chain/connecting/", "ETH");
        e[1] = Entry(0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stablecoin, 6, 1000000000, 100000000000, 0x3e923357c9fec4a143997c7739234247bacfd7879e4bd952532e113e5137e3a0), "https://docs.robinhood.com/chain/contracts/", "USDG");
        e[2] = Entry(0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 2995142844911360437, 299514284491136043673, 0xc6369606af98af3e14a320fe15399524823f40a0beebfdb626df63da67abeba3), "https://api.robinhood.com/rhj/assets", "AAPL");
        e[3] = Entry(0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 4262998106792762023, 426299810679276202271, 0x4b499bdd596144395ceb2c3b1062ce5a72672ca5d86a4098bdfe6d6281390df9), "https://api.robinhood.com/rhj/assets", "NVDA");
        e[4] = Entry(0x322F0929c4625eD5bAd873c95208D54E1c003b2d, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 2694945629471925404, 269494562947192540390, 0x0613a702d2f8407dd1dfba29feac697a9eae6defca75d35ca5d6c5d4d4eb3388), "https://api.robinhood.com/rhj/assets", "TSLA");
        e[5] = Entry(0x86923f96303D656E4aa86D9d42D1e57ad2023fdC, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 1579342203972045643, 157934220397204564298, 0x936d7cac440dd0b228085ce683561d5d5ca4a584bb8cd38ade94c6e0bbc7fddf), "https://api.robinhood.com/rhj/assets", "AMD");
        e[6] = Entry(0xe93237C50D904957Cf27E7B1133b510C669c2e74, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 1931159015249381904, 193115901524938190309, 0xd0cdbcfb9680ac88ab3a297d6aa4d9cbb0b5f46bf393c0d9e987c9edf763636f), "https://api.robinhood.com/rhj/assets", "MSFT");
        e[7] = Entry(0x2e0847E8910a9732eB3fb1bb4b70a580ADAD4FE3, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 2906032970062853298, 290603297006285329776, 0xcd689de0b15d634ef64adc8667913b9f0b228e5e78754ff788420694f46a664e), "https://api.robinhood.com/rhj/assets", "GOOGL");
        e[8] = Entry(0x894E1EC2D74FFE5AEF8Dc8A9e84686acCB964F2A, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 5298481111442036580, 529848111144203657972, 0x7da6bc3c9cd33d099744a38344da4298e14f5224443eb877c22d9e48095c27d2), "https://api.robinhood.com/rhj/assets", "PLTR");
        e[9] = Entry(0x7066A64c24e4206CD62E83bf198c1E7EB361F51e, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 35975685041799428937, 3597568504179942893636, 0x143a91920064dfbe59c7bc4d46c05881940a23a6d103f6d52e818684381314c8), "https://api.robinhood.com/rhj/assets", "PFE");
        e[10] = Entry(0x03DfbBE0AC4E7bCDaFd08eD41A400326B77D8c80, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 3907119942076173034, 390711994207617303379, 0xb8f7bca5d3c460ed6fa9c90b19f0c6a3c733d766d5393bd4fa1b733f6aab81c3), "https://api.robinhood.com/rhj/assets", "JNJ");
        e[11] = Entry(0x8005d266423c7ea827372c9c864491e5786600ea, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 873826826564778706, 87382682656477870535, 0xdea03e17d3c9a1de7bc3081aca7f605fa441a66b874eb912edab18fae0b94c25), "https://api.robinhood.com/rhj/assets", "LLY");
        e[12] = Entry(0xC9a981FEE1F9DEc688bb123ccDeCc63D0deBFC4e, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 2600000000000000000, 259570000000000000000, 0xea5a5addd7e4a8b1579b0cafdbda96162d71601c11d0a97bc225586bc804f803), "https://api.robinhood.com/rhj/assets", "GLD");
        e[13] = Entry(0x411eFb0E7f985935DAec3D4C3ebaEa0d0AD7D89f, FastLaunchRegistry.Quote(FastLaunchRegistry.Kind.Stock, 18, 18090000000000000000, 1808640000000000000000, 0xd0e86ee915f8e058a18115f481026b2867f9f3d69146fcf3a193048ce58dba54), "https://api.robinhood.com/rhj/assets", "SLV");
    }

}
