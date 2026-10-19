#!/usr/bin/env bash
# Push the application clone and this platform repository to Gitea.
# The original application repository is never modified.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$ROOT/versions.env"
load_env

APP_CLONE="$RUNTIME/repos/lowcode-platform"
[ -d "$APP_CLONE/.git" ] || die "missing app clone at $APP_CLONE"

git_identity() {
  git -C "$1" config user.name >/dev/null 2>&1 || git -C "$1" config user.name "vibeCiCd bootstrap"
  git -C "$1" config user.email >/dev/null 2>&1 || git -C "$1" config user.email "vibecicd@example.local"
}

# Initial pushes use the admin account; CI uses the scoped ci-bot token.
write_git_credentials "$GITEA_ADMIN_USER" "$GITEA_ADMIN_PASSWORD" "127.0.0.1:${GITEA_PORT}"

log "pushing application repo (main) to Gitea"
git_identity "$APP_CLONE"
if ! git -C "$APP_CLONE" remote get-url gitea >/dev/null 2>&1; then
  git -C "$APP_CLONE" remote add gitea "http://127.0.0.1:${GITEA_PORT}/lowcode/lowcode-platform.git"
fi
git -C "$APP_CLONE" push gitea main

log "committing platform repository"
if [ ! -d "$ROOT/.git" ]; then
  git -C "$ROOT" init -b main
fi
git_identity "$ROOT"
git -C "$ROOT" add -A
if ! git -C "$ROOT" diff --cached --quiet; then
  git -C "$ROOT" commit -m "chore: phase 0/1 platform bootstrap (app CI scaffolding)" >/dev/null
fi
if ! git -C "$ROOT" remote get-url gitea >/dev/null 2>&1; then
  git -C "$ROOT" remote add gitea "http://127.0.0.1:${GITEA_PORT}/lowcode/vibe-cicd.git"
fi
git -C "$ROOT" push gitea main

log "repos pushed:"
git -C "$APP_CLONE" log --oneline -1
git -C "$ROOT" log --oneline -1
