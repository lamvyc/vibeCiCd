#!/usr/bin/env bash
# Start/stop the Gitea -> Jenkins polling bridge (webhook fallback).
# The sandbox blocks Gitea egress to non-public IPs; see docs/verification.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$ROOT/versions.env"
load_env

PID_FILE="$RUNTIME/ci-bridge.pid"
ACTION="${1:-start}"

case "$ACTION" in
  start)
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
      log "CI bridge already running (pid $(cat "$PID_FILE"))"
      exit 0
    fi
    mkdir -p "$LOGS"
    GITEA_CI_TOKEN="$GITEA_CI_TOKEN" \
    GITEA_URL="http://127.0.0.1:${GITEA_PORT}" \
    JENKINS_URL="http://127.0.0.1:${JENKINS_PORT}" \
    JENKINS_ADMIN_USER="$JENKINS_ADMIN_USER" \
    JENKINS_ADMIN_PASSWORD="$JENKINS_ADMIN_PASSWORD" \
    nohup python3 "$ROOT/scripts/ci/gitea-jenkins-bridge.py" >> "$LOGS/bridge.log" 2>&1 &
    echo $! > "$PID_FILE"
    chmod 600 "$PID_FILE"
    log "CI bridge started (pid $(cat "$PID_FILE"))"
    ;;
  stop)
    if [ -f "$PID_FILE" ]; then
      kill "$(cat "$PID_FILE")" 2>/dev/null || true
      rm -f "$PID_FILE"
      log "CI bridge stopped"
    fi
    ;;
  status)
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
      log "CI bridge running (pid $(cat "$PID_FILE"))"
    else
      log "CI bridge not running"
    fi
    ;;
  *)
    die "usage: $0 start|stop|status"
    ;;
esac
