---
status: planning
started: 2026-06-17
last_updated: 2026-06-17
---
# Showcase comprehensive coverage

## Goal

The marketing showcase demonstrates the *static* surfaces well (library
grid, detail modals, calendar, history heatmap) but hides the features
that make Media Centaur look sophisticated: movie collections,
multi-season detail, acquisition decision/plan modals, status
drill-ins/incidents, an available update, and per-entity language
memory. Several of those are runtime states the current seeder can't
fabricate. This campaign expands the PD/CC catalog and the
`showcase_mode` machinery so the screenshot tour can show off the
high-impact feature set — every documented capability that photographs
well — without ever depicting non-public-domain media.

## Status

Phase 1 underway. Catalog expansion + PD fixture swaps shipped (5 filler
movies, One Step Beyond → 3 seasons, Detour/His Girl Friday review
fixtures replaced with confirmed-PD titles; 16/16 showcase tests green).
Remaining Phase 1: credits, file-track metadata, language overrides,
status incidents.

## Decisions made

Append-only log.

* `2026-06-17` — **Coverage = high-impact, not exhaustive.** Cover the
  visually compelling gaps (collections, multi-season detail,
  pursuit/plan modals, status drill-ins/incidents, upcoming detail,
  credits/files tabs, language badges). Explicitly **skip** in-app Guide
  `/guide`, console journal source, Settings → Danger Zone, Setup tour,
  and first-run empty states. (owner decision, this session)
* `2026-06-17` — **Full app-side stub work is in scope.** Extend
  `showcase_mode` so update-available and acquisition decision/alternatives
  render; seed incidents/draft-plans/awaiting-decision pursuit as data.
  This is the "pause to update the app" path. (owner decision)
* `2026-06-17` — **Expand the PD/CC catalog** with a real collection +
  a genuinely multi-season PD show + variety, gated by owner
  verification of every new title's PD/CC status. (owner decision)
* `2026-06-17` — **Skip first-run / Setup tour screenshots** — they need
  an empty DB that conflicts with the populated showcase; not worth a
  second snapshot for this pass. (owner decision)
* `2026-06-17` — **Movie collections are best-effort and droppable.**
  Low-interest feature; demo it only if a clean all-PD TMDB collection
  falls out of a quick look, never by building a synthetic grouping.
  Broader steer: be critical about which features earn a screenshot —
  don't pad for completeness. (owner decision)
* `2026-06-17` — **Phase 0 PD/CC list owner-approved.** Multi-season:
  extend *One Step Beyond* (TMDB 10377) to all 3 seasons / 97 eps,
  **excluding stills from the 12 renewed episodes** (Avengers,
  Confession, Eye Witness, Face, Justice, Nightmare, Prisoner, Room
  Upstairs, Signal Received, Sorceror, Stranger, Tiger). Fillers (5):
  Charade 1963 (4808), The General 1926 (961), Sprite Fright 2021
  (891761), Coffee Run 2020 (717986), El Cosmonauta 2013 (86817).
  Collections **skipped** (only lead, Mr. Wong 220448, is consensus-only
  PD). Swap the `Detour (1945)` review-queue fixture for a confirmed PD
  title (Detour is on the could-not-confirm drop list). (owner approval)
* `2026-06-17` — Content policy unchanged: every showcase-visible string
  is PD or CC. The canonical policy lives in `MediaCentaur.Showcase`'s
  moduledoc; `House on Haunted Hill (1959)` stays out despite wide PD
  listing. New candidates are owner-verified before they land.

## Next steps

Test-first throughout (`showcase_test.exs` already asserts seed
invariants; each new seed shape gets a red test first). Phases are
ordered so screenshots come last, against fully-seeded state.

### Phase 0 — PD/CC content research (owner-gated)

The single hard external dependency. No title lands until the owner
confirms its PD/CC status — I propose candidates with sourcing; I do
not assert PD status.

1. **A movie collection — best-effort, skippable.** The app groups by
   TMDB collection, so this needs a TMDB collection whose *every* member
   is PD/CC, which is rare. Quick look only (e.g. the *Mr. Wong*
   Monogram series, *Bulldog Drummond* entries). **If nothing clean
   turns up, skip collections entirely** — it's a low-interest feature
   and not worth contortions. Do **not** build a synthetic movie-series
   grouping just to demo it.
2. **A multi-season PD show.** Strongest candidate: *One Step Beyond*
   (Alcoa Presents) ran three seasons (1959–61) and is already seeded at
   S1 — extend to S1–S3 after confirming all-season PD status. Beverly
   Hillbillies / Petticoat Junction PD status is *episode-specific* — do
   not deep-seed those without per-episode confirmation.
3. **Variety fillers** to round out the grid — more Blender/CC titles or
   vetted renewal-failure films.

Deliverable: an owner-approved title list with TMDB ids, added to the
`Showcase.Catalog` moduledoc as the canonical set.

### Phase 1 — Catalog & seed-data expansion

1. ✅ Collection — **dropped** (no clean all-PD TMDB collection; decision
   above). No `movie_series` seeding added.
2. ✅ Extended One Step Beyond to its 3 real seasons (commit on `main`);
   seeder already summed multi-season counts, so this was a catalog
   `seasons: [1, 2, 3]` change + a red→green multi-season test.
   Also added 5 filler movies (Charade, The General, Sprite Fright,
   Coffee Run, El Cosmonauta) and swapped the Detour/His Girl Friday
   review fixtures for A Farewell to Arms (1932) + Teenagers from Outer
   Space (1959).
