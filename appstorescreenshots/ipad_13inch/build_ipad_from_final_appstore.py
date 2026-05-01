#!/usr/bin/env python3
"""
Schaaft de bestaande App Store-bronscreenshots (redisgnn/final/appstore) op naar
2732 × 2048 (13" iPad landscape) met GYMIES-gele marge — zelfde bron als Play Store-export.
"""

from pathlib import Path

from PIL import Image

W, H = 2732, 2048
PAD = (254, 190, 35)  # GYMIES geel — zelfde als export_playstore_sizes.py

HERE = Path(__file__).resolve().parent
SRC_DIR = HERE.parent / "redisgnn" / "final" / "appstore"
OUT_DIR = HERE


def resize_contain_pad(img: Image.Image, tw: int, th: int) -> Image.Image:
    """Maximaal vergroten binnen doel, volledige screenshot zichtbaar, gele rand."""
    img = img.convert("RGB")
    iw, ih = img.size
    scale = min(tw / iw, th / ih)
    nw, nh = int(iw * scale), int(ih * scale)
    resized = img.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", (tw, th), PAD)
    x, y = (tw - nw) // 2, (th - nh) // 2
    canvas.paste(resized, (x, y))
    return canvas


def main() -> None:
    if not SRC_DIR.is_dir():
        raise SystemExit(f"Bronmap ontbreekt: {SRC_DIR}")

    for png in sorted(SRC_DIR.glob("redisgnn_*.png")):
        img = Image.open(png)
        out = resize_contain_pad(img, W, H)
        dest = OUT_DIR / f"{png.stem}_2732x2048.png"
        out.save(dest, "PNG", optimize=True)
        print(dest.name, "←", png.name, "| bron", img.size, "→", out.size)


if __name__ == "__main__":
    main()
