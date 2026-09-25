---
title: Customizing mpv
part: Watching
slug: customizing-mpv
order: 10
---
Playback runs through mpv (see [Playback](/guide/playback)). Media Centaur
starts mpv with its own additions on every play and leaves your mpv
configuration alone. Both layers apply at once.

## What is built in

These load on every play from the app. No files to install.

| Feature | What you get |
|---|---|
| Track menu | **Tab** opens an overlay with Audio, Subtitles and a **Sound** column (night mode, dialogue boost). Sound choices are remembered per folder. **n** toggles night mode without opening the menu. |
| Skip Intro | A button on intro chapters. **Enter** or a click jumps to the next chapter. |
| Next Episode | A button while the credits roll when the next episode is queued, and a countdown in the last 20 seconds. **Enter** or a click plays it now. |

These run only when Media Centaur starts mpv. mpv opened by hand does not
have them.

## Turning one off

Each feature has a switch in mpv's script options. Create
`~/.config/mpv/script-opts/media_centaur.conf` with the lines you want:

```ini
skip_intro=no
next_episode=no
track_menu=no
```

Use this when another script you run covers the same ground, such as uosc's
menus or a chapter-skip script.

## Your own configuration

mpv reads `~/.config/mpv/` as usual: `mpv.conf`, `input.conf`, everything in
`scripts/`, fonts. Media Centaur never writes there. Your key bindings in
`input.conf` take precedence over the built-in ones, so you can move
**Tab** or **n** to other keys, or unbind them.

Two things Media Centaur sets on the command line each time it starts mpv,
which `mpv.conf` cannot change for those plays:

- Playback position comes from Media Centaur, not from mpv's watch-later
  files. Position is saved as you watch no matter how you quit, so a
  `quit-watch-later` binding gains nothing here.
- `keep-open=yes`, so the player window stays until Media Centaur closes it
  at the end of the queue.

## Scripts you can add

Drop them into `~/.config/mpv/scripts/`. They load alongside the built-in
features and need no Media Centaur changes.

- **[uosc](https://github.com/tomasklaen/uosc)**: a richer, proximity-based player UI.
- **[mpv-mpris](https://github.com/hoyon/mpv-mpris)**: standard Linux media-key support.
- **[mpv-kscreen-doctor](https://gitlab.com/smaniottonicola/mpv-kscreen-doctor)**: match the display's refresh rate to the video's framerate (Wayland-friendly).
- **[mpv-oled-screensaver](https://github.com/Akemi/mpv-oled-screensaver)**: fade to black when paused in fullscreen.

## A starting point for mpv.conf

The **[contrib repo](https://github.com/media-centaur/contrib)** keeps an
example configuration under
[`mpv/`](https://github.com/media-centaur/contrib/tree/main/mpv): an
`mpv.conf` with rendering, HDR and audio dynamic-range settings, an
`input.conf` grouped by concern, and `hdr-display.lua`, a script that
switches a Hyprland display into HDR mode while HDR content plays. Copy
what you want into `~/.config/mpv/`; nothing in Media Centaur needs it.
The audio settings are explained in the contrib
[mpv-setup guide](https://github.com/media-centaur/contrib/blob/main/guides/mpv-setup.md).

## If you installed the scripts by hand before

Earlier versions asked you to copy `skip-intro.lua`, `next-episode.lua` and
`track-menu.lua` into `~/.config/mpv/scripts/`. mpv still loads those, so
each feature runs twice and you see two buttons. Delete the three files.
Status → Playback names them while they are present.
