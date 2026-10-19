#!/usr/bin/env bash
# Start native Jenkins (WAR) with a project-local JENKINS_HOME and install the
# pinned plugin set. Idempotent; the first run downloads plugins.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$ROOT/versions.env"
load_env

JENKINS_HOME="$RUNTIME/jenkins"
JENKINS_LOG="$LOGS/jenkins.log"
JENKINS_URL="http://127.0.0.1:${JENKINS_PORT}/"
CLI_JAR="$RUNTIME/jenkins-cli.jar"

[ -f "$TOOLS/jenkins.war" ] || die "missing $TOOLS/jenkins.war (download + verify first)"
mkdir -p "$JENKINS_HOME/init.groovy.d"
cp "$ROOT/ci/jenkins/init.groovy.d/00-security.groovy" "$JENKINS_HOME/init.groovy.d/"

start_update_center() {
  # Jenkins' SetupWizard/UpdateCenter Java client hangs on TLS in this network.
  # Serve the official metadata locally so startup completes; plugins are
  # installed separately from the TUNA mirror with SHA256 verification.
  mkdir -p "$RUNTIME/uc"
  if [ -f /tmp/jenkins-uc.json ] && [ ! -f "$RUNTIME/uc/update-center.json" ]; then
    cp /tmp/jenkins-uc.json "$RUNTIME/uc/update-center.json"
  fi
  if ! lsof -nP -iTCP:8899 -sTCP:LISTEN >/dev/null 2>&1; then
    nohup python3 -m http.server 8899 --bind 127.0.0.1 --directory "$RUNTIME/uc"       > "$LOGS/update-center.log" 2>&1 &
    echo $! > "$RUNTIME/uc/http.pid"
    chmod 600 "$RUNTIME/uc/http.pid"
  fi
}

write_update_site() {
  cat > "$JENKINS_HOME/hudson.model.UpdateCenter.xml" <<EOF
<?xml version='1.1' encoding='UTF-8'?>
<sites>
  <site>
    <id>default</id>
    <url>http://127.0.0.1:8899/update-center.json</url>
  </site>
</sites>
EOF
}

start_jenkins() {
  if [ -f "$JENKINS_HOME/jenkins.pid" ] && kill -0 "$(cat "$JENKINS_HOME/jenkins.pid")" 2>/dev/null; then
    log "Jenkins already running (pid $(cat "$JENKINS_HOME/jenkins.pid"))"
    return
  fi
  start_update_center
  write_update_site
  log "starting Jenkins on 127.0.0.1:${JENKINS_PORT}"
  (
    export JENKINS_HOME
    export JENKINS_ADMIN_USER JENKINS_ADMIN_PASSWORD
    export GITEA_CI_USER GITEA_CI_TOKEN REGISTRY_USER REGISTRY_PASSWORD WEBHOOK_TOKEN
    export DOCKER_HOST="unix://${RUNTIME}/colima/default/docker.sock"
    export DOCKER_CONFIG="${RUNTIME}/docker"
    export CASC_JENKINS_CONFIG="$ROOT/ci/jenkins/casc.yaml"
    nohup java -Xms256m -Xmx1024m \
      -Djenkins.install.runSetupWizard=false \
      -Djava.net.preferIPv4Stack=true \
      -Dfile.encoding=UTF-8 \
      -jar "$TOOLS/jenkins.war" --httpPort="${JENKINS_PORT}" --httpListenAddress=127.0.0.1 \
      >> "$JENKINS_LOG" 2>&1 &
    echo $! > "$JENKINS_HOME/jenkins.pid"
  )
  chmod 600 "$JENKINS_HOME/jenkins.pid"
}

start_jenkins
log "waiting for Jenkins (this can take 1-2 minutes)"
wait_for_http "${JENKINS_URL}login" 180

if [ ! -f "$CLI_JAR" ]; then
  log "downloading Jenkins CLI"
  curl -fsS "${JENKINS_URL}jnlpJars/jenkins-cli.jar" -o "$CLI_JAR"
  chmod 600 "$CLI_JAR"
fi

# Jenkins may create the built-in admin with an initial password before
# init.groovy.d runs. Capture that password once if our .env.local value does
# not authenticate, then persist it (never print it).
if ! curl -fsS -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" "${JENKINS_URL}api/json?tree=mode" >/dev/null 2>&1; then
  initial_file="$JENKINS_HOME/secrets/initialAdminPassword"
  if [ -f "$initial_file" ]; then
    initial_password="$(cat "$initial_file")"
    if curl -fsS -u "${JENKINS_ADMIN_USER}:${initial_password}" "${JENKINS_URL}api/json?tree=mode" >/dev/null 2>&1; then
      set_env_var JENKINS_ADMIN_PASSWORD "$initial_password"
      JENKINS_ADMIN_PASSWORD="$initial_password"
      log "captured Jenkins initial admin password into .env.local"
    fi
  fi
fi

curl -fsS -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" "${JENKINS_URL}api/json?tree=mode" >/dev/null \
  || die "admin login failed; check Jenkins init script and JENKINS_ADMIN_PASSWORD"

if [ ! -f "$JENKINS_HOME/plugins/configuration-as-code.jpi" ]; then
  log "installing Jenkins plugins (first run; may take several minutes)"
  jenkins_cli install-plugin \
    configuration-as-code \
    workflow-aggregator \
    git \
    credentials-binding \
    plain-credentials \
    junit \
    timestamper \
    ws-cleanup \
    generic-webhook-trigger \
    pipeline-stage-view \
    -deploy > "$LOGS/jenkins-plugins.log" 2>&1 || {
      warn "plugin install returned non-zero; see $LOGS/jenkins-plugins.log"
    }
  log "restarting Jenkins to load plugins"
  jenkins_cli safe-restart >/dev/null 2>&1 || jenkins_cli restart >/dev/null 2>&1 || true
  sleep 5
  wait_for_http "${JENKINS_URL}login" 240
else
  log "JCasC plugin already installed"
fi

# Apply JCasC if the plugin is loaded; a restart already applies it, but this
# makes the script work after a config edit without a manual restart.
# JCasC is applied at startup; avoid a blocking CLI reload here.

log "Jenkins ready: ${JENKINS_URL}"
curl -fsS -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" "${JENKINS_URL}api/json?tree=jobs[name]" | jq -c '{jobs: [.jobs[].name]}'
