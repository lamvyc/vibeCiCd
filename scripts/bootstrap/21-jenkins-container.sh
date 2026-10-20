#!/usr/bin/env bash
# Start Jenkins from the official image (derived tools image) instead of the
# host-native WAR. Uses a full copy of the existing JENKINS_HOME so jobs,
# credentials, plugins and build history are preserved; the original WAR
# install and its data are never touched.
#
# Rollback: stop this container and re-run scripts/bootstrap/20-jenkins.sh.
#
# Networking: the container runs with --network host inside the Colima VM, so
# Gitea (127.0.0.1:3000), Zot (127.0.0.1:5001) and the k3s API (127.0.0.1:6443)
# are reachable without publishing ports, and the VM Docker socket supports
# image builds/pushes. The controller is reached from the host via the VM IP
# (test phase) or via the SSH local forward on 127.0.0.1:8081 (after cutover).
#
# Usage:
#   scripts/bootstrap/21-jenkins-container.sh              # start on 18082
#   JENKINS_CONTAINER_PORT=8081 scripts/bootstrap/21-jenkins-container.sh
#   scripts/bootstrap/21-jenkins-container.sh stop
#   scripts/bootstrap/21-jenkins-container.sh status
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$ROOT/versions.env"
load_env

NAME="vibe-jenkins"
IMAGE="vibe-cicd/jenkins:${JENKINS_VERSION}-tools-1"
PORT="${JENKINS_CONTAINER_PORT:-18082}"
SOURCE_HOME="$RUNTIME/jenkins"
CONTAINER_HOME="$RUNTIME/jenkins-container"
KUBECONFIG_CONTAINER="$RUNTIME/kubeconfig-container"

# Pipeline tools (git/pnpm/go/curl) inside the container get no proxy env from
# the VM; without it they have no egress. Local services must bypass the proxy
# (same scope as the Docker daemon drop-in). Set JENKINS_CONTAINER_PROXY="" to
# disable.
CONTAINER_PROXY="${JENKINS_CONTAINER_PROXY:-http://192.168.5.2:7897}"
CONTAINER_NO_PROXY="${JENKINS_CONTAINER_NO_PROXY:-localhost,127.0.0.1,::1,192.168.5.1}"

ensure_data_copy() {
  if [ -d "$CONTAINER_HOME" ]; then
    log "JENKINS_HOME copy already present: $CONTAINER_HOME"
    return
  fi
  [ -d "$SOURCE_HOME" ] || die "missing $SOURCE_HOME; run scripts/bootstrap/20-jenkins.sh first"
  log "copying JENKINS_HOME for container use (one-time, ~1.6GB)"
  rm -rf "$CONTAINER_HOME.tmp"
  cp -a "$SOURCE_HOME" "$CONTAINER_HOME.tmp"
  rm -f "$CONTAINER_HOME.tmp/jenkins.pid"
  mv "$CONTAINER_HOME.tmp" "$CONTAINER_HOME"
}

# The container reaches the update center on VM loopback; the host-side server
# on 127.0.0.1:8899 is a different namespace, so run one inside the VM.
start_vm_update_center() {
  if colima ssh -- sh -c "ss -tln 2>/dev/null | awk '{print \$4}' | grep -q ':8899\$'"; then
    log "VM update-center server already listening on 8899"
    return
  fi
  colima ssh -- sh -c "nohup python3 -m http.server 8899 --bind 127.0.0.1 --directory '$ROOT/.runtime/uc' >/tmp/jenkins-uc.log 2>&1 </dev/null &"
  log "started VM update-center server on 127.0.0.1:8899"
}

# Same local update-site mechanism as 20-jenkins.sh, applied to the copy.
write_update_site() {
  cat > "$CONTAINER_HOME/hudson.model.UpdateCenter.xml" <<EOF
<?xml version='1.1' encoding='UTF-8'?>
<sites>
  <site>
    <id>default</id>
    <url>http://127.0.0.1:8899/update-center.json</url>
  </site>
</sites>
EOF
}

# Pipeline stages call kubectl against the k3s API; inside the VM the API is on
# 127.0.0.1:6443 directly (the host kubeconfig uses the SSH tunnel on 16443).
prepare_kubeconfig() {
  [ -f "$RUNTIME/kubeconfig" ] || die "missing $RUNTIME/kubeconfig"
  sed 's#server: .*#server: https://127.0.0.1:6443#' \
    "$RUNTIME/kubeconfig" > "$KUBECONFIG_CONTAINER"
  chmod 600 "$KUBECONFIG_CONTAINER"
}

