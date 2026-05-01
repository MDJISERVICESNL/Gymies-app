#!/usr/bin/env python3
"""Resize mockups to App Store and Play Store dimensions with yellow padding."""

from pathlib import Path
from PIL import Image

# GYMIES yellow #FEBE23
PAD_COLOR = (254, 190, 35, 255)

# Store dimensions (portrait)
APPSTORE_SIZE = (1290, 2796)   # iPhone 6.9"
PLAYSTORE_SIZE = (1080, 1920)  # 9:16

def resize_and_pad(img: Image.Image, target: tuple[int, int]) -> Image.Image:
    """Resize image to fit within target, add padding to reach exact size."""
    target_w, target_h = target
    img_w, img_h = img.size
    
    # Scale to fit width
    scale = target_w / img_w
    new_w = target_w
    new_h = int(img_h * scale)
    
    if new_h > target_h:
        scale = target_h / img_h
        new_h = target_h
        new_w = int(img_w * scale)
    
    resized = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
    
    # Create canvas with yellow background
    canvas = Image.new("RGBA", target, PAD_COLOR)
    
    # Paste centered
    x = (target_w - new_w) // 2
    y = (target_h - new_h) // 2
    canvas.paste(resized, (x, y))
    
    return canvas.convert("RGB")

def main():
    base = Path(__file__).resolve().parent
    appstore_dir = base / "appstore"
    playstore_dir = base / "playstore"
    appstore_dir.mkdir(exist_ok=True)
    playstore_dir.mkdir(exist_ok=True)
    
    files = [f for f in sorted(base.glob("mockup_0*.png")) 
             if f.parent == base]  # Only files in base, not in subdirs
    if not files:
        print("No mockup_0*.png files found in", base)
        return
    for f in files:
        print(f"Processing {f.name}...")
        img = Image.open(f).convert("RGBA")
        
        appstore_out = appstore_dir / f.name
        playstore_out = playstore_dir / f.name
        
        resize_and_pad(img, APPSTORE_SIZE).save(appstore_out, "PNG", quality=95)
        resize_and_pad(img, PLAYSTORE_SIZE).save(playstore_out, "PNG", quality=95)
    
    print("Done! Check appstore/ and playstore/ folders.")

if __name__ == "__main__":
    main()
