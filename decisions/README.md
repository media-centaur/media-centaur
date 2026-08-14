# Decision Records

This directory contains decision records organized by category. All records use the [MADR 4.0 lean template](https://adr.github.io/madr/).

**Filename convention:** `YYYY-MM-DD-NNN-short-title.md` — sequential numbering is per category.

Gaps in the numbering are deliberate: a record whose decision became fictional,
was fully superseded, or is now enforced by code-as-spec gets retired rather than
left to mislead. Git history is the archive.

> This index is generated from the filenames and first headings. Regenerate it
> when you add or retire a record.

## Architecture (`architecture/`)

System design, data model, integration patterns, and engineering standards. These decisions affect how the application is built, how components interact, and what technical constraints are enforced.

| # | Date | Decision | Status |
|---|------|----------|--------|
| 005 | 2026-02-20 | [Stable entity UUIDs and one-image-per-role storage](architecture/2026-02-20-005-entity-identity-and-image-storage.md) | accepted |
| 006 | 2026-02-20 | [TOML configuration at XDG paths and Req as HTTP client](architecture/2026-02-20-006-toml-config-and-http-client.md) | accepted |
| 008 | 2026-02-20 | [Broadway pipeline as mediator with pure-function stages](architecture/2026-02-20-008-broadway-pipeline-as-mediator.md) | accepted |
| 001 | 2026-02-27 | [Record architecture decisions](architecture/2026-02-27-001-record-architecture-decisions.md) | accepted |
| 010 | 2026-02-27 | [PubSub-driven pipeline input](architecture/2026-02-27-010-pubsub-driven-pipeline-input.md) | accepted |
| 011 | 2026-02-27 | [Mutation broadcast contract](architecture/2026-02-27-011-mutation-broadcast-contract.md) | accepted |
| 013 | 2026-03-01 | [Use MPV --start flag for resume instead of IPC seek](architecture/2026-03-01-013-mpv-resume-via-cli-start-flag.md) | accepted |
| 014 | 2026-03-01 | [Replace real-time playback ticks with save-driven progress updates](architecture/2026-03-01-014-save-driven-progress-updates.md) | accepted |
| 015 | 2026-03-01 | [Two-phase file removal: immediate cleanup for deletions, TTL for unavailability](architecture/2026-03-01-015-two-phase-file-removal.md) | accepted |
| 016 | 2026-03-01 | [Test environment must never read user config or use real filesystem paths](architecture/2026-03-01-016-test-env-filesystem-isolation.md) | accepted |
| 017 | 2026-03-02 | [All LiveViews must update in real time via PubSub](architecture/2026-03-02-017-liveviews-must-be-realtime.md) | accepted |
| 021 | 2026-03-03 | [No magic numbers](architecture/2026-03-03-021-no-magic-numbers.md) | accepted |
| 022 | 2026-03-03 | [OTP supervision requirements](architecture/2026-03-03-022-otp-supervision-requirements.md) | accepted |
| 023 | 2026-03-06 | [Durable process design](architecture/2026-03-06-023-durable-process-design.md) | accepted |
| 026 | 2026-03-07 | [GenServer API encapsulation](architecture/2026-03-07-026-genserver-api-encapsulation.md) | accepted |
| 027 | 2026-03-07 | [Regression tests are append-only](architecture/2026-03-07-027-regression-tests-append-only.md) | accepted |
| 028 | 2026-03-07 | [This app is the sole writer to entity records and image storage](architecture/2026-03-07-028-backend-write-ownership.md) | accepted |
| 029 | 2026-03-26 | [Bounded context decoupling via PubSub](architecture/2026-03-26-029-data-decoupling.md) | accepted |
| 030 | 2026-04-02 | [Extract LiveView behavior into tested pure functions](architecture/2026-04-02-030-liveview-logic-extraction.md) | accepted |
| 031 | 2026-04-05 | [In-memory log buffer and UI-driven filtering for the Guake-style console](architecture/2026-04-05-031-console-log-buffer-and-ui-filtering.md) | accepted |
| 033 | 2026-04-06 | [Data has a TTL — delete over hide](architecture/2026-04-06-033-data-ttl-delete-over-hide.md) | accepted |
| 034 | 2026-04-08 | [Use trackable FKs, not display metadata, for persistence decisions](architecture/2026-04-08-034-trackable-fk-for-persistence-decisions.md) | accepted |
| 035 | 2026-04-15 | [Prowlarr as the single optional integration point for media acquisition](architecture/2026-04-15-035-acquisition-prowlarr-integration.md) | accepted |
| 036 | 2026-04-16 | [Minimum protections for sensitive information](architecture/2026-04-16-036-sensitive-information-minimum-protections.md) | accepted |
| 037 | 2026-04-16 | [Acquisition integration scope — Prowlarr-first, no runtime introspection](architecture/2026-04-16-037-acquisition-integration-scope.md) | accepted |
| 038 | 2026-04-30 | [LiveViews never couple to each other — extract shared concerns](architecture/2026-04-30-038-liveview-decoupling.md) | accepted |
| 039 | 2026-05-07 | [Acquisition pursuits — a goal-level aggregate over grab attempts](architecture/2026-05-07-039-acquisition-pursuits.md) | accepted |
| 040 | 2026-05-09 | [Data migrations — a parallel migrator for one-shot row backfills](architecture/2026-05-09-040-data-migrations.md) | accepted |
| 041 | 2026-05-10 | [In-memory projections: ETS view models behind a Cache.Worker, brief eventual consistency](architecture/2026-05-10-041-in-memory-projection-architecture.md) | accepted |
| 042 | 2026-05-10 | [Multi-session campaigns: tracked markdown per long-running initiative](architecture/2026-05-10-042-multi-session-campaigns.md) | accepted |
| 043 | 2026-05-10 | [Acquisition split — extract Downloads and Search as sibling contexts](architecture/2026-05-10-043-acquisition-split.md) | accepted |
| 044 | 2026-05-14 | [No blocking external I/O in LiveView mount, handle_event, or handle_info](architecture/2026-05-14-044-no-blocking-io-in-liveview-handlers.md) | accepted |
| 045 | 2026-05-17 | [File-presence ownership belongs to Library; Watcher is a thin observer](architecture/2026-05-17-045-file-presence-ownership.md) | accepted |
| 046 | 2026-05-17 | [Cascading deletes are an application concern, not a database concern](architecture/2026-05-17-046-app-owned-cascading-deletes.md) | accepted |
| 047 | 2026-05-17 | [PlayableItem is the canonical leaf of the Library schema](architecture/2026-05-17-047-playable-item-reification.md) | accepted |
| 048 | 2026-05-22 | [Language codes are canonicalized to ISO 639-2/T at the boundary; one comparison helper](architecture/2026-05-22-048-canonical-language-codes-at-boundary.md) | accepted |
| 049 | 2026-05-22 | [Testing principles: a well-managed, high-performance suite](architecture/2026-05-22-049-testing-principles.md) | accepted |
| 050 | 2026-05-23 | [A single presentable resolver decides movie-vs-collection for every surface](architecture/2026-05-23-050-presentable-resolver.md) | accepted |
| 051 | 2026-05-29 | [Desktop LiveViews load on first paint; never flash fabricated values](architecture/2026-05-29-051-desktop-first-paint-loads-synchronously.md) | accepted |
| 052 | 2026-05-31 | [The download stack owns its control plane; Media Centaur stays thin](architecture/2026-05-31-052-download-stack-control-plane.md) | accepted |
| 053 | 2026-06-06 | [Input system reconciles only the focus it owns; unmanaged surfaces cede](architecture/2026-06-06-053-focus-ownership-boundary.md) | accepted |
| 054 | 2026-06-08 | [External-dependency faults are subsystem health, not log incidents](architecture/2026-06-08-054-external-dependency-faults-are-subsystem-health.md) | accepted |
| 055 | 2026-06-09 | [Composite pursuits — units carry the attempt thread](architecture/2026-06-09-055-composite-pursuits.md) | accepted |
| 056 | 2026-06-10 | [Release-tracking wants — tracks emit plan-based pursuits](architecture/2026-06-10-056-release-tracking-wants.md) | accepted |
| 057 | 2026-06-14 | [Derived data is recomputable, never frozen](architecture/2026-06-14-057-derived-data-is-recomputable.md) | accepted |
| 058 | 2026-06-17 | [Canonical episode identity — one TMDB-anchored vocabulary, ambiguity only at the edges](architecture/2026-06-17-058-canonical-episode-identity.md) | superseded |
| 059 | 2026-07-12 | [Versions split into cuts (PlayableItem) and renditions (WatchedFile)](architecture/2026-07-12-059-cuts-vs-renditions.md) | accepted |
| 060 | 2026-08-06 | [Events publish through a per-topic `Events` chokepoint, over a `Topics` transport](architecture/2026-08-06-060-event-publication-idiom.md) | accepted |

## User Interface (`user-interface/`)

Visual conventions, component behavior, layout patterns, and interaction design. These decisions ensure consistency across all pages and prevent recurring style debates. Referenced in code and docs as **UIDR-NNN**.

| # | Date | Decision | Status |
|---|------|----------|--------|
| 001 | 2026-03-03 | [File path display convention](user-interface/2026-03-03-001-file-path-display-convention.md) | accepted |
| 002 | 2026-03-03 | [Badge style convention](user-interface/2026-03-03-002-badge-style-convention.md) | accepted |
| 003 | 2026-03-03 | [Button style convention](user-interface/2026-03-03-003-button-style-convention.md) | accepted |
| 004 | 2026-03-05 | [Human-readable durations](user-interface/2026-03-05-004-human-readable-durations.md) | accepted |
| 005 | 2026-03-06 | [Playback card hierarchy](user-interface/2026-03-06-005-playback-card-hierarchy.md) | accepted |
| 006 | 2026-03-09 | [Library two-zone layout with zone-dependent detail shells](user-interface/2026-03-09-006-library-zone-architecture.md) | accepted |
| 007 | 2026-03-09 | [Left wall enters sidebar](user-interface/2026-03-09-007-left-wall-enters-sidebar.md) | accepted |
| 008 | 2026-03-15 | [Flex rows with mixed-size text use baseline alignment](user-interface/2026-03-15-008-flex-row-text-baseline-alignment.md) | accepted |
| 009 | 2026-04-06 | [Modal panels must set explicit text color](user-interface/2026-04-06-009-modal-panel-color-inheritance.md) | accepted |
| 010 | 2026-04-27 | [Page redistribution: Watch / System sidebar groups + dedicated Home, Library, Upcoming, History](user-interface/2026-04-27-010-page-redistribution.md) |  |
| 011 | 2026-05-12 | [Text and logos over imagery use shared `.text-on-image*` utilities](user-interface/2026-05-12-011-text-on-imagery.md) | accepted |
| 012 | 2026-05-20 | [Desktop-app rendering defaults — eager, sync, stable, immutable](user-interface/2026-05-20-012-desktop-app-rendering-defaults.md) | accepted |
| 013 | 2026-06-08 | [Modals declare an ephemeral or persistent dismissal mode through one seam](user-interface/2026-06-08-013-modal-dismissal-modes.md) | accepted |
| 014 | 2026-06-10 | [Media-search front door — omnibox, coverage language, and imagery discipline](user-interface/2026-06-10-014-media-search-front-door.md) | accepted |
| 015 | 2026-07-11 | [Merge Upcoming and Downloads into one "Incoming" page](user-interface/2026-07-11-015-incoming-page.md) | accepted |
| 016 | 2026-08-01 | [Needs attention — one problem-only section for acquisition capability faults](user-interface/2026-08-01-016-needs-attention-section.md) | accepted |
| 017 | 2026-08-03 | [Coming Up depth is the house modal, and unscheduled titles are rows](user-interface/2026-08-03-017-coming-up-title-depth.md) | accepted |
| 018 | 2026-08-07 | [Focus cursor and scroll behaviour](user-interface/2026-08-07-018-focus-cursor-and-scroll.md) | accepted |
| 019 | 2026-08-07 | [The detail modal navigates as two regions, and BACK peels containment](user-interface/2026-08-07-019-detail-modal-two-regions.md) | accepted |
| 020 | 2026-08-10 | [Cursor treatment tiers — ring by default, soft fill where the ring collides](user-interface/2026-08-10-020-cursor-treatment-tiers.md) | accepted |
| 021 | 2026-08-11 | [Cinematic modal frame for TMDB-grounded modals; artwork promotion ladder](user-interface/2026-08-11-021-cinematic-frame-artwork-ladder.md) | accepted |
| 022 | 2026-08-11 | [Gap banner states the diagnosed world, with its evidence — never a bare "not available"](user-interface/2026-08-11-022-gap-banner-adaptive-verdict.md) | accepted |
| 023 | 2026-08-13 | [Movie-first collection modal with a poster-rail picker](user-interface/2026-08-13-023-movie-first-collection-modal.md) | accepted |
| 024 | 2026-08-13 | [Subject progress lives in the hero hairline, from one shared component](user-interface/2026-08-13-024-subject-progress-hero-hairline.md) | accepted |
| 025 | 2026-08-14 | [Collections are filing, not content — activity surfaces speak in movies](user-interface/2026-08-14-025-collections-are-filing-not-content.md) | accepted |
