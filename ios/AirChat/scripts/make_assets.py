#!/usr/bin/env python3
"""
make_assets.py — builds ios/AirChat/AirChat/Resources/Assets.xcassets.

AirChat's Android icon (app/src/main/ic_launcher-playstore.png) is a 512px square with
rounded, transparent corners. iOS wants an opaque, full-bleed square and masks it into
a squircle itself, so the corners are painted from the artwork's own gradient before
resampling. Then the classic iOS icon idioms + the launch-screen logo are emitted.

Needs Pillow:  pip3 install --break-system-packages pillow
"""
import json
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                                   # ios/AirChat
REPO = os.path.dirname(os.path.dirname(ROOT))                  # repo root
SOURCE = os.path.join(REPO, "app", "src", "main", "ic_launcher-playstore.png")
CATALOG = os.path.join(ROOT, "AirChat", "Resources", "Assets.xcassets")

# size -> (scale, filename) for the classic iPhone app icon
IPHONE_ICON = [
    ("20x20", 2), ("20x20", 3),
    ("29x29", 2), ("29x29", 3),
    ("40x40", 2), ("40x40", 3),
    ("60x60", 2), ("60x60", 3),
]


def base_artwork(size=1024):
    img = Image.open(SOURCE).convert("RGBA")
    w, h = img.size
    # Gradient endpoints taken from the artwork itself: first/last opaque pixel in the
    # centre column. Filling the transparent corners keeps the icon opaque as required.
    def first_y(reverse=False):
        xs = range(h - 1, -1, -1) if reverse else range(h)
        for y in xs:
            if img.getpixel((w // 2, y))[3] > 200:
                return y
        return 0
    top, bottom = first_y(), first_y(reverse=True)
    top_rgba = img.getpixel((w // 2, top))
    bottom_rgba = img.getpixel((w // 2, bottom))

    canvas = Image.new("RGB", (size, size))
    draw = ImageDraw.Draw(canvas)
    for y in range(size):
        t = y / max(1, size - 1)
        colour = tuple(int(top_rgba[i] * (1 - t) + bottom_rgba[i] * t) for i in range(3))
        draw.line([(0, y), (size, y)], fill=colour)
    artwork = img.resize((size, size), Image.LANCZOS)
    canvas.paste(artwork, (0, 0), artwork)
    return canvas


def write_png(image, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save(path, "PNG", optimize=True)


def app_icon():
    folder = os.path.join(CATALOG, "AppIcon.appiconset")
    os.makedirs(folder, exist_ok=True)
    big = base_artwork(1024)
    entries = []
    for (logical, scale) in IPHONE_ICON:
        px = int(logical.split("x")[0]) * scale
        name = "icon-%d-%dx.png" % (px, px)
        write_png(big.resize((px, px), Image.LANCZOS), os.path.join(folder, name))
        entries.append({
            "size": logical, "idiom": "iphone", "scale": "%dx" % scale, "filename": name
        })
    write_png(big, os.path.join(folder, "icon-1024.png"))
    entries.append({"size": "1024x1024", "idiom": "ios-marketing", "scale": "1x", "filename": "icon-1024.png"})
    entries.append({"size": "20x20", "idiom": "ipad", "scale": "1x"})
    entries.append({"size": "20x20", "idiom": "ipad", "scale": "2x"})
    entries.append({"size": "29x29", "idiom": "ipad", "scale": "1x"})
    entries.append({"size": "29x29", "idiom": "ipad", "scale": "2x"})
    entries.append({"size": "40x40", "idiom": "ipad", "scale": "1x"})
    entries.append({"size": "40x40", "idiom": "ipad", "scale": "2x"})
    entries.append({"size": "76x76", "idiom": "ipad", "scale": "1x"})
    entries.append({"size": "76x76", "idiom": "ipad", "scale": "2x"})
    entries.append({"size": "83.5x83.5", "idiom": "ipad", "scale": "2x"})
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({"images": entries, "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")


def imageset(name, image, sizes=(1, 2, 3), base=160):
    folder = os.path.join(CATALOG, name + ".imageset")
    os.makedirs(folder, exist_ok=True)
    entries = []
    for scale in sizes:
        side = base * scale
        suffix = "" if scale == 1 else "@%dx" % scale
        filename = "%s%s.png" % (name, suffix)
        write_png(image.resize((side, side), Image.LANCZOS), os.path.join(folder, filename))
        entries.append({"idiom": "universal", "scale": "%dx" % scale, "filename": filename})
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({"images": entries,
                   "properties": {"template-rendering-intent": "original"},
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")


def colorset(name, rgba):
    folder = os.path.join(CATALOG, name + ".colorset")
    os.makedirs(folder, exist_ok=True)
    components = [round(c / 255.0, 4) for c in rgba[:3]]
    entries = [{"idiom": "universal",
                "color": {"components": {"red": components[0], "green": components[1],
                                         "blue": components[2], "alpha": str(rgba[3])}}}]
    if name == "SplashBackground":
        # follow the system appearance, like the Android values-night theme does
        entries.append({"idiom": "universal", "appearances": [{"appearance": "luminosity", "value": "light"}],
                        "color": {"components": {"red": "1.0", "green": "1.0", "blue": "1.0", "alpha": "1.0"}}})
        entries[0]["color"]["components"] = {"red": "0.0", "green": "0.0", "blue": "0.0", "alpha": "1.0"}
        entries[0]["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({"colors": entries, "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")


def main():
    os.makedirs(CATALOG, exist_ok=True)
    with open(os.path.join(CATALOG, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")
    artwork = base_artwork(1024)
    app_icon()
    imageset("SplashLogo", artwork.convert("RGBA"), sizes=(1, 2, 3), base=150)
    colorset("AccentColor", (0, 132, 255, 1))
    colorset("SplashBackground", (0, 0, 0, 1))
    print("wrote " + CATALOG)


if __name__ == "__main__":
    main()
