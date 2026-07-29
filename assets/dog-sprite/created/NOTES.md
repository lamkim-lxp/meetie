# Meetie dog run-cycle sprites

Original pixel-art assets for SPEC R14 / section 2.4 (DogView). Side-view running
dog, facing **right**, 6-frame gallop cycle, 32x32 px per frame, transparent
background, 1px dark outline so the sprite reads over any background. Flip
horizontally at render time for leftward-running Dogs.

## Files

- `shiba/frame1.png` … `frame6.png`, `corgi/frame1.png` … `frame6.png` — individual
  32x32 RGBA frames, transparent background.
- `shiba-sheet.png`, `corgi-sheet.png` — 192x32 sprite sheets, frames 1–6 left to
  right at 32px stride.
- `shiba-preview.gif`, `corgi-preview.gif` — 4x nearest-neighbour animated previews,
  90 ms/frame (~11 fps), looping. These have an opaque background and a ground
  shadow **for preview only**; use the PNGs in the app.
- `contact-sheet.png` — both variants, all frames, 4x on a checkerboard.
- `generate.py` — the script that produced every asset (run with any Python 3 +
  Pillow to regenerate or tweak).

## Run cycle (frames 1→6)

| Frame | Pose | Body |
|---|---|---|
| 1 | front paw strikes ground, rear legs trailing back (stretch) | mid |
| 2 | front leg vertical under chest, rear legs swing forward | low (+1px) |
| 3 | gathered: rear paw plants forward, front leg folds back (squash) | low (+1px) |
| 4 | rear leg drives off the ground, front leg reaches | mid |
| 5 | full extension, airborne — tongue out | high (−1px) |
| 6 | airborne, legs tucking back in — tongue out | high (−1px) |

Secondary motion: ears and tail trail the body bob by one frame (1px offsets);
the head shifts ±1px to stretch/squash the silhouette.

## Frame timing recommendation

- **80–100 ms per frame** (10–12.5 fps) reads as a relaxed, charming trot-gallop;
  the preview GIFs use 90 ms.
- At the overlay's 60 fps (R26): hold each frame for **5–6 ticks** (~83–100 ms).
  Scale the hold with Dog speed if you want faster Dogs to scamper (4 ticks) and
  slow ones to lope (7 ticks).
- Render at 2x (64 px logical height, per section 2.4) with
  `magnificationFilter = .nearest` — the 32px canvas scales cleanly.

## Variants and palettes

Both variants share the same animation geometry; they differ in markings, ears
and tail. 6 colours each + transparency.

### Shiba (orange/tan)

Pointy triangular ears, curled tail carried over the back (cream underside),
cream muzzle, chest and belly.

| Role | Hex |
|---|---|
| Outline | `#3A2317` |
| Base coat (orange) | `#E8923A` |
| Shade coat (far legs, inner ear) | `#B5651D` |
| Cream (muzzle, chest, belly, tail) | `#F7E3C0` |
| Eye / nose | `#1A1A1A` |
| Tongue | `#E26A6A` |

### Corgi (brown & white)

Big rounded upright ears (far ear shaded), stubby white-tipped nub tail, white
blaze up the face, white chest, belly and socks.

| Role | Hex |
|---|---|
| Outline | `#35221A` |
| Base coat (brown) | `#9C5A2E` |
| Shade coat (far legs, far ear) | `#6E3D1E` |
| White (blaze, chest, belly, socks, tail tip) | `#FBF6EC` |
| Eye / nose | `#1A1A1A` |
| Tongue | `#E26A6A` |

## Licensing / provenance

These sprites are **original works generated programmatically for this project**
(see `generate.py` — every pixel is placed by that script; no third-party art,
fonts, or reference images were copied or traced). No license constraints:
Meetie may use, modify, and redistribute them freely.
