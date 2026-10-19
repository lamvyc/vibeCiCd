#!/usr/bin/env bash
# Verify an Argo CD deployment: sync/health, rollout status, and live endpoints.
# Usage: verify-deploy.sh <dev|prod> <expected-app-sha> <image-tag>
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$ROOT/versions.env"

ENV_NAME="${1:?usage: verify-deploy.sh <dev|prod> <sha> <tag>}"
EXPECTED_SHA="${2:?expected app sha required}"
TAG="${3:?image tag required}"
NS="lowcode-${ENV_NAME}"
APP="lowcode-${ENV_NAME}"
KUBECONFIG="${KUBECONFIG:-$RUNTIME/kubeconfig}"
export KUBECONFIG
require_cmd kubectl curl jq
[ -f "$KUBECONFIG" ] || die "missing kubeconfig at $KUBECONFIG"

mkdir -p "$RUNTIME/deployments" "$RUNTIME/logs"
LOG="$RUNTIME/logs/verify-${ENV_NAME}-${TAG}.log"
: > "$LOG"

log "waiting for Argo CD application ${APP} (Synced/Healthy)"
sync=""; health=""
for i in $(seq 1 60); do
  sync=$(kubectl -n argocd get application "$APP" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
  health=$(kubectl -n argocd get application "$APP" -o jsonpath='{.status.health.status}' 2>/dev/null || true)
  echo "attempt=${i} sync=${sync:-none} health=${health:-none}" >> "$LOG"
  if [ "$sync" = "Synced" ] && [ "$health" = "Healthy" ]; then break; fi
  sleep 3
done
if [ "$sync" != "Synced" ] || [ "$health" != "Healthy" ]; then
  kubectl -n argocd get application "$APP" -o yaml > "$RUNTIME/logs/${APP}-application.yaml" 2>&1 || true
  kubectl -n "$NS" get pods -o wide >> "$LOG" 2>&1 || true
  kubectl -n "$NS" get events --sort-by=.lastTimestamp >> "$LOG" 2>&1 || true
  die "Argo CD app not healthy: sync=${sync:-none} health=${health:-none}; see $LOG"
fi

log "waiting for deployment rollout"
kubectl -n "$NS" rollout status deployment/lowcode-web --timeout=180s | tee -a "$LOG"

log "starting port-forward for endpoint checks"
kubectl -n "$NS" port-forward svc/lowcode-web 18081:80 > "$RUNTIME/logs/port-forward-${ENV_NAME}.log" 2>&1 &
PF_PID=$!
cleanup() { kill "$PF_PID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

for i in $(seq 1 30); do
  if curl -fsS --max-time 2 http://127.0.0.1:18081/healthz >/dev/null 2>&1; then break; fi
  sleep 1
done

healthz=$(curl -fsS --max-time 5 http://127.0.0.1:18081/healthz)
readyz=$(curl -fsS --max-time 5 http://127.0.0.1:18081/readyz)
version_json=$(curl -fsS --max-time 5 http://127.0.0.1:18081/api/version)
html_ok=$(curl -fsS --max-time 5 http://127.0.0.1:18081/ | grep -ci '<!doctype html>' || true)
live_commit=$(printf '%s' "$version_json" | jq -r '.commit')

if [ "$html_ok" -lt 1 ]; then die "frontend HTML check failed"; fi
if [ "$live_commit" != "$EXPECTED_SHA" ]; then
  die "live commit ${live_commit} != expected ${EXPECTED_SHA}"
fi

digest=$(kubectl -n "$NS" get deployment lowcode-web \
  -o jsonpath='{.spec.template.spec.containers[0].image}')
record="$RUNTIME/deployments/${ENV_NAME}-${TAG}.json"
jq -n \
  --arg env "$ENV_NAME" --arg app "$APP" --arg tag "$TAG" \
  --arg image "$digest" --arg sha "$EXPECTED_SHA" \
  --arg sync "$sync" --arg health "$health" \
  --arg healthz "$healthz" --arg readyz "$readyz" \
  --arg version "$version_json" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{env:$env,application:$app,tag:$tag,image:$image,commit:$sha,sync:$sync,health:$health,healthz:$healthz,readyz:$readyz,version:($version|fromjson),verifiedAt:$ts}' \
  > "$record"
log "deployment verified: $record"
cat "$record"
