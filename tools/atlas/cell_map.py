#!/usr/bin/env python3
"""Map atlas units onto the engine's logical grid (equirectangular cell centres, row 0 north).

cell id = y*W + x; cell (x,y) covers lon [-180+360x/W, -180+360(x+1)/W), lat (90-180y/H) down to (90-180(y+1)/H)
(from internal/sim/world.go). Each cell is sampled on an SxS sub-grid (default 18x18 = 0.05 deg for 400x200);
samples are assigned to units by point-in-polygon rasterisation of the stored geometry, and weighted by cos(lat).
Output is many-to-many with area fractions: a cell may overlap several units and a unit several cells.

usage: cell_map.py UNITS_DIR OUT.json [--width 400 --height 200 --sub 9]
"""
import argparse, hashlib, json, math, sys
from pathlib import Path
import numpy as np

def scanline_mask(rings, lon0, lat0, px, r0, r1, c0, c1):
    """Exact even-odd fill evaluated at sample centres (no boundary-inclusion bias)."""
    m = np.zeros((r1 - r0, c1 - c0), bool)
    xc = lon0 + (np.arange(c0, c1) + .5) * px
    segs = []
    for ring in rings:
        r = np.asarray(ring, float)
        segs.append(np.stack([r[:-1, 0], r[:-1, 1], r[1:, 0], r[1:, 1]], 1))
    e = np.concatenate(segs)
    for row in range(r0, r1):
        y = lat0 - (row + .5) * px
        sel = (e[:, 1] > y) != (e[:, 3] > y)
        if not sel.any():
            continue
        q = e[sel]
        xs = np.sort(q[:, 0] + (y - q[:, 1]) * (q[:, 2] - q[:, 0]) / (q[:, 3] - q[:, 1]))
        # a sample is inside when an odd number of crossings lies to its left
        m[row - r0] = (np.searchsorted(xs, xc, side="right") % 2) == 1
    return m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("units"); ap.add_argument("out")
    ap.add_argument("--width", type=int, default=400); ap.add_argument("--height", type=int, default=200)
    ap.add_argument("--sub", type=int, default=18)
    a = ap.parse_args()
    d = Path(a.units)
    U = json.loads((d / "units.json").read_text()); gj = json.loads((d / "units_geom.json").read_text()); sc = gj["scale"]
    G = {k: [[(x / sc, y / sc) for x, y in r] for r in rs] for k, rs in gj["rings"].items()}
    meta, units = U["meta"], U["units"]
    W, H, S = a.width, a.height, a.sub
    cw, ch = 360 / W, 180 / H
    bw, bs, be, bn = meta["bbox"]
    # cell-aligned window covering the bbox
    x0, x1 = math.floor((bw + 180) / cw), math.ceil((be + 180) / cw)
    y0, y1 = math.floor((90 - bn) / ch), math.ceil((90 - bs) / ch)
    rw, rh = (x1 - x0) * S, (y1 - y0) * S
    px = cw / S                       # degrees per sample
    lon0, lat0 = -180 + x0 * cw, 90 - y0 * ch
    ids = np.full((rh, rw), -1, np.int32)
    idx_of = {u["id"]: k for k, u in enumerate(units)}
    for u in units:
        ub = u["bbox"]
        c0 = max(0, int((ub[0] - lon0) / px) - 1); c1 = min(rw, int((ub[2] - lon0) / px) + 2)
        r0 = max(0, int((lat0 - ub[3]) / px) - 1); r1 = min(rh, int((lat0 - ub[1]) / px) + 2)
        if c1 <= c0 or r1 <= r0:
            continue
        m = scanline_mask(G[u["id"]], lon0, lat0, px, r0, r1, c0, c1)
        sub = ids[r0:r1, c0:c1]
        sub[m & (sub < 0)] = idx_of[u["id"]]
    # per-cell fractions
    lat_rows = lat0 - (np.arange(rh) + .5) * px
    wgt = np.cos(np.radians(lat_rows))[:, None] * np.ones((1, rw))
    cells, unit_area_samples = [], np.zeros(len(units))
    tot_cell_w = {}
    for cy in range(y1 - y0):
        for cx in range(x1 - x0):
            blk = ids[cy * S:(cy + 1) * S, cx * S:(cx + 1) * S]
            if (blk >= 0).sum() == 0:
                continue
            wb = wgt[cy * S:(cy + 1) * S, cx * S:(cx + 1) * S]
            tot = wb.sum()
            acc = {}
            for k in np.unique(blk[blk >= 0]):
                acc[int(k)] = float(wb[blk == k].sum() / tot)
            cell_id = (y0 + cy) * W + (x0 + cx)
            cell_area = (40075.0 / W) * (20004.0 / H) * math.cos(math.radians(90 - (y0 + cy + .5) * ch))
            for k, f in acc.items():
                unit_area_samples[k] += f * cell_area
            cells.append({"cell": cell_id, "covered": round(sum(acc.values()), 4),
                          "units": [[units[k]["id"], round(f, 4)] for k, f in sorted(acc.items(), key=lambda t: (-t[1], t[0]))]})
    areas = np.array([u["areaKm2"] for u in units])
    rel = np.abs(unit_area_samples - areas) / areas
    # units wholly inside the cell-aligned window and larger than 20 000 km2 (smaller ones are dominated by
    # simplification/sampling noise; units crossing the window edge are legitimately cut)
    wx0, wx1, wy1, wy0 = lon0, lon0 + (x1 - x0) * cw, lat0, lat0 - (y1 - y0) * ch
    big = np.array([u["bbox"][0] >= wx0 and u["bbox"][2] <= wx1 and u["bbox"][1] >= wy0 and u["bbox"][3] <= wy1 and u["areaKm2"] > 20000 for u in units])
    unmapped = [u["id"] for k, u in enumerate(units) if unit_area_samples[k] == 0]
    out_meta = {
        "schema": "asabiya/atlas-cell-map-v1", "unitsSha256": hashlib.sha256((d / "units.json").read_bytes()).hexdigest(),
        "grid": {"width": W, "height": H, "idFormula": "y*width+x", "lonOfX": "-180+360*(x+0.5)/width", "latOfY": "90-180*(y+0.5)/height", "rowZero": "north"},
        "subSamplesPerCellAxis": S, "cellsMapped": len(cells),
        "cellsFullyCovered": sum(c["covered"] >= 0.9999 for c in cells),
        "cellsPartlyCovered": sum(c["covered"] < 0.9999 for c in cells),
        "unitsWithNoCellSamples": len(unmapped),
        "interiorUnitAreaVsSamples": {"units": int(big.sum()), "maxRelErr": round(float(rel[big].max()), 4), "medianRelErr": round(float(np.median(rel[big])), 4),
                              "p95RelErr": round(float(np.percentile(rel[big], 95)), 4),
                              "note": "edge units are cut by the window, so totals differ"},
        "totalSampledKm2": round(float(unit_area_samples.sum()), 1), "totalUnitKm2": round(float(areas.sum()), 1),
        "note": "Many-to-many with area fractions. Cells only partly covered lie on the bbox edge or the coast; "
                "the engine's own land/sea decision is not used here.",
    }
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    Path(a.out).write_text(json.dumps({"meta": out_meta, "cells": cells}, separators=(",", ":")))
    print(json.dumps(out_meta, indent=1))

if __name__ == "__main__":
    main()
