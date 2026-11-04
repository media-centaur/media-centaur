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
| Discovery | `/discovery` | The titles you do not own yet, built like Home: search for a title, a hero and shelves — Out Now, New Releases, Reviewed by Friends, your Watchlist by release stage. Needs a TMDB key |
| Watchlist | `/watchlist` | Every title you have put on your list, grouped by what you asked the app to do about it — Auto-grab, Tracking, On your list, Ignored — with what it knows of each one's releases; change any of that on the row |
| Downloads | `/downloads` | Release search, download plans, live downloads and what recently landed. Without Prowlarr it says what it needs |
| Watch history | `/history` | Viewing stats, an activity heatmap, and a filterable list of everything watched |
| Review | `/review` | Files that couldn't be identified confidently, waiting for you to match them |
| Status | `/status` | Operator dashboard: subsystem health, pipeline, storage, integrations, playback — with drill-ins |
| Settings | `/settings` | Credentials, service toggles and actions, the setup tour, and the link to this guide |

Library, Discovery, Watchlist, Downloads, Review, and Settings are places you *act*; Watch history and Status are
mostly *read* — though Status rewards clicking into its tiles.

## The Console, from Status

Every subsystem's logs flow into the Console, tagged by component and filterable live. Each
Status drill-in shows its subsystem's latest lines; **Open in console** opens `/console`
filtered to that subsystem. The systemd journal is on Status → System. When you want to know
what the app just did, look here first.

The whole app is navigable by keyboard and gamepad (see
[Keyboard & gamepad](/guide/keyboard-and-gamepad)). This guide lives at `/guide`, linked from
Settings → System rather than the nav.

> [!TIP]
> The **Status tiles open**: select one for a detail pane with that subsystem's metrics, its
> recent logs and the way into the Console, and from there an incident's full report. Most of
> Status's depth is one step in.
