#!/usr/bin/env python3
"""Rasterise Natural Earth land polygons to an equirectangular 8-bit mask (255 land, 0 sea).

Deterministic: pure numpy/Pillow, no randomness. Pixel centres are sampled.
usage: land_mask.py ZIP OUT_DIR [--bbox W S E N] [--px-per-deg N]
"""
import argparse, hashlib, io, json, struct, sys, zipfile
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

def read_polygons(shp):
    """Yield polygons as lists of rings (Polygon type 5 only)."""
    typ = struct.unpack("<i", shp[32:36])[0]
    if typ != 5:
        raise ValueError(f"unsupported shape type {typ}")
    pos = 100
    while pos < len(shp):
        length = struct.unpack(">i", shp[pos + 4:pos + 8])[0] * 2
        rec = shp[pos + 8:pos + 8 + length]
        pos += 8 + length
        if struct.unpack("<i", rec[:4])[0] == 0:
            continue
        nparts, npts = struct.unpack("<ii", rec[36:44])
        parts = list(struct.unpack(f"<{nparts}i", rec[44:44 + 4 * nparts])) + [npts]
        pts = np.frombuffer(rec, "<f8", npts * 2, 44 + 4 * nparts).reshape(npts, 2)
        yield [pts[parts[i]:parts[i + 1]] for i in range(nparts)]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("zip"); ap.add_argument("out")
    ap.add_argument("--bbox", type=float, nargs=4, default=[-12, 29, 45, 72], metavar=("W", "S", "E", "N"))
    ap.add_argument("--px-per-deg", type=int, default=20)
    a = ap.parse_args()
    w, s, e, n = a.bbox
    k = a.px_per_deg
    W, H = round((e - w) * k), round((n - s) * k)
    zf = zipfile.ZipFile(a.zip)
    shp_name = next(x for x in zf.namelist() if x.endswith(".shp"))
    mask = np.zeros((H, W), bool)
    for rings in read_polygons(zf.read(shp_name)):
        allp = np.concatenate(rings)
        if allp[:, 0].max() < w or allp[:, 0].min() > e or allp[:, 1].max() < s or allp[:, 1].min() > n:
            continue
        poly = np.zeros((H, W), bool)  # even-odd: holes toggle out
        for r in rings:
            im = Image.new("1", (W, H), 0)
            xy = [((x - w) * k - .5, (n - y) * k - .5) for x, y in r]
            ImageDraw.Draw(im).polygon(xy, fill=1)
            poly ^= np.asarray(im, bool)
        mask |= poly
    img = Image.fromarray((mask * 255).astype(np.uint8), "L")
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    buf = io.BytesIO(); img.save(buf, "PNG", optimize=False)
    (out / "land_mask.png").write_bytes(buf.getvalue())
    meta = {
        "schema": "asabiya/atlas-land-mask-v1",
        "source": {"zip": Path(a.zip).name, "sha256": hashlib.sha256(Path(a.zip).read_bytes()).hexdigest()},
        "crs": "EPSG:4326", "projection": "equirectangular", "bbox": a.bbox, "pxPerDeg": k,
        "width": W, "height": H, "landPixels": int(mask.sum()),
        "sha256": hashlib.sha256(buf.getvalue()).hexdigest(),
        "note": "Contemporary coast; not paleogeographic. 255=land 0=sea.",
    }
    (out / "land_mask.json").write_text(json.dumps(meta, indent=2) + "\n")
    print(json.dumps(meta))

if __name__ == "__main__":
    main()
