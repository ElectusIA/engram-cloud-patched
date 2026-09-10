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

## Correcciones de Windows (2026-09-10)

La suite inicial fall?: autosync observaba un estado transitorio entre ciclos cada 10 ms;
la prueba de migraci?n descartaba un resultado SQL abierto; y Store.New ten?a una fuga
real del handle cuando fallaba la inicializaci?n. El retry inicial de MCP pas?.
Todos esos resultados hist?ricos se conservan en validation-evidence.json.

- tests/store-constructor-cleanup.patch cierra la base al fallar pragma, migraci?n o reparaci?n.
  Conserva el error original y cualquier error de cierre mediante errors.Join. No cambia la API.
  Tambi?n corrige newWithoutRepair, que comparte el mismo ciclo de vida.
- tests/store_cleanup_test.go comprueba que el handle queda cerrado, tanto ante pragma
  inv?lido como ante migraci?n fallida, en ambos constructores. Esta regresi?n fall? antes
  del parche; detecta la fuga tambi?n en Linux, donde unlink no revela archivos abiertos.
- tests/windows-test-fixtures.patch cierra sql.Rows en la prueba de idempotencia y ejecuta
  un solo ciclo dirty en la prueba de recuperaci?n de p?nico. Conserva la aserci?n
  PhaseBackoff/internal_error sin que un ciclo posterior sobrescriba el estado observado.
- tests/relations-fixture.patch completa judgment_status, marked_by_actor y marked_by_kind
  en un fixture upstream de relaciones. Son campos ya exigidos por chunkcodec; las
  aserciones permanecen intactas. Los overlays de fixtures no cambian el binario.

Docker y CI aplican el parche de constructor. CI prueba Linux con Postgres ef?mero,
Windows sin base remota y build/ejecuci?n de imagen. El script local aplica todos los
parches de forma idempotente y falla si el checkout no coincide. Para m?quina nueva:

```powershell
./validate-candidate.ps1 -GoBinary <ruta/go.exe>
```

Los resultados y hashes locales vigentes se registran en validation-evidence.json.
La ejecuci?n CI anterior (3985e8c) est? documentada como hist?rica; debe repetirse sobre
el nuevo parche antes de promover. Ning?n resultado local acredita un restore ni un
servicio productivo. El pin cliente sigue en 1.19.0 hasta que el operador verifique
backup/restore, digest, metadata y compatibilidad del servidor desplegado.
