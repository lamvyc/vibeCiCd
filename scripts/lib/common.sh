#!/usr/bin/env bash
# Shared helpers for bootstrap/verification scripts.
# All scripts are intended to run from the repository root.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export ROOT

RUNTIME="${ROOT}/.runtime"
TOOLS="${ROOT}/.tools"
LOGS="${RUNTIME}/logs"
ENV_FILE="${ROOT}/.env.local"

mkdir -p "$RUNTIME" "$TOOLS" "$LOGS"

log()  { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(date '+%H:%M:%S')" "$*" >&2; exit 1; }

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "required command not found: $c"
  done
}

load_env() {
  [ -f "$ENV_FILE" ] || die "missing $ENV_FILE; run scripts/bootstrap/00-env.sh first"
  # shellcheck disable=SC1090
  set -a; . "$ENV_FILE"; set +a
}

rand_hex() { openssl rand -hex "${1:-24}"; }

wait_for_http() {
  local url="$1" timeout="${2:-60}" i=0
  until curl -fsS -o /dev/null --max-time 2 "$url" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge "$timeout" ] && die "timeout waiting for $url"
    sleep 1
  done
}

# Gitea API using the admin account (basic auth). Never echo the password.
gitea_api() {
  local method="$1" path="$2" body="${3:-}"
  local auth="${GITEA_ADMIN_USER:?}:${GITEA_ADMIN_PASSWORD:?}"
  if [ -n "$body" ]; then
    curl -fsS -X "$method" -u "$auth" \
      -H 'Content-Type: application/json' \
      --data "$body" "http://127.0.0.1:3000/api/v1${path}"
  else
    curl -fsS -X "$method" -u "$auth" \
      -H 'Accept: application/json' \
      "http://127.0.0.1:3000/api/v1${path}"
  fi
}

# Gitea API as a named user (used to mint scoped access tokens).
gitea_api_as() {
  local user="$1" password="$2" method="$3" path="$4" body="${5:-}"
  if [ -n "$body" ]; then
    curl -fsS -X "$method" -u "${user}:${password}" \
      -H 'Content-Type: application/json' \
      --data "$body" "http://127.0.0.1:3000/api/v1${path}"
  else
    curl -fsS -X "$method" -u "${user}:${password}" \
      -H 'Accept: application/json' \
      "http://127.0.0.1:3000/api/v1${path}"
  fi
}

# Jenkins CLI wrapper. Uses the admin password; never echo it.
jenkins_cli() {
  local jar="${RUNTIME}/jenkins-cli.jar"
  [ -f "$jar" ] || die "missing $jar"
  java -jar "$jar" -s "http://127.0.0.1:8081/" \
    -auth "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" "$@"
}

# Git credential store, mode 600, outside Git.
write_git_credentials() {
  local user="$1" token="$2" host="${3:-127.0.0.1:3000}"
  local file="${RUNTIME}/git-credentials"
  umask 077
  printf 'http://%s:%s@%s\n' "$user" "$token" "$host" > "$file"
  chmod 600 "$file"
  export GIT_CONFIG_GLOBAL="${RUNTIME}/gitconfig"
  git config --global credential.helper "store --file=${file}"
}

is_true() { case "${1:-}" in 1|true|TRUE|yes|YES|on|ON) return 0;; *) return 1;; esac; }

# Update or append a key in .env.local without printing the value.
set_env_var() {
  local key="$1" value="$2" file="${3:-$ENV_FILE}"
  python3 - "$file" "$key" "$value" <<'PY'
import os, sys
path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
lines = []
found = False
if os.path.exists(path):
    with open(path, encoding='utf-8') as f:
        for line in f:
            if line.startswith(key + '='):
                lines.append(f"{key}={value}\n")
                found = True
            else:
                lines.append(line)
if not found:
    lines.append(f"{key}={value}\n")
tmp = path + '.tmp'
with open(tmp, 'w', encoding='utf-8') as f:
    f.writelines(lines)
os.chmod(tmp, 0o600)
os.replace(tmp, path)
PY
}
