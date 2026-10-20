#!/usr/bin/env bash
# Bring the local lab up in dependency order. Idempotent for running services.
#
# Jenkins runtime is selectable: JENKINS_RUNTIME=container (default) runs the
# official-image container inside the Colima VM; JENKINS_RUNTIME=war keeps the
# legacy host-native WAR. Both use separate JENKINS_HOME copies, so switching
# never destroys data and can be reverted at any time.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$ROOT/versions.env"
load_env

JENKINS_RUNTIME="${JENKINS_RUNTIME:-container}"

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

log "5/8 Jenkins host access (runtime: ${JENKINS_RUNTIME})"
SSH_CONFIG="$LIMA_HOME/colima/ssh.config"
SSH_SOCK="$LIMA_HOME/colima/ssh.sock"
# Only one side may own 8081: the WAR binds the host, the container binds the
# VM. Drop the opposite forward first so the bind cannot conflict.
if [ "$JENKINS_RUNTIME" = "war" ]; then
  ssh -F "$SSH_CONFIG" -S "$SSH_SOCK" -O cancel -L 127.0.0.1:8081:127.0.0.1:8081 lima-colima 2>/dev/null || true
  # A container controller would keep VM 8081 and block the reverse forward.
  JENKINS_CONTAINER_PORT="${JENKINS_PORT}" "$ROOT/scripts/bootstrap/21-jenkins-container.sh" stop >/dev/null 2>&1 || true
  if ! ssh -F "$SSH_CONFIG" -S "$SSH_SOCK" -O forward -R 0.0.0.0:8081:127.0.0.1:8081 lima-colima 2>/dev/null; then
    log "remote forward 8081 already present or unavailable (webhook is sandbox-blocked; bridge is primary)"
  fi
else
  ssh -F "$SSH_CONFIG" -S "$SSH_SOCK" -O cancel -R 0.0.0.0:8081:127.0.0.1:8081 lima-colima 2>/dev/null || true
  # A WAR controller would keep host 8081 and shadow the local forward.
  if [ -f "$RUNTIME/jenkins/jenkins.pid" ] && kill -0 "$(cat "$RUNTIME/jenkins/jenkins.pid")" 2>/dev/null; then
    log "stopping legacy WAR Jenkins (pid $(cat "$RUNTIME/jenkins/jenkins.pid")); data kept in $RUNTIME/jenkins"
    kill "$(cat "$RUNTIME/jenkins/jenkins.pid")" 2>/dev/null || true
    for _ in $(seq 1 30); do kill -0 "$(cat "$RUNTIME/jenkins/jenkins.pid")" 2>/dev/null || break; sleep 1; done
    rm -f "$RUNTIME/jenkins/jenkins.pid"
  fi
  if ! ssh -F "$SSH_CONFIG" -S "$SSH_SOCK" -O forward -L 127.0.0.1:8081:127.0.0.1:8081 lima-colima 2>/dev/null; then
    log "local forward 8081 already present"
  fi
fi

log "6/8 Jenkins (${JENKINS_RUNTIME})"
if [ "$JENKINS_RUNTIME" = "war" ]; then
  "$ROOT/scripts/bootstrap/20-jenkins.sh"
else
  JENKINS_CONTAINER_PORT="${JENKINS_PORT}" "$ROOT/scripts/bootstrap/21-jenkins-container.sh" start
fi

log "7/8 Argo CD + Prometheus"
"$ROOT/scripts/bootstrap/70-argocd.sh"
"$ROOT/scripts/bootstrap/80-prometheus.sh"

log "8/8 CI bridge"
"$ROOT/scripts/bootstrap/60-bridge.sh" start

log "lab ready"
"$ROOT/scripts/bootstrap/60-bridge.sh" status
