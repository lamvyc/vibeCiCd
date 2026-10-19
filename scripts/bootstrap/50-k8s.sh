#!/usr/bin/env bash
# Start a verified single-node k3s inside the Colima VM using assets extracted
# from the official k3s image (binary + CNI plugins) and the verified Rancher
# airgap image bundle. Expose the API to the host through an SSH tunnel.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$ROOT/versions.env"
load_env

K3S_BIN="$RUNTIME/k3s/k3s-arm64"
K3S_AIRGAP="$RUNTIME/k3s/k3s-airgap-images-arm64.tar.gz"
[ -x "$K3S_BIN" ] || die "missing $K3S_BIN"
[ -s "$K3S_AIRGAP" ] || die "missing $K3S_AIRGAP"
require_cmd colima kubectl ssh

colima status >/dev/null 2>&1 || die "Colima is not running"
VM_IP=$(colima ssh -- sh -c "ip -4 -o addr show eth0 | awk '{print \$4}' | cut -d/ -f1" | tr -d '\r' | head -1)
[ -n "$VM_IP" ] || die "could not determine VM IP"
log "Colima VM IP: $VM_IP"

if colima ssh -- test -f "$ROOT/.runtime/k3s/k3s-arm64" >/dev/null 2>&1; then
  log "installing k3s binary from shared workspace"
  colima ssh -- sudo install -m 0755 "$ROOT/.runtime/k3s/k3s-arm64" /usr/local/bin/k3s
  colima ssh -- sudo mkdir -p /var/lib/rancher/k3s/agent/images
  colima ssh -- sudo cp "$ROOT/.runtime/k3s/k3s-airgap-images-arm64.tar.gz" /var/lib/rancher/k3s/agent/images/
else
  log "shared workspace not visible; streaming assets over SSH"
  colima ssh -- "sudo tee /usr/local/bin/k3s >/dev/null" < "$K3S_BIN"
  colima ssh -- sudo chmod 0755 /usr/local/bin/k3s
  colima ssh -- sudo mkdir -p /var/lib/rancher/k3s/agent/images
  colima ssh -- "sudo tee /var/lib/rancher/k3s/agent/images/k3s-airgap-images-arm64.tar.gz >/dev/null" < "$K3S_AIRGAP"
fi

log "writing k3s registry mirror config"
mkdir -p "$RUNTIME/k3s"
cat > "$RUNTIME/k3s/registries.yaml" <<EOF
mirrors:
  "localhost:${REGISTRY_PORT}":
    endpoint:
      - "http://localhost:${REGISTRY_PORT}"
EOF
colima ssh -- sudo mkdir -p /etc/rancher/k3s
colima ssh -- sudo cp "$ROOT/.runtime/k3s/registries.yaml" /etc/rancher/k3s/registries.yaml
colima ssh -- sudo cat /etc/rancher/k3s/registries.yaml

if colima ssh -- "pgrep -f 'k3s server' >/dev/null" 2>/dev/null; then
  log "k3s is already running"
else
  log "starting k3s server"
  colima ssh -- sudo sh -c "PATH=/opt/cni/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin nohup k3s server \
    --disable=traefik \
    --disable=servicelb \
    --disable=metrics-server \
    --disable=local-storage \
    --write-kubeconfig-mode=644 \
    --tls-san=${VM_IP} \
    > /var/log/k3s-server.log 2>&1 &"
fi

log "waiting for kubeconfig"
for i in $(seq 1 90); do
  if colima ssh -- test -f /etc/rancher/k3s/k3s.yaml >/dev/null 2>&1; then break; fi
  sleep 2
done
colima ssh -- test -f /etc/rancher/k3s/k3s.yaml >/dev/null 2>&1 || {
  colima ssh -- sudo tail -50 /var/log/k3s-server.log || true
  die "k3s did not produce a kubeconfig"
}
colima ssh -- sudo cat /etc/rancher/k3s/k3s.yaml > "$RUNTIME/kubeconfig"
chmod 600 "$RUNTIME/kubeconfig"

# Lima's usernet does not expose the VM's 6443 to the host. Forward it over the
# existing SSH ControlMaster; the API certificate includes 127.0.0.1.
SSH_CONFIG="$LIMA_HOME/colima/ssh.config"
SSH_SOCK="$LIMA_HOME/colima/ssh.sock"
if ! lsof -nP -iTCP:16443 -sTCP:LISTEN >/dev/null 2>&1; then
  log "opening SSH tunnel 127.0.0.1:16443 -> VM 127.0.0.1:6443"
  if [ -S "$SSH_SOCK" ]; then
    ssh -F "$SSH_CONFIG" -S "$SSH_SOCK" -O forward -L 127.0.0.1:16443:127.0.0.1:6443 lima-colima 2>/dev/null || true
  fi
  if ! lsof -nP -iTCP:16443 -sTCP:LISTEN >/dev/null 2>&1; then
    ssh -F "$SSH_CONFIG" -f -N -L 127.0.0.1:16443:127.0.0.1:6443 lima-colima
  fi
fi
for i in $(seq 1 20); do
  lsof -nP -iTCP:16443 -sTCP:LISTEN >/dev/null 2>&1 && break
  sleep 1
done
lsof -nP -iTCP:16443 -sTCP:LISTEN >/dev/null 2>&1 || die "SSH tunnel to k3s API is not listening"

sed -i '' 's#https://127.0.0.1:6443#https://127.0.0.1:16443#' "$RUNTIME/kubeconfig"
export KUBECONFIG="$RUNTIME/kubeconfig"

log "waiting for node Ready"
ready=""
for i in $(seq 1 90); do
  ready=$(kubectl get nodes --request-timeout=5s --no-headers 2>/dev/null | awk '$2=="Ready"{print $1}' | head -1 || true)
  [ -n "$ready" ] && break
  sleep 2
done
[ -n "$ready" ] || {
  kubectl get nodes -o wide || true
  colima ssh -- sudo tail -50 /var/log/k3s-server.log || true
  die "k3s node did not become Ready"
}
log "node ready: $ready"

log "waiting for system pods"
for i in $(seq 1 60); do
  notready=$(kubectl get pods -A --request-timeout=5s --no-headers 2>/dev/null | grep -vcE 'Running|Completed' || true)
  [ "${notready:-1}" = "0" ] && break
  sleep 2
done
kubectl get nodes -o wide
kubectl get pods -A -o wide || true
log "K8s ready; kubeconfig=$KUBECONFIG"
