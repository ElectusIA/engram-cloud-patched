# Engram Cloud — imagen parcheada para el ecosistema Electus (issue platform#49)
#
# Por qué existe: la imagen oficial ghcr.io/gentleman-programming/engram:v1.19.0 tiene un bug
# que hace IMPOSIBLE emitir tokens managed (CLI y dashboard): el guard `sensitiveAuthAuditKey`
# (internal/cloud/cloudstore/identity.go) rechaza toda clave de metadata que contenga la
# subcadena "token", y el bootstrap de tokens envía la clave booleana `issued_token` en su
# auditoría de completitud -> el audit falla -> la emisión se revierte (atómica) -> nunca hay
# primer token managed. Sin managed tokens no hay registro de usuarios por dashboard.
#
# Fix (1 línea): añadir `issued_token` a las excepciones permitidas del guard, igual que ya
# existe para `token_prefix`. `issued_token` es un booleano de telemetría, no un secreto.
#
# Mantener este repo hasta que el upstream corrija el bug; entonces volver a la imagen oficial.
# Reportado en: (pendiente — abrir issue en Gentleman-Programming/engram).

FROM golang:1.25-alpine AS builder
RUN apk add --no-cache git
WORKDIR /src
ARG ENGRAM_REF=v1.19.0
RUN git clone --depth 1 --branch "${ENGRAM_REF}" https://github.com/Gentleman-Programming/engram.git .

# Parche: permitir la clave `issued_token` (booleano) en el guard de metadata de auditoría.
RUN set -eux; \
    f=internal/cloud/cloudstore/identity.go; \
    grep -q 'key == "token_prefix"' "$f"; \
    sed -i 's/if key == "token_prefix" {/if key == "token_prefix" || key == "issued_token" {/' "$f"; \
    grep -q 'key == "issued_token"' "$f"

RUN CGO_ENABLED=0 GOOS=linux go build \
      -ldflags="-s -w -X main.version=${ENGRAM_REF}-electus-patch1" \
      -o /out/engram ./cmd/engram

FROM alpine:3.21
RUN apk add --no-cache ca-certificates tzdata && adduser -D -u 10001 engram
USER engram
WORKDIR /home/engram
COPY --from=builder /out/engram /usr/local/bin/engram
EXPOSE 18080
ENTRYPOINT ["engram"]
CMD ["cloud", "serve"]
