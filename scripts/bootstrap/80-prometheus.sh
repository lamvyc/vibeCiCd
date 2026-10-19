#!/usr/bin/env bash
# Deploy the lightweight Prometheus instance that scrapes lowcode-web /metrics.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$ROOT/versions.env"
load_env

export KUBECONFIG="${KUBECONFIG:-$RUNTIME/kubeconfig}"
[ -f "$KUBECONFIG" ] || die "missing kubeconfig at $KUBECONFIG"
kubectl apply -f "$ROOT/platform/prometheus/manifests.yaml" >/dev/null
kubectl -n monitoring rollout status deployment/prometheus --timeout=240s
log "Prometheus ready: kubectl -n monitoring port-forward svc/prometheus 9090:9090"
