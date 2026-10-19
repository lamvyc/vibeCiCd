#!/usr/bin/env python3
"""Install pinned Jenkins plugins from the TUNA mirror.

The Jenkins Java HTTP client fails TLS negotiation with updates.jenkins.io in
this environment, while curl and the TUNA mirror work. This tool reads the
official update-center metadata (fetched with curl), resolves the dependency
tree, downloads plugin HPIs from TUNA, and verifies the SHA256 published in the
metadata before placing them in $JENKINS_HOME/plugins.

Usage:
  install-jenkins-plugins.py --jenkins-home DIR [--metadata FILE]
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOTS = [
    "configuration-as-code",
    "workflow-aggregator",
    "git",
    "credentials-binding",
    "plain-credentials",
    "junit",
    "timestamper",
    "ws-cleanup",
    "generic-webhook-trigger",
    "pipeline-stage-view",
]

TUNA = "https://mirrors.tuna.tsinghua.edu.cn/jenkins/plugins"
OFFICIAL = "https://updates.jenkins.io/download/plugins"


def curl(url: str, dest: Path, attempts: int = 3) -> None:
    last = ""
    for _ in range(attempts):
        proc = subprocess.run(
            ["curl", "-4", "-L", "--fail", "--silent", "--show-error",
             "--retry", "2", "--retry-delay", "1", "--max-time", "120",
             "-o", str(dest), url],
            capture_output=True, text=True,
        )
        if proc.returncode == 0 and dest.exists() and dest.stat().st_size > 0:
            return
        last = (proc.stderr or "").strip()
        dest.unlink(missing_ok=True)
    raise RuntimeError(f"download failed: {url}: {last}")


def load_metadata(path: Path) -> dict:
    raw = path.read_text(encoding="utf-8")
    return json.loads(raw[raw.find("{"): raw.rfind("}") + 1])


def expected_sha(entry: dict) -> str | None:
    value = entry.get("sha256")
    if not value:
        return None
    value = value.strip()
    if len(value) == 64 and all(c in "0123456789abcdefABCDEF" for c in value):
        return value.lower()
    try:
        return base64.b64decode(value).hex()
    except Exception:
        return None


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--jenkins-home", required=True)
    ap.add_argument("--metadata", default="/tmp/jenkins-uc.json")
    args = ap.parse_args()

    metadata = load_metadata(Path(args.metadata))
    plugins = metadata["plugins"]

    resolved: dict[str, dict] = {}
    queue = list(ROOTS)
    while queue:
        name = queue.pop()
        if name in resolved:
            continue
        entry = plugins.get(name)
        if not entry:
            print(f"WARN: plugin not in update center: {name}", file=sys.stderr)
            continue
        resolved[name] = entry
        for dep in entry.get("dependencies", []):
            if not dep.get("optional") and dep["name"] not in resolved:
                queue.append(dep["name"])

    plugin_dir = Path(args.jenkins_home) / "plugins"
    plugin_dir.mkdir(parents=True, exist_ok=True)
    for stale in plugin_dir.glob("*.tmp"):
        stale.unlink(missing_ok=True)

    errors = []
    for name in sorted(resolved):
        entry = resolved[name]
        version = entry["version"]
        dest = plugin_dir / f"{name}.jpi"
        want = expected_sha(entry)
        if dest.exists() and dest.stat().st_size > 0:
            if not want or sha256_file(dest) == want:
                print(f"present: {name} {version}")
                continue
        tmp = dest.with_suffix(".jpi.part")
        urls = [
            f"{TUNA}/{name}/{version}/{name}.hpi",
            f"{OFFICIAL}/{name}/{version}/{name}.hpi",
        ]
        ok = False
        for url in urls:
            try:
                curl(url, tmp)
                got = sha256_file(tmp)
                if want and got != want:
                    raise RuntimeError(f"sha256 mismatch: got {got}, want {want}")
                os.replace(tmp, dest)
                print(f"installed: {name} {version}")
                ok = True
                break
            except Exception as exc:  # try next mirror
                print(f"  mirror failed: {url}: {exc}", file=sys.stderr)
                tmp.unlink(missing_ok=True)
        if not ok:
            errors.append(name)

    if errors:
        print("FAILED plugins: " + ", ".join(errors), file=sys.stderr)
        return 1
    print(f"OK: {len(resolved)} plugins installed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
