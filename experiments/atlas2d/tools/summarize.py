"""Summarize raw JSONL with explicit metric definitions; standard library only."""
import argparse
import json
import math
from pathlib import Path


def percentile(values, q):
    if not values:
        return None
    values = sorted(values)
    rank = (len(values) - 1) * q
    lo, hi = math.floor(rank), math.ceil(rank)
    return values[lo] + (values[hi] - values[lo]) * (rank - lo)


def summary(path):
    rows = [json.loads(line) for line in Path(path).read_text(encoding="utf-8-sig").splitlines() if line.strip()]
    environment = next(r for r in rows if r["kind"] == "environment")
    frames = [r["frame_ms"] for r in rows if r["kind"] == "frame"]
    if not frames or any(not math.isfinite(v) or v <= 0 for v in frames):
        raise ValueError("Missing/invalid frame samples")
    sample = next((r for r in rows if r["kind"] == "sample_begin"), None)
    end = next((r for r in rows if r["kind"] == "end"), None)
    is_atlas = environment.get("schema") == "asabiya/atlas2d-measure-v1"
    ready = next((r for r in rows if r["kind"] == "ready"), None)
    if is_atlas and (not ready or not ready.get("framebuffer_size") or ready["framebuffer_size"] != ready.get("window_size")):
        raise ValueError("Framebuffer resolution not validated")
    if is_atlas and (not sample or not end or not any(r["kind"] == "verified_pause" and r.get("exact") for r in rows)):
        raise ValueError("Incomplete capture / pause not verified")
    measured = [r for r in rows if not sample or sample["ticks_us"] <= r.get("ticks_us", 0) <= end["ticks_us"]]
    result = {"file": Path(path).name, "environment": environment,
              "frames": len(frames), "fps_p50": 1000 / percentile(frames, .5),
              "fps_mean": 1000 * len(frames) / sum(frames),
              "frame_ms_p50": percentile(frames, .5), "frame_ms_p95": percentile(frames, .95), "frame_ms_p99": percentile(frames, .99),
              "frames_above_33_333ms_percent": 100 * sum(t > 1000 / 30 for t in frames) / len(frames),
              "godot_static_peak_bytes": max((r.get("godot_static_bytes", 0) for r in rows), default=0),
              "target_hardware_verified": False,
              "ready": next((r for r in rows if r["kind"] == "ready"), None)}
    for kind in ("selection_local", "selection_present", "selection_query", "map_present"):
        values = [r["ms"] for r in measured if r["kind"] == kind]
        result[kind + "_ms"] = {"samples": len(values), "p50": percentile(values, .5), "p95": percentile(values, .95)}
    for field in ("projection_ms", "upload_ms"):
        values = [r[field] for r in measured if r["kind"] == "map_update"]
        result[field] = {"samples": len(values), "p50": percentile(values, .5), "p95": percentile(values, .95)}
    result["years_per_second"] = ((end["year"] - sample["year"]) * 1e6 / (end["ticks_us"] - sample["ticks_us"])) if sample and end else None
    memory_path = Path(path).with_suffix(".memory.jsonl")
    if memory_path.exists():
        memory = [json.loads(line) for line in memory_path.read_text(encoding="utf-8-sig").splitlines() if line.strip()]
        result["process_working_set_peak_bytes"] = {key: max((r.get(key, 0) for r in memory), default=0) for key in ("godot_bytes", "go_bytes", "combined_bytes")}
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("captures", nargs="+")
    parser.add_argument("--out")
    args = parser.parse_args()
    data = [summary(path) for path in args.captures]
    content = json.dumps(data, indent=2) + "\n"
    if args.out:
        Path(args.out).write_text(content)
    print(content)
