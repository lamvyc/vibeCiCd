#!/usr/bin/env bash
# Install/refresh Argo CD (Helm chart rendered locally) and its repo secret,
# namespaces and Application manifests. Idempotent.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$ROOT/versions.env"
load_env

export KUBECONFIG="${KUBECONFIG:-$RUNTIME/kubeconfig}"
[ -f "$KUBECONFIG" ] || die "missing kubeconfig at $KUBECONFIG"
require_cmd kubectl helm

MANIFEST="$RUNTIME/cache/argocd-install.yaml"
mkdir -p "$RUNTIME/cache" "$RUNTIME/helm" "$RUNTIME/helm-cache" "$RUNTIME/helm-data"
if [ ! -s "$MANIFEST" ]; then
  log "rendering Argo CD chart ${ARGOCD_CHART_VERSION}"
  HELM_CONFIG_HOME="$RUNTIME/helm" HELM_CACHE_HOME="$RUNTIME/helm-cache" HELM_DATA_HOME="$RUNTIME/helm-data" \
    helm template argocd oci://ghcr.io/argoproj/argo-helm/argo-cd \
      --version "$ARGOCD_CHART_VERSION" --namespace argocd --include-crds \
      --set dex.enabled=false --set applicationSet.enabled=false --set notifications.enabled=false \
      > "$MANIFEST"
fi

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null
log "applying Argo CD manifests (server-side; CRDs exceed client-side annotation limit)"
kubectl apply --server-side --force-conflicts -n argocd -f "$MANIFEST" >/dev/null

kubectl -n argocd create secret generic gitea-repo \
  --from-literal=type=git \
  --from-literal=url="http://192.168.5.1:${GITEA_PORT}/lowcode/vibe-cicd.git" \
  --from-literal=username="$GITEA_ARGOCD_USER" \
  --from-literal=password="$GITEA_ARGOCD_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n argocd label secret gitea-repo argocd.argoproj.io/secret-type=repository --overwrite >/dev/null

for ns in lowcode-dev lowcode-prod; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n "$ns" create secret docker-registry regcred \
    --docker-server=localhost:5001 \
    --docker-username="$REGISTRY_USER" \
    --docker-password="$REGISTRY_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done

kubectl apply -f "$ROOT/gitops/argocd/project.yaml" >/dev/null
kubectl apply -f "$ROOT/gitops/argocd/application-dev.yaml" >/dev/null
kubectl apply -f "$ROOT/gitops/argocd/application-prod.yaml" >/dev/null
kubectl -n argocd annotate application lowcode-dev argocd.argoproj.io/refresh=normal --overwrite >/dev/null 2>&1 || true

log "waiting for Argo CD pods"
kubectl -n argocd rollout status deployment/argocd-server --timeout=240s
kubectl -n argocd get applications
log "Argo CD ready (port-forward: kubectl -n argocd port-forward svc/argocd-server 8443:443)"
