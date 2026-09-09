# engram-cloud-patched (Electus)

Imagen Docker de [engram](https://github.com/Gentleman-Programming/engram) **cloud server**
con un único parche mínimo para el ecosistema Electus (issue `JAngelLM/electus-platform#49`).

## El bug que arregla

La imagen oficial `ghcr.io/gentleman-programming/engram:v1.19.0` **no puede emitir tokens
managed** (ni por CLI `engram cloud bootstrap admin --issue-token`, ni por el dashboard
Admin → Users). Causa: el guard `sensitiveAuthAuditKey` rechaza cualquier clave de metadata
de auditoría que contenga la subcadena `"token"`; el bootstrap envía la clave booleana
`issued_token` en su auditoría de completitud → el audit falla → la emisión atómica se
revierte → nunca existe un primer managed admin con token → el dashboard devuelve
`policy_forbidden` en toda mutación.

## El parche

Una línea: añadir `issued_token` a las excepciones permitidas del guard (junto a
`token_prefix`, que ya lo estaba). `issued_token` es un flag booleano de telemetría, no un
secreto. Ver `Dockerfile`.

## Build

Multi-stage: clona el tag `ENGRAM_REF` (default `v1.20.0`), aplica el parche por `sed` (con
verificación pre y post), y compila el binario Go. Runtime `alpine`, usuario no-root, mismo
`ENTRYPOINT`/`CMD`/puerto que la imagen oficial (`cloud serve` en `:18080`).

## Provisional

Mantener hasta que el upstream corrija el bug; entonces volver a la imagen oficial pineada.

## Candidato v1.20.0 (platform#194, sin despliegue)

Esta rama prepara `v1.20.0-electus-patch1` sobre el commit upstream
`ba9e46ced152c37a7cb9e576153c41995873e2fc`. El Dockerfile verifica el commit
resuelto por el tag y conserva exactamente la excepción `issued_token`.
`tests/electus_patch_test.go` demuestra que el booleano se admite y los campos
sensibles siguen rechazándose. El build Docker ejecuta esa regresión antes de compilar.

La regresión falló en upstream sin el parche y pasó al aplicar la línea de Electus.
Hay validación local Windows con Go portable 1.25.10 (hash oficial del ZIP:
`ca37af2dadd8544464f1a9ca7c3886499d1cdfcb263855d0a1d71f194b2bd222`).
El directorio local `artifacts/` conserva logs y binarios de ensayo; `.tools/` y
`upstream/` contienen el toolchain aislado y el checkout exacto. No se versionan.
`validate-candidate.ps1` documenta los comandos de suite y compilación.

**No promover aún**: Docker Desktop no tiene daemon disponible en el equipo de ensayo;
no se construyó una imagen ni se probó Postgres/restore. La suite amplia en Windows
reportó un fallo de temporización en autosync y errores de limpieza de temporales SQLite
por archivos abiertos; se conservan como limitaciones, sin modificar comportamiento upstream.
El pin de clientes permanece en 1.19.0 hasta imagen por digest, restore y compatibilidad
CLI/MCP verificados contra un servidor aislado y después el servidor desplegado.

La CI Linux confirmó build y ejecución de la imagen. La integración Postgres detectó un
fixture upstream incompleto en `TestWriteChunkMaterializesRelationMutationIntoCloudMutations`:
omitía `judgment_status`, `marked_by_actor` y `marked_by_kind`, campos que chunkcodec ya exige
en v1.19.0 y que el modelo serializado de relaciones contiene. `tests/relations-fixture.patch`
completa solo ese dato de prueba; conserva todas sus aserciones. Se aplica a la suite de
compatibilidad y no modifica el binario ni relaja su validación.

Resultados exactos y hashes de binarios locales: `validation-evidence.json`. La suite amplia tuvo 1.276 acciones de test/subtest PASS, 5 FAIL (incluye padre) y 29 SKIP. Autosync fall? tambi?n en retry aislado; MCP pas? el retry, conservando su fallo inicial.

En m?quina nueva: instalar Go 1.25.10 desde la distribuci?n oficial (ZIP Windows con SHA-256 arriba) y ejecutar `./validate-candidate.ps1 -GoBinary <ruta/go.exe>`. El script clona/verifica upstream, aplica el parche idempotente y a?ade la regresi?n. No descarga toolchains ni modifica el Go global. CI prueba Linux con Postgres ef?mero y construye/ejecuta la imagen sin publicarla.
