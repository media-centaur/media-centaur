---
title: Playback
part: Watching
slug: playback
order: 9
---
Media Centaur doesn't play video in your browser. It launches mpv on the machine running the
app, full-screen, and controls it over a local socket. The browser is a remote that starts
playback and watches what happens — the playing happens on the couch-side machine, where mpv
owns the screen and the input.

## What Play does

Pressing Play works out where to start (see Resume), launches a dedicated mpv process for
that title, and connects over an IPC socket. Each title gets its own instance, so more than
one can run at once. The backend only *observes* mpv — it records position, pause, and
end-of-file. It deliberately does not drive mpv from the browser: there's no pause or seek
button in the web UI. Input belongs to whoever is at the screen.

## Resume

- Progress saves every few seconds while you're watching, immediately on pause or quit, and
  **never while seeking** — so scrubbing doesn't corrupt your position.
- A title is **complete at 90%** watched, and stays complete once it crosses that line.
- For a series, Play finds the last episode you were on: resumes it if unfinished, plays the
  next if finished, or starts over if you've finished them all.

## On-screen controls

The bundled mpv configuration (in `contrib/mpv`) adds a track menu (**Tab** → an Audio /
Subtitles overlay; changing tracks here is how per-title overrides get captured — see
[Languages, subtitles & track selection](/guide/languages-subtitles-and-track-selection))
and a **Skip Intro** prompt on intro chapters. The common keys:

| Key | Action |
|---|---|
| Space | Pause / play |
| ← / → | Seek ∓5s · ↓ / ↑ seek ∓30s |
| `[` / `]` | Speed down / up · Backspace resets |
| Tab | Track menu (audio / subtitles) |
| v · a | Cycle subtitle visibility · cycle audio |
| f | Fullscreen |
| Esc / q | Quit and save position |

> [!TIP]
> Two things people don't expect. **Restarting the app doesn't kill playback** — the backend
> reconnects to the running mpv and keeps recording progress. And when a title's drive is
> unmounted, its Play button goes quiet rather than erroring — it won't start something that
> isn't there.
