---
status: in-progress
started: 2026-05-24
last_updated: 2026-06-15
---
# Track selection: resolver as source of truth (kill mislabeled-forced subs)

## Goal

Stop full subtitle tracks that are *mislabeled* `forced` from being
auto-enabled when the audio is in a language the user understands.
Today the on-screen subtitle is chosen by **mpv's own auto-selection**
from our launch flags plus the file's disposition flags; our
`TrackResolver.resolve/5` only *shadows* that choice for
override-capture and never enforces it. The fix is to make the resolver
the **single source of truth**: it decides, mpv obeys (active `set
property sid`), and it distrusts a `forced` flag that is contradicted by
a `default` flag (the mislabel signature). Matters because the default
`forced_subs: "fill_gaps"` policy means this misfires on every release
that stamps `forced` onto a full dialogue track — common for scene x265
rips.

## Status

**Core fix shipped 2026-06-15 — at a stable resting point.** The A/B/C
fix (resolver distrusts the `forced+default` mislabel and actively
enforces `sid`) is implemented, tested, and pushed to `main` (commit
`3d07f74b`). Everything below in "Remaining" is **additive and
optional** — none of it touches the shipped code, none of it leaves the
app half-built. The campaign can be resumed cold at any time with zero
burden on the running app; if it's never resumed, the app is still
correct and complete for the reported bug.

*Implemented test-first per `automated-testing` (red→green on each unit).*

*Reconciled 2026-06-15 (v0.97.2):* code still matches the diagnosis —
`TrackResolver.Track` (`track_resolver.ex:28-42`) has no `default`
field; `LanguageContext.build_track/1` (`language_context.ex:95-107`)
parses `forced` but not `default`; `MpvSession.handle_track_list_update/2`
(`mpv_session.ex:508-523`) computes `compute_resolver_choice/1`
(`:525-544`) and only logs, never sends a `set_property`. `find_forced/2`
is at `:347-351`, `forced_fallback/3` at `:333-345`, `resolve/5` at
`:165`. `send_mpv_command/2` (the IPC primitive) at `mpv_session.ex:847`;
`observe_properties/1` at `:835`. All pointers below re-verified at
v0.97.2.

*Scope decisions settled 2026-06-15 (the three open questions):*

* **sid-only enforcement** for v1, with a clear seam for `aid` (the
  reported bug is subtitle-only; audio enforcement adds risk for no
  current payoff). `aid` enforcement would be the symmetric call.
* **`forced+default` disposition heuristic** is the v1 mislabel signal.
  Cue-count capture (ffprobe-at-import) is the *stronger* signal but is
  deferred — it's the natural home for the "surface ffprobe subtitle
  detail" thread that spawned this resume. Disposition is free at
  launch; cue counts require a pipeline change.
