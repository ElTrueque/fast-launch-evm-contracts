# Despliegue de Fast Launch con supply a elección (12/10/2026)

Única guía vigente. Lo que está en `historico/` es de versiones anteriores y NO se usa.

| Red | DEX | Script | Wallet que firma | Nonce previsto | Transacciones |
|---|---|---|---|---|---|
| BNB Chain (56) | PancakeSwap v3 | `script/DeployFastLaunchCLNets.s.sol` | 0xc570FBEB05FE1CA1bd52B7780D747021D6AAb245 | 70 | 23 |
| HyperEVM (999) | Project X | `script/DeployFastLaunchCLNets.s.sol` | 0x22DB1f7bAf9e7ECCDf7183Ab442A3EA4A7cd1210 | 42 | 6 |
| Arc (5042) | Uniswap v4 | `script/DeployFastLaunchNets.s.sol` | 0xc570FBEB05FE1CA1bd52B7780D747021D6AAb245 | 23 | 4 |
| Robinhood Chain (4663) | Uniswap v4 | `script/DeployFastLaunchNets.s.sol` | 0xc570FBEB05FE1CA1bd52B7780D747021D6AAb245 | 111 | 17 |

Cada script elige DEX y pares por `block.chainid` y revierte en cualquier otra red. Cada despliegue envía:
registro, fábrica (crea sus componentes), firmante de holders y una transacción por par
(BNB 20, HyperEVM 3, Arc 1, Robinhood 14).

## 1. Comprobaciones previas (por red, sin firmar)

1. `cast chain-id --rpc-url <RPC>` devuelve el chain id de la tabla.
2. `cast nonce <WALLET> --rpc-url <RPC>` coincide con la tabla. Si no coincide, las direcciones previstas
   cambian: avisar antes de seguir (la web y el bot se preparan con estas direcciones).
3. `cast balance <WALLET> --rpc-url <RPC> --ether` supera el costo de la simulación con margen.
4. Solo HyperEVM: la wallet tiene bloques grandes activos
   (`eth_usingBigBlocks` con la wallet como parámetro devuelve `true`; la fábrica no entra en un bloque chico).

## 2. Simulación justo antes de firmar (no envía nada)

    forge script <SCRIPT> --rpc-url <RPC> --sender <WALLET> [--disable-block-gas-limit solo en HyperEVM]

Debe imprimir REGISTRO, FABRICA, COMPONENTES y PARES iguales a los previstos en PARA-CODEX y en la web.

## 3. Envío

    forge script <SCRIPT> --rpc-url <RPC> --account <KEYSTORE> --sender <WALLET> --broadcast --slow [--disable-block-gas-limit en HyperEVM]

`--slow` envía una transacción por vez y espera su confirmación (HyperEVM acepta pocas transacciones
pendientes por cuenta). En HyperEVM, `--disable-block-gas-limit` solo evita que la simulación local previa
falle con el límite de bloque chico; en la red, las transacciones van a bloques grandes por la configuración
de la wallet.

## 4. Qué guardar

- La salida de la consola (direcciones) y `broadcast/<script>/<chainid>/run-latest.json` (hashes y recibos).
- Comprobar en la cadena: `registry.configuration(par)` de cada par, `factory.registry()`,
  `factory.components()` y el código de los tres contratos.

## 5. Si el envío se corta a mitad

Orden de las transacciones de cada script: 1) crear el registro, 2) crear la fábrica (crea sus componentes),
3) `configureSnapshotSigner`, 4) un `configureQuote` por par. Las direcciones del registro y de la fábrica
dependen del nonce de la wallet en el momento de crearlas.

1. NO volver a correr el script desde cero: desplegaría otro registro y otra fábrica en otras direcciones.
2. Guardar el diario de forge: `broadcast/<script>/<chainid>/run-latest.json` y su par en
   `cache/<script>/<chainid>/run-latest.json`.
3. Comprobar, sin firmar: el recibo de cada transacción del diario (`cast receipt <hash>`), el nonce `latest` y
   `pending` de la wallet (`cast nonce <WALLET> --block latest` y `--block pending`) y el código real en las
   direcciones previstas del registro, la fábrica y los componentes (`cast code <dirección>`). Que una dirección
   figure en el diario no prueba que el contrato exista.
4. Si el registro existe y la creación de la fábrica NO se envió: lo siguiente tiene que ser crear la fábrica,
   con el nonce que le correspondía y los mismos argumentos, ANTES de cualquier `configureSnapshotSigner` o
   `configureQuote` (que consumirían ese nonce y moverían la dirección de la fábrica y de sus componentes).
   Hacerlo con la reanudación controlada del diario original:
   `forge script <SCRIPT> --rpc-url <RPC> --account <KEYSTORE> --sender <WALLET> --resume --slow [--disable-block-gas-limit en HyperEVM]`.
   `--resume` ENVÍA transacciones: no es una simulación.
5. Si una creación falló y consumió su nonce, o la wallet envió cualquier otra transacción en medio: detenerse.
   Las direcciones previstas ya no son alcanzables; hay que recalcularlas y avisar antes de seguir, porque la
   web y el bot se preparan con ellas. No prometer que una reanudación conserve direcciones que ya no se pueden obtener.
6. Solo con registro, fábrica y componentes comprobados (código presente, `factory.registry()` = registro y
   `factory.components()` = componentes previstos), completar lo que falte desde la misma wallet:
   `configureSnapshotSigner(0x785C44F1428Bf1366127aE68fdD8D0fA22D524ef)` si `registry.snapshotSigner()` es otro,
   y `configureQuote` de cada par cuya configuración no coincida en TODOS sus valores (tipo, decimales, mínimo,
   máximo y evidencia) con `script/FastLaunchNetQuotes.sol`.

## 6. Después

- Verificación de registro, fábrica y componentes en Sourcify (con la compilación de este proyecto y la
  transacción de creación).
- Publicar la web, el bot y los pagos a holders que conocen las fábricas nuevas.
- Recién después: en Ethereum, `configureQuote` de tBTC, GLDon y SLVon; en Base, de cbBTC
  (cbBTC NO va en Ethereum: su registro rechaza 8 decimales).
