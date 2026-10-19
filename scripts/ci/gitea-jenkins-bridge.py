#!/usr/bin/env python3
"""Poll Gitea for new branch/PR heads and trigger the Jenkins pipeline.

The lab sandbox blocks outbound TCP from Gitea to non-public addresses
(127.0.0.1 and 192.168.5.1), so Gitea's HTTP webhook cannot reach Jenkins even
though both services are healthy. This bridge is the documented fallback:
it uses only Gitea's read API (host-local curl-level egress is permitted) and
Jenkins' authenticated build API.

State is kept in .runtime/bridge-state.json so a restart does not re-trigger old
commits. Use --once to initialize the state without triggering anything.
"""

from __future__ import annotations

import argparse
import base64
import http.cookiejar
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STATE = ROOT / ".runtime" / "bridge-state.json"
LOG = ROOT / ".runtime" / "logs" / "bridge.log"

GITEA = os.environ.get("GITEA_URL", "http://127.0.0.1:3000")
GITEA_TOKEN = os.environ.get("GITEA_CI_TOKEN", "")
JENKINS = os.environ.get("JENKINS_URL", "http://127.0.0.1:8081")
JENKINS_USER = os.environ.get("JENKINS_ADMIN_USER", "admin")
JENKINS_PASS = os.environ.get("JENKINS_ADMIN_PASSWORD", "")
OWNER = os.environ.get("GITEA_REPO_OWNER", "lowcode")
REPO = os.environ.get("GITEA_REPO_NAME", "lowcode-platform")
JOB = os.environ.get("JENKINS_JOB", "lowcode-platform")
INTERVAL = int(os.environ.get("BRIDGE_INTERVAL", "8"))


def log(msg: str) -> None:
    line = f"{time.strftime('%Y-%m-%dT%H:%M:%S')} {msg}"
    print(line, flush=True)
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with LOG.open("a", encoding="utf-8") as f:
        f.write(line + "\n")


def http_json(url: str, headers: dict[str, str] | None = None, data: bytes | None = None, opener=None):
    req = urllib.request.Request(url, data=data, headers=headers or {})
    try:
        with (opener or urllib.request.build_opener()).open(req, timeout=15) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        return exc.code, body


def gitea_get(path: str):
    status, body = http_json(
        f"{GITEA}/api/v1{path}",
        headers={"Authorization": f"token {GITEA_TOKEN}", "Accept": "application/json"},
    )
    if status != 200:
        raise RuntimeError(f"Gitea GET {path} -> {status}: {body}")
    return body


class Jenkins:
    def __init__(self) -> None:
        self.jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.jar))
        auth = base64.b64encode(f"{JENKINS_USER}:{JENKINS_PASS}".encode()).decode()
        self.headers = {"Authorization": f"Basic {auth}"}

    def crumb(self) -> tuple[str, str]:
        status, body = http_json(f"{JENKINS}/crumbIssuer/api/json", headers=self.headers, opener=self.opener)
        if status != 200:
            raise RuntimeError(f"Jenkins crumb -> {status}: {body}")
        return body["crumbRequestField"], body["crumb"]

    def trigger(self, params: dict[str, str]) -> int:
        field, crumb = self.crumb()
        query = urllib.parse.urlencode(params)
        req = urllib.request.Request(
            f"{JENKINS}/job/{JOB}/buildWithParameters?{query}",
            data=b"",
            headers={**self.headers, field: crumb, "Content-Type": "application/x-www-form-urlencoded"},
            method="POST",
        )
        try:
            with self.opener.open(req, timeout=20) as resp:
                return resp.status
        except urllib.error.HTTPError as exc:
            raise RuntimeError(f"Jenkins trigger -> {exc.code}: {exc.read().decode('utf-8', 'replace')}") from exc


def collect_events() -> list[dict[str, str]]:
    events: list[dict[str, str]] = []
    for branch in gitea_get(f"/repos/{OWNER}/{REPO}/branches"):
        name = branch["name"]
        commit = branch["commit"]["id"]
        events.append({
            "key": f"branch:{name}",
            "kind": "branch",
            "ref": f"refs/heads/{name}",
            "sha": commit,
            "pr": "0",
            "repo": f"{GITEA}/{OWNER}/{REPO}.git",
            "label": f"branch {name}@{commit[:12]}",
        })
    for pr in gitea_get(f"/repos/{OWNER}/{REPO}/pulls?state=open&limit=50"):
        head = pr.get("head", {})
        sha = head.get("sha")
        if not sha:
            continue
        number = str(pr.get("number"))
        clone = (head.get("repo") or {}).get("clone_url") or f"{GITEA}/{OWNER}/{REPO}.git"
        events.append({
            "key": f"pr:{number}",
            "kind": "pull_request",
            "ref": f"refs/heads/{head.get('ref', 'unknown')}",
            "sha": sha,
            "pr": number,
            "repo": clone,
            "label": f"PR #{number}@{sha[:12]}",
        })
    return events


def load_state() -> dict[str, str]:
    if STATE.exists():
        try:
            return json.loads(STATE.read_text(encoding="utf-8"))
        except Exception:
            log("state file unreadable; starting empty")
    return {}


def save_state(state: dict[str, str]) -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=2, sort_keys=True), encoding="utf-8")
    os.chmod(tmp, 0o600)
    os.replace(tmp, STATE)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--once", action="store_true", help="initialize/print state without triggering")
    ap.add_argument("--trigger-existing", action="store_true", help="trigger current heads on first run")
    args = ap.parse_args()

    if not GITEA_TOKEN:
        print("GITEA_CI_TOKEN is required", file=sys.stderr)
        return 2
    if not JENKINS_PASS:
        print("JENKINS_ADMIN_PASSWORD is required", file=sys.stderr)
        return 2

    jenkins = Jenkins()
    state = load_state()
    first_run = not STATE.exists()

    while True:
        try:
            events = collect_events()
            if first_run and not args.trigger_existing:
                for event in events:
                    state[event["key"]] = event["sha"]
                save_state(state)
                log(f"initialized state with {len(events)} branch/PR heads")
                first_run = False
                if args.once:
                    return 0
            else:
                for event in events:
                    if state.get(event["key"]) == event["sha"]:
                        continue
                    params = {
                        "APP_REPO_URL": event["repo"],
                        "APP_REF": event["ref"],
                        "APP_SHA": event["sha"],
                        "APP_PR": event["pr"],
                        # Jenkins may not apply updated defaults to API-triggered
                        # builds; pass explicitly. The pipeline gates these on main.
                        "PUBLISH_IMAGE": "true",
                        "GITOPS_ENABLED": "true",
                        "DEPLOY_ENABLED": "true",
                    }
                    code = jenkins.trigger(params)
                    state[event["key"]] = event["sha"]
                    save_state(state)
                    log(f"triggered {event['label']} kind={event['kind']} http={code}")
                first_run = False
                if args.once:
                    return 0
        except Exception as exc:  # keep polling; log actionable error
            log(f"ERROR: {exc}")
            if args.once:
                return 1
        time.sleep(INTERVAL)


if __name__ == "__main__":
    raise SystemExit(main())
