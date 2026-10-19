#!/usr/bin/env bash
# Start Gitea (native, SQLite) and create the local users/org/repos/tokens.
# Idempotent: existing users, repos and tokens are reused.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$ROOT/versions.env"
load_env

[ -x "$TOOLS/gitea" ] || die "missing $TOOLS/gitea; run the pinned download first"

# Stable secrets are generated once and kept out of Git.
if ! grep -q '^GITEA_SECRET_KEY=' "$ENV_FILE"; then
  set_env_var GITEA_SECRET_KEY "$(rand_hex 32)"
fi
if ! grep -q '^GITEA_INTERNAL_TOKEN=' "$ENV_FILE"; then
  set_env_var GITEA_INTERNAL_TOKEN "$(rand_hex 48)"
fi
load_env

GITEA_HOME="$RUNTIME/gitea"
GITEA_CONF="$GITEA_HOME/app.ini"
mkdir -p "$GITEA_HOME"/{data,repositories,log,tmp,ssh,home/.ssh} "$GITEA_HOME/custom/conf"
chmod 700 "$GITEA_HOME/home/.ssh"

umask 077
cat > "$GITEA_CONF" <<EOF
APP_NAME = vibeCiCd local Gitea
RUN_USER = $(id -un)
RUN_MODE = prod
WORK_PATH = $GITEA_HOME

[server]
PROTOCOL = http
HTTP_ADDR = 127.0.0.1
HTTP_PORT = ${GITEA_PORT}
ROOT_URL = http://127.0.0.1:${GITEA_PORT}/
DISABLE_SSH = true
START_SSH_SERVER = false
SSH_ROOT = $GITEA_HOME/ssh
SSH_PORT = 2222
OFFLINE_MODE = true
LFS_START_SERVER = false
ENABLE_GZIP = false

[database]
DB_TYPE = sqlite3
PATH = $GITEA_HOME/data/gitea.db
LOG_SQL = false

[repository]
ROOT = $GITEA_HOME/repositories
DEFAULT_BRANCH = main

[security]
INSTALL_LOCK = true
SECRET_KEY = ${GITEA_SECRET_KEY}
INTERNAL_TOKEN = ${GITEA_INTERNAL_TOKEN}
PASSWORD_COMPLEXITY = off

[service]
DISABLE_REGISTRATION = true
REQUIRE_SIGNIN_VIEW = false
DEFAULT_ALLOW_CREATE_ORGANIZATION = false
ENABLE_NOTIFY_MAIL = false

[openid]
ENABLE_OPENID_SIGNIN = false
ENABLE_OPENID_SIGNUP = false

[actions]
ENABLED = false

[packages]
ENABLED = false

[log]
MODE = file
LEVEL = Info
ROOT_PATH = $GITEA_HOME/log

[ui]
DEFAULT_THEME = gitea
SHOW_USER_EMAIL = false
EOF
chmod 600 "$GITEA_CONF"

start_gitea() {
  if [ -f "$GITEA_HOME/gitea.pid" ] && kill -0 "$(cat "$GITEA_HOME/gitea.pid")" 2>/dev/null; then
    log "Gitea already running (pid $(cat "$GITEA_HOME/gitea.pid"))"
    return
  fi
  log "starting Gitea on 127.0.0.1:${GITEA_PORT}"
  HOME="$GITEA_HOME/home" GITEA_WORK_DIR="$GITEA_HOME" nohup "$TOOLS/gitea" web --config "$GITEA_CONF" \
    >> "$LOGS/gitea.log" 2>&1 &
  echo $! > "$GITEA_HOME/gitea.pid"
  chmod 600 "$GITEA_HOME/gitea.pid"
}

start_gitea
wait_for_http "http://127.0.0.1:${GITEA_PORT}/api/v1/version" 90
log "Gitea is up: $(curl -fsS "http://127.0.0.1:${GITEA_PORT}/api/v1/version")"

user_exists() {
  curl -fsS -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" \
    "http://127.0.0.1:${GITEA_PORT}/api/v1/users/$1" >/dev/null 2>&1
}

create_user() {
  local name="$1" password="$2" admin="$3" email="$4"
  if user_exists "$name"; then
    log "user exists: $name"
    return
  fi
  local args=(admin user create --config "$GITEA_CONF" --username "$name" --password "$password" --email "$email" --must-change-password=false)
  if [ "$admin" = "true" ]; then args+=(--admin); fi
  log "creating user: $name (admin=$admin)"
  GITEA_WORK_DIR="$GITEA_HOME" "$TOOLS/gitea" "${args[@]}" >> "$LOGS/gitea-admin.log" 2>&1 || {
    warn "gitea admin user create failed; see $LOGS/gitea-admin.log"
    return 1
  }
}

create_user "$GITEA_ADMIN_USER" "$GITEA_ADMIN_PASSWORD" true "$GITEA_ADMIN_EMAIL"
create_user "$GITEA_CI_USER" "$GITEA_CI_PASSWORD" false "ci-bot@example.local"
create_user "$GITEA_ARGOCD_USER" "$GITEA_ARGOCD_PASSWORD" false "argocd@example.local"

# Org
if ! gitea_api GET "/orgs/lowcode" >/dev/null 2>&1; then
  log "creating org: lowcode"
  gitea_api POST "/orgs" '{"username":"lowcode","full_name":"lowcode","visibility":"private"}' >/dev/null
else
  log "org exists: lowcode"
fi

# Repos (empty; content is pushed separately)
for repo in lowcode-platform vibe-cicd; do
  if gitea_api GET "/repos/lowcode/${repo}" >/dev/null 2>&1; then
    log "repo exists: lowcode/${repo}"
  else
    log "creating repo: lowcode/${repo}"
    gitea_api POST "/orgs/lowcode/repos" "{\"name\":\"${repo}\",\"private\":true,\"auto_init\":false,\"default_branch\":\"main\"}" >/dev/null
  fi
done

# Collaborator permissions (least privilege).
add_collaborator() {
  local repo="$1" user="$2" permission="$3"
  log "collaborator ${user} -> ${repo} (${permission})"
  gitea_api PUT "/repos/lowcode/${repo}/collaborators/${user}" "{\"permission\":\"${permission}\"}" >/dev/null
}
add_collaborator lowcode-platform "$GITEA_CI_USER" write
add_collaborator vibe-cicd "$GITEA_CI_USER" write
add_collaborator vibe-cicd "$GITEA_ARGOCD_USER" read

# Scoped tokens. Tokens cannot be read back, so persist them once in .env.local.
mint_token() {
  local user="$1" password="$2" token_name="$3" scopes="$4" var_name="$5"
  if grep -q "^${var_name}=." "$ENV_FILE"; then
    log "token already stored: ${var_name}"
    return
  fi
  local response token
  response=$(gitea_api_as "$user" "$password" POST "/users/${user}/tokens" \
    "{\"name\":\"${token_name}\",\"scopes\":${scopes}}")
  token=$(printf '%s' "$response" | jq -r '.sha1 // empty')
  [ -n "$token" ] || die "failed to mint token for ${user}: ${response}"
  set_env_var "$var_name" "$token"
  log "stored ${var_name} for ${user}"
}

mint_token "$GITEA_CI_USER" "$GITEA_CI_PASSWORD" "jenkins-ci" \
  '["write:repository","read:repository","read:user"]' GITEA_CI_TOKEN
mint_token "$GITEA_ARGOCD_USER" "$GITEA_ARGOCD_PASSWORD" "argocd-read" \
  '["read:repository"]' GITEA_ARGOCD_TOKEN

load_env
log "Gitea bootstrap complete"
