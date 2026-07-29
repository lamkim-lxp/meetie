# Meetie

A macOS menu bar app that makes meeting starts impossible to miss. Shortly
before a Meeting (1/5/10 minutes, or right at start — your pick), a big pixel
Dog towing a Banner bounces around every monitor — including over fullscreen
Spaces — barking now and then, until you Acknowledge it (Dismiss or Join).

See [docs/SPEC.md](docs/SPEC.md) for the full behavioral contract and
[CONTEXT.md](CONTEXT.md) for terminology.

## Setup

Meetie reads Meetings locally from the built-in macOS Calendar via EventKit
([ADR 0001](docs/adr/0001-eventkit-via-macos-calendar.md)) — it never talks to
Outlook/Exchange directly. **Add your work calendar to Calendar.app first:**

1. System Settings → **Internet Accounts** → **Add Account…** → **Microsoft Exchange**.
2. Sign in with your work account and enable **Calendars**.
3. Open Calendar.app once and confirm your meetings appear.

Any other synced calendars (iCloud, Google) work the same way. All calendars
are Watched by default; opt individual ones out from the menu bar dropdown
(**Calendars ▸**).

## Build & run

Requires macOS 14+ and Xcode command line tools.

```sh
make run        # builds a debug app with Test Dog and launches it
```

On first launch, grant **full calendar access** when prompted. If you decline,
the menu bar shows `⚠️` and the dropdown's first item deep-links to
System Settings → Privacy & Security → Calendars.

- `make debug` - build the debug bundle without launching
- `make app` - build the release bundle without launching
- `make clean` - remove build products

The build is a local, ad-hoc-signed personal build — not sandboxed, not
notarized (spec R28). To keep it running across reboots, enable
**Launch at Login** in the dropdown.

## Using it

- The menu bar shows a pixel clock plus the next Meeting's countdown
  (`12m`, `2h`), glyph-only when nothing is scheduled within 12 h.
- The dropdown lists the next 5 Meetings and is the entire settings surface:
  calendar opt-outs, **Notify At** (1/5/10 minutes before, or when the meeting
  starts), a **Sound** on/off toggle, Launch at Login, and Quit. Debug builds
  add **Test Dog** (a compressed 30-second fake Alert).
- An Alert fires at your notify-at lead: one big Dog bounces around each
  screen — diagonal, DVD-screensaver style, at a slow clickable pace —
  barking every 8–12 s, with a bark burst at T−0, then silent persistence
  until acknowledged or the Meeting's end time passes.
- Clicking the Dog or the Banner opens the Meeting's name, date, venue, and
  description with Dismiss and Join actions (the Dog freezes while it's open);
  the Banner's Join button joins in one click.
  Each choice affects only that Meeting's Alert; overlapping Meetings alert
  independently.
- Everything else on screen stays fully clickable and typeable — the overlay
  only intercepts the mouse directly over a Dog or Banner.

Known, by-design limitations (spec §5): no snooze, no replay of Alert moments
missed while asleep/not running, a Meeting created less than 60 s before it
starts never alerts, and Dogs are visible in screen shares.

## Development

Plain SwiftPM package (`swift build`), AppKit, no dependencies, no storyboards.
`scripts/bundle.sh` assembles `build/Meetie.app` from the selected binary plus
`assets/` (sprites, barks, icons — see [assets/ASSETS.md](assets/ASSETS.md)).

Test Dog and the debug flags exist in debug builds only (`make run` and
`make debug` bundle one). Run the binary directly, e.g.
`build/Meetie.app/Contents/MacOS/Meetie --test-dog`:

- `--test-dog` — fire a Test Dog 1 s after launch
- `--no-calendar` — skip EventKit entirely (overlay work without the permission prompt)

```
MeetieApp (NSApplicationDelegate)
├── CalendarStore        EventKit access, Meeting mapping, change observation
├── AlertScheduler       next T−60s computation, single armed timer, skip rule
├── AlertCoordinator     owns active Alerts, Test Dog entry point, reconcile
│   └── AlertController  per-Alert escalation state machine, ack routing
├── OverlayManager       NSPanel per screen, display tick, click-through, Dog/Banner layers
├── SoundPlayer          bark pool playback (AVAudioPlayer)
├── MenuBarController    NSStatusItem, countdown, dropdown, settings surface
└── SettingsStore        UserDefaults: watched-calendar opt-outs
```
