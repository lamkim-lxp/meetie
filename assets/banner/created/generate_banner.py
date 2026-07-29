#!/usr/bin/env python3
"""Original pixel-art Banner assets for Meetie (R14, §2.4).

Generates a 9-slice wooden sign (cream board in a wood frame, matching the
dog-sprite palette) and a matching red Join button. Shipped pre-scaled 3x
(1 art px = 3 pt) to match the Dog's 3x rendering; the app stretches only
the 9-slice center, so the pixel border stays crisp at any banner width.

Run with: uv run --with pillow python3 generate_banner.py
"""

from PIL import Image, ImageDraw

SCALE = 3  # art px -> logical pt in-app (dog: 32 px sprite at 3x = 96 pt)

# Palette — shares the dog/app-icon colours (see dog-sprite/created/NOTES.md).
OUTLINE = (58, 35, 23, 255)      # 3A2317 dark wood outline
WOOD = (156, 90, 46, 255)        # 9C5A2E frame base
WOOD_HI = (198, 118, 64, 255)    # frame top highlight
WOOD_SH = (110, 61, 30, 255)     # 6E3D1E frame bottom shade
CREAM = (247, 227, 192, 255)     # F7E3C0 board
CREAM_HI = (253, 246, 236, 255)  # FDF6EC board top highlight
CREAM_SH = (227, 203, 160, 255)  # board bottom shade
RED = (214, 69, 61, 255)         # D6453D alarm red (app icon bells)
RED_HI = (236, 128, 122, 255)    # EC807A sheen
RED_SH = (168, 55, 48, 255)      # bottom shade

SIGN_W, SIGN_H = 36, 24     # art px; 9-slice fixed inset: 6 art px (18 pt)
JOIN_W, JOIN_H = 26, 14     # art px; 9-slice fixed inset: 5 art px (15 pt)


def sign() -> Image.Image:
    w, h = SIGN_W, SIGN_H
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=4, fill=OUTLINE)
    d.rounded_rectangle([1, 1, w - 2, h - 2], radius=3, fill=WOOD)
    d.rectangle([3, 1, w - 4, 1], fill=WOOD_HI)          # sun hits the top rail
    d.rectangle([3, h - 2, w - 4, h - 2], fill=WOOD_SH)  # shade under the bottom rail
    d.rounded_rectangle([3, 3, w - 4, h - 4], radius=2, fill=OUTLINE)
    d.rounded_rectangle([4, 4, w - 5, h - 5], radius=1, fill=CREAM)
    d.rectangle([5, 4, w - 6, 4], fill=CREAM_HI)
    d.rectangle([5, h - 6, w - 6, h - 6], fill=CREAM_SH)
    # Corner nails in the frame (inside the 9-slice corners, so never stretched).
    for x, y in [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)]:
        d.point([(x, y)], fill=OUTLINE)
    return img


def join() -> Image.Image:
    w, h = JOIN_W, JOIN_H
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=4, fill=OUTLINE)
    d.rounded_rectangle([1, 1, w - 2, h - 2], radius=3, fill=RED)
    d.rectangle([3, 1, w - 4, 1], fill=RED_HI)
    d.rectangle([3, h - 2, w - 4, h - 2], fill=RED_SH)
    return img


def upscale(img: Image.Image, factor: int) -> Image.Image:
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


def nine_slice(img: Image.Image, inset: int, tw: int, th: int) -> Image.Image:
    """Reference implementation of the app's CALayer contentsCenter stretch —
    used for the preview so slicing insets are validated visually."""
    w, h = img.size
    out = Image.new("RGBA", (tw, th), (0, 0, 0, 0))

    def part(x0, y0, x1, y1):
        return img.crop((x0, y0, x1, y1))

    def put(piece, x0, y0, x1, y1):
        pw, ph = max(1, x1 - x0), max(1, y1 - y0)
        out.paste(piece.resize((pw, ph), Image.NEAREST), (x0, y0))

    i = inset
    put(part(0, 0, i, i), 0, 0, i, i)                                # corners
    put(part(w - i, 0, w, i), tw - i, 0, tw, i)
    put(part(0, h - i, i, h), 0, th - i, i, th)
    put(part(w - i, h - i, w, h), tw - i, th - i, tw, th)
    put(part(i, 0, w - i, i), i, 0, tw - i, i)                       # edges
    put(part(i, h - i, w - i, h), i, th - i, tw - i, th)
    put(part(0, i, i, h - i), 0, i, i, th - i)
    put(part(w - i, i, w, h - i), tw - i, i, tw, th - i)
    put(part(i, i, w - i, h - i), i, i, tw - i, th - i)              # center
    return out


def main() -> None:
    s, j = sign(), join()
    s.save("sign-base.png")
    j.save("join-base.png")
    upscale(s, SCALE).save("sign@3x.png")
    upscale(j, SCALE).save("join@3x.png")

    # Preview: sign stretched to a typical banner width with the button composited.
    stretched = nine_slice(s, 6, 110, SIGN_H)
    stretched.alpha_composite(j, (110 - JOIN_W - 6, (SIGN_H - JOIN_H) // 2))
    upscale(stretched, 6).save("preview.png")
    print("wrote sign-base/join-base, sign@3x/join@3x, preview.png")


if __name__ == "__main__":
    main()
