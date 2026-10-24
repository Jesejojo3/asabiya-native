#!/usr/bin/env python3
"""HydroRIVERS v10 (shapefile) -> simplified, topology-checked river reaches for a lon/lat box.

Keeps reaches with ORD_FLOW <= --max-ord-flow (1 = largest rivers; 4 ~ continental,
6 ~ regional, 8 ~ local). Observed/modelled values stay separate: `modelled` holds
HydroSHEDS' modelled mean discharge; navigability is NOT derived here.

usage: rivers.py ZIP OUT.json [--bbox W S E N] [--max-ord-flow N] [--tol DEG]
"""
import argparse, hashlib, json, struct, sys, zipfile
from pathlib import Path
import numpy as np

CITATION = ("Lehner, B., Grill G. (2013): Global river hydrography and network routing: baseline data and new "
            "approaches to study the world's large river systems. Hydrological Processes, 27(15): 2171-2186. "
            "Data is available at www.hydrosheds.org.")

def dbf_reader(data):
    n, hl, rl = struct.unpack("<IHH", data[4:12])
    fields, pos = [], 32
    while data[pos] != 0x0D:
        d = data[pos:pos + 32]
        fields.append((d[:11].split(b"\0")[0].decode(), d[16]))
        pos += 32
    def get(i):
        rec = data[hl + i * rl + 1: hl + (i + 1) * rl]
        out, o = {}, 0
        for name, ln in fields:
            out[name] = rec[o:o + ln].strip(); o += ln
        return out
    return n, get

def rdp(pts, tol):
    """Douglas-Peucker (iterative); keeps endpoints."""
    n = len(pts)
    if n < 3:
        return pts
    keep = np.zeros(n, bool); keep[[0, -1]] = True
    stack = [(0, n - 1)]
    while stack:
        a, b = stack.pop()
        if b <= a + 1:
            continue
        p, q = pts[a], pts[b]
        d = q - p
        seg = pts[a + 1:b] - p
        L = np.hypot(*d)
        dist = np.hypot(*seg.T) if L == 0 else np.abs(d[0] * seg[:, 1] - d[1] * seg[:, 0]) / L
        i = int(dist.argmax())
        if dist[i] > tol:
            m = a + 1 + i; keep[m] = True
            stack += [(a, m), (m, b)]
    return pts[keep]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("zip"); ap.add_argument("out")
    ap.add_argument("--bbox", type=float, nargs=4, default=[-12, 29, 45, 72])
    ap.add_argument("--max-ord-flow", type=int, default=6)
    ap.add_argument("--tol", type=float, default=0.005)
    a = ap.parse_args()
    w, s, e, n = a.bbox
    zf = zipfile.ZipFile(a.zip)
    shp = zf.read(next(x for x in zf.namelist() if x.endswith(".shp")))
    cnt, get = dbf_reader(zf.read(next(x for x in zf.namelist() if x.endswith(".dbf"))))
    assert struct.unpack("<i", shp[32:36])[0] == 3, "expected PolyLine"
    reaches, pos, i = {}, 100, 0
    while pos < len(shp):
        ln = struct.unpack(">i", shp[pos + 4:pos + 8])[0] * 2
        rec = shp[pos + 8:pos + 8 + ln]; pos += 8 + ln
        xmin, ymin, xmax, ymax = struct.unpack("<4d", rec[4:36])
        idx, i = i, i + 1
        if xmax < w or xmin > e or ymax < s or ymin > n:
            continue
        at = get(idx)
        of = int(at["ORD_FLOW"])
        if of > a.max_ord_flow:
            continue
        nparts, npts = struct.unpack("<ii", rec[36:44])
        pts = np.frombuffer(rec, "<f8", npts * 2, 44 + 4 * nparts).reshape(npts, 2)
        pts = rdp(pts, a.tol)
        rid = int(at["HYRIV_ID"])
        reaches[rid] = {
            "id": rid, "nextDown": int(at["NEXT_DOWN"]), "basin": int(at["MAIN_RIV"]),
            "lengthKm": float(at["LENGTH_KM"]), "ordFlow": of, "ordStrahler": int(at["ORD_STRA"]),
            "endorheic": int(at["ENDORHEIC"]),
            "modelled": {"meanDischargeCms": float(at["DIS_AV_CMS"])},
            "line": [[round(float(x), 5), round(float(y), 5)] for x, y in pts],
        }
    # topology checks
    external = sum(1 for r in reaches.values() if r["nextDown"] and r["nextDown"] not in reaches)
    mouths = [r for r in reaches.values() if r["nextDown"] == 0]
    pairs = [(r, reaches[r["nextDown"]]) for r in reaches.values() if r["nextDown"] in reaches]
    # discharge may dip slightly downstream (losses/diversions, rounding at class limits): flag only >10% drops
    class_dips = sum(1 for r, d in pairs if d["ordFlow"] > r["ordFlow"])
    bad_order = sum(1 for r, d in pairs if d["modelled"]["meanDischargeCms"] < 0.9 * r["modelled"]["meanDischargeCms"])
    state, cycles = {}, 0
    for rid in reaches:  # iterative cycle detection along nextDown chains
        path, cur = [], rid
        while cur in reaches and state.get(cur) is None:
            state[cur] = 1; path.append(cur); cur = reaches[cur]["nextDown"]
        if state.get(cur) == 1 and cur in path:
            cycles += 1
        for p in path:
            state[p] = 2
    top = sorted(mouths, key=lambda r: -r["modelled"]["meanDischargeCms"])[:8]
    meta = {
        "schema": "asabiya/atlas-rivers-v1", "source": "HydroRIVERS v10 (Europe and Middle East shapefile)",
        "sourceSha256": hashlib.sha256(Path(a.zip).read_bytes()).hexdigest(), "citation": CITATION,
        "license": "HydroSHEDS License Agreement (free incl. commercial; redistribution terms NOT yet reviewed)",
        "crs": "EPSG:4326", "bbox": a.bbox, "maxOrdFlow": a.max_ord_flow, "simplifyTolDeg": a.tol,
        "reachCount": len(reaches), "mouths": len(mouths), "downstreamOutsideSet": external,
        "downstreamDischargeDropsOver10pct": bad_order, "downstreamClassDips": class_dips, "cycles": cycles,
        "note": "ordFlow 1 = largest. Discharge is modelled, not observed. Navigability not derived.",
    }
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    Path(a.out).write_text(json.dumps({"meta": meta, "reaches": [reaches[k] for k in sorted(reaches)]}, separators=(",", ":")))
    print(json.dumps(meta, indent=1))
    print("largest mouths (id, modelled m3/s, mouth lon/lat):")
    for r in top:
        print(r["id"], r["modelled"]["meanDischargeCms"], r["line"][-1])
    sys.exit(1 if cycles else 0)

if __name__ == "__main__":
    main()
