#!/usr/bin/env python3
"""Original pixel-art dog run-cycle generator for Meetie (R14).

Draws a 6-frame side-view gallop, facing right, on a 32x32 transparent
canvas, in two colour variants (shiba / corgi). All pixels are placed
deliberately via a small compositor: far legs -> body -> tail -> near
legs -> head -> markings, then a 1px auto-outline (4-neighbour dilate).
"""
from PIL import Image, ImageDraw
import os

W = H = 32
OUT = "/Users/klam/dev/meetie/assets/dog-sprite/created"

# ---------------------------------------------------------------- palettes
PALETTES = {
    "shiba": {
        "O": (58, 35, 23, 255),     # outline - very dark brown
        "B": (232, 146, 58, 255),   # base coat - shiba orange
        "S": (181, 101, 29, 255),   # shade coat - far legs / depth
        "L": (247, 227, 192, 255),  # cream - belly, muzzle, tail tip
        "K": (26, 26, 26, 255),     # black - eye, nose
        "P": (226, 106, 106, 255),  # pink - tongue
    },
    "corgi": {
        "O": (53, 34, 26, 255),     # outline - dark chocolate
        "B": (156, 90, 46, 255),    # base coat - brown
        "S": (110, 61, 30, 255),    # shade coat - far legs / depth
        "L": (251, 246, 236, 255),  # white - blaze, chest, socks, belly
        "K": (26, 26, 26, 255),     # black - eye, nose
        "P": (226, 106, 106, 255),  # pink - tongue
    },
}

# ------------------------------------------------------------- frame poses
# 6-frame rotary gallop.  bob: body vertical offset. head_dx: stretch/squash.
# feet are (x, y) of the near-side paw; far legs mirror at (-1,-1).
POSES = [
    # 1: front paw strikes ground, rear legs trailing back        (stretch)
    dict(bob=0,  head_dx=1,  front=(22, 26), rear=(4, 23)),
    # 2: front leg vertical under chest, rear legs swing forward  (pull)
    dict(bob=1,  head_dx=0,  front=(17, 26), rear=(9, 24)),
    # 3: gathered - rear paw plants forward, front folds back     (squash)
    dict(bob=1,  head_dx=-1, front=(16, 25), rear=(12, 26)),
    # 4: rear leg drives back off the ground, front reaches       (push)
    dict(bob=0,  head_dx=0,  front=(20, 24), rear=(7, 26)),
    # 5: full extension, airborne                                 (fly)
    dict(bob=-1, head_dx=1,  front=(23, 24), rear=(4, 24)),
    # 6: airborne, legs folding back in                           (tuck)
    dict(bob=-1, head_dx=0,  front=(20, 23), rear=(8, 24)),
]
BOBS = [p["bob"] for p in POSES]


def blob(g, x0, y0, x1, y1, key, cut=1):
    """Filled rect with `cut` corner pixels removed (rounded look)."""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if cut:
                cx = (x == x0 or x == x1)
                cy = (y == y0 or y == y1)
                if cx and cy:
                    continue
            g[(x, y)] = key


def leg(g, hip, foot, key, sock_key=None):
    """2px-thick leg from hip to foot, plus a toe pixel."""
    hx, hy = hip
    fx, fy = foot
    dy = max(fy - hy, 1)
    pts = []
    for i in range(dy + 1):
        y = hy + i
        x = round(hx + (fx - hx) * i / dy)
        pts.append((x, y))
    for (x, y) in pts:
        k = sock_key if (sock_key and y >= fy - 1) else key
        g[(x, y)] = k
        g[(x - 1, y)] = k
    # toe points the way the leg leans
    toe = 1 if fx >= hx else -1
    g[(fx + toe, fy)] = sock_key or key


