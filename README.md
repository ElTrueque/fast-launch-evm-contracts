# El Trueque Fast Launch EVM contracts

Approved variable-supply sources deployed on BNB Chain (PancakeSwap v3), HyperEVM (Project X), Arc and Robinhood Chain (Uniswap v4).

- [Source project](fl-v3n/) contains the reviewed sources, scripts, tests and vendored dependencies.
- [Deployed addresses and explorer links](DEPLOYMENTS.md); machine-readable constructors and creation transactions in [DEPLOYMENTS.json](DEPLOYMENTS.json).
- [Runtime verification](verification/runtime-verification.json): all 12 deployed runtime bytecodes match, including immutable values independently checked through getters. Metadata bytes are retained.
- [Standard JSON inputs](verification/standard-json/) reproduce all five contract classes exactly; see [comparison](verification/standard-json-reproducibility.json).
- [Deployment recovery guide](fl-v3n/DESPLIEGUE.md). Contracts are already deployed; publishing this repository sends no blockchain transactions.

## Reproducible compilation

Forge 1.8.1, Solidity v0.8.26+commit.8a97fa7a; Cancun, viaIR, optimizer 200, metadata.bytecodeHash none. From fl-v3n run forge build. Vendored libraries are included; no dependency installation is needed. Each source retains its SPDX license and dependency license files are preserved.

32 supplied fork tests and 8 independent review tests passed in R2. R3 only changed DESPLIEGUE.md. This publication additionally recompiled five Standard JSON inputs and checked all 12 deployed runtime contracts. Internal components' creation input was taken from the deployment journal; runtime, deterministic CREATE address, getters and parent transaction receipt were independently checked. No historical execution trace was used.

## Provenance and publication scope

Approved original ZIP SHA-256: 83f616541450aa00ce82c002e66aba969cd2e96365055d004c65d074cfd4bcf2. This public source bundle omits historical deployment projects, wallets, keys, local caches, broadcast journals and private RPC configuration. Constructor arguments and transaction hashes are public chain data. File checksums are in SOURCE-SHA256.json.

This clean repository does not expose the history or settings of the private verification repository. It contains no Solana code and does not change the website, bot, holder payment services, or on-chain configuration. Explorer status is reported separately from local runtime equivalence; Sourcify success does not imply explorer Exact Match.
