---
status: active
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

Backend + Settings UI shipped and on `main`. Feature works end-to-end:
policy is configurable in Settings → Playback, applied at mpv launch,
overrides capture on playback and apply next time. **Remaining:** the
entity-detail override badge + reset (task #7, fully traced below) and
live validation of the override-capture round-trip in real playback.

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

## Next steps

1. **Validate override-capture round-trip in real playback** (cheap, do
   first): play a foreign film (e.g. Pulse, movie id
   `9f9e75f0-40f3-49bc-a502-895a7ced52d8`), press `#` to switch audio
   mid-playback, wait ~4s for the `captured track override` log line,
   quit, replay — confirm it launches with the captured track. Inspect
   via `Library.get_media_track_override(:movie, id)`.
2. **Task #7 — entity-detail override badge + reset.** Traced plan:
   * Entity map (`Library.Views.DetailItem.to_entity_map/1`) already
     carries `:id` + `:type` → owner_type = type when ∈ {movie,
     tv_series}, owner_id = id.
   * `EntityModal.refresh_selected_entry/1`
     (lib/media_centarr_web/live/entity_modal.ex:602): after
     `put_resume_target`, merge `track_override` into `entry.entity`
     via `Library.get_media_track_override/2` (movie/tv_series only).
   * Render "Tracks: jpn audio · eng subs · [Reset to default]" in
     `MoreInfoPanel` (lib/media_centarr_web/components/detail/more_info_panel.ex)
     gated on `entity[:track_override]` — **add a storybook variation**
     (MC0009 tax).
   * Add `reset_track_override` handler to EntityModal injected events →
     `Library.clear_media_track_override/2` + refresh.
   * Optionally subscribe to `TrackOverrideChanged` on `playback:events`
     for live refresh.
   * Tests: EntityModal reset flow + render assertion.
3. **Wiki update** — document the Settings → Playback → Language &
   Subtitles controls in the user-facing wiki (Settings-Reference.md).
4. **CHANGELOG entry** for the next release once task #7 lands.

## Deferred to v2+ (raise once v1 fully lands)

From the brainstorm — valid, explicitly deferred (see plan doc):
per-season overrides; audio descriptions; secondary/dual subtitles;
pre-indexed audio tracks at import; `:movie_series` collection
overrides; multi-viewer profiles; forced-subs language ≠ audio nuance.

## Completion criteria

* Policy configurable in Settings UI — **done**.
* Tracks auto-selected at playback per policy — **done** (validate live).
* Mid-playback track changes captured + applied next play — **done**
  (validate live, step 1).
* Override visible + resettable from the entity detail UI — **task #7**.
* Wiki + CHANGELOG updated for the user-visible surface.

## Pointers

* Plan: `~/.claude/plans/let-s-think-about-a-elegant-meteor.md`
* ADR: [048 canonical language codes](../decisions/architecture/2026-05-22-048-canonical-language-codes-at-boundary.md)
* Modules: `MediaCentarr.Playback.{LanguagePolicy, TrackResolver,
  OverrideCapture, LanguageContext, Iso639}`,
  `MediaCentarr.Library.MediaTrackOverride`,
  `MediaCentarr.Playback.MpvSession` (capture wiring),
  `MediaCentarrWeb.Live.SettingsLive` (playback section)
* Auto-memory: `project-language-prefs-v1.md` (v2 follow-ups),
  `feedback-no-co-authored-by-claude.md`
