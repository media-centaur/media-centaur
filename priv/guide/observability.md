---
title: Observability
part: Operating it
slug: observability
order: 17
---
Media Centaur is built to be watched. Two surfaces let you see what it's doing: the Console,
for the live log stream, and the Status page, for subsystem health over time. Between them
you can answer most "what is it doing right now, and is it healthy?" questions without
leaving the app.

## The Console

Every subsystem's logs flow into a ring buffer, each line tagged with the component that
produced it — `watcher`, `pipeline`, `tmdb`, `playback`, `acquisition`, and so on. Press the
backtick (`` ` ``) from any page for the Console drawer, or open `/console` full-screen.

It's built for narrowing down, not just scrolling. Filter by level, toggle whole components
on or off (framework noise is hidden by default), and search the messages. When the app runs
under systemd, a second tab tails the systemd journal alongside the app's own output, so you
can correlate a system event with an app failure in one place. You can copy or download the
buffer to share it.

Diagnostically, the move is: reproduce the problem with the Console open, filtered to the
component you suspect. A file not importing? Filter to `watcher` then `pipeline` and `tmdb`.
Playback not starting? Filter to `playback` and press Play.

## The Status page

Where the Console is the live stream, Status is the dashboard. A health board shows one tile
per subsystem, calm until something needs attention — colour is reserved for health, not
decoration. Select a tile to drill in: a plain-language briefing of what that subsystem does
and how it degrades, an activity widget with its real metrics (pipeline queue depth, TMDB
rate-limit window, scan freshness, active playback sessions), its recent log sample, and its
data-retention stats — what it keeps and what the last sweep removed.

Problems surface here as **incidents**. Some are detected automatically (errors are
fingerprinted and grouped), some are raised by a subsystem that notices it's degraded (a
drive offline, a stalled pipeline), and you can file one yourself. A count appears on the
Status nav item when there's something unseen. Drill from a tile to an incident to its full
report, and dismiss it when handled.

> [!TIP]
> If you want to send a bug report, the "Report a problem" flow builds a complete, redacted
> report — app version, the error, recent activity — and lets you review and remove anything
> before it's used. It then hands you a prefilled GitHub issue that you post under your own
> account; nothing is transmitted by the app itself. You see and control exactly what's
> shared.

In short: the Console is the live, component-tagged log stream you filter and search to
diagnose in the moment; the Status page is the per-subsystem health board with drill-ins,
activity metrics, retention stats, and incidents — together, the app's full diagnostic
surface. The next chapter puts them to work.
