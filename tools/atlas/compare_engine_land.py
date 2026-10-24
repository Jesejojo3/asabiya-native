#!/usr/bin/env python3
"""Compare the engine's logical land/sea layer with the Natural Earth land mask (cells fully inside the mask bbox).

usage: compare_engine_land.py EXPORT_DIR LAND_MASK_DIR [CELL_MAP.json]
EXPORT_DIR holds manifest.json + geography.bin from `asabiya-headless --export`.
Read-only diagnostic: nothing is written. Exit 0 always (it reports, it does not gate).
"""
import json, sys
from pathlib import Path
import numpy as np
from PIL import Image

def main():
    ex, md = Path(sys.argv[1]), Path(sys.argv[2])
    man = json.loads((ex / "manifest.json").read_text())
    W, H = man["logical"]["width"], man["logical"]["height"]
    lay = next(l for l in man["layers"] if l["name"] == "land")
    land = np.frombuffer((ex / "geography.bin").read_bytes(), np.uint8, lay["count"], lay["offset"]).reshape(H, W) > 0
    mm = json.loads((md / "land_mask.json").read_text())
    mask = np.asarray(Image.open(md / "land_mask.png")) > 127
    w, s, e, n = mm["bbox"]; k = mm["pxPerDeg"]
    cwx, chy = 360 / W, 180 / H
    tp = fp = fn = tn = amb = 0  # python ints
    for y in range(H):
        for x in range(W):
            lo0, la1 = -180 + x * cwx, 90 - y * chy
            lo1, la0 = lo0 + cwx, la1 - chy
            if lo0 < w or lo1 > e or la0 < s or la1 > n:
                continue
            f = mask[round((n - la1) * k):round((n - la0) * k), round((lo0 - w) * k):round((lo1 - w) * k)].mean()
            ne, en = f >= .5, bool(land[y, x])
            tp += int(en and ne); tn += int((not en) and (not ne)); fp += int(en and not ne); fn += int(ne and not en)
            if en != ne and .15 <= f <= .85:
                amb += 1
    t = tp + tn + fp + fn
    print(json.dumps({"cellsCompared": int(t), "agreementPct": round(100 * (tp + tn) / t, 2), "bothLand": int(tp), "bothSea": int(tn),
                      "engineOnlyLand": int(fp), "naturalEarthOnlyLand": int(fn), "mismatchesWithCoastalAmbiguity": int(amb),
                      "engineWorldSha256": man.get("worldSHA256")}, indent=1))

if __name__ == "__main__":
    main()
