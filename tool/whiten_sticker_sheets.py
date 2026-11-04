"""Re-bakes every built-in sticker sheet on warm white paper: each cut-out
sticker at its place with a soft shadow, so the white borders still show."""
import re, sys
from PIL import Image, ImageFilter
PAPER = (251, 248, 243, 255)
src = open('lib/sticker_book.dart', encoding='utf8').read()
for sid, label, sheet, aspect, body in [m for m in re.findall(r"StickerSheet\('(\w+)', '([^']+)', '([^']+)', ([\d.]+), \[(.*?)\]\)", src, re.S) if len(sys.argv) < 2 or m[0] in sys.argv[1:]]:
    W, H = Image.open(sheet).size
    paper = Image.new('RGBA', (W, H), PAPER)
    k = W / 1000
    for asset, l, t, w, h in re.findall(r"SheetSticker\('([^']+)', Rect.fromLTWH\(([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+)\)\)", body):
        im = Image.open(asset).convert('RGBA')
        x, y = round(float(l) * W), round(float(t) * H)
        im = im.resize((max(1, round(float(w) * W)), max(1, round(float(h) * H))), Image.LANCZOS)
        m = round(14 * k)
        sh = Image.new('RGBA', (im.width + 2 * m, im.height + 2 * m), (70, 50, 40, 0))
        a = Image.new('L', sh.size, 0); a.paste(im.getchannel('A').point(lambda v: v * 46 // 255), (m, m + round(4 * k)))
        sh.putalpha(a.filter(ImageFilter.GaussianBlur(5 * k)))
        paper.alpha_composite(sh, (x - m, y - m))
        paper.alpha_composite(im, (x, y))
    paper.convert('RGB').save(sheet, 'WEBP', quality=90, method=6)
    print(sid, W, H)
