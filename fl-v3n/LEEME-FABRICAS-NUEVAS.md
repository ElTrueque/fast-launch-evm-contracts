# Fast Launch con supply a elección en BNB, HyperEVM, Arc y Robinhood (12/10/2026)

Cada red conserva su DEX actual:
- BNB Chain -> PancakeSwap v3 e HyperEVM -> Project X: fábrica CL nueva (src/cl/), script/DeployFastLaunchCLNets.s.sol.
- Arc y Robinhood Chain -> Uniswap v4: la fábrica de Ethereum y Base (FactoryETH, sin cambios), script/DeployFastLaunchNets.s.sol.

Cambios de contrato (todo lo demás es idéntico a lo desplegado y verificado en Ethereum y Base):
- src/FastLaunchRegistry.sol (cambios-registro.diff): tipo Crypto al final del enum; monedas de 6, 8 o 18 decimales.
- src/cl/ (cambios-cl.diff): la fábrica CL usa FastLaunchTokenETH y FastLaunchMathETH (las piezas con supply de
  Ethereum y Base), valida el supply de 1.000 a 1 billón de tokens enteros (igual que FactoryETH), lo guarda en
  launches() y lo emite en Launched; el bloqueo informa lo bloqueado según lo recibido; los componentes despliegan
  FastLaunchHolderRewardsETH (tope de elegibles = totalSupply del token, no 1.000.000).

Pares: script/FastLaunchNetQuotes.sol, copiados de los registros EN PRODUCCIÓN (tipo, decimales, mínimo, máximo,
evidencia y fuente oficial de la web), más ASTER, BTCB, GLDon y SLVon en BNB.

Pruebas (contra copias de las redes reales; HyperEVM necesita --disable-block-gas-limit):
  forge test --match-contract "FastLaunchCLNets|FastLaunchNets|FastLaunchCLBnbForkTest|FastLaunchCLHyperForkTest" --disable-block-gas-limit
Despliegue: DESPLIEGUE.md. Lo de historico/ no se usa.
