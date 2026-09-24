# Meetie assets — final manifest

Candidates were gathered in created/found pairs, reviewed, and pruned; only the selected assets remain. Spec bindings: R14a (sprites, font), R16a (barks), R20 (menu bar glyph).

| Asset | Selection | Files |
|---|---|---|
| Dog sprites | Original corgi + shiba 8-frame run cycles, 48×48 pixels rendered at 2×; sprites face right, flip for leftward Dogs | `dog-sprite/created/{shiba,corgi}/frame1-8.png` (+ sheets, previews); rebuild from generated masters via `prepare.swift` |
| Barks | Pool of four CC0 sounds, random pick per bark event; `dog_barking_mono_full` preferred for the T−0 burst | `bark/found/rubberduck-cartoon-barks/bark-01.wav`, `bark-02.wav` (WAV trims of the `.ogg` originals kept beside them — OGG isn't AVAudioPlayer-playable), `bark/found/brandon-morris-real-bark/bark-single.wav`, `dog_barking_mono_full.wav` |
| Banner sign | Original 9-slice pixel wood sign + red Join button, stretched only in the center so the frame stays crisp; palette shared with the sprites | `banner/created/sign@3x.png`, `join@3x.png` (masters + preview beside them; regenerate via `generate_banner.py`) |
| Menu bar icon | Single-state pixel clock template glyph (pure black + alpha), no warning variant | `icons/menubar/created/clock@{1x,2x}.png` |
| App icon | Clock-only pixel alarm clock, hands at one minute to the hour (the T−1:00 pose) | `icons/app/Meetie-clock.icns`, master `clock-1024.png` |
| Banner font | System font (SF Pro) — nothing bundled | — |

Licenses: sprites and icons are original works (no constraints); all bark samples are CC0, provenance and source URLs in `bark/found/SOURCES.md` (which also documents candidates that were reviewed and removed).
