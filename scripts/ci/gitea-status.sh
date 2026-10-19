#!/usr/bin/env bash
# Post a commit status to the application repo in Gitea.
# Usage: gitea-status.sh <pending|success|failure|error> <description> <sha>
# Requires GITEA_CI_TOKEN in the environment (Jenkins credential binding).
set -euo pipefail

state="${1:?state required}"
description="${2:-}"
sha="${3:?sha required}"
owner="${GITEA_REPO_OWNER:-lowcode}"
repo="${GITEA_REPO_NAME:-lowcode-platform}"
context="${GITEA_STATUS_CONTEXT:-ci/jenkins}"
target="${BUILD_URL:-}"

[ -n "${GITEA_CI_TOKEN:-}" ] || { echo "GITEA_CI_TOKEN is required" >&2; exit 1; }
case "$sha" in
  ????????????????????????????????????????) ;; # 40 hex chars
  *) echo "invalid sha: $sha" >&2; exit 1 ;;
esac

payload=$(jq -nc \
  --arg state "$state" \
  --arg context "$context" \
  --arg description "$description" \
  --arg target_url "$target" \
  '{state:$state, context:$context, description:$description, target_url:$target_url}')

curl -fsS -X POST \
  -H "Authorization: token ${GITEA_CI_TOKEN}" \
  -H 'Content-Type: application/json' \
  --data "$payload" \
  "http://127.0.0.1:3000/api/v1/repos/${owner}/${repo}/statuses/${sha}" >/dev/null

echo "gitea status: ${context}=${state} sha=${sha}"
