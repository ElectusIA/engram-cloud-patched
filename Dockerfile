# Engram Cloud — imagen validada para el ecosistema Electus (issues platform#49, #194 y #241)
#
# Por qué existe: el server de Electus necesita una identidad de build verificable en /health
# (version, patchRevision y el imageDigest que inyecta el despliegue) para que el mantenimiento
# validado del cliente (ElectusIA/electus-platform#241) compare lo vivo con lo validado.
#
# Historia del parche de issued_token: v1.19.0 y v1.20.0 rechazaban la clave booleana
# `issued_token` en la auditoría del bootstrap de tokens managed (el guard `sensitiveAuthAuditKey`
# de internal/cloud/cloudstore/identity.go veía la subcadena "token") y la imagen aplicaba un sed.
# Upstream v3.0.0 lo corrige con `auditKeyValueExempt` (exento solo si el valor es booleano):
# el sed sale y tests/electus_patch_test.go queda como regresión que PASA sin parche.
# La fuga del constructor del store (store-constructor-cleanup.patch) también la corrige v3
# (newStore cierra la DB hasta el éxito): sale el patch y queda tests/store_cleanup_test.go.
#
# Overlays vivos: tests/health_metadata.go + tests/health-metadata.patch (identidad de /health).
# Rollback: tag electus-1.20.0-patch2 (imagen v1.20.0-electus-patch2).

FROM golang:1.25.10-alpine AS builder
RUN apk add --no-cache git
WORKDIR /src
ARG ENGRAM_REF=v3.0.0
ARG ENGRAM_COMMIT=15a2f78885d7ad8ced23b2d1d88383e9bb472c17
RUN git clone --depth 1 --branch "${ENGRAM_REF}" https://github.com/Gentleman-Programming/engram.git .
RUN test "$(git rev-parse HEAD)" = "${ENGRAM_COMMIT}"

COPY tests/electus_patch_test.go internal/cloud/cloudstore/electus_patch_test.go
COPY tests/health_metadata.go internal/cloud/cloudserver/electus_metadata.go
COPY tests/health_metadata_test.go internal/cloud/cloudserver/electus_metadata_test.go
COPY tests/health-metadata.patch /tmp/health-metadata.patch
RUN git apply --check /tmp/health-metadata.patch && git apply /tmp/health-metadata.patch
COPY tests/store_cleanup_test.go internal/store/electus_cleanup_test.go
RUN go test ./internal/cloud/cloudstore ./internal/cloud/cloudserver ./internal/store -run 'TestElectusIssuedTokenAuditMetadata|TestElectusConstructorClosesDatabaseOnFailure|TestElectusHealthBuildIdentity' -count=1

RUN CGO_ENABLED=0 GOOS=linux go build \
      -ldflags="-s -w -X main.version=${ENGRAM_REF}-electus-patch3" \
      -o /out/engram ./cmd/engram

FROM alpine:3.21
RUN apk add --no-cache ca-certificates tzdata && adduser -D -u 10001 engram
USER engram
WORKDIR /home/engram
COPY --from=builder /out/engram /usr/local/bin/engram
EXPOSE 18080
ENTRYPOINT ["engram"]
CMD ["cloud", "serve"]