def draw_dog(pose, variant, frame_i):
    g = {}
    bob = pose["bob"]
    hdx = pose["head_dx"]
    lag = BOBS[(frame_i - 1) % len(BOBS)]  # ears/tail trail the body by 1 frame

    fhx, rhx = 18, 9              # front / rear hip x
    hipy = 19 + bob

    fr = pose["front"]
    re = pose["rear"]
    far_lift = 2 if frame_i == 2 else 1   # tuck far legs harder on gather
    far_fr = (fr[0] - 1, max(fr[1] - far_lift, hipy + 3))
    far_re = (re[0] - 1, max(re[1] - far_lift, hipy + 3))

    corgi = variant == "corgi"
    sock = "L" if corgi else None

    # far-side legs (drawn first, behind the body)
    leg(g, (rhx - 2, hipy), far_re, "S")
    leg(g, (fhx - 2, hipy), far_fr, "S")

    # body
    blob(g, 6, 13 + bob, 20, 20 + bob, "B")

    # tail (wags with 1-frame lag behind the body bob)
    if corgi:  # stubby white-tipped nub, rooted into the rump
        ty = 11 + lag
        for x, y, k in ((5, ty, "L"), (6, ty, "L"),
                        (4, ty + 1, "B"), (5, ty + 1, "B"), (6, ty + 1, "B"),
                        (5, ty + 2, "B"), (6, ty + 2, "B"),
                        (6, ty + 3, "B"), (7, ty + 3, "B")):
            g[(x, y)] = k
    else:      # shiba curl: 4x4 spiral disc + stem into the rump
        ty = 9 + lag
        blob(g, 5, ty, 8, ty + 3, "B", cut=1)
        del g[(7, ty + 1)]            # hole -> auto-outline dots the curl
        g[(5, ty + 2)] = "L"          # cream underside of the curl
        g[(6, ty + 3)] = "L"
        blob(g, 8, ty + 3, 9, ty + 4, "B", cut=0)  # 2x2 stem into the rump

    # belly / chest markings (before near legs so legs overlap them)
    if corgi:
        blob(g, 10, 17 + bob, 19, 20 + bob, "L", cut=1)
        blob(g, 18, 15 + bob, 20, 18 + bob, "L", cut=0)
    else:
        blob(g, 11, 18 + bob, 18, 20 + bob, "L", cut=1)
        blob(g, 19, 16 + bob, 20, 18 + bob, "L", cut=0)

    # near-side legs
    leg(g, (rhx, hipy), re, "B", sock)
    leg(g, (fhx, hipy), fr, "B", sock)

    # head (big - corgi/shiba proportions)
    hx0 = 18 + hdx
    hy0 = 6 + bob
    blob(g, hx0, hy0, hx0 + 9, hy0 + 9, "B")

    # ears (trail the body by one frame)
    edy = lag - bob
    ex = hx0
    ey = hy0 + edy
    if corgi:  # big rounded upright ears, far ear a shaded nub behind
        blob(g, ex + 1, ey - 3, ex + 3, ey - 1, "S", cut=1)
        blob(g, ex + 5, ey - 4, ex + 7, ey, "B", cut=1)
        g[(ex + 6, ey - 1)] = "S"
        g[(ex + 6, ey - 2)] = "S"
    else:      # pointy shiba ears: sharp triangles, swept back
        # back ear
        g[(ex + 1, ey - 3)] = "B"
        g[(ex + 1, ey - 2)] = "B"
        g[(ex + 2, ey - 2)] = "B"
        g[(ex + 2, ey - 1)] = "B"
        g[(ex + 3, ey - 1)] = "B"
        # front ear
        g[(ex + 6, ey - 3)] = "B"
        g[(ex + 6, ey - 2)] = "B"
        g[(ex + 7, ey - 2)] = "B"
        g[(ex + 6, ey - 1)] = "B"
        g[(ex + 7, ey - 1)] = "S"  # inner ear hint

    # muzzle + face
    mx = hx0 + 7
    my = hy0 + 5
    blob(g, mx, my, mx + 3, my + 3, "L", cut=1)
    if corgi:  # white blaze up the face
        blob(g, mx + 1, hy0 + 1, mx + 2, my, "L", cut=0)
    g[(mx + 4, my + 1)] = "K"          # nose, protruding past the muzzle
    g[(hx0 + 6, hy0 + 4)] = "K"        # eye
    if frame_i in (4, 5):              # tongue out while flying
        g[(mx + 2, my + 4)] = "P"

    # 1px auto-outline: dilate every filled pixel into empty 4-neighbours
    outline = {}
    for (x, y) in g:
        for nx, ny in ((x+1, y), (x-1, y), (x, y+1), (x, y-1)):
            if (nx, ny) not in g and 0 <= nx < W and 0 <= ny < H:
                outline[(nx, ny)] = "O"
    g.update(outline)
    return g


