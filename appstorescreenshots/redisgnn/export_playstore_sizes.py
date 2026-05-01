#!/usr/bin/env python3
"""
Export Play Store (en compatibele) screenshot-formaten uit de final App Store bron (1290×2796).

Afmetingen:
- 1242 × 2688 (portrait)
- 2688 × 1242 (landscape)
- 1284 × 2778 (portrait)
- 2778 × 1284 (landscape)
"""

from pathlib import Path
from PIL import Image

PAD = (254, 190, 35)  # GYMIES geel

SIZES = [
    ("1242x2688_portrait", 1242, 2688),
    ("2688x1242_landscape", 2688, 1242),
    ("1284x2778_portrait", 1284, 2778),
    ("2778x1284_landscape", 2778, 1284),
]


def resize_cover(img: Image.Image, tw: int, th: int) -> Image.Image:
    """Schaal zodat hele doel gevuld is, crop midden."""
    iw, ih = img.size
    scale = max(tw / iw, th / ih)
    nw, nh = int(iw * scale), int(ih * scale)
    resized = img.resize((nw, nh), Image.Resampling.LANCZOS)
    left = (nw - tw) // 2
    top = (nh - th) // 2
    return resized.crop((left, top, left + tw, top + th))


def resize_contain_pad(img: Image.Image, tw: int, th: int) -> Image.Image:
    """Schaal passend binnen doel, gele rand."""
    iw, ih = img.size
    scale = min(tw / iw, th / ih)
    nw, nh = int(iw * scale), int(ih * scale)
    resized = img.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", (tw, th), PAD)
    x, y = (tw - nw) // 2, (th - nh) // 2
    canvas.paste(resized, (x, y))
    return canvas


def main():
    root = Path(__file__).resolve().parent
    src_dir = root / "final" / "appstore"
    out_root = root / "final" / "playstore_all_sizes"
    if not src_dir.is_dir():
        print("Bron ontbreekt:", src_dir)
        return

    for png in sorted(src_dir.glob("redisgnn_*.png")):
        img = Image.open(png).convert("RGB")
        for folder, w, h in SIZES:
            out_dir = out_root / folder
            out_dir.mkdir(parents=True, exist_ok=True)
            if w > h:
                # landscape: draai bron 90° met de klok mee → breed beeld
                rot = img.transpose(Image.Transpose.ROTATE_270)
                out = resize_cover(rot, w, h)
            else:
                out = img.resize((w, h), Image.Resampling.LANCZOS)
            dest = out_dir / png.name
            out.save(dest, "PNG", quality=95)
            print(dest.relative_to(root))

    # Ook legacy playstore map bijwerken met 1284×2778 (meest gebruikelijk naast 1242×2688)
    legacy = root / "final" / "playstore"
    legacy.mkdir(parents=True, exist_ok=True)
    for png in sorted(src_dir.glob("redisgnn_*.png")):
        img = Image.open(png).convert("RGB")
        out = img.resize((1284, 2778), Image.Resampling.LANCZOS)
        out.save(legacy / png.name, "PNG", quality=95)
    print("Updated final/playstore/ → 1284×2778")

    print("Done:", out_root)


if __name__ == "__main__":
    main()
