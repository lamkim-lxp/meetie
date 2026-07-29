# Meetie — Implementation Spec

A macOS menu bar app that makes meeting starts impossible to miss. At the configured notify-at lead (default one minute) before a Meeting, a big pixel Dog towing a Banner bounces around every monitor — including over fullscreen Spaces — until the user Acknowledges it.

Terminology (Meeting, Alert, Dog, Banner, Acknowledge, Watched Calendar) is defined in [CONTEXT.md](../CONTEXT.md) and used with those exact meanings throughout. Architectural decisions are recorded in [docs/adr/](./adr/).

---

## 1. Product requirements

### 1.1 Meeting detection

- **R1** Meetings are read locally via EventKit from the built-in macOS Calendar (ADR 0001). Setup documentation must instruct the user to add their Outlook account to Calendar.app.
- **R2** A Meeting is any timed (non-all-day) event on a Watched Calendar that the user has not declined. Attendee count and join links are irrelevant. Tentative and unanswered invites count.
- **R3** Events where the current user's participant status is `declined` are excluded. Cancelled events are excluded.
- **R4** All calendars are Watched by default. The user can opt individual calendars out; the opt-out set persists across launches.
- **R5** Calendar changes (new/moved/deleted events, new calendars) must be picked up automatically within seconds, not on a polling delay. A calendar added later is Watched by default (opt-out model).

### 1.2 Alert lifecycle

- **R6** Each Meeting gets exactly one Alert, fired at the configured **notify-at lead** before the Meeting's start: 1 minute (default), 5 minutes, 10 minutes, or at the Meeting's start. "T−lead" below means this moment; the lead persists across launches.
- **R7** An Alert persists until one of:
  - **Acknowledge** — user clicks any Dog or Banner belonging to that Alert, reviews the Meeting name, date, venue, and description, then chooses **Dismiss**;
  - **Join** — user clicks the Join button on the Banner, or chooses **Join** from the Meeting details (opens the join URL in the default handler, then behaves exactly like Acknowledge);
  - **Self-expiry** — the Meeting's end time passes.
- **R8** Acknowledge is final: nothing for that Meeting occurrence fires again, even before T−0.
- **R9** Alerts fire only at their scheduled moment. If T−lead passes while the Mac is asleep, the screen is locked, or Meetie is not running, that Alert is skipped and never replayed. On launch/wake, only future T−lead moments are scheduled.
- **R10** Overlapping Meetings each get their own independent Alert: separate Dogs, separate Banners, acknowledged separately. Clicking a Dog affects only its own Alert.
- **R11** After T−0 with no Acknowledge, the Alert persists and the Banner countdown switches to `started Xm ago`, until self-expiry.

### 1.3 Alert presentation

- **R12** Dogs render on **every attached display simultaneously**, above everything: fullscreen apps, all Spaces, all monitors.
- **R13** The overlay never steals keyboard focus and never blocks clicks except directly on a Dog or Banner. Typing and clicking through the rest of the screen must work exactly as if the overlay were not there.
- **R14** Presentation: one big pixel-art Dog per Alert roams the screen towing the Banner — a 9-slice pixel wood sign (`assets/banner/created/`) carrying the Meeting title, live countdown `M:SS`, and a Join button when a join URL exists. The Dog moves **diagonally** at a slow, clickable pace (horizontal screen-crossing 16–22 s) and **bounces off the monitor edges** DVD-screensaver style; the Banner chases behind it with a soft lag, connected by a drawn tow-rope.
- **R14a** Dog sprites: the original created sets `assets/dog-sprite/created/shiba/` and `corgi/` (6-frame run cycles, 32×32, rendered at 3× ≈ 96 px). Each Alert's Dog is randomly a shiba or a corgi. Sprites face right; flipped horizontally while moving leftward. Banner text uses the **system font** (SF Pro) — no bundled font.
- **R15** No escalation: an Alert is a single Dog per screen from T−lead until it ends. (The Pack concept was retired — one big Dog proved less distracting and easier to click.)
- **R16** Sound: an occasional bark every **8–12 s** while the Alert is running, plus a final bark burst at T−0. After T−0, the Dog persists **silently**. Sound plays through the default output at system volume via `AVAudioPlayer`/`NSSound` — deliberately not Notification Center, so macOS Focus/DND cannot suppress it.
- **R16a** Bark samples: a pool of four CC0 sounds used interchangeably (random pick per bark event) — `assets/bark/found/rubberduck-cartoon-barks/bark-01.wav`, `bark-02.wav` (WAV trims of `barking_01`/`barking_02` — the OGG originals are not AVAudioPlayer-playable), `brandon-morris-real-bark/bark-single.wav`, and `dog_barking_mono_full.wav`. The last is 2.0 s (four barks), exempt from the ≤0.5 s guideline; prefer it for the T−0 burst.
- **R17** No screen-capture exclusion: Dogs are visible in screen shares and recordings (`sharingType` left at default). A click clears them, which is the accepted mitigation.
- **R18** Long Meeting titles truncate with an ellipsis at ~40 characters on the Banner.

