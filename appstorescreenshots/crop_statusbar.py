#!/usr/bin/env python3
"""Crop status bar (battery, time, signal) from screenshots."""

from pathlib import Path
from PIL import Image

# Status bar height in pixels (iPhone ~60px at 2x)
STATUSBAR_HEIGHT = 60

def main():
    base = Path(__file__).resolve().parent
    out_dir = base / "cropped"
    out_dir.mkdir(exist_ok=True)
    
    for f in sorted(base.glob("IMG_*.PNG")):
        img = Image.open(f).convert("RGB")
        w, h = img.size
        cropped = img.crop((0, STATUSBAR_HEIGHT, w, h))
        out_path = out_dir / f.name
        cropped.save(out_path, "PNG", quality=95)
        print(f"Cropped {f.name} -> {out_path}")

if __name__ == "__main__":
    main()
