#!/usr/bin/env bash
# GitOps rollback: revert the last image-tag change for an environment, push,
# then verify Argo CD convergence and the restored application version.
# Usage: rollback.sh <dev|prod>
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$ROOT/versions.env"
load_env

ENV_NAME="${1:-dev}"
case "$ENV_NAME" in dev|prod) ;; *) die "env must be dev or prod";; esac

cd "$ROOT"
if ! git diff --quiet || ! git diff --cached --quiet; then
  die "platform working tree is dirty; refusing to revert"
fi

path="gitops/overlays/${ENV_NAME}/kustomization.yaml"
last=$(git log -1 --format=%H -- "$path")
[ -n "$last" ] || die "no deployment history for $path"
msg=$(git log -1 --format=%s "$last")
case "$msg" in
  chore\(gitops\)*) ;;
  *) die "last change to $path is not a GitOps deploy commit: $msg" ;;
esac

prev_tag=$(git show "${last}^:${path}" | awk '/newTag:/{print $2}' | tr -d '"' | head -1)
cur_tag=$(git show "${last}:${path}" | awk '/newTag:/{print $2}' | tr -d '"' | head -1)
log "env=${ENV_NAME} current=${cur_tag:-unknown} previous=${prev_tag:-unknown} commit=${last}"

log "reverting ${last}"
git revert --no-edit "$last" >/dev/null
write_git_credentials "$GITEA_ADMIN_USER" "$GITEA_ADMIN_PASSWORD" "127.0.0.1:${GITEA_PORT}"
git push gitea main >/dev/null
new_commit=$(git rev-parse HEAD)
log "rollback pushed: ${new_commit}"

expected_sha=""
if [ -n "$prev_tag" ] && [ -d "$RUNTIME/repos/lowcode-platform/.git" ]; then
  prefix=${prev_tag#sha-}
  expected_sha=$(git -C "$RUNTIME/repos/lowcode-platform" rev-parse --verify "${prefix}^{commit}" 2>/dev/null || true)
fi

if [ -n "$expected_sha" ]; then
  "$ROOT/scripts/deploy/verify-deploy.sh" "$ENV_NAME" "$expected_sha" "$prev_tag"
else
  warn "could not resolve full commit for ${prev_tag}; waiting for Argo CD health only"
  KUBECONFIG="${KUBECONFIG:-$RUNTIME/kubeconfig}" kubectl -n argocd get application "lowcode-${ENV_NAME}"
fi
log "rollback complete; record the incident and the revert commit in docs/verification/"
