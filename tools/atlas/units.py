#!/usr/bin/env python3
"""Stable territorial units from HydroBASINS (Pfafstetter level) for a lon/lat box.

1. take basins whose bbox centre lies in --bbox (clipping basins would invent borders);
2. compute adjacency from shared polygon edges (HydroBASINS is an exact partition);
3. merge slivers (< --min-area km2) into the neighbour with the longest shared border
   (deterministic: ascending area, then id); islands without neighbours are kept;
4. unit id = "u" + HYBAS_ID of its largest member basin (stable within an atlas version).

Units are geographic only: no political or cultural meaning.
usage: units.py ZIP OUT_DIR [--bbox W S E N] [--min-area 400]
"""
import argparse, hashlib, json, math, struct, sys, zipfile
from collections import defaultdict
from pathlib import Path
import numpy as np

R = 6371.0088
SCHEMA = "asabiya/atlas-units-v1"

def dbf_rows(data):
    n, hl, rl = struct.unpack("<IHH", data[4:12]); f = []; p = 32
    while data[p] != 0x0D:
        d = data[p:p + 32]; f.append((d[:11].split(b"\0")[0].decode(), d[16])); p += 32
    for i in range(n):
        rec = data[hl + i * rl + 1:hl + (i + 1) * rl]; o = 0; r = {}
        for k, l in f:
            r[k] = rec[o:o + l].strip(); o += l
        yield r

def ring_signed_area(r):
    lon, lat = np.radians(r[:, 0]), np.radians(r[:, 1])
    dl = np.diff(lon); dl -= 2 * math.pi * np.round(dl / (2 * math.pi))
    return float((dl * (np.sin(lat[:-1]) + np.sin(lat[1:])) / 2).sum()) * R * R

