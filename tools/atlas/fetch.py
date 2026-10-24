#!/usr/bin/env python3
"""Download a source listed in sources.json into a cache dir and verify its SHA-256."""
import hashlib, json, sys, urllib.request
from pathlib import Path

def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()

def main():
    here = Path(__file__).parent
    cache = Path(sys.argv[1] if len(sys.argv) > 1 else "build/atlas/cache")
    cache.mkdir(parents=True, exist_ok=True)
    for s in json.loads((here / "sources.json").read_text())["sources"]:
        dst = cache / Path(s["url"]).name
        if not dst.exists():
            req = urllib.request.Request(s["url"], headers={"User-Agent": "asabiya-atlas-fetch/1"})
            with urllib.request.urlopen(req) as r, open(dst, "wb") as f:
                while chunk := r.read(1 << 20):
                    f.write(chunk)
        got = sha256(dst)
        if got != s["sha256"]:
            sys.exit(f"{s['id']}: hash mismatch {got} != {s['sha256']}")
        print(f"ok {s['id']} {dst}")

if __name__ == "__main__":
    main()