* **Startup-flash:** gate enforcement on subtitle tracks being present
  (don't fire `sid=no` during the audio-only incremental window), and
  accept the brief possible flash of the mislabeled sub before
  enforcement turns it off. Inverting to launch-`--sid=no` (mitigation
  in the campaign) is deferred — accept the flash for v1.

*Implementation landed 2026-06-15 (pushed to main, commit `3d07f74b`):*

* **A** — `TrackResolver.Track` now carries `default: false`;
  `LanguageContext.build_track/1` parses `"default"` from the mpv map.
  Unit test in `language_context_test.exs` (red→green).
* **B** — `find_forced/2` now matches via `genuinely_forced?/1`
  (`forced and not default`), so `forced+default` tracks are distrusted
  in both fill_gaps and always paths. Three appended resolver tests
  (mislabel distrusted, genuine forced still resolves, genuine forced
  beats a mislabeled sibling).
* **C** — `TrackResolver.sid_enforcement/2` (pure, unit-tested) decides
  `:skip | {:set, "no"} | {:set, index}`; `MpvSession.enforce_subtitle_selection/2`
  sends `set_property sid` idempotently (only on change) from
  `handle_track_list_update/2`, tracked via the new `enforced_sid` state
  field. mpv's disable form is the string `"no"`.

**Remaining — all additive, none blocks the shipped fix.** Resume any of
these independently; the app stays correct if none are ever done.

* **Manual verification — WAIVED 2026-06-15.** The completion criterion
  was "play the repro file (The Wire S01E01) on a fresh-install default
  policy and confirm no subtitles + a `track-resolver: enforcing
  sid="no"` Console line." Owner declined to test; the fix ships on its
  automated-test coverage alone. *This is the one thing the shipped code
  has not had eyes-on in a real player* — if subs ever still misbehave
  on that file, start here (the Console line tells you whether the
  resolver decided wrong (B) or the IPC didn't land (C)).
* **Cue-count capture at import (highest-value follow-up).** ffprobe the
  subtitle stream's cue count during the pipeline and persist it as
  track metadata, so the resolver can distrust a "forced" track by
  *length* (full ≈ hundreds, genuine forced ≈ tens) instead of / on top
  of the `forced+default` disposition heuristic. This is the home for
  the "surface ffprobe subtitle detail" thread that spawned this work.
* **`aid` (audio) enforcement.** Symmetric to the shipped `sid`
  enforcement; the seam is documented on `TrackResolver.sid_enforcement/2`.
* **Startup-flash mitigation.** Launch with `--sid=no` and let
  enforcement turn subs *on*, trading a flash of missing subs (foreign
  audio) for the current flash of unwanted subs (understood audio).
* **Inverse case (pre-existing, low priority).** A foreign-audio title
  whose *only* subtitle is a mislabeled `forced+default` full track now
  yields no subtitles. This was already true before the fix; out of
  scope, noted so it isn't rediscovered as a new regression.
* **Wiki note.** A Troubleshooting/FAQ line ("subtitles appeared on
  understood-audio content; now auto-corrected") if worth surfacing.

## Background — the confirmed bug

User report: first-ever play of **Sample Show S01E01** (English audio the
user understands) comes up with subtitles **on**. Expected: off.

First hypothesis (untagged audio) was **wrong** — disproven by probing
the actual file. Always confirm before resolving.

**Evidence (deterministic, gathered 2026-05-24):**

* Live-node query (`~/scripts/mc-rpc`): series `Sample Show`,
  `original_language = "en"`; S01E01 ("Sample Episode") file is
  `…/Sample.Show.S01E01.1080p.Bluray.x265-HiQVE.mkv`. Global policy is the
  built-in default (`subtitles_when = "when_audio_not_understood"`,
  `understood_languages = ["eng"]`, `forced_subs = "fill_gaps"`).
* `ffprobe` of that file:
  * **Audio** stream `index=1`, `codec=ac3`, **`language=eng`** —
    correctly tagged, so "audio is understood" is correctly `true`.
  * **Subtitle** stream `index=2`, **`codec=subrip`**, `language=eng`,
    **`DISPOSITION:forced=1` AND `DISPOSITION:default=1`**, title
    "English", and **863 cues**. 863 SubRip cues is a *full episode
    dialogue track*; a genuine forced track (foreign dialogue / signs
    only) has a few dozen at most. → **the `forced` flag is a lie.**

**Why subs end up on (two-part root cause):**

1. **Policy trusts the bogus `forced` flag.** With audio understood and
   `forced_subs = "fill_gaps"`, the resolver's forced-fallback returns
   the (fake) forced English track — `track_resolver.ex:339-343`
   (`forced_fallback(%{forced_subs: "fill_gaps"}, …)` →
   `audio_understood?("eng", ["eng"]) == true` → `find_forced/2` at
   `:347-351` finds the `forced=1` track).
2. **The visible selection is mpv's, not ours.** The actual on-screen
   track is chosen by mpv from the launch flags
   (`--slang=eng --sub-visibility=yes --subs-with-matching-audio=forced`,
   built in `track_resolver.ex:110-152` / applied
   `mpv_session.ex:340`) **plus the file's `default=1` disposition**.
   `resolve/5` is computed post-launch only to feed
   `OverrideCapture.compute/2` (`mpv_session.ex:494`, `528-546`,
   `571`); it never sends a `set sid`. So even a perfect resolver
   wouldn't change what the user sees today — the file's `default=1`
   would still drive mpv.

**Therefore a launch-flag-only fix is impossible:** the mislabel
(`forced+default`, full-length) is only visible *after* mpv reports the
track-list. The fix has to act post-launch.

## The chosen approach (option 1 of 3 — user picked the systemic fix)

Make the resolver the source of truth; have `MpvSession` enforce its
decision; teach the resolver to distrust the mislabel.

**A. Parse the `default` disposition into the Track struct.**
`TrackResolver.Track` (`track_resolver.ex:28-42`) currently has
`index, lang, title, forced, sdh` — **no `default`.** Add
`default: false`. Parse it in `LanguageContext.build_track/1`
(`language_context.ex:97-109`) from the mpv track-list map
(`Map.get(track, "default", false) == true`; mpv exposes a boolean
`default` per track alongside `forced`).

**B. Distrust contradictory forced flags in the resolver.** A track
flagged **both `forced` and `default`** in an understood language is not
a genuine forced track — treat it as *not forced* for fill-gaps
purposes (i.e. `find_forced/2` / the `fill_gaps` branch must skip it).
Heuristic, because cue counts aren't available at launch; `forced=1 AND
default=1` on the same track is contradictory in intent ("only show when
needed" vs "the main track") and is a strong, *free* mislabel signal.
Keep the change localized to the forced-fallback path so genuine forced
tracks (forced, not default, sparse) still work.

**C. Active enforcement — resolver decides, mpv obeys.** After the
track-list settles, `MpvSession` sends `set_property sid` to mpv to
match `resolve/5`'s `sub_index` (or disable: `sid` → `"no"`/`false` when
`sub_index == nil`). Today `handle_track_list_update/2`
(`mpv_session.ex:511-526`) computes the choice and logs it but takes no
action; add the IPC send here. Use the existing
`send_mpv_command/2` (see `observe_property` sends at
`mpv_session.ex:843-845`). **Verify mpv's accepted disable form** for
sid over JSON IPC (`"no"` string vs `false`). Optionally enforce `aid`
too for a fully consistent source-of-truth model — **scope decision
below.**

**Keep the launch flags** as the pre-launch best guess (they give a
reasonable initial selection before track-list arrives); enforcement
corrects them once the real tracks are known. Accept (or mitigate) a
possible brief startup flash where mpv shows the mislabeled sub for a
moment before enforcement turns it off — see Risks.

## Interactions to get right (the wiring, where the real bugs live)

* **Incremental track-list.** mpv populates tracks incrementally (audio
  demuxes before subs) — the existing comment at
  `mpv_session.ex:504-510` documents this. Enforce only once subtitle
  tracks are present/stable; re-affirm on later track-list updates.
* **Don't fight the user.** Per the same comment, a *user* track switch
  fires `aid`/`sid`, **never** `track-list`. So enforcing on
  `track-list` updates won't clobber a deliberate user selection. Our
  own `set sid` *does* fire a `sid` event (`mpv_session.ex:494`) — make
  sure enforcement triggers on `track-list` only, never re-fires off its
  own `sid` echo (no enforcement loop).
* **OverrideCapture stays correct (arguably cleaner).** After we enforce
  `sid = resolver_choice.sub_index`, current state == resolver_choice →
  `OverrideCapture.compute/2` returns `:no_change` (no spurious
  override). A later user change diverges from the baseline and is
  captured as today. Confirm `resolver_choice` (capture baseline) and
  the enforced sid are the *same* `resolve/5` result.

## Test plan (test-first, mandatory)

1. **Reproduce in a failing pure test first** (red before fix), then
   fix, then green — per `automated-testing`.
2. **Resolver unit tests** (`test/media_centaur/playback/track_resolver_test.exs`,
   `async: true`, **append-only per ADR-027**):
   * The currently-missing combo the first hypothesis exposed:
     `subtitles_when = "when_audio_not_understood"` + audio understood +
     a `forced` sub present → fill_gaps behavior.
   * **New:** a track that is `forced AND default` in an understood
     language is **not** returned by the forced-fallback (the mislabel
     case). A `forced`-only (not default) track **is** returned (genuine
     forced still works).
3. **Track parsing test** for `LanguageContext.parse_track_list/1` —
   asserts `default` is parsed from the mpv map into `Track.default`.
   (LanguageContext is glue; the parse is pure-ish and worth a direct
   test of the struct it produces.)
4. **Enforcement decision is pure / extracted.** Per testing policy,
   `MpvSession` is a thin external wrapper (not mocked). `resolve/5`
   already yields `sub_index`/`audio_index`, so the *what to send*
   decision is already pure. If any "should we (re)send given
   prev_choice vs new_choice" logic is added, extract it to a pure
   helper and unit-test it; keep the IPC `send_mpv_command` call itself
   thin and untested.
5. **No new flakes:** `mix test --repeat-until-failure N` on touched
   files; full `mix precommit` green before shipping.

## Scope decisions to settle on resume

* **Audio enforcement too?** Cleanest "source of truth" = enforce both
  `aid` and `sid`. Minimal scope = `sid` only (the reported bug).
  Recommendation: start `sid`-only, leave a clear seam for `aid`.
* **Heuristic strength.** `forced+default` is the cheap signal. A
  stronger signal is **cue count** (forced ≈ tens, full ≈ hundreds),
  but that needs probing the subtitle stream — not available from mpv's
  track-list. Possible later enhancement: capture sub-track cue counts
  at *import* time (ffprobe in the pipeline) and persist as track
  metadata, so the resolver can use a count threshold instead of /in
  addition to the disposition heuristic. Out of scope for v1.
* **Startup flash mitigation.** If the brief flash is objectionable,
  consider launching with `--sid=no` and letting enforcement turn subs
  *on* (rather than the reverse). Trade-off: a flash of *missing* subs
  for foreign-audio content instead of a flash of *unwanted* subs for
  understood-audio content. Decide based on which is rarer/less jarring.

## Interim workaround (already works, no code)

A per-title override is the escape hatch *today*: while playing Sample
Show, turn subtitles off once — `OverrideCapture` persists
`subtitles_off = true` for the series
(`override_capture.ex` `subtitles_off_override/2`), and the next launch
applies `--sid=no` (`build_disable_subs/2` →
`track_resolver.ex:145-152`). Verified by reading the path end-to-end.
Per-title and manual; this campaign exists because it doesn't fix the
systemic mislabel.

## Alternatives considered (and why not)

* **Per-title override only** — works but manual/per-title; doesn't help
  other mislabeled releases.
* **Global `forced_subs: "never"`** — discards legitimate forced subs
  everywhere AND may not beat a `default=1` track without active
  enforcement, so it doesn't even reliably fix this file.

## Completion criteria

* `Track` carries `default`; `LanguageContext.parse_track_list/1`
  populates it, with a unit test.
* The resolver's forced-fallback skips `forced+default` tracks in an
  understood language; genuine `forced`-only tracks still resolve.
  Covered by appended resolver tests (red→green).
* `MpvSession` actively sets `sid` (and optionally `aid`) post-launch to
  match `resolve/5`, with no enforcement loop and no clobbering of user
  selections; OverrideCapture still captures only real user divergence.
* Playing Sample Show S01E01 on a fresh install (default policy, no
  override) results in **no subtitles**; the `track-resolver:` Console
  line reflects the skip. (Manual verification against the real file;
  automated coverage lives in the pure resolver tests.)
* `mix precommit` green; no new flakes.

## Pointers

* `lib/media_centaur/playback/track_resolver.ex` — Track struct
  (`:28-42`), `resolve/5` (`:165`), pick_subtitle_from_policy
  (`:277`), forced_fallback / fill_gaps (`:333-351`), launch-flag
  builders (`:110-152`).
* `lib/media_centaur/playback/language_context.ex` — `build_track/1`
  (`:97-109`), `to_mpv_flags/1` (`:67-79`).
* `lib/media_centaur/playback/mpv_session.ex` — `spawn_mpv/2` flags
  (`:336-366`), `handle_track_list_update/2` (`:511-526`),
  `compute_resolver_choice/1` (`:528-546`), sid event handler (`:494`),
  capture (`:562-583`), `send_mpv_command` usage (`:843-845`).
* `lib/media_centaur/playback/override_capture.ex` — capture diff;
  `subtitles_off_override/2` is the interim-workaround mechanism.
* `lib/media_centaur/playback/language_policy.ex` — built-in defaults
  (`:48-55`).
* Reproduction file:
  `…/Sample.Show.S01-S05…HiQVE/…/Sample.Show.S01E01.1080p.Bluray.x265-HiQVE.mkv`
  (`ffprobe -select_streams s -show_entries stream_disposition=default,forced`
  shows `forced=1 default=1`, 863 subrip cues).
* `docs/playback.md` — playback domain overview.
