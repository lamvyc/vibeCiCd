#!/usr/bin/env bash
# Start the local Zot OCI registry with htpasswd authentication.
# The Docker daemon must be running and localhost:5001 must be configured as an
# insecure registry (Colima: docker.insecure-registries).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$ROOT/versions.env"
load_env

require_cmd docker openssl
REG_HOME="$RUNTIME/registry"
mkdir -p "$REG_HOME/data"

if [ ! -s "$REG_HOME/htpasswd" ]; then
  umask 077
  hash=$(openssl passwd -apr1 "$REGISTRY_PASSWORD")
  printf '%s:%s\n' "$REGISTRY_USER" "$hash" > "$REG_HOME/htpasswd"
  chmod 600 "$REG_HOME/htpasswd"
  log "generated htpasswd for ${REGISTRY_USER}"
fi

if docker container inspect lowcode-zot >/dev/null 2>&1; then
  log "removing previous Zot container"
  docker rm -f lowcode-zot >/dev/null
fi

log "starting Zot on 127.0.0.1:${REGISTRY_PORT} -> 5000"
docker run -d --name lowcode-zot --restart unless-stopped \
  -p "127.0.0.1:${REGISTRY_PORT}:5000" \
  -v "$REG_HOME/data:/var/lib/registry" \
  -v "$ROOT/platform/registry/zot-config.json:/etc/zot/config.json:ro" \
  -v "$REG_HOME/htpasswd:/etc/zot/htpasswd:ro" \
  "$ZOT_IMAGE" serve /etc/zot/config.json >/dev/null

log "waiting for registry"
for i in $(seq 1 60); do
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 2 "http://127.0.0.1:${REGISTRY_PORT}/v2/" 2>/dev/null || true)
  if [ "$code" = "401" ]; then break; fi
  if [ "$code" = "200" ]; then
    warn "registry responded 200 without auth; check the auth config"
    break
  fi
  sleep 1
done
code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 2 "http://127.0.0.1:${REGISTRY_PORT}/v2/" 2>/dev/null || true)
[ "$code" = "401" ] || die "registry auth check failed (got HTTP ${code:-none})"

log "testing docker login/push permissions"
set +x
echo "$REGISTRY_PASSWORD" | docker login "127.0.0.1:${REGISTRY_PORT}" -u "$REGISTRY_USER" --password-stdin >/dev/null
set -e
log "registry ready: http://127.0.0.1:${REGISTRY_PORT} (auth required)"
docker ps --filter name=lowcode-zot --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
