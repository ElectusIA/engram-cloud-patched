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

Multi-stage: clona el tag `ENGRAM_REF` (default `v1.19.0`), aplica el parche por `sed` (con
verificación pre y post), y compila el binario Go. Runtime `alpine`, usuario no-root, mismo
`ENTRYPOINT`/`CMD`/puerto que la imagen oficial (`cloud serve` en `:18080`).

## Provisional

Mantener hasta que el upstream corrija el bug; entonces volver a la imagen oficial pineada.
