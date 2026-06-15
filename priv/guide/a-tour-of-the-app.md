---
title: A tour of the app
part: Orientation
slug: a-tour-of-the-app
order: 3
---
Media Centaur is a handful of pages, reached from a sidebar on the left. They fall into two
groups: a **Watch** group for using your library, and a **System** group for managing it.

## The pages

- **Home** (`/`) — the landing page: a hero title, Continue Watching, what's coming up, and
  recently added.
- **Library** (`/library`) — your full catalog as a poster grid, with type tabs, sorting,
  and a text filter. Selecting a title opens its detail overlay.
- **Upcoming** (`/upcoming`) — a time-ordered forecast of releases you're tracking, with
  their status and auto-grab controls.
- **Watch history** (`/history`) — your viewing stats, an activity heatmap, and a filterable
  list of everything you've watched.
- **Downloads** (`/download`) — search, download plans, active pursuits, and history in one
  place. It only appears in the nav once Prowlarr and a download client are configured.
- **Review** (`/review`) — files that couldn't be identified confidently, waiting for you to
  match them. See [How identification works](/guide/how-identification-works).
- **Status** (`/status`) — the operator dashboard: subsystem health, pipeline activity,
  storage, integrations, and playback, with drill-ins for the details.
- **Settings** (`/settings`) — credentials, service toggles and actions, and the setup tour.

Some pages are places you *act* — Library, Downloads, Review, Settings. Others you mostly
*read* — Watch history and Status — though Status rewards clicking into its tiles.

## The Console, from anywhere

Press the backtick key — `` ` `` — on any page and the Console drawer slides down. Every
subsystem's logs flow into it, tagged by component and filterable live; Escape closes it.
The same logs have a full-page home at `/console`, with a tab for the systemd journal
alongside the app's own output. When you're trying to understand what the app just did,
this is the first place to look.

> [!TIP]
> Two things people miss for months. First, the **Console is global** — the backtick works
> on every page, not just Settings or Status. Second, the **Status tiles are clickable**: a
> subsystem tile opens a detail pane, and an incident inside it opens its full report. Most
> of the depth on Status is behind a click.

The whole app is navigable by keyboard and gamepad — arrow keys move focus, Enter selects,
Escape goes back — and the bindings are remappable under Settings → Controls. This guide
lives at `/guide`; it's linked from Settings → System rather than the nav, so it stays out
of the way until you want it.

In short: a Watch group for your library and a System group to manage it, the Console a
backtick away from anywhere, and more depth behind the Status tiles than they first show.
