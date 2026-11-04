"""Makes every app icon from one square picture (design/app_icon.png).

Run from the project root:  python tool/make_app_icons.py [picture]

- iOS: every size in AppIcon.appiconset, opaque (iOS rejects transparency;
  the system rounds the corners itself).
- Android: the old square icons (mipmap-*/ic_launcher.png), and an adaptive
  icon for Android 8+. Launchers mask the adaptive icon to a circle, squircle
  or square showing only the middle two thirds of its 108 dp layers, so the
  whole picture goes in that middle and the edges around it are the picture
  mirrored outwards: nothing important is cut off, and no seam shows when
  the launcher moves the layer a little.
- A picture on a plain background (its edges one colour) is laid out by
  what's drawn on it instead: that is shrunk to fit inside the round mask
  and iOS's rounded corners, on the same colour.
"""
import json, os, sys
from PIL import Image, ImageChops, ImageFilter, ImageOps

SRC = sys.argv[1] if len(sys.argv) > 1 else 'design/app_icon.png'
RES = 'android/app/src/main/res'
IOS = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'

src = Image.open(SRC).convert('RGB')
side = min(src.size)
src = src.crop(((src.width - side) // 2, (src.height - side) // 2, (src.width + side) // 2, (src.height + side) // 2))


# A plain background: its colour, and the box around what's drawn on it.
edge = ([src.getpixel((x, y)) for x in range(0, side, 16) for y in (0, side - 1)]
        + [src.getpixel((x, y)) for y in range(0, side, 16) for x in (0, side - 1)])
plain = all(max(e[c] for e in edge) - min(e[c] for e in edge) <= 16 for c in range(3))
if plain:
    bg_color = tuple(sorted(e[c] for e in edge)[len(edge) // 2] for c in range(3))
    diff = Image.eval(ImageChops.difference(src, Image.new('RGB', src.size, bg_color)).convert('L'), lambda v: 255 if v > 30 else 0)
    box = diff.getbbox()
    content = src.crop(box)
    # Blended in softly: the background isn't quite one colour, and a hard
    # edge around the drawing's box would show on the flat colour.
    soft = diff.filter(ImageFilter.MaxFilter(31)).filter(ImageFilter.GaussianBlur(14)).crop(box)


def placed(size, fit):
    """The drawing, its box's diagonal [fit] of [size], on the plain colour."""
    canvas = Image.new('RGB', (size, size), bg_color)
    w, h = content.size
    k = fit * size / (w * w + h * h) ** .5
    to = (max(1, round(w * k)), max(1, round(h * k)))
    canvas.paste(content.resize(to, Image.LANCZOS), ((size - to[0]) // 2, (size - to[1]) // 2), soft.resize(to, Image.LANCZOS))
    return canvas


def scaled(size):
    # Inside iOS's rounded corners and the old square icons' edges.
    return placed(size, 1.12) if plain else src.resize((size, size), Image.LANCZOS)


# iOS: the sizes Contents.json asks for.
contents = json.load(open(f'{IOS}/Contents.json', encoding='utf8'))
for img in contents['images']:
    if 'filename' not in img:
        continue
    pt = float(img['size'].split('x')[0])
    px = round(pt * int(img['scale'].rstrip('x')))
    scaled(px).save(f'{IOS}/{img["filename"]}')

# Android, square icons for launchers before adaptive icons.
legacy = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
for density, px in legacy.items():
    scaled(px).save(f'{RES}/mipmap-{density}/ic_launcher.png')

# Android adaptive icon: the picture in the visible middle (72 of 108 dp)
# of the background layer, mirrored outwards to fill the rest; the
# foreground layer is empty.
layer = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}
for density, px in layer.items():
    os.makedirs(f'{RES}/drawable-{density}', exist_ok=True)
    if plain:
        # Within the round mask: the visible circle is 72 of 108 dp across.
        placed(px, 72 / 108).save(f'{RES}/drawable-{density}/ic_launcher_background.png')
        Image.new('RGBA', (px, px), (0, 0, 0, 0)).save(f'{RES}/drawable-{density}/ic_launcher_foreground.png')
        continue
    inner = round(px * 72 / 108)
    pad = (px - inner + 1) // 2
    pic = scaled(inner)
    # Mirror the picture around itself, then cut the layer from the middle.
    big = Image.new('RGB', (inner * 3, inner * 3))
    for gx in range(3):
        for gy in range(3):
            tile = pic
            if gx != 1:
                tile = ImageOps.mirror(tile)
            if gy != 1:
                tile = ImageOps.flip(tile)
            big.paste(tile, (gx * inner, gy * inner))
    off = inner - pad
    bg = big.crop((off, off, off + px, off + px))
    os.makedirs(f'{RES}/drawable-{density}', exist_ok=True)
    bg.save(f'{RES}/drawable-{density}/ic_launcher_background.png')
    Image.new('RGBA', (px, px), (0, 0, 0, 0)).save(f'{RES}/drawable-{density}/ic_launcher_foreground.png')

os.makedirs(f'{RES}/mipmap-anydpi-v26', exist_ok=True)
open(f'{RES}/mipmap-anydpi-v26/ic_launcher.xml', 'w', encoding='utf8', newline='\n').write(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@drawable/ic_launcher_background"/>\n'
    '    <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n'
    '</adaptive-icon>\n')
print('icons made from', SRC)
