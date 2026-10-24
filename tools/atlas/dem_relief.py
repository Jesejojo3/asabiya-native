#!/usr/bin/env python3
"""Copernicus DEM GLO-90 -> elevation, slope and shaded relief for a lon/lat box.

Whole-degree box only. Outputs are block-averaged by --factor (default 4 => 300 px/deg). Missing tiles (open sea) are treated as elevation 0 and
reported. Deterministic (numpy only). Tile SHA-256s are recorded in the output
metadata (trust-on-first-use: the provider publishes no checksums).

usage: dem_relief.py CACHE_DIR OUT_DIR W S E N [--zfactor 2.0]
"""
import argparse, hashlib, io, json, math, sys, urllib.error, urllib.request
from pathlib import Path
import numpy as np
import tifffile
from PIL import Image

BASE = "https://copernicus-dem-90m.s3.amazonaws.com"
PX = 1200  # pixels per degree (3 arc-seconds)
R = 6371008.8
ATTRIBUTION = ("produced using Copernicus WorldDEM-90 © DLR e.V. 2010-2014 and © Airbus Defence and "
               "Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved")

def tile_name(lon, lat):
    ns = f"{'N' if lat >= 0 else 'S'}{abs(lat):02d}_00"
    ew = f"{'E' if lon >= 0 else 'W'}{abs(lon):03d}_00"
    return f"Copernicus_DSM_COG_30_{ns}_{ew}_DEM"

def fetch(cache, name):
    dst = cache / f"{name}.tif"
    if not dst.exists():
        try:
            urllib.request.urlretrieve(f"{BASE}/{name}/{name}.tif", dst)
        except urllib.error.HTTPError as e:
            if e.code in (403, 404):
                return None
            raise
    return dst

def hypsometric(z):
    """Soft editorial tint (RGB 0-255) from elevation in metres."""
    stops = [(0, (170, 200, 150)), (300, (205, 215, 160)), (800, (225, 210, 160)),
             (1500, (200, 170, 130)), (2500, (170, 150, 135)), (3500, (215, 210, 205)), (4500, (250, 250, 250))]
    xs = [s[0] for s in stops]
    out = np.empty(z.shape + (3,), np.float64)
    for c in range(3):
        out[..., c] = np.interp(z, xs, [s[1][c] for s in stops])
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cache"); ap.add_argument("out")
    ap.add_argument("bbox", type=int, nargs=4, metavar=("W", "S", "E", "N"))
    ap.add_argument("--factor", type=int, default=4, help="block-mean downsample of the outputs (shading is computed at full resolution first)")
    ap.add_argument("--zfactor", type=float, default=2.0, help="vertical exaggeration for shading only")
    a = ap.parse_args()
    w, s, e, n = a.bbox
    cache = Path(a.cache); cache.mkdir(parents=True, exist_ok=True)
    W, H = (e - w) * PX, (n - s) * PX
    dem = np.zeros((H, W), np.float32)
    tiles, missing = {}, []
    for lat in range(s, n):
        for lon in range(w, e):
            name = tile_name(lon, lat)
            p = fetch(cache, name)
            if p is None:
                missing.append(name); continue
            arr = tifffile.imread(p)
            assert arr.shape == (PX, PX), (name, arr.shape)
            dem[(n - lat - 1) * PX:(n - lat) * PX, (lon - w) * PX:(lon - w + 1) * PX] = arr
            tiles[name] = hashlib.sha256(p.read_bytes()).hexdigest()
    dem = np.maximum(dem, 0)  # bathymetry is not in this product; keep >= 0

    # Horn gradients with latitude-dependent cell size.
    lat_c = n - (np.arange(H) + .5) / PX
    dx = (R * np.cos(np.radians(lat_c)) * np.radians(1 / PX))[:, None]
    dy = R * np.radians(1 / PX)
    z = np.pad(dem, 1, mode="edge").astype(np.float64)
    zx = ((z[:-2, 2:] + 2 * z[1:-1, 2:] + z[2:, 2:]) - (z[:-2, :-2] + 2 * z[1:-1, :-2] + z[2:, :-2])) / (8 * dx)
    zy = ((z[2:, :-2] + 2 * z[2:, 1:-1] + z[2:, 2:]) - (z[:-2, :-2] + 2 * z[:-2, 1:-1] + z[:-2, 2:])) / (8 * dy)
    slope = np.degrees(np.arctan(np.hypot(zx, zy)))
    zf = a.zfactor
    az, alt = math.radians(315), math.radians(45)
    sl = np.arctan(zf * np.hypot(zx, zy))
    asp = np.arctan2(zy, -zx)  # image rows grow southwards
    shade = np.clip(np.sin(alt) * np.cos(sl) + np.cos(alt) * np.sin(sl) * np.cos(az - asp), 0, 1)
    shade_n = np.sin(alt)  # flat-terrain shade, so flat land keeps its tint
    k = 0.45 + 0.55 * shade / shade_n
    rgb = np.clip(hypsometric(dem) * np.clip(k, 0, 1.3)[..., None], 0, 255).astype(np.uint8)

    f = a.factor
    def block(x):
        x = x.astype(np.float64)
        return x.reshape(H // f, f, W // f, f, *x.shape[2:]).mean(axis=(1, 3))
    rgb = np.rint(block(rgb)).astype(np.uint8)
    slope = block(slope)
    dem_out = block(dem)

    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    def save(name, img, **kw):
        buf = io.BytesIO(); img.save(buf, "PNG", **kw)
        (out / name).write_bytes(buf.getvalue())
        return hashlib.sha256(buf.getvalue()).hexdigest()
    outs = {
        "relief.png": save("relief.png", Image.fromarray(rgb, "RGB")),
        "slope.png": save("slope.png", Image.fromarray(np.clip(slope * 2.5, 0, 255).astype(np.uint8), "L")),  # 0.4 deg/level
        "elevation_u16.png": save("elevation_u16.png", Image.fromarray(np.clip(np.rint(dem_out), 0, 65535).astype(np.uint16))),
    }
    meta = {
        "schema": "asabiya/atlas-relief-v1", "source": "Copernicus DEM GLO-90 (COP-DEM_GLO-90)",
        "provider": f"{BASE}/ (AWS Open Data)", "attribution": ATTRIBUTION,
        "note": "DSM (includes vegetation/buildings). Shading uses zfactor; elevation PNG is unexaggerated metres (16-bit).",
        "crs": "EPSG:4326", "projection": "equirectangular", "bbox": a.bbox, "pxPerDeg": PX // f, "sourcePxPerDeg": PX, "downsample": f,
        "width": W // f, "height": H // f, "zfactor": zf, "light": {"azimuthDeg": 315, "altitudeDeg": 45},
        "elevationM": {"min": float(dem.min()), "max": float(dem.max()), "note": "min/max of full-resolution DEM"},
        "tiles": tiles, "missingTilesTreatedAsSea": missing, "outputs": outs,
    }
    (out / "relief.json").write_text(json.dumps(meta, indent=2) + "\n")
    print(json.dumps({k: meta[k] for k in ("width", "height", "elevationM", "outputs")}), "missing:", len(missing))

if __name__ == "__main__":
    main()
