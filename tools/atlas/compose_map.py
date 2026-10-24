#!/usr/bin/env python3
"""Paint sea (from the Natural Earth land mask) over a shaded-relief PNG on the same grid.

usage: compose_map.py RELIEF_DIR MASK_DIR OUT_PNG
Both inputs must share bbox and pxPerDeg (generate the mask with the same --bbox/--px-per-deg).
"""
import hashlib, json, sys
from pathlib import Path
import numpy as np
from PIL import Image

def main():
    rd, md, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    rm, mm = json.loads((rd / "relief.json").read_text()), json.loads((md / "land_mask.json").read_text())
    for k in ("bbox", "pxPerDeg", "width", "height"):
        if rm[k] != mm[k]:
            sys.exit(f"grid mismatch on {k}: relief {rm[k]} vs mask {mm[k]}")
    rgb = np.asarray(Image.open(rd / "relief.png").convert("RGB")).astype(np.float64)
    land = np.asarray(Image.open(md / "land_mask.png")) > 127
    sea = np.array([168, 196, 214], np.float64)
    # sea depth cue: lighter near coast is not modelled (no bathymetry); flat tint only
    res = np.where(land[..., None], rgb, sea)
    Image.fromarray(res.astype(np.uint8), "RGB").save(out)
    print(hashlib.sha256(out.read_bytes()).hexdigest(), out)

if __name__ == "__main__":
    main()
