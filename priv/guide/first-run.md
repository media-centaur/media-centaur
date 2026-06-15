---
title: First run
part: Orientation
slug: first-run
order: 2
---
On first launch the app sends you to the setup tour at `/setup`. It walks through the
handful of things Media Centaur needs to know about your system, tests each one, and shows
you what's working. You can re-run it any time from Settings → System → *Run setup tour* —
and each step is a deep link, so you can jump straight back to the one you need.

The tour has eight steps. Two are required before the app is useful; the rest unlock
optional capabilities.

## The required steps

- **Media directories** — the folders your video files live in. Without at least one, the
  library stays empty. This is what the watcher scans and what feeds identification.
- **TMDB** — a free API key from [themoviedb.org](https://www.themoviedb.org/settings/api).
  It identifies your titles and downloads artwork, and it's what powers release tracking,
  the Review queue, and in-app search. The tour won't advance past this step until the
  connection test passes.

## The optional steps

Each is skippable, and each unlocks something specific:

- **mpv** — the player binary. Without it, the Play button does nothing. The tour
  auto-detects it in the usual locations.
- **ffprobe** — ships with ffmpeg. It reads the audio and subtitle tracks embedded in your
  files, which is what makes language-aware track selection work. See
  [How identification works](/guide/how-identification-works).
- **Prowlarr** — an indexer manager. Configuring it turns on in-app release search.
- **Download client** — qBittorrent today. With it, the app tracks download progress and
  drives acquisition end to end.

> [!TIP]
> ffprobe is the step most people skip, and the one that quietly costs the most. mpv plays
> fine without it, so skipping it feels safe — but then the app only sees sidecar `.srt`
> files, never the subtitle and audio tracks inside your videos. If track selection isn't
> offering languages you know are in a file, this is usually why.

## Where it's listening

A release build listens on port **2160**; a development build uses **1080**. The port is
configurable, but those are the defaults you'll find it on.

In short: media directories and a TMDB key get you a working library; mpv adds playback;
and the optional steps — ffprobe especially — are where most of the unused capability hides.