### 1.4 Menu bar presence

- **R19** Meetie is a menu bar app with no Dock icon (`LSUIElement = YES`).
- **R20** The menu bar item is a simple pixel clock glyph (template image, single state — no icon variants) followed by the next Meeting's countdown, e.g. `⏱ 12m` (minutes granularity; `⏱ 2h` beyond 60 min; glyph only when nothing is scheduled in the next 12 h). Updates at least once per minute.
- **R21** The dropdown is the entire settings surface:
  - next 5 upcoming Meetings (title + start time); the imminent one highlighted;
  - **Calendars ▸** submenu: checkbox per calendar (checked = Watched), grouped under account headers — several accounts ship same-named calendars ("Calendar", "Birthdays"), so titles alone would read as duplicates;
  - **Notify At ▸** submenu: 1 minute (default) / 5 minutes / 10 minutes before, or when the meeting starts (R6); persisted;
  - **Sound** toggle: barks on/off (checked = on, default on); persisted; silences barks and the T−0 burst;
  - **Test Dog** — runs a full fake Alert (self-clears after 30 s if not clicked); **debug builds only**;
  - **Launch at Login** toggle (`SMAppService.mainApp`);
  - **Quit**.
- **R22** If calendar permission is missing/denied, the menu bar item's countdown text is replaced with `⚠️` (same clock glyph — no icon variant) and the dropdown's first item explains and deep-links to System Settings → Privacy & Security → Calendars. Silent failure is unacceptable — this is the app's one forbidden failure mode.

### 1.5 Join URL detection

- **R23** A Meeting's join URL is the first match found in, in order: the event's URL field, location, then notes. Recognized patterns: `teams.microsoft.com/l/meetup-join`, `teams.live.com`, `zoom.us/j/`, `meet.google.com/`, `webex.com/meet|join`. Stored as a compiled regex list that is trivial to extend.
- **R24** No join URL → the Banner simply has no Join button; the Alert otherwise behaves identically.

### 1.6 Non-functional

