---
title: What Media Centaur is (and isn't)
nav_label: What it is
part: Orientation
slug: what-media-centaur-is
order: 1
---
Media Centaur manages a local media library and plays it back. It scans the video
directories you point it at, identifies what it finds against TMDB, downloads artwork and
metadata, tracks what you've watched, and plays files through mpv on the same machine —
all from a browser UI. Acquisition (searching indexers and grabbing releases) is optional
and stays off until you configure it.

It runs as one application against one SQLite database. That single fact explains most of
what follows.

## What it deliberately isn't

Knowing the boundaries is as useful as knowing the features — it tells you when you're
holding it wrong.

- **No transcoding.** Files play at their native codec and resolution; Media Centaur never
  re-encodes. If something won't play, the fix is the player or the file, not a setting.
- **No streaming to other devices.** Playback happens on the machine running the app,
  through mpv. There's no remote web player, no casting, no mobile app.
- **One database, no accounts.** All state lives in one SQLite file. There are no users, no
  logins, no permissions — whoever is at the keyboard or on the couch is the only user.
- **No cloud.** Beyond TMDB lookups and optional indexer search, it needs no internet. Your
  library, progress, and metadata are all local.
- **Linux-first.** Linux is the supported platform; macOS (Apple Silicon) is experimental.

These aren't gaps waiting to be filled — they're the shape of the project. The reasoning
behind each is in the [FAQ](https://github.com/media-centaur/media-centaur/wiki/FAQ).

## How it's built, and why that matters to you

A few design choices show through to how you operate it:

- **It reacts in real time.** State changes — a file detected, artwork downloaded, playback
  started — are broadcast internally, so every open page updates itself. You rarely refresh.
- **Derived data is recomputable.** Watch progress, image caches, and the coverage figures
  you see are computed from source data, not stored as the truth. If one looks wrong, it's
  rebuilt from scratch rather than repaired — which is why destructive-looking maintenance
  actions are safe.
- **Features gate on capabilities.** Anything that needs TMDB, an indexer, or a download
  client only appears once its connection test passes, so you won't land on a dead end.
- **It's built to be observed.** Every subsystem logs to the Console and reports health on
  the Status page, and keeps its data on a stated retention schedule. When something's off,
  you can see what the app is actually doing.

> [!TIP]
> Two lists that look alike are deliberately different. **Continue Watching** keeps a title
> even if its drive disconnects mid-session, so your progress is safe; **Library** only
> shows titles whose files are present right now. A title disappearing from Library isn't
> lost — it's just offline.

In short: one app, one database, local playback, no cloud — and a system designed so you
can always see what it's doing and safely recompute what it derived.
