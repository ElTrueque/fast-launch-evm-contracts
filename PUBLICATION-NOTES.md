# Publication hygiene

Contract sources, deployment scripts, project tests, compiler settings and Standard JSON inputs are unchanged from the approved R3 package. The bundled forge-std dependency contained a default Sepolia Infura URL with an embedded project identifier. The public copy replaces that URL with https://sepolia.drpc.org in lib/forge-std/src/StdChains.sol . This only changes a test/deployment-tool default for Sepolia, not any contract source or the four deployed mainnets. No private RPC URL is published. The original package remains untouched. Published contract bytecode is checked again after this substitution.

The source comparison recorded in verification/manifest.json is the comparison of the original deployment folder against approved R3. SOURCE-SHA256.json describes the final public files, including this documented dependency-only substitution.

Third-party forge-std self-tests are omitted, including their universal example wallet mnemonic. All Fast Launch project tests in fl-v3n/test are retained. This does not alter compiler inputs for the deployed contracts.