- **R25** Idle footprint: no periodic polling loops; scheduling is timer-based and event-driven. Target < 50 MB RAM idle, ~0% CPU when no Alert is active.
- **R26** Animation runs at 60 fps on the overlay while active; the overlay windows are ordered out (not just hidden) when no Alert is active.
- **R27** macOS 14 (Sonoma) minimum — allows `EKEventStore.requestFullAccessToEvents` and modern `SMAppService` without legacy fallbacks.
- **R28** Distribution: local Xcode build for personal use. Not sandboxed, not notarized, no auto-update. (Revisit only if it's ever shared.)

### 1.7 Onboarding

- **R29** First launch presents a four-step setup window: introduction, Calendar permission, Outlook setup, and ready summary. The system Calendar prompt appears only after the user chooses **Allow Calendar Access**.
- **R30** The permission explanation states which Meeting fields Meetie reads, that EventKit Full Access is required to read details, that Meetie never edits calendars, and that data stays on the Mac.
- **R31** Denied Calendar access provides a direct path to System Settings. Restricted access explains that a device or organization policy is responsible. Setup remains dismissible and can be reopened from **Set Up Meetie…** in the menu.
- **R32** Outlook setup explains that Microsoft Exchange continuously syncs Outlook with Apple Calendar; it is not a one-time import. The instructions cover Calendar → Add Account → Microsoft Exchange → sign in → enable Calendars.
- **R33** When Calendar access is available, setup detects Exchange calendars through EventKit and refreshes when the event store changes. Exchange is optional because iCloud, Google, and other Apple Calendar sources remain supported.
- **R34** Onboarding presentation and completion are persisted separately and versioned. Dismissing setup prevents it from reopening automatically on every launch without falsely recording successful completion.

---

## 2. Architecture

Single Swift app target, AppKit lifecycle (`NSApplicationDelegateAdaptor` optional; plain `NSApplicationDelegate` is fine). No storyboards except the mandatory empty Main entitlement; all UI in code.

```
MeetieApp (NSApplicationDelegate)
├── CalendarStore        EventKit access, Meeting mapping, change observation
├── AlertScheduler       computes next T−lead moments, owns timers, wake/launch rules
├── AlertController      one per active Alert: state machine, bounce movement, ack routing
│   └── OverlayManager   one NSPanel per NSScreen, click-through management
│       └── DogView      sprite animation (Core Animation), Banner view, hit areas
├── SoundPlayer          bark playback
├── MenuBarController    NSStatusItem, countdown text, dropdown menu, Test Dog
├── OnboardingWindowController
│                         first-launch setup, permission recovery, Outlook guidance
└── SettingsStore        UserDefaults: watched-calendar opt-outs, launch-at-login
```

### 2.1 CalendarStore

- Wraps one `EKEventStore`. Startup reads the existing authorization state without prompting. Onboarding requests full access (`requestFullAccessToEvents`) only after an explicit user action; the store publishes an `authorizationState` observed by the menu and onboarding (R22, R29).
- Exposes `upcomingMeetings(within: TimeInterval) -> [Meeting]` using `predicateForEvents(withStart:end:calendars:)` over the next 12 h, filtered per R2–R4. EventKit expands recurring events into occurrences automatically.
- `Meeting` is a value type: `occurrenceID` (eventIdentifier + occurrence start date — required to distinguish occurrences of recurring events), `title`, `start`, `end`, `joinURL?`, `venue?`, `details?`, `calendarID`.
- Observes `.EKEventStoreChanged` and emits a coalesced (debounced ~2 s) change signal; AlertScheduler recomputes on it.

### 2.2 AlertScheduler

- Maintains a single armed timer for the **next** T−lead moment only (re-armed after each firing, on any change signal, or when the notify-at lead changes) — not one timer per event.
- Recompute triggers: store change signal, timer fire, `NSWorkspace.didWakeNotification`, `screensDidChangeNotification` (indirectly, via OverlayManager), and app launch.
- **Skip rule (R9):** on recompute, only Meetings with `start − lead > now` are eligible for scheduling. An in-flight armed time that is now in the past is discarded, not fired.
- Keeps an in-memory `Set<occurrenceID>` of Acknowledged/expired Alerts to guarantee once-only firing across recomputes. In-memory is sufficient — the skip rule makes persistence across restarts unnecessary.
- Fires by handing the Meeting to a new `AlertController`. Multiple Meetings sharing one fire moment produce multiple controllers (R10).

### 2.3 AlertController + OverlayManager

- **Windows:** one borderless, transparent `NSPanel` per `NSScreen`, shared by all active Alerts:
  - `level = .init(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))`
  - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`
  - `isFloatingPanel = true`, `becomesKeyOnlyIfNeeded = true`, `hidesOnDeactivate = false`
  - `backgroundColor = .clear`, `isOpaque = false`, `hasShadow = false`
  - Never made key; buttons use `NSClickGestureRecognizer`/mouseDown, no first-responder needs (R13).
- **Click-through (R13):** panels start with `ignoresMouseEvents = true`. A global+local `NSEvent` mouse-moved monitor checks whether the cursor is inside any Dog/Banner hit rect; toggle `ignoresMouseEvents` accordingly. This is the standard per-region click-through technique — `hitTest` alone cannot pass clicks to windows below.
- **Screen topology:** on `NSApplication.didChangeScreenParametersNotification`, tear down and rebuild panels; active Alerts re-render on the new screen set.
- **State machine** per Alert: `running` → `overdue` at T−0 → terminal `acknowledged | expired`. The display tick updates Banner countdowns; self-expiry checks `meeting.end`.
- Ack routing: a click resolves to the owning Alert via the hit rect registry; that Alert alone tears down (R10).

### 2.4 DogView / rendering

- Pixel-art run cycle: 6 frames, ~96 px logical height (32 px sprite at 3×), `magnificationFilter = .nearest` for crisp pixels, driven by a `CADisplayLink` synced to the display refresh on a `CALayer` (no SpriteKit dependency needed for this scale).
- Each Alert's Dog: position/velocity live in a unit square mapped to each screen's roaming band (the lower ⅔), so every screen renders identically-composed content; the velocity is a mostly-horizontal diagonal that reflects off the band's edges (the bounce). The Dog freezes while its Meeting details are open. The Banner is a 9-slice pixel wood-sign layer (`CALayer.contentsCenter` stretches only the board, keeping the frame crisp) that chases the Dog with a soft lag (so it swings around smoothly on bounces), linked by a `CAShapeLayer` tow-rope; the Banner is itself a hit area (Join zone joins directly; any other Dog/Banner click opens the Meeting details and actions).
- Same Alert renders identically-composed (not necessarily frame-synced) content on every screen (R12).

### 2.5 SoundPlayer

- Preloads the four-sample bark pool (R16a); each bark event plays a random sample from the pool. A bark every 8–12 s while running (pre T−0 only); the burst at T−0 (prefer `dog_barking_mono_full`); silent after (R16).

### 2.6 Onboarding

- `CalendarStore.start()` reads the existing EventKit authorization state but never requests access. `requestAccess()` is invoked only by the onboarding permission action.
- `OnboardingWindowController` owns a reusable AppKit setup window. Calendar authorization and EventKit change callbacks refresh its current step without polling.
- Exchange detection uses calendars whose EventKit source type is `.exchange`. The Outlook step can be continued when none are present.
- `SettingsStore` records the current presented and completed onboarding versions independently.

---

## 3. Edge cases (behavioral contract)

| Scenario | Behavior |
|---|---|
| Meeting moved after its Alert was scheduled | Change signal → recompute; old moment discarded, new T−60 s armed. If moved while its Alert is on screen: Alert continues against old data; next recompute self-expires it if now out of window. Acceptable v1. |
| Meeting deleted / cancelled while Alert on screen | Next recompute (fires on store change) tears the Alert down. |
| Declined after Alert scheduled | Same as deleted — filtered out on recompute. |
| Two Meetings, same start | Two full Alerts, independent Dogs and acks (R10). |
| Meeting starts within the notify-at lead of being created | Its T−lead is already past → skip rule applies; no Alert. Documented limitation. |
| Back-to-back meetings (A ends 10:30, B starts 10:30) | B's Alert fires 10:29 while A may still be on a call — by design; that's the ping the user needs. |
| Mac asleep / Meetie not running at T−60 s | Skipped, never replayed (R9). |
| Screen locked at T−60 s | Fires into the void and self-expires; treated as the asleep case. No special handling v1. |
| All-day event | Not a Meeting; never alerts. |
| Calendar permission revoked mid-run | Store change/error → menu bar warning state (R22); scheduler idles. |
| Display unplugged during an Alert | Panels rebuilt; Alert continues on remaining screens. |
| No join URL | Banner without Join button (R24). |

---

## 4. Build order (milestones)

Risk-first: the overlay technique is the only genuinely uncertain part, so it goes first.

1. **M1 — Overlay proof:** menu bar skeleton + Test Dog. One hardcoded Alert: panel-per-screen at screen-saver level, verify it renders over a fullscreen app on every monitor, click-through works everywhere except the Dog, clicking the Dog dismisses. *Exit criterion: dogs over a fullscreen video on two monitors while typing into the app below.*
2. **M2 — Calendar + scheduling:** CalendarStore, permission onboarding + warning state, AlertScheduler with skip rule, real Alerts at T−60 s, self-expiry, menu bar countdown.
3. **M3 — Escalation + sound:** Pack growth, lanes/speeds/directions, bark cadence, overdue Banner state, per-Alert ack routing for overlaps.
4. **M4 — Settings surface:** watched-calendar opt-outs (persisted), launch-at-login, upcoming-meetings list, Test Dog wired to the real pipeline (compressed timings).
5. **M5 — Hardening:** wake/screen-change recompute paths, moved/deleted-meeting handling, footprint check against R25/R26, pixel-art polish.

---

## 5. Out of scope (v1)

Explicit no-s, so nobody "fixes" them later without a decision:

- No snooze — Acknowledge is final by design.
- No Microsoft Graph / OAuth path (ADR 0001).
- No replay of missed Alert moments after sleep/launch (R9).
- No screen-capture exclusion of the overlay (R17).
- No auto-detection that the user actually joined a call.
- No Windows/Linux, no App Store, no auto-update.
