---
title: Customizing mpv
part: Watching
slug: customizing-mpv
order: 10
---
Playback runs through mpv (see [Playback](/guide/playback)). Media Centaur ships an optional
mpv configuration — a couple of Lua scripts plus tuned settings — that makes mpv behave like
a media-center player: a track picker, a Skip Intro button, sensible rendering, and audio
that doesn't blast you. It's not installed automatically; you opt in by copying it into your
mpv config.

The config is the source of truth in the **[contrib repo](https://github.com/media-centaur/contrib)**,
under [`mpv/`](https://github.com/media-centaur/contrib/tree/main/mpv).

## What it adds

| Piece | What you get |
|---|---|
| [`scripts/track-menu.lua`](https://github.com/media-centaur/contrib/blob/main/mpv/scripts/track-menu.lua) | A glassy **Tab** overlay: Audio, Subtitles, and a **Sound** column (night mode + dialogue boost), remembered per folder |
| [`scripts/skip-intro.lua`](https://github.com/media-centaur/contrib/blob/main/mpv/scripts/skip-intro.lua) | A **Skip Intro** button on intro chapters |
| [`mpv.conf`](https://github.com/media-centaur/contrib/blob/main/mpv/mpv.conf) | Rendering (Vulkan + hardware decode), language defaults, OSD, and audio dynamic-range handling |
| [`input.conf`](https://github.com/media-centaur/contrib/blob/main/mpv/input.conf) | Key bindings, grouped by concern |

## Installing it

mpv reads from `~/.config/mpv/`, so you install by copying the files there:

```sh
git clone https://github.com/media-centaur/contrib.git
cp contrib/mpv/mpv.conf ~/.config/mpv/mpv.conf
cp contrib/mpv/input.conf ~/.config/mpv/input.conf
cp -r contrib/mpv/scripts/ ~/.config/mpv/scripts/
```

Scripts auto-load — no registration. Restart mpv (close any open playback) to pick up changes.

## Keeping it up to date

There's no automatic sync. After `git pull` in the contrib repo, re-copy the changed files —
or **symlink** them once so a pull updates mpv directly:

```sh
ln -sf "$PWD"/contrib/mpv/scripts/*.lua ~/.config/mpv/scripts/
ln -sf "$PWD"/contrib/mpv/input.conf ~/.config/mpv/input.conf
```

Keep **`mpv.conf` as your own copy** rather than a symlink — it carries per-machine bits
(GPU/display) you'll want to tune locally.

## Taming loud-then-quiet audio

The standout feature. Theatrical mixes whisper the dialogue and then deafen you with the
explosion; on a home setup that range is punishing. The config offers three independent fixes,
two of them as live toggles in the track menu's **Sound** column (or the `n` key):

- **Authored DRC** (on by default) — applies the dynamic-range curve the film's own mixers
  wrote, the least destructive option.
- **Night mode** — evens out loud and quiet passages when the authored curve isn't enough.
- **Dialogue boost** — lifts buried dialogue (often a casualty of a 5.1→stereo downmix).

Sound choices are **remembered per folder**, so setting night mode once on a season folder
carries to every episode. The full rationale and tuning is in the contrib
[mpv-setup guide](https://github.com/media-centaur/contrib/blob/main/guides/mpv-setup.md).

## Going further

That same guide recommends external plugins that complement the bundled config — they drop
into `~/.config/mpv/scripts/` and need no Media Centaur changes:

- **[uosc](https://github.com/tomasklaen/uosc)** — a richer, proximity-based player UI.
- **[mpv-mpris](https://github.com/hoyon/mpv-mpris)** — standard Linux media-key support.
- **[mpv-kscreen-doctor](https://gitlab.com/smaniottonicola/mpv-kscreen-doctor)** — match the display's refresh rate to the video's framerate to kill judder (Wayland-friendly).
- **[mpv-oled-screensaver](https://github.com/Akemi/mpv-oled-screensaver)** — fade to black when paused in fullscreen, to spare OLED panels.

> [!TIP]
> The per-folder sound memory is the bit people miss: flip **night mode** once for a show and
> every episode in that folder inherits it, while a film in an unconfigured folder still starts
> at the faithful default.
