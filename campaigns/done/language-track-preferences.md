---
status: shipped
started: 2026-05-21
last_updated: 2026-05-22
---
# Audio & Subtitle Language Preferences

## Goal

Pick the right audio and subtitle tracks automatically when playback
starts, so the user never re-picks "Japanese audio + English subs" at
the start of every episode. A configurable per-install **policy**
(original audio when possible; subtitles only when the audio isn't a
language you understand) handles the common case; **per-entity
overrides** captured when the user changes tracks mid-playback handle
the exceptions and apply on the next play of the same series/movie.
Expressive enough that other installs (Spanish-speakers, deaf users,
dub-preferrers, language learners) can configure it for themselves.

## Status

**Complete.** Policy configurable in Settings → Playback, applied at
mpv launch; overrides capture mid-playback and apply next time;
entity-detail **Remembered tracks** badge + **Reset to default** shipped
in the *More info* panel, with live refresh on `TrackOverrideChanged`.
Round-trip covered by an integration test
(`track_override_round_trip_test.exs`) plus the manual real-playback
procedure below. Wiki (Playback + Settings-Reference) and CHANGELOG
updated. Closing items bucketed under *Completion criteria*.

## Decisions made

* `2026-05-21` — Feature shape: configurable policy + per-entity
  overrides, not "remember whatever I clicked". Override stored as
  language descriptors (not raw track indices) so it survives re-rips.
  Polymorphic `Library.MediaTrackOverride` (owner_type ∈ {tv_series,
  movie}). Plan: `~/.claude/plans/let-s-think-about-a-elegant-meteor.md`.
* `2026-05-21` — Capture only when the user's selection diverges from
  the resolver's choice; overrides stick until explicitly reset (no
  expiry). Captured via ~3s debounce on aid/sid changes.
* `2026-05-21` — Policy lives in the DB `settings_entries` table under
  key `playback.tracks` (not TOML — TOML is restart-required bootstrap
  only). Defaults in code via `LanguagePolicy` builtin map.
* `2026-05-21` — mpv launch strategy: lean on mpv's own `--alang` /
  `--slang` priority lists + `--subs-with-matching-audio` rather than
  post-launch track-switching. "Ship simplest, measure later" for the
  edge cases (forced/SDH/override pinning). (commit `c00d7014`)
* `2026-05-22` — `--subs-with-matching-audio` valid values are
  `yes|no|forced` (NOT "exclusive"). Default policy (fill_gaps) maps to
  `forced`, which gives native Greedo-scene behavior. (commit `1b62d497`)
* `2026-05-22` — **ADR-048**: canonicalize all language codes to
  3-letter ISO 639-2/T at the boundary (parse_track_list, original_
  language, understood_languages) + one comparison helper
  (`TrackResolver.matches_lang?/2`). Root-causes the whole class of
  TMDB-2-letter vs mpv-3-letter mismatch bugs.
  ([ADR-048](../decisions/architecture/2026-05-22-048-canonical-language-codes-at-boundary.md),
  commit `bab02d25`)
* `2026-05-22` — Settings form: languages as comma-separated text;
  audio preference as a 3-way preset select (original-first /
  understood-first / no-preference); subtitle controls as native
  selects. Parse logic extracted to `LanguagePolicy.from_form/1`.
  (commit `29608ad1`)
* `2026-05-22` — `Co-Authored-By: Claude` trailers stripped from repo
  history and never to be re-added (user directive; saved to
  auto-memory).

### Bugs found via real-playback testing (all fixed + regression-tested)

* ISO 639 mismatch broke "original audio" for every non-English entity
  (`"ja"` ≠ `"jpn"`). (commit `d910e11a`)
* Subtitle picker missed the same normalization, so foreign-audio films
  showed no subs. (commit `bd7be78b`)
* Invalid `--subs-with-matching-audio=exclusive` → mpv fatal-error at
  launch. (commit `1b62d497`)
* Resolver baseline computed on an audio-only track-list (incremental
  demux) → now recomputes on every track-list update. (commit `ca45a3bc`)

## How it shipped (final session)