start_container() {
  if [ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null || true)" = "true" ]; then
    local running_port
    running_port="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$NAME" 2>/dev/null \
      | sed -n 's/^JENKINS_OPTS=.*httpPort=\([0-9]*\).*/\1/p')"
    if [ "${running_port:-}" = "$PORT" ]; then
      log "container $NAME already running on ${PORT}"
      return
    fi
    log "container $NAME on ${running_port:-unknown} does not match requested ${PORT}; recreating"
    docker rm -f "$NAME" >/dev/null
  fi
  docker inspect "$NAME" >/dev/null 2>&1 && docker rm -f "$NAME" >/dev/null

  local docker_sock_gid
  docker_sock_gid="$(colima ssh -- stat -c %g /var/run/docker.sock 2>/dev/null || echo 991)"

  docker run -d --name "$NAME" --restart unless-stopped --network host \
    --user 501:20 --group-add "$docker_sock_gid" \
    -v "$CONTAINER_HOME:/var/jenkins_home" \
    -v "$ROOT/ci/jenkins/casc.yaml:/var/jenkins_home/casc.yaml:ro" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$RUNTIME/docker:/jenkins-docker-config:ro" \
    -v "$KUBECONFIG_CONTAINER:/jenkins-kubeconfig:ro" \
    -e JAVA_OPTS="-Xms256m -Xmx1024m -Djava.net.preferIPv4Stack=true -Dfile.encoding=UTF-8 -Djenkins.install.runSetupWizard=false" \
    -e JENKINS_OPTS="--httpPort=${PORT} --httpListenAddress=0.0.0.0" \
    -e CASC_JENKINS_CONFIG=/var/jenkins_home/casc.yaml \
    -e KUBECONFIG=/jenkins-kubeconfig \
    -e DOCKER_CONFIG=/jenkins-docker-config \
    -e DOCKER_HOST=unix:///var/run/docker.sock \
    -e COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    -e HTTP_PROXY="$CONTAINER_PROXY" -e HTTPS_PROXY="$CONTAINER_PROXY" \
    -e NO_PROXY="$CONTAINER_NO_PROXY" \
    -e http_proxy="$CONTAINER_PROXY" -e https_proxy="$CONTAINER_PROXY" \
    -e no_proxy="$CONTAINER_NO_PROXY" \
    -e JENKINS_ADMIN_USER -e JENKINS_ADMIN_PASSWORD \
    -e GITEA_CI_USER -e GITEA_CI_TOKEN \
    -e REGISTRY_USER -e REGISTRY_PASSWORD \
    -e WEBHOOK_TOKEN \
    "$IMAGE"
  chmod 600 "$KUBECONFIG_CONTAINER" 2>/dev/null || true
}

stop_container() {
  if docker inspect "$NAME" >/dev/null 2>&1; then
    docker rm -f "$NAME" >/dev/null
    log "container $NAME removed"
  else
    log "container $NAME not present"
  fi
}

status_container() {
  if [ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null || true)" = "true" ]; then
    log "container $NAME is running (port ${PORT})"
    docker logs --tail 5 "$NAME" 2>&1 | sed 's/^/  /'
  else
    log "container $NAME is not running"
  fi
}

case "${1:-start}" in
  stop)   stop_container; exit 0 ;;
  status) status_container; exit 0 ;;
  start)  ;;
  *)      die "usage: $0 [start|stop|status]" ;;
esac

docker image inspect "$IMAGE" >/dev/null 2>&1 \
  || die "missing image $IMAGE; build it with infra/jenkins/Dockerfile first"

ensure_data_copy
start_vm_update_center
write_update_site
prepare_kubeconfig
start_container

log "waiting for Jenkins container on VM port ${PORT} (1-2 minutes on first boot)"
ok=""
for _ in $(seq 1 240); do
  # --noproxy: the VM curl carries proxy env without no_proxy and would
  # otherwise resolve 127.0.0.1 through the host proxy (wrong namespace).
  if colima ssh -- curl -fsS --noproxy '*' -o /dev/null "http://127.0.0.1:${PORT}/login" 2>/dev/null; then ok=1; break; fi
  sleep 1
done
[ -n "$ok" ] || { docker logs --tail 40 "$NAME" 2>&1 | sed 's/^/  /'; die "container Jenkins did not become ready; see logs above"; }

# The container listens in the VM; the host reaches it only through the SSH
# local forward that 90-start-all.sh (or a manual `ssh -O forward -L`) installs.
# The VM's own address is NOT routable from the host, so do not advertise it.
log "Jenkins container ready inside VM: http://127.0.0.1:${PORT}/"
SSH_CONFIG="$LIMA_HOME/colima/ssh.config"
SSH_SOCK="$LIMA_HOME/colima/ssh.sock"
if ssh -F "$SSH_CONFIG" -S "$SSH_SOCK" -O check lima-colima >/dev/null 2>&1 \
   && ssh -F "$SSH_CONFIG" -S "$SSH_SOCK" -O forward -L "127.0.0.1:${PORT}:127.0.0.1:${PORT}" lima-colima >/dev/null 2>&1; then
  log "from the host: http://127.0.0.1:${PORT}/ (SSH local forward)"
else
  warn "no SSH local forward for ${PORT}; run scripts/bootstrap/90-start-all.sh or:"
  warn "  ssh -F $SSH_CONFIG -S $SSH_SOCK -O forward -L 127.0.0.1:${PORT}:127.0.0.1:${PORT} lima-colima"
fi
log "follow logs with: docker logs -f $NAME"