3. ✅ Seed **credits** (cast/crew) — `seed_movie!`/`seed_tv_series!` now
   map the already-fetched TMDB `credits`/`aggregate_credits` payload via
   `TMDB.Mapper.extract_cast/extract_crew/extract_creators` (same path as
   `Maintenance.refresh_*_credits`). Self-healing real factual credits;
   populates the detail **Credits** tab.
4. **Files tab — scoped down, subtitle tracks DEFERRED to Phase 3.**
   WatchedFile/FilePresence store only file size; there is NO
   codec/resolution storage (would need a new ffprobe-backed media-info
   subsystem — out of scope, low marketing value). Subtitle tracks
   (`Subtitles.create_track/1`) are the only enrichment available; decide
   whether they're worth seeding when the real Files-tab render is in
   front of us at Phase 3. The language story is already told by the
   override badge, so this is optional polish, not a gap.
5. ✅ Seed **per-entity language/subtitle override** — catalog-driven
   (`track_override` on El Cosmonauta: Spanish audio · English subtitles),
   applied in `seed_movie!` via `Library.upsert_media_track_override/3`.
   Renders the detail "remembered tracks" badge.
6. ✅ Seed **status incidents** — two `:log` incidents via
   `ErrorReports.Store.upsert_log_incident/1` (tmdb rate-limit warning +
   backdrop-404 error), opened-then-bumped for a real first_seen→last_seen
   span; Buckets cache rebuilds from store on the reseed→restart→tour
   boot. Calm board, one-issue-each, no stub.

### Phase 2 — `showcase_mode` stub seams

Mirror the existing Prowlarr/qBittorrent plug-swap pattern.

1. **Update-available:** inject a stub `%Req.Request{}` into
   `SelfUpdate.UpdateChecker.latest_release/1` under `showcase_mode` so
   the Settings → System + Status update card show "update available
   vX" with version history. Reuse the cache path.
2. **Acquisition decision + alternatives:** extend
   `Showcase.Stubs.prowlarr_plug/1` to return alternative releases for
   the decision modal; seed one pursuit in **awaiting-decision** state
   and one **draft plan** (Planning/Ready) so the pursuit modal
   (timeline/unit board) and plan targeting (season picker) render.

### Phase 3 — Tour expansion

Add screenshot stops to `test/e2e/screenshot.tour.js` for the new
surfaces, against the seeded state:

* `library-detail-collection` — movie-series detail
* `library-detail-tv-multiseason` — deep seasons/episodes
* `detail-credits`, `detail-files` — entity modal tabs
* `detail-language-badge` — remembered-tracks badge
* `download-plan-targeting` — season picker modal
* `download-pursuit-modal` — timeline + unit board
* `download-decision` — awaiting-decision alternatives
* `status-drilldown`, `status-incident`, `status-update-available`
* `upcoming-detail` — title detail overlay + status progression

### Phase 4 — Publish

1. `TMDB_API_KEY=… scripts/reseed-showcase` then
   `scripts/regenerate-screenshots` (boots :4003, runs tour, publishes
   web shots → main, 4K → assets repo).
2. Wire new screenshots into `README.md`, `docs-site/index.html`, and
   the wiki pages whose features they illustrate (per CLAUDE.md
   keep-the-wiki-in-sync rule).
3. `mix precommit` green; ship per the usual flow.

## Completion criteria

* Every high-impact feature in the gap table has at least one
  screenshot driven by real seeded/stubbed state (no SVG placeholders —
  the tour's >50% real-image audit passes).
* Multi-season TV detail is demonstrated for the first time. (Movie
  collections only if a clean all-PD TMDB collection exists — otherwise
  dropped, not a gap.)
* Acquisition decision/plan modals, status incident + update-available,
  and language badges render from `showcase_mode` without a live backend.
* Every new showcase-visible string is owner-verified PD/CC.
* `scripts/regenerate-screenshots` publishes the new set to README,
  docs-site, and wiki; `mix precommit` green.
* Skipped-by-decision (Guide, console journal, Danger Zone, Setup tour,
  first-run, mpv playback overlay) are recorded here as deliberate
  no-ops, not gaps.

## Pointers

* Seeder: `lib/media_centaur/showcase.ex`, `lib/media_centaur/showcase/catalog.ex`
* Stubs: `lib/media_centaur/showcase/stubs.ex` (plug-swap under `showcase_mode`)
* Stub seams: `lib/media_centaur/self_update/update_checker.ex` (`latest_release/1`),
  `lib/media_centaur/search/prowlarr.ex`, `lib/media_centaur/downloads/download_client/qbittorrent.ex`
* Incident/status data: `lib/media_centaur/error_reports.ex`, `lib/media_centaur/status.ex`, `lib/media_centaur/diagnostics.ex`
* Tour: `test/e2e/screenshot.tour.js`, `scripts/screenshot-tour`, `scripts/regenerate-screenshots`, `scripts/reseed-showcase`
* Seed invariants test: `test/media_centaur/showcase_test.exs`
* Config override: `defaults/media-centaur-showcase.toml` (:4003)
* Skill: `screenshot-showcase` (full pipeline + failure modes)