* **Decorator seam over the two construction paths.** Both modal-entry
  builders funnel through `DetailItem.to_entity_map/1` (pure, no DB), so
  the override fetch lives in one context decorator
  `Library.put_track_override/1`, applied after `to_entity_map` in
  `build_modal_entry/3` (movies + every refresh) **and**
  `SeriesDetail.compose_from_detail/2` (TV-series initial open). Chosen
  over the originally-traced "merge in `refresh_selected_entry`" because
  that only covered refresh, not initial open. DB reads stay in the
  context.
* **Badge** = `MoreInfoPanel.track_override_summary/1` (pure, unit-tested)
  + a private `track_override_badge` render gated on
  `entity[:track_override]`, between the meta block and external links.
  Languages shown as raw ISO codes (`jpn audio · eng subtitles`) to
  match the *Language* meta line directly above — friendly names were
  rejected as inconsistent (would need to upgrade the meta line too;
  deferred). Three storybook variations (audio+subs, subs-off, forced).
* **Reset** = macro-injected `handle_event("reset_track_override")` →
  `EntityModal.reset_track_override/1` (clear + surgical
  `put_entry_track_override/2` merge — no reload, so a `%SeriesDetail{}`
  entry keeps its typed seasons).
* **Live refresh** = `handle_modal_pubsub({:track_override_changed,
  %{owner_type, owner_id}}, …)` matched structurally (the Events struct
  isn't exported across the Playback boundary), reusing the same
  surgical merge.

### Manual real-playback validation (the one seam tests can't cover)

`MpvSession` is a thin mpv wrapper — not worth mocking (per
`automated-testing`), so the capture→apply wiring is confirmed live:

1. Start the dev server and play a foreign-audio film.
2. Press `#` (cycle audio) / `j` (cycle subs) in mpv to a selection that
   differs from what launched.
3. Wait ~4s (debounce) for the `captured track override` log line
   (Console drawer, `` ` ``, or `~/scripts/mc-rpc`).
4. Inspect: `~/scripts/mc-rpc 'MediaCentaur.Library.get_media_track_override(:movie, "<id>") |> inspect()'`.
5. Quit mpv, replay the same entity → confirm it launches with the
   captured tracks (`--alang`/`--slang` reflect the override).
6. Open the entity's **More info** → the **Remembered tracks** badge
   shows the captured languages; **Reset to default** clears it and the
   next play returns to policy.

## Deferred to v2+ (raise as their own initiatives)

From the brainstorm — valid, explicitly deferred (see plan doc):
per-season overrides; audio descriptions; secondary/dual subtitles;
pre-indexed audio tracks at import; `:movie_series` collection
overrides; multi-viewer profiles; forced-subs language ≠ audio nuance.

## Completion criteria

* Policy configurable in Settings UI — **done**.
* Tracks auto-selected at playback per policy — **done**.
* Mid-playback track changes captured + applied next play — **done**
  (round-trip integration test + manual procedure above).
* Override visible + resettable from the entity detail UI — **done**
  (Remembered tracks badge + Reset, live-refreshing).
* Wiki + CHANGELOG updated for the user-visible surface — **done**.

Deferred follow-up (re-home as its own concern, not blocking): friendly
language names in the detail UI (`Japanese` vs `jpn`) — would also
upgrade the meta-block *Language* line for consistency.

## Pointers

* Plan: `~/.claude/plans/let-s-think-about-a-elegant-meteor.md`
* ADR: [048 canonical language codes](../decisions/architecture/2026-05-22-048-canonical-language-codes-at-boundary.md)
* Modules: `MediaCentaur.Playback.{LanguagePolicy, TrackResolver,
  OverrideCapture, LanguageContext, Iso639}`,
  `MediaCentaur.Library.MediaTrackOverride`,
  `MediaCentaur.Playback.MpvSession` (capture wiring),
  `MediaCentaurWeb.Live.SettingsLive` (playback section)
* Auto-memory: `project-language-prefs-v1.md` (v2 follow-ups),
  `feedback-no-co-authored-by-claude.md`
