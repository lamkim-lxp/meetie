# Meetie running dogs

Original shiba and corgi artwork created for Meetie using the built-in image
generation tool. The generated masters and exact prompts live in `source/`.
No external sprite packs or reference artwork were used.

## App assets

- `shiba/frame1.png` through `frame8.png` and `corgi/frame1.png` through
  `frame8.png`: 48×48 RGBA, 12-color palette, hard transparent edges.
- `shiba-sheet.png` and `corgi-sheet.png`: 384×48 strips in playback order.
- `shiba-preview.gif` and `corgi-preview.gif`: looping 4× previews at 70 ms/frame.
- `contact-sheet.png`: both cycles at 3× on a light background.

Dogs face right. The app mirrors them when moving left and renders them at
96×96 points with nearest-neighbor filtering. Each dog chooses a frame hold
between 65 and 75 ms, giving a complete stride every 520 to 600 ms.

The cycle moves through extension, forepaw contact, weight bearing, gathered
legs, hind-paw contact, push-off, and flight. Shaded far legs separate the paws;
the shiba has a curled cream tail and the corgi has a white blaze and nub tail.

## Rebuild

From the repository root, run:

```sh
swift assets/dog-sprite/created/prepare.swift
make debug
```

The preparation script uses macOS CoreGraphics and ImageIO, with no external
dependencies. It extracts the eight largest connected silhouettes from each
master, applies one shared scale per breed, anchors the nose and ear positions,
adds a restrained vertical bob, and samples onto the 48×48 pixel grid. It maps
colors to the shared palette and keeps alpha strictly 0 or 255. This prevents
adjacent-frame fragments, background halos, size pumping, and soft scaling.
Playback uses source cells 1, 8, 2, 3, 4, 5, 6, 7 so the final landing
in-between follows extension and the loop closes through flight.

Generated masters are preserved so app assets can be rebuilt deterministically
without another image generation call. Preview backgrounds are not in app PNGs.
