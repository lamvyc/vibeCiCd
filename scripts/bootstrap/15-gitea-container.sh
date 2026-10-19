#!/usr/bin/env bash
# Start Gitea inside the Colima VM (host network) and expose it to the host via
# an SSH local forward. The VM placement is required because the host sandbox
# blocks Gitea egress to Jenkins; see docs/verification/environment-limitations.md.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$ROOT/versions.env"
load_env

require_cmd docker ssh
colima status >/dev/null 2>&1 || die "Colima is not running"
GITEA_HOME="$RUNTIME/gitea"
mkdir -p "$GITEA_HOME"/{data,repositories,log,ssh,home}
umask 077
cat > "$GITEA_HOME/app.container.ini" <<EOF
APP_NAME = vibeCiCd local Gitea
RUN_MODE = prod
WORK_PATH = /data

[server]
PROTOCOL = http
HTTP_ADDR = 0.0.0.0
HTTP_PORT = 3000
ROOT_URL = http://localhost:3000/
DISABLE_SSH = true
START_SSH_SERVER = false
SSH_ROOT = /data/ssh
OFFLINE_MODE = true
LFS_START_SERVER = false

[database]
DB_TYPE = sqlite3
PATH = /data/data/gitea.db
LOG_SQL = false

[repository]
ROOT = /data/repositories
DEFAULT_BRANCH = main

[security]
INSTALL_LOCK = true
SECRET_KEY = ${GITEA_SECRET_KEY:?missing GITEA_SECRET_KEY in .env.local}
INTERNAL_TOKEN = ${GITEA_INTERNAL_TOKEN:?missing GITEA_INTERNAL_TOKEN in .env.local}
PASSWORD_COMPLEXITY = off

[service]
DISABLE_REGISTRATION = true
REQUIRE_SIGNIN_VIEW = false
DEFAULT_ALLOW_CREATE_ORGANIZATION = false

[openid]
ENABLE_OPENID_SIGNIN = false
ENABLE_OPENID_SIGNUP = false

[actions]
ENABLED = false

[packages]
ENABLED = false

[log]
MODE = console
LEVEL = Info

[ui]
DEFAULT_THEME = gitea
SHOW_USER_EMAIL = false
EOF
chmod 600 "$GITEA_HOME/app.container.ini"

if docker container inspect lowcode-gitea >/dev/null 2>&1; then
  log "recreating lowcode-gitea container"
  docker rm -f lowcode-gitea >/dev/null
fi
log "starting Gitea container in VM host network"
docker run -d --name lowcode-gitea --restart unless-stopped \
  --network host \
  --user "$(id -u):$(id -g)" \
  -e HOME=/data/home \
  --entrypoint /usr/local/bin/gitea \
  -v "$GITEA_HOME:/data" \
  "$GITEA_IMAGE" web --config /data/app.container.ini >/dev/null

for i in $(seq 1 60); do
  if colima ssh -- curl -fsS -m 3 http://127.0.0.1:3000/api/v1/version >/dev/null 2>&1; then break; fi
  sleep 1
done
colima ssh -- curl -fsS -m 3 http://127.0.0.1:3000/api/v1/version >/dev/null 2>&1 \
  || die "Gitea did not become ready in the VM"

# Host access via SSH local forward (idempotent).
SSH_CONFIG="$LIMA_HOME/colima/ssh.config"
SSH_SOCK="$LIMA_HOME/colima/ssh.sock"
if ! lsof -nP -iTCP:3000 -sTCP:LISTEN >/dev/null 2>&1; then
  if [ -S "$SSH_SOCK" ]; then
    ssh -F "$SSH_CONFIG" -S "$SSH_SOCK" -O forward -L 127.0.0.1:3000:127.0.0.1:3000 lima-colima 2>/dev/null || true
  fi
  if ! lsof -nP -iTCP:3000 -sTCP:LISTEN >/dev/null 2>&1; then
    ssh -F "$SSH_CONFIG" -f -N -L 127.0.0.1:3000:127.0.0.1:3000 lima-colima
  fi
fi
wait_for_http "http://127.0.0.1:${GITEA_PORT}/api/v1/version" 30
log "Gitea ready: http://127.0.0.1:${GITEA_PORT} (container=lowcode-gitea)"
