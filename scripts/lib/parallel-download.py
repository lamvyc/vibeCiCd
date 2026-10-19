#!/usr/bin/env python3
"""Parallel range downloader with mandatory SHA256 verification.

Why: some release CDNs throttle a single connection to tens of KB/s. This
utility splits a file into ranges, downloads them concurrently with curl,
concatenates the parts, and refuses to install the result unless the SHA256
matches the expected value published by the upstream project.

Usage:
  parallel-download.py URL OUTPUT SHA256 [--workers N] [--chunk-bytes N]

The tool is intentionally dependency-free (Python stdlib + curl).
"""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def run(cmd: list[str], timeout: int = 120) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def remote_size(url: str) -> int:
    proc = run(["curl", "-4", "-sSIL", "--max-time", "60", url], timeout=90)
    if proc.returncode != 0:
        raise RuntimeError(f"HEAD failed: {proc.stderr.strip()}")
    sizes = []
    for line in proc.stdout.splitlines():
        if line.lower().startswith("content-length:"):
            try:
                value = int(line.split(":", 1)[1].strip())
            except ValueError:
                continue
            if value > 0:
                sizes.append(value)
    if not sizes:
        raise RuntimeError("no Content-Length in HEAD response")
    return sizes[-1]


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def download_chunk(url: str, start: int, end: int, dest: Path, attempts: int = 4) -> None:
    expected = end - start + 1
    if dest.exists() and dest.stat().st_size == expected:
        return
    dest.unlink(missing_ok=True)
    last_err = ""
    for attempt in range(1, attempts + 1):
        proc = run(
            [
                "curl", "-4", "-L", "--fail", "--silent", "--show-error",
                "--retry", "3", "--retry-delay", "2", "--max-time", "900",
                "--range", f"{start}-{end}", "-o", str(dest), url,
            ],
            timeout=960,
        )
        if proc.returncode == 0 and dest.exists() and dest.stat().st_size == expected:
            return
        last_err = (proc.stderr or "").strip()
        # Do not keep a truncated part across attempts.
        dest.unlink(missing_ok=True)
        if attempt < attempts:
            time.sleep(2 * attempt)
    raise RuntimeError(f"chunk {start}-{end} failed after {attempts} attempts: {last_err}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("url")
    ap.add_argument("output")
    ap.add_argument("sha256")
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--chunk-bytes", type=int, default=8 * 1024 * 1024)
    args = ap.parse_args()

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        if sha256_file(out) == args.sha256.lower():
            print(f"already present and verified: {out}")
            return 0
        print(f"existing file has wrong checksum, replacing: {out}", file=sys.stderr)
        out.unlink()

    size = remote_size(args.url)
    nchunks = max(1, (size + args.chunk_bytes - 1) // args.chunk_bytes)
    print(f"size={size} bytes, chunks={nchunks}, workers={args.workers}", flush=True)

    parts_dir = Path(tempfile.mkdtemp(prefix=out.name + ".parts.", dir=str(out.parent)))
    ranges = []
    for i in range(nchunks):
        start = i * args.chunk_bytes
        end = min(size - 1, start + args.chunk_bytes - 1)
        ranges.append((start, end, parts_dir / f"{i:05d}.part"))

    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
            futures = {
                pool.submit(download_chunk, args.url, s, e, p): (s, e)
                for s, e, p in ranges
            }
            for done, fut in enumerate(concurrent.futures.as_completed(futures), 1):
                s, e = futures[fut]
                fut.result()
                total = sum(p.stat().st_size for _, _, p in ranges if p.exists())
                print(f"progress {done}/{nchunks} chunks, {total}/{size} bytes", flush=True)

        with out.open("wb") as dst:
            for _, _, part in ranges:
                with part.open("rb") as src:
                    shutil.copyfileobj(src, dst)
        actual = sha256_file(out)
        if actual != args.sha256.lower():
            out.unlink(missing_ok=True)
            raise RuntimeError(f"sha256 mismatch: got {actual}, want {args.sha256.lower()}")
        print(f"verified sha256={actual}", flush=True)
        return 0
    finally:
        shutil.rmtree(parts_dir, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
