---
title: A tour of the app
nav_label: App tour
part: Orientation
slug: a-tour-of-the-app
order: 3
---
Media Centaur is a handful of pages reached from a sidebar on the left, in two groups: a
**Watch** group for using your library and a **System** group for managing it.

## The pages

| Page | Route | What it's for |
|---|---|---|
| Home | `/` | Landing page: a hero title, Continue Watching, what's coming up, recently added |
| Library | `/library` | Your full catalog as a poster grid — type tabs, sort, text filter; select a title for its detail overlay |
| Upcoming | `/upcoming` | Time-ordered forecast of releases you're tracking, with status and auto-grab controls |
| Watch history | `/history` | Viewing stats, an activity heatmap, and a filterable list of everything watched |
| Downloads | `/download` | Search, download plans, active pursuits, and history. Appears once Prowlarr + a download client are configured |
| Review | `/review` | Files that couldn't be identified confidently, waiting for you to match them |
| Status | `/status` | Operator dashboard: subsystem health, pipeline, storage, integrations, playback — with drill-ins |
| Settings | `/settings` | Credentials, service toggles and actions, the setup tour, and the link to this guide |

Library, Downloads, Review, and Settings are places you *act*; Watch history and Status are
mostly *read* — though Status rewards clicking into its tiles.

## The Console, from anywhere

Press the backtick — `` ` `` — on any page to drop the Console drawer; Escape closes it.
Every subsystem's logs flow into it, tagged by component and filterable live, with a tab for
the systemd journal alongside the app's own output. The same logs have a full-page home at
`/console`. When you want to know what the app just did, look here first.

The whole app is navigable by keyboard and gamepad (see
[Keyboard & gamepad](/guide/keyboard-and-gamepad)). This guide lives at `/guide`, linked from
Settings → System rather than the nav.

> [!TIP]
> Two things people miss for months: the **Console is global** — the backtick works on every
> page, not just Settings or Status — and the **Status tiles are clickable**, opening a detail
> pane and, from there, an incident's full report. Most of Status's depth is behind a click.
