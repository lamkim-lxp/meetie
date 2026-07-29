# Meetie Banner sign assets

Original pixel-art assets for SPEC R14 / §2.4 (the Banner the Dog tows):
a wooden sign with a cream board, plus a matching alarm-red Join button.
Palette shared with the dog sprites and app icon (outline `#3A2317`, cream
`#F7E3C0`, wood `#9C5A2E`, alarm red `#D6453D`).

## Files

- `sign-base.png` — 36×24 art-pixel master (RGBA, transparent corners).
- `sign@3x.png` — 108×72, nearest-neighbor 3× (1 art px = 3 pt, matching the
  Dog's 3× rendering). **This is what the app ships.**
- `join-base.png` / `join@3x.png` — 26×14 art px → 78×42 Join button.
- `preview.png` — the sign 9-slice-stretched to a typical banner width with
  the button composited, 6×.
- `generate_banner.py` — regenerates everything
  (`uv run --with pillow python3 generate_banner.py`).

## 9-slice

The app stretches only the center region via `CALayer.contentsCenter`
(`magnificationFilter = .nearest`), so the frame pixels stay crisp at any
banner width:

- sign: fixed inset **6 art px** (18 pt at 3×) — covers outline, wood frame,
  inner outline, and the board's highlight/shade rows; corner nails sit
  inside the fixed corners so they never stretch.
- join: fixed inset **5 art px** (15 pt at 3×).

Text (title, countdown, "Join") is drawn by the app with the system font
per R14a — nothing bundled.

## Licensing / provenance

Original works generated programmatically for this project (`generate_banner.py`
places every pixel; no third-party art). No license constraints.
