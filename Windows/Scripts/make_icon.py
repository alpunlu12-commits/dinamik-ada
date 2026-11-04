"""Dinamik Ada Windows simgesini çizer (Assets/AppIcon.ico).

macOS sürümündeki tools/make_icon.swift ile aynı tasarım: koyu degrade zemin,
üst kenara yaslanan siyah ada (dışa açılan üst kıvrımlar) ve içinde camgöbeğinden
pembeye geçen dört dalga formu çubuğu.

Kullanım:  python Windows/Scripts/make_icon.py   (Pillow gerekir)
"""
import colorsys
import math
from pathlib import Path

from PIL import Image, ImageDraw

CONTENT_INSET = 0.09
SQUIRCLE_RADIUS = 0.185
ISLAND_W, ISLAND_H = 0.50, 0.34
ISLAND_BOTTOM_R, ISLAND_FLARE = 0.095, 0.045
BAR_W, BAR_GAP = 0.032, 0.038
BAR_HEIGHTS = [0.075, 0.115, 0.055, 0.095]
BG_TOP, BG_BOTTOM = (78, 80, 88), (24, 24, 27)
BAR_START, BAR_END = (43, 200, 214), (255, 59, 107)
SS = 4  # süper örnekleme: kenarlar yumuşak çıksın


def arc(cx, cy, r, a0, a1, steps=24):
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / steps)),
             cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / steps))) for i in range(steps + 1)]


def blend_hue(a, b, t):
    ha = colorsys.rgb_to_hsv(*[c / 255 for c in a])
    hb = colorsys.rgb_to_hsv(*[c / 255 for c in b])
    h, s, v = (ha[i] + (hb[i] - ha[i]) * t for i in range(3))
    return tuple(int(round(c * 255)) for c in colorsys.hsv_to_rgb(h, s, v)) + (255,)


def draw(size: int) -> Image.Image:
    S = size * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    inset = S * CONTENT_INSET
    art = (inset, inset, S - inset, S - inset)

    # Degrade zemin + üst yarıda hafif parlama, yuvarlak kare içinde
    bg = Image.new("RGBA", (S, S))
    d = ImageDraw.Draw(bg)
    for y in range(S):
        t = min(1, max(0, (y - inset) / (S - 2 * inset)))
        c = [int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3)]
        if y < S / 2:
            sheen = 0.16 * (1 - (y - inset) / (S / 2 - inset)) if y > inset else 0.16
            c = [int(v + (255 - v) * sheen) for v in c]
        d.line([(0, y), (S, y)], fill=tuple(c) + (255,))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(art, radius=S * SQUIRCLE_RADIUS, fill=255)
    img.paste(bg, (0, 0), mask)

    # Ada: üst kenara yaslı, kıvrımlar dışa açılır
    iw, ih = S * ISLAND_W, S * ISLAND_H
    left, top = (S - iw) / 2, inset
    right, bottom = left + iw, top + ih
    br, fl = S * ISLAND_BOTTOM_R, S * ISLAND_FLARE
    pts = [(left - fl, top)]
    pts += arc(left - fl, top + fl, fl, 270, 360)          # sol üst kıvrım (dışa)
    pts += [(left, bottom - br)]
    pts += arc(left + br, bottom - br, br, 180, 90)        # sol alt
    pts += [(right - br, bottom)]
    pts += arc(right - br, bottom - br, br, 90, 0)         # sağ alt
    pts += [(right, top + fl)]
    pts += arc(right + fl, top + fl, fl, 180, 270)         # sağ üst kıvrım (dışa)
    island = Image.new("L", (S, S), 0)
    ImageDraw.Draw(island).polygon(pts, fill=255)
    island_layer = Image.new("RGBA", (S, S), (0, 0, 0, 255))
    clipped = Image.composite(island_layer, Image.new("RGBA", (S, S), (0, 0, 0, 0)), island)
    img = Image.alpha_composite(img, Image.composite(clipped, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask))

    # Dalga formu çubukları
    d = ImageDraw.Draw(img)
    total = len(BAR_HEIGHTS) * S * BAR_W + (len(BAR_HEIGHTS) - 1) * S * BAR_GAP
    x = (left + right) / 2 - total / 2
    centre = bottom - (ih - fl) / 2
    for i, h in enumerate(BAR_HEIGHTS):
        w, hh = S * BAR_W, S * h
        d.rounded_rectangle((x, centre - hh / 2, x + w, centre + hh / 2), radius=w / 2,
                            fill=blend_hue(BAR_START, BAR_END, i / (len(BAR_HEIGHTS) - 1)))
        x += w + S * BAR_GAP
    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    out = Path(__file__).resolve().parent.parent / "Assets" / "AppIcon.ico"
    out.parent.mkdir(parents=True, exist_ok=True)
    sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    images = [draw(s) for s in sizes]
    images[-1].save(out, format="ICO", sizes=[(s, s) for s in sizes], append_images=images[:-1])
    print(f"simge yazıldı: {out}")


if __name__ == "__main__":
    main()
