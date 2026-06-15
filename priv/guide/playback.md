---
title: Playback
part: Watching
slug: playback
order: 9
---
Media Centaur doesn't play video in your browser. It launches mpv on the machine running
the app, full-screen, and controls it over a local socket. The browser is a remote that
starts playback and watches what happens — the actual playing happens on the couch-side
machine, where mpv has the screen and the input.

## What Play does

When you press Play, the app works out *where* to start (see Resume, below), then launches a
dedicated mpv process for that title and connects to it over an IPC socket. Each title you
play gets its own mpv instance, so you can have more than one going at once.

The backend only *observes* mpv — it watches the position, pause state, and end-of-file and
records your progress. It deliberately does **not** drive mpv from the browser: there's no
pause or seek button in the web UI. Input belongs to whoever is at the screen — keyboard,
remote, or gamepad — with no round-trip through the browser. The web UI shows that something
is playing and updates live; it doesn't remote-control it.

## Resume

Progress is saved every few seconds while you're actually watching, immediately when you
pause or quit, and never while you're seeking — so scrubbing around doesn't corrupt your
saved position. A title counts as **completed** at 90% watched, and once complete it stays
complete.

Resume is smart about series. Play a series and it finds the last episode you were on: if
you didn't finish it, it resumes there; if you did, it plays the next one; if you've
finished them all, it starts over. Movies resume where you left off, or restart if you'd
already finished.

## On screen

mpv shows its standard on-screen controller. The bundled mpv configuration (in `contrib/mpv`)
adds two things worth knowing:

- **A track menu** — press Tab for a two-column Audio / Subtitles overlay you navigate with
  the arrow keys. Changing tracks here is also how per-title overrides get captured (see
  [Languages, subtitles & track selection](/guide/languages-subtitles-and-track-selection)).
- **Skip Intro** — when playback enters a chapter named like an intro or opening, a Skip
  Intro prompt appears that jumps to the next chapter.

Standard mpv keys apply too — space to pause, arrows to seek, `f` for fullscreen, Esc or `q`
to quit and save your position.

> [!TIP]
> Two things people don't expect. First, **restarting the app doesn't kill playback** — when
> the backend comes back it reconnects to the still-running mpv and keeps recording your
> progress. Second, when a title's drive is unmounted its Play button goes quiet rather than
> erroring — it just won't start something that isn't there.

In short: Play launches mpv locally and the backend watches it; input lives at the screen,
not the browser; resume saves continuously (but not while seeking) and auto-advances series;
and the bundled mpv config adds a track menu and intro-skipping.
