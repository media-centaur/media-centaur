---
title: First run
part: Orientation
slug: first-run
order: 2
---
On first launch the app opens the setup tour at `/setup`. It tests each thing Media Centaur
needs and shows you what's working. Re-run it any time from Settings → System → *Run setup
tour*; each step is a deep link, so you can jump straight to one.

A release build listens on port **2160**, a development build on **1080**.

## The steps

Two steps are required; the rest are optional and each unlocks one capability.

| Step | Required? | Configure | Unlocks |
|---|---|---|---|
| Media directories | **Yes** | The folders your video files live in | File discovery — the watcher scans these |
| TMDB | **Yes** (test must pass) | A free API key | Identification, artwork, release tracking, Review queue, in-app search |
| mpv | No | Path to the mpv binary (auto-detected) | Playback — the Play button |
| ffprobe | No | Path to ffprobe (ships with ffmpeg) | Reading embedded audio/subtitle tracks → language-aware track selection |
| Prowlarr | No | Base URL + API key | In-app release search |
| Download client | No | qBittorrent URL + credentials | Download progress and auto-grab |

Get a TMDB key at [themoviedb.org](https://www.themoviedb.org/settings/api). The tour won't
advance past the TMDB step until its connection test passes; the media-directories step needs
at least one folder. Optional steps can be skipped and configured later in Settings.

> [!TIP]
> ffprobe is the step most people skip, and the one that quietly costs the most. mpv plays
> fine without it, so skipping it feels safe — but then the app only sees sidecar `.srt`
> files, never the subtitle and audio tracks inside your videos. If track selection isn't
> offering languages you know are in a file, this is usually why. See
> [How identification works](/guide/how-identification-works).
