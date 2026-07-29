# Meetie

A macOS app that makes meeting starts impossible to miss: playful, full-attention alerts that reach every monitor and fullscreen Space, unlike the small corner toast that only appears on one desktop.

## Language

**Meeting**:
Any timed (non-all-day) event on a Watched Calendar that the user has not declined. Deliberately broad — attendee count and join links do not matter; tentative and unanswered invites count.
_Avoid_: Event, appointment

**Alert**:
The full-attention, playful notification for one Meeting. Appears at the configured notify-at lead before start (1 minute by default; 5 or 10 minutes, or right at start) and persists until Acknowledged, or self-expires when the Meeting's end time passes. It fires only at its scheduled moment — a moment that passes while the Mac is asleep or Meetie isn't running is skipped, never replayed.
_Avoid_: Notification, reminder, toast

**Dog**:
The pixel-art mascot. One Dog per Alert roams every screen — bouncing off the monitor edges — towing the Banner of the Meeting it announces.
_Avoid_: Cat, critter, sprite, mascot

**Banner**:
The sign a Dog tows: Meeting title, live countdown, and the Join action when a join URL exists.
_Avoid_: Toast, sign, label

**Acknowledge**:
The deliberate action that makes an Alert go away. Clicking a Dog or Banner opens the Meeting details; choosing Dismiss, or Join when a join URL exists, Acknowledges the Alert. The Banner's Join button joins in one click.
_Avoid_: Snooze

**Watched Calendar**:
A calendar whose events are eligible to become Meetings. All calendars are watched by default; the user can opt individual calendars out.
_Avoid_: Enabled calendar, selected calendar