def render(g, palette):
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for (x, y), key in g.items():
        if 0 <= x < W and 0 <= y < H:
            im.putpixel((x, y), palette[key])
    return im


def checker(w, h, cell=8):
    im = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(im)
    for y in range(0, h, cell):
        for x in range(0, w, cell):
            c = (210, 210, 210, 255) if (x // cell + y // cell) % 2 else (240, 240, 240, 255)
            d.rectangle([x, y, x + cell - 1, y + cell - 1], fill=c)
    return im


def main():
    scale = 4
    frames = {}
    for variant in ("shiba", "corgi"):
        pal = PALETTES[variant]
        vdir = os.path.join(OUT, variant)
        os.makedirs(vdir, exist_ok=True)
        imgs = []
        for i, pose in enumerate(POSES):
            im = render(draw_dog(pose, variant, i), pal)
            im.save(os.path.join(vdir, f"frame{i+1}.png"))
            imgs.append(im)
        frames[variant] = imgs

        # sprite sheet
        sheet = Image.new("RGBA", (W * len(imgs), H), (0, 0, 0, 0))
        for i, im in enumerate(imgs):
            sheet.paste(im, (i * W, 0))
        sheet.save(os.path.join(OUT, f"{variant}-sheet.png"))

        # animated GIF preview, 4x nearest, ~11 fps, soft bg + ground shadow
        gif_frames = []
        for i, im in enumerate(imgs):
            bg = Image.new("RGBA", (W, H), (238, 235, 228, 255))
            d = ImageDraw.Draw(bg)
            bob = POSES[i]["bob"]
            grounded = bob >= 0
            sx0, sx1 = (7 - bob, 22 + bob) if grounded else (10, 19)
            d.rectangle([sx0, 28, sx1, 28], fill=(206, 200, 188, 255))
            bg.alpha_composite(im)
            gif_frames.append(bg.resize((W * scale, H * scale), Image.NEAREST).convert("P", palette=Image.ADAPTIVE))
        gif_frames[0].save(
            os.path.join(OUT, f"{variant}-preview.gif"),
            save_all=True, append_images=gif_frames[1:],
            duration=90, loop=0, disposal=2,
        )

    # contact sheet: both variants, all frames, 4x on checkerboard
    pad, label_h = 8, 18
    cw = len(POSES) * (W * scale + pad) + pad
    ch = 2 * (H * scale + pad + label_h) + pad
    sheet = checker(cw, ch, 16)
    d = ImageDraw.Draw(sheet)
    for row, variant in enumerate(("shiba", "corgi")):
        y0 = pad + row * (H * scale + pad + label_h)
        d.text((pad, y0), variant, fill=(40, 40, 40, 255))
        for i, im in enumerate(frames[variant]):
            big = im.resize((W * scale, H * scale), Image.NEAREST)
            x0 = pad + i * (W * scale + pad)
            sheet.alpha_composite(big, (x0, y0 + label_h))
            d.text((x0, y0 + label_h + H * scale + 1), f"f{i+1}", fill=(40, 40, 40, 255))
    sheet.save(os.path.join(OUT, "contact-sheet.png"))
    print("done")


if __name__ == "__main__":
    main()
