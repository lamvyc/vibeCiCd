#!/usr/bin/env bash
# Wire Gitea -> Jenkins: webhook (push + PR) and main branch protection.
# Requires Jenkins job "lowcode-platform" and Gitea app repo to exist.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$ROOT/versions.env"
load_env

APP_REPO="lowcode/lowcode-platform"
HOOK_URL="http://127.0.0.1:${JENKINS_PORT}/generic-webhook-trigger/invoke"

log "checking Jenkins job"
curl -fsS -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
  "http://127.0.0.1:${JENKINS_PORT}/job/lowcode-platform/api/json?tree=name" >/dev/null \
  || die "Jenkins job lowcode-platform not found"

log "configuring Gitea webhook"
hook_body=$(jq -nc \
  --arg url "$HOOK_URL" \
  --arg auth "Bearer ${WEBHOOK_TOKEN}" \
  --arg secret "$WEBHOOK_TOKEN" \
  '{type:"gitea",active:true,events:["push","pull_request"],branch_filter:"*",
    config:{url:$url,content_type:"json",http_method:"post",authorization_header:$auth,secret:$secret}}')

hooks=$(gitea_api GET "/repos/${APP_REPO}/hooks")
hook_id=$(printf '%s' "$hooks" | jq -r --arg url "$HOOK_URL" '.[] | select(.config.url==$url) | .id' | head -1)
if [ -n "$hook_id" ]; then
  log "updating existing webhook id=$hook_id"
  gitea_api PATCH "/repos/${APP_REPO}/hooks/${hook_id}" "$hook_body" >/dev/null
else
  log "creating webhook"
  hook_id=$(gitea_api POST "/repos/${APP_REPO}/hooks" "$hook_body" | jq -r '.id')
fi
printf '%s\n' "$hook_id" > "$RUNTIME/gitea-hook-id"
chmod 600 "$RUNTIME/gitea-hook-id"
log "webhook id=${hook_id} url=${HOOK_URL} (token supplied via Authorization header)"

log "configuring main branch protection"
protection=$(jq -nc '{
  branch_name:"main",
  enable_push:false,
  enable_push_whitelist:false,
  enable_merge_whitelist:false,
  required_approvals:0,
  enable_status_check:true,
  status_check_contexts:["ci/jenkins"],
  block_on_rejected_reviews:false,
  block_on_outdated_branch:false,
  dismiss_stale_approvals:false,
  require_signed_commits:false
}')
existing=$(gitea_api GET "/repos/${APP_REPO}/branch_protections" || true)
if printf '%s' "$existing" | jq -e '.[] | select(.branch_name=="main")' >/dev/null 2>&1; then
  log "updating existing main protection"
  gitea_api PATCH "/repos/${APP_REPO}/branch_protections/main" "$protection" >/dev/null
else
  log "creating main protection"
  gitea_api POST "/repos/${APP_REPO}/branch_protections" "$protection" >/dev/null
fi

log "posting a one-off successful status to verify the token/context"
sha=$(curl -fsS -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" \
  "http://127.0.0.1:${GITEA_PORT}/api/v1/repos/${APP_REPO}/branches/main" | jq -r '.commit.id')
GITEA_CI_TOKEN="$GITEA_CI_TOKEN" BUILD_URL="http://127.0.0.1:${JENKINS_PORT}/" \
  "$ROOT/scripts/ci/gitea-status.sh" success "wiring check" "$sha"

log "wired. Verify webhook deliveries in Gitea after the next push."
