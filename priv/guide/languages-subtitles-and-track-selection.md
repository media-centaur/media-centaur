---
title: Languages, subtitles & track selection
part: Your library
slug: languages-subtitles-and-track-selection
order: 8
---
A video file often carries several audio and subtitle tracks. Media Centaur learns which
tracks a file has, then decides which ones to play based on your preferences — rather than
leaving it to whatever the file happens to flag as default. Two pieces do this work:
detection at import, and resolution at playback.

## Detection: learning a file's tracks

At import, if [ffprobe](/guide/first-run) is configured, it reads the embedded subtitle
streams and their language tags. Alongside that, the app looks for sidecar files next to the
video — `.srt`, `.ass`, and similar — taking the language from a suffix like `Movie.en.srt`.
Both kinds are stored as tracks against the file, with their languages normalised to a
single form so comparisons are reliable later.

Without ffprobe you still get sidecar subtitles, but the app can't see the languages of the
tracks *inside* your files — so it can't pick them for you by language. This is the single
biggest reason to configure ffprobe.

## Resolution: choosing what plays

When you start playback, a resolver decides which audio and subtitle track should play, and
then makes mpv obey by setting the tracks directly. It is the source of truth — not the
file's own "default" flags, which can't be trusted.

Its decision follows your **language policy** (set under Settings):

- **Understood languages** — the languages you don't need subtitles for, in priority order.
  The resolver picks audio in your original-or-understood preference, and uses this list to
  choose a subtitle language when one is needed.
- **When to show subtitles** — never, only when the audio isn't a language you understand
  (the default), or always.
- **Subtitle language and style** — match your understood language or the audio language
  (useful for language learners), and optionally prefer SDH (hearing-impaired) tracks.
- **Forced subtitles** — whether to show forced subs always, never, or only to fill gaps
  when you understand the audio (the default — this is what subtitles the alien dialogue in
  an otherwise-English film).

> [!TIP]
> Scene rips frequently mislabel a *full* dialogue subtitle track as both `forced` and
> `default`. Left alone, mpv would switch it on over audio you understand. Media Centaur
> distrusts that exact combination — a track flagged `forced` *and* `default` is treated as
> not genuinely forced — so you stop getting full subtitles burned on over English audio.
> Genuinely forced tracks (forced, not default) still work.

## Per-title overrides, captured automatically

You don't have to configure anything per show. Change the audio or subtitle track during
playback, leave it a moment, and that choice is remembered as an override for that title —
applied automatically the next time you play it (or the next episode of that series).
Overrides are stored by language, not track number, so they survive a re-rip.

In short: ffprobe lets the app see your files' tracks; a resolver — not the file's flags —
picks audio and subtitles from your language policy, distrusts mislabeled forced tracks, and
quietly learns your per-title preferences as you set them during playback.
