"""Stage an independent Godot project with byte-identical shared adapters."""
import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SHARED = [f"data/{n}.gd" for n in (
    "bridge_source", "history_source", "history_frame", "world_data",
    "native_frame_decoder", "local_response_buffer", "annual_trace",
)] + ["map/map_layers.gd"]


def stage(destination):
    destination = Path(destination).resolve()
    if destination == ROOT or ROOT in destination.parents and not destination.is_relative_to(ROOT / "build"):
        raise ValueError("Stage only outside source or under build/")
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copytree(ROOT / "experiments/atlas2d/godot", destination, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns(".godot", "*.uid"))
    shared = destination / "shared"
    shared.mkdir(exist_ok=True)
    hashes = {}
    for relative in SHARED:
        source = ROOT / "client/godot/scripts" / relative
        content = source.read_bytes()
        (shared / source.name).write_bytes(content)
        hashes[str(source.relative_to(ROOT))] = hashlib.sha256(content).hexdigest()
    tree_hash = hashlib.sha256()
    for source in sorted((ROOT / "experiments/atlas2d").rglob("*")):
        if source.is_file() and "__pycache__" not in source.parts and source.suffix not in (".pyc", ".uid"):
            tree_hash.update(str(source.relative_to(ROOT)).encode()+b"\0"+source.read_bytes())
    atlas_hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((ROOT / "experiments/atlas2d/godot").glob("*")) if p.is_file() and p.suffix != ".uid"}
    manifest = {"atlasSourcesSHA256": atlas_hashes, "experimentTreeSHA256": tree_hash.hexdigest(), "schema": "asabiya/atlas2d-build-v1", "base": "79035761f1e61041a3ccbf74b648577e53ba7150",
                "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                "sharedAdaptersSHA256": hashes}
    (destination / "build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=str(ROOT / "build/atlas2d/project"))
    print(stage(parser.parse_args().out))