def rdp(pts, tol):
    n = len(pts)
    if n < 4:
        return pts
    keep = np.zeros(n, bool); keep[[0, -1]] = True; st = [(0, n - 1)]
    while st:
        a, b = st.pop()
        if b <= a + 1: continue
        p, q = pts[a], pts[b]; d = q - p; seg = pts[a + 1:b] - p; L = math.hypot(*d)
        dist = np.hypot(*seg.T) if L == 0 else np.abs(d[0] * seg[:, 1] - d[1] * seg[:, 0]) / L
        i = int(dist.argmax())
        if dist[i] > tol:
            m = a + 1 + i; keep[m] = True; st += [(a, m), (m, b)]
    return pts[keep]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("zip"); ap.add_argument("out")
    ap.add_argument("--bbox", type=float, nargs=4, default=[-12, 29, 45, 72])
    ap.add_argument("--min-area", type=float, default=400.0)
    ap.add_argument("--tol", type=float, default=0.01)
    a = ap.parse_args()
    w, s, e, n = a.bbox
    zf = zipfile.ZipFile(a.zip)
    shp = zf.read(next(x for x in zf.namelist() if x.endswith(".shp")))
    rows = list(dbf_rows(zf.read(next(x for x in zf.namelist() if x.endswith(".dbf")))))
    basins = {}  # id -> dict
    pos = i = 0; pos = 100
    while pos < len(shp):
        ln = struct.unpack(">i", shp[pos + 4:pos + 8])[0] * 2; rec = shp[pos + 8:pos + 8 + ln]; pos += 8 + ln
        at = rows[i]; i += 1
        x0, y0, x1, y1 = struct.unpack("<4d", rec[4:36])
        if not (w <= (x0 + x1) / 2 <= e and s <= (y0 + y1) / 2 <= n):
            continue
        nparts, npts = struct.unpack("<ii", rec[36:44])
        parts = list(struct.unpack(f"<{nparts}i", rec[44:44 + 4 * nparts])) + [npts]
        pts = np.frombuffer(rec, "<f8", npts * 2, 44 + 4 * nparts).reshape(npts, 2)
        rings = [pts[parts[k]:parts[k + 1]] for k in range(nparts)]
        area = abs(sum(ring_signed_area(r) for r in rings))
        edges = set()
        for r in rings:
            q = np.rint(r * 1e6).astype(np.int64)
            for p0, p1 in zip(map(tuple, q[:-1]), map(tuple, q[1:])):
                edges.add((p0, p1) if p0 <= p1 else (p1, p0))
        hid = int(at["HYBAS_ID"])
        basins[hid] = {"id": hid, "area": area, "attrArea": float(at["SUB_AREA"]), "coast": int(at["COAST"]),
                       "next": int(at["NEXT_DOWN"]), "rings": rings, "edges": edges}
    # adjacency by shared edges (weights = number of shared segments)
    owner = defaultdict(list)
    for hid, b in basins.items():
        for ed in b["edges"]:
            owner[ed].append(hid)
    adj = defaultdict(lambda: defaultdict(int))
    for ed, o in owner.items():
        if len(o) == 2:
            adj[o[0]][o[1]] += 1; adj[o[1]][o[0]] += 1
    # merge slivers
    group = {h: h for h in basins}          # basin -> representative
    members = {h: [h] for h in basins}
    garea = {h: basins[h]["area"] for h in basins}
    gadj = {h: dict(adj[h]) for h in basins}
    for h in sorted(basins, key=lambda h: (garea[h], h)):
        g = group[h]
        if g != h or garea[g] >= a.min_area or not gadj[g]:
            continue
        tgt = max(gadj[g], key=lambda k: (gadj[g][k], -k))
        # merge g into tgt
        for m in members[g]: group[m] = tgt
        members[tgt] += members.pop(g); garea[tgt] += garea.pop(g)
        for k, wgt in gadj.pop(g).items():
            if k == tgt: continue
            gadj[tgt][k] = gadj[tgt].get(k, 0) + wgt
            gadj[k][tgt] = gadj[k].get(tgt, 0) + wgt
            del gadj[k][g]
        gadj[tgt].pop(g, None)
    uid = {}
    for g, ms in members.items():
        big = max(ms, key=lambda m: (basins[m]["area"], -m)); uid[g] = f"u{big}"
    for g in members: assert uid[g]
    m2u = {m: uid[g] for g, ms in members.items() for m in ms}
    units, geom = [], {}
    for g in sorted(members, key=lambda g: uid[g]):
        ms = sorted(members[g]); c = np.concatenate([r for m in ms for r in basins[m]["rings"]])
        nb = sorted(({uid[k]: v for k, v in gadj[g].items()}).items())
        nxt = {m2u[basins[m]["next"]] for m in ms if basins[m]["next"] in m2u and m2u[basins[m]["next"]] != uid[g]}
        units.append({"id": uid[g], "basins": ms, "areaKm2": round(garea[g], 2),
                      "bbox": [round(float(c[:, 0].min()), 5), round(float(c[:, 1].min()), 5), round(float(c[:, 0].max()), 5), round(float(c[:, 1].max()), 5)],
                      "coastal": any(basins[m]["coast"] for m in ms), "island": not nb,
                      "neighbours": [{"unit": k, "sharedSegments": v} for k, v in nb],
                      "drainsTo": sorted(nxt)})
        geom[uid[g]] = [[[round(float(x), 4), round(float(y), 4)] for x, y in rdp(r, a.tol)] for m in ms for r in basins[m]["rings"]]
    # checks
    asym = sum(1 for u in units for nb in u["neighbours"] if u["id"] not in {x["unit"] for x in next(v for v in units if v["id"] == nb["unit"])["neighbours"]}) if len(units) < 3000 else -1
    tot = sum(u["areaKm2"] for u in units); attr = sum(b["attrArea"] for b in basins.values())
    areas = np.array([u["areaKm2"] for u in units])
    meta = {"schema": SCHEMA, "source": "HydroBASINS v1c (standard, Europe)", "sourceSha256": hashlib.sha256(Path(a.zip).read_bytes()).hexdigest(),
            "bbox": a.bbox, "minAreaKm2": a.min_area, "basinsIn": len(basins), "units": len(units),
            "islands": sum(u["island"] for u in units), "mergedAway": len(basins) - len(units),
            "areaKm2": {"total": round(tot, 1), "attributeTotal": round(attr, 1), "median": round(float(np.median(areas)), 1),
                        "p5": round(float(np.percentile(areas, 5)), 1), "p95": round(float(np.percentile(areas, 95)), 1),
                        "min": round(float(areas.min()), 1), "max": round(float(areas.max()), 1)},
            "adjacencyAsymmetries": asym,
            "note": "Geographic units only. Outer bbox edge follows whole basins (no clipping). Ids stable only within this atlas version."}
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    (out / "units.json").write_text(json.dumps({"meta": meta, "units": units}, separators=(",", ":")))
    (out / "units_geom.json").write_text(json.dumps({"schema": SCHEMA + "-geometry", "tolDeg": a.tol, "crs": "EPSG:4326", "rings": geom}, separators=(",", ":")))
    print(json.dumps(meta, indent=1))
    ok = abs(tot - attr) / attr < 0.02 and asym == 0 and len(set(u["id"] for u in units)) == len(units)
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
