#!/usr/bin/env bash
# Read application logs through the VM's pod log files.
# `kubectl logs` fails in this lab because the API server's kubelet path
# (192.168.5.1:10250) is not reachable (Lima usernet hairpin). The kubelet log
# files on the VM are still available.
# Usage: logs.sh [dev|prod] [pod-name]
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
ENV_NAME="${1:-dev}"
NS="lowcode-${ENV_NAME}"
export KUBECONFIG="${KUBECONFIG:-$RUNTIME/kubeconfig}"
require_cmd kubectl

POD="${2:-$(kubectl -n "$NS" get pods -o jsonpath='{.items[0].metadata.name}')}"
[ -n "$POD" ] || die "no pod found in $NS"
POD_UID=$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.metadata.uid}')
LOG="/var/log/pods/${NS}_${POD}_${POD_UID}/web/0.log"
log "reading $LOG"
exec colima ssh -- sudo tail -n 100 "$LOG"
