#!/usr/bin/env bash
# Bring the local lab up in dependency order. Idempotent for running services.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$ROOT/versions.env"
load_env

log "1/8 Colima"
if ! colima status >/dev/null 2>&1; then
  colima start --cpu 6 --memory 8 --disk 60
else
  log "Colima already running"
fi

if ! colima ssh -- test -s /etc/resolv.conf >/dev/null 2>&1; then
  log "repairing VM resolv.conf"
  colima ssh -- sudo sh -c 'rm -f /etc/resolv.conf; printf "nameserver 114.114.114.114\nnameserver 8.8.8.8\n" > /etc/resolv.conf'
fi

log "2/8 registry"
"$ROOT/scripts/bootstrap/40-registry.sh"

log "3/8 k3s + API tunnel"
"$ROOT/scripts/bootstrap/50-k8s.sh"

log "4/8 Gitea (VM host network)"
"$ROOT/scripts/bootstrap/15-gitea-container.sh"

log "5/8 Jenkins -> VM webhook reverse forward"
SSH_CONFIG="$LIMA_HOME/colima/ssh.config"
SSH_SOCK="$LIMA_HOME/colima/ssh.sock"
if ! ssh -F "$SSH_CONFIG" -S "$SSH_SOCK" -O forward -R 0.0.0.0:8081:127.0.0.1:8081 lima-colima 2>/dev/null; then
  log "remote forward 8081 already present or unavailable (webhook is sandbox-blocked; bridge is primary)"
fi

log "6/8 Jenkins"
"$ROOT/scripts/bootstrap/20-jenkins.sh"

log "7/8 Argo CD + Prometheus"
"$ROOT/scripts/bootstrap/70-argocd.sh"
"$ROOT/scripts/bootstrap/80-prometheus.sh"

log "8/8 CI bridge"
"$ROOT/scripts/bootstrap/60-bridge.sh" start

log "lab ready"
"$ROOT/scripts/bootstrap/60-bridge.sh" status
