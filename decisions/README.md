# Decision Records

Decision records organized by category, in the [MADR 4.0 lean template](https://adr.github.io/madr/).

**Filename convention:** `YYYY-MM-DD-NNN-short-title.md` — sequential numbering is per category.

Gaps in the numbering are deliberate: a record whose decision became fictional,
was fully superseded, or is now enforced by code-as-spec gets retired rather than
left to mislead. Git history is the archive. A record captures a point in time;
verify any claim about current behaviour against the code before relying on it,
and correct a wrong record in place with a dated amendment.

> This index is generated from the filenames, frontmatter and first headings
> (`scripts/gen-decisions-index`). Regenerate it when you add, amend or retire a record.

## Architecture (`architecture/`)

System design, data model, integration patterns, and engineering standards. Cited as **ADR-NNN**.

| # | Date | Decision | Status |
|---|------|----------|--------|
| 016 | 2026-03-01 | [Test environment must never read user config or use real filesystem paths](architecture/2026-03-01-016-test-env-filesystem-isolation.md) | accepted |
| 022 | 2026-03-03 | [OTP supervision requirements](architecture/2026-03-03-022-otp-supervision-requirements.md) | accepted |
| 023 | 2026-03-06 | [Durable process design](architecture/2026-03-06-023-durable-process-design.md) | accepted, amended 2026-09-12 |
| 026 | 2026-03-07 | [GenServer API encapsulation](architecture/2026-03-07-026-genserver-api-encapsulation.md) | accepted |
| 027 | 2026-03-07 | [Regression tests are append-only](architecture/2026-03-07-027-regression-tests-append-only.md) | accepted |
| 029 | 2026-03-26 | [Bounded context decoupling via PubSub](architecture/2026-03-26-029-data-decoupling.md) | accepted |
| 030 | 2026-04-02 | [Extract LiveView behavior into tested pure functions](architecture/2026-04-02-030-liveview-logic-extraction.md) | accepted |
| 033 | 2026-04-06 | [Data has a TTL — delete over hide](architecture/2026-04-06-033-data-ttl-delete-over-hide.md) | accepted |
| 036 | 2026-04-16 | [Minimum protections for sensitive information](architecture/2026-04-16-036-sensitive-information-minimum-protections.md) | accepted |
| 037 | 2026-04-16 | [Acquisition integration scope — Prowlarr-first, no runtime introspection](architecture/2026-04-16-037-acquisition-integration-scope.md) | accepted, amended 2026-09-14 |
| 038 | 2026-04-30 | [LiveViews never couple to each other — extract shared concerns](architecture/2026-04-30-038-liveview-decoupling.md) | accepted |
| 039 | 2026-05-07 | [Acquisition pursuits — a goal-level aggregate over grab attempts](architecture/2026-05-07-039-acquisition-pursuits.md) | accepted |
| 040 | 2026-05-09 | [Data migrations — a parallel migrator for one-shot row backfills](architecture/2026-05-09-040-data-migrations.md) | accepted |
| 041 | 2026-05-10 | [In-memory projections: ETS view models behind a Cache.Worker, brief eventual consistency](architecture/2026-05-10-041-in-memory-projection-architecture.md) | accepted |
| 042 | 2026-05-10 | [Multi-session campaigns: tracked markdown per long-running initiative](architecture/2026-05-10-042-multi-session-campaigns.md) | accepted, amended 2026-08-05 |
| 044 | 2026-05-14 | [No blocking external I/O in LiveView mount, handle_event, or handle_info](architecture/2026-05-14-044-no-blocking-io-in-liveview-handlers.md) | accepted, amended 2026-05-22 |
| 045 | 2026-05-17 | [File-presence ownership belongs to Library; Watcher is a thin observer](architecture/2026-05-17-045-file-presence-ownership.md) | accepted |
| 046 | 2026-05-17 | [Cascading deletes are an application concern, not a database concern](architecture/2026-05-17-046-app-owned-cascading-deletes.md) | accepted |
| 047 | 2026-05-17 | [PlayableItem is the canonical leaf of the Library schema](architecture/2026-05-17-047-playable-item-reification.md) | accepted |
| 049 | 2026-05-22 | [Testing principles: a well-managed, high-performance suite](architecture/2026-05-22-049-testing-principles.md) | accepted, amended 2026-09-08 |
| 050 | 2026-05-23 | [A single presentable resolver decides movie-vs-collection for every surface](architecture/2026-05-23-050-presentable-resolver.md) | accepted |
| 051 | 2026-05-29 | [Desktop LiveViews load on first paint; never flash fabricated values](architecture/2026-05-29-051-desktop-first-paint-loads-synchronously.md) | accepted |
| 052 | 2026-05-31 | [The download stack owns its control plane; Media Centaur stays thin](architecture/2026-05-31-052-download-stack-control-plane.md) | accepted |
| 053 | 2026-06-06 | [Input system reconciles only the focus it owns; unmanaged surfaces cede](architecture/2026-06-06-053-focus-ownership-boundary.md) | accepted |
| 054 | 2026-06-08 | [External-dependency faults are subsystem health, not log incidents](architecture/2026-06-08-054-external-dependency-faults-are-subsystem-health.md) | accepted |
| 055 | 2026-06-09 | [Composite pursuits — units carry the attempt thread](architecture/2026-06-09-055-composite-pursuits.md) | accepted |
| 056 | 2026-06-10 | [Release-tracking wants — tracks emit plan-based pursuits](architecture/2026-06-10-056-release-tracking-wants.md) | accepted, amended 2026-09-13 |
| 057 | 2026-06-14 | [Derived data is recomputable, never frozen](architecture/2026-06-14-057-derived-data-is-recomputable.md) | accepted |
| 058 | 2026-06-17 | [Canonical episode identity — one TMDB-anchored vocabulary, ambiguity only at the edges](architecture/2026-06-17-058-canonical-episode-identity.md) | accepted, amended 2026-06-17 |
| 059 | 2026-07-12 | [Versions split into cuts (PlayableItem) and renditions (WatchedFile)](architecture/2026-07-12-059-cuts-vs-renditions.md) | accepted |
| 060 | 2026-08-06 | [Events publish through a per-topic `Events` chokepoint, over a `Topics` transport](architecture/2026-08-06-060-event-publication-idiom.md) | accepted |
| 061 | 2026-08-16 | [Release quality: gates bound, ladders order, a profile chooses — size is never a signal](architecture/2026-08-16-061-source-quality-ladder.md) | accepted, amended 2026-09-13 |
| 062 | 2026-08-18 | [Episode auto-advance rides the mpv playlist inside one session](architecture/2026-08-18-062-playlist-based-episode-advance.md) | accepted, amended 2026-08-19 |
| 063 | 2026-08-31 | [Plan diagnosis model: per-unit outcomes, per-title quality bounds, status-observed cancellation](architecture/2026-08-31-063-plan-diagnosis-model.md) | accepted, amended 2026-09-07 |
| 064 | 2026-09-04 | [Outbound HTTP goes through one seam: upstream tagging, instrumentation, and an origin-freshness cache](architecture/2026-09-04-064-outbound-http-seam.md) | accepted |
| 066 | 2026-09-07 | [One ladder per title: an authored rung, and machinery derived from it](architecture/2026-09-07-066-one-ladder-per-title.md) | accepted, amended 2026-09-09 |
| 067 | 2026-09-11 | [A listing replaces tracking as the shared act about wanting a title](architecture/2026-09-11-067-listing-replaces-tracking-on-the-wire.md) | accepted |
| 068 | 2026-09-12 | [A review replaces the recommendation as the shared opinion about a title](architecture/2026-09-12-068-review-replaces-recommendation-on-the-wire.md) | accepted |
| 069 | 2026-09-17 | [No Elixir dead-code gate; JS keeps one](architecture/2026-09-17-069-no-elixir-dead-code-gate.md) | accepted |
| 070 | 2026-09-19 | [Durable observational time series live outside the main database](architecture/2026-09-19-070-time-series-outside-the-database.md) | accepted |
| 071 | 2026-09-20 | [TMDB knowledge is one record per title, asked only when due](architecture/2026-09-20-071-tmdb-store-one-record-per-title.md) | accepted |

## User Interface (`user-interface/`)

Visual conventions, component behavior, layout patterns, and interaction design. Cited as **UIDR-NNN**.

| # | Date | Decision | Status |
|---|------|----------|--------|
| 010 | 2026-04-27 | [Page redistribution: Watch / System sidebar groups + dedicated Home, Library, Upcoming, History](user-interface/2026-04-27-010-page-redistribution.md) | accepted |
| 011 | 2026-05-12 | [Text and logos over imagery use shared `.text-on-image*` utilities](user-interface/2026-05-12-011-text-on-imagery.md) | accepted |
| 012 | 2026-05-20 | [Desktop-app rendering defaults — eager, sync, stable, immutable](user-interface/2026-05-20-012-desktop-app-rendering-defaults.md) | accepted, amended 2026-08-07 |
| 013 | 2026-06-08 | [Modals declare an ephemeral or persistent dismissal mode through one seam](user-interface/2026-06-08-013-modal-dismissal-modes.md) | accepted |
| 014 | 2026-06-10 | [Media-search front door — omnibox, coverage language, and imagery discipline](user-interface/2026-06-10-014-media-search-front-door.md) | accepted |
| 015 | 2026-07-11 | [Merge Upcoming and Downloads into one "Incoming" page](user-interface/2026-07-11-015-incoming-page.md) | accepted, amended 2026-08-02 |
| 016 | 2026-08-01 | [Needs attention — one problem-only section for acquisition capability faults](user-interface/2026-08-01-016-needs-attention-section.md) | accepted, amended 2026-08-02 |
| 018 | 2026-08-07 | [Focus cursor and scroll behaviour](user-interface/2026-08-07-018-focus-cursor-and-scroll.md) | accepted |
| 019 | 2026-08-07 | [The detail modal navigates as two regions, and BACK peels containment](user-interface/2026-08-07-019-detail-modal-two-regions.md) | accepted, amended 2026-09-14 |
| 020 | 2026-08-10 | [Cursor treatment tiers — ring by default, soft fill where the ring collides](user-interface/2026-08-10-020-cursor-treatment-tiers.md) | accepted |
| 021 | 2026-08-11 | [Cinematic modal frame for TMDB-grounded modals; artwork promotion ladder](user-interface/2026-08-11-021-cinematic-frame-artwork-ladder.md) | accepted |
| 022 | 2026-08-11 | [Gap banner states the diagnosed world, with its evidence — never a bare "not available"](user-interface/2026-08-11-022-gap-banner-adaptive-verdict.md) | accepted, amended 2026-09-14 |
| 023 | 2026-08-13 | [Movie-first collection modal with a poster-rail picker](user-interface/2026-08-13-023-movie-first-collection-modal.md) | accepted, amended 2026-09-14 |
| 024 | 2026-08-13 | [Subject progress lives in the hero hairline, from one shared component](user-interface/2026-08-13-024-subject-progress-hero-hairline.md) | accepted |
| 025 | 2026-08-14 | [Collections are filing, not content — activity surfaces speak in movies](user-interface/2026-08-14-025-collections-are-filing-not-content.md) | accepted |
| 026 | 2026-08-14 | [Re-selecting the current page in the main nav scrolls to the top](user-interface/2026-08-14-026-nav-reselect-scrolls-to-top.md) | accepted |
| 027 | 2026-08-17 | [Play affordances play in place — the modal is never a waystation](user-interface/2026-08-17-027-play-in-place.md) | accepted |
| 028 | 2026-08-19 | [Back enters the main menu; left stays in the page](user-interface/2026-08-19-028-back-enters-main-menu.md) | accepted |
| 029 | 2026-08-31 | [The plan board narrates a diagnosis, not a procedure](user-interface/2026-08-31-029-plan-board-diagnosis.md) | accepted |
| 030 | 2026-09-05 | [Follow-up pill and condition dot — the sidebar's two badge idioms](user-interface/2026-09-05-030-follow-up-pill-and-condition-dot.md) | accepted |
| 032 | 2026-09-06 | [Page hero backdrops paint from a decoded-bitmap cache](user-interface/2026-09-06-032-page-hero-backdrops-paint-from-a-decoded-bitmap-cache.md) | accepted, amended 2026-09-07 |
| 033 | 2026-09-07 | [Home is the only page that carries artwork](user-interface/2026-09-07-033-home-is-the-only-page-with-artwork.md) | accepted |
| 034 | 2026-09-07 | [An empty surface states the diagnosed reason it is empty, and the one action that changes it](user-interface/2026-09-07-034-empty-surfaces-state-a-diagnosed-reason.md) | accepted |
| 035 | 2026-09-07 | [Two title surfaces, split by whether the title has files](user-interface/2026-09-07-035-two-title-surfaces.md) | accepted, amended 2026-09-14 |
| 036 | 2026-09-07 | [One control per title, because there is one ladder](user-interface/2026-09-07-036-one-control-per-title.md) | accepted, amended 2026-09-14 |
| 037 | 2026-09-08 | [Friend provenance is the pennant, on every title surface](user-interface/2026-09-08-037-friend-provenance-is-the-pennant.md) | accepted, amended 2026-09-12 |
| 038 | 2026-09-11 | [The Feed is friends' actions, one entry each](user-interface/2026-09-11-038-the-feed-is-friends-actions-one-entry-each.md) | accepted, amended 2026-09-12 |
| 039 | 2026-09-11 | [Add to watchlist first, then the tracking controls](user-interface/2026-09-11-039-add-to-watchlist-then-the-tracking-controls.md) | accepted, amended 2026-09-12 |
| 040 | 2026-09-12 | [A review is an opinion of any valence: the sentiment shows when given, nothing when none](user-interface/2026-09-12-040-a-review-is-an-opinion-of-any-valence.md) | accepted |
| 041 | 2026-09-13 | [Settings cards are readouts with actions, from one kit](user-interface/2026-09-13-041-settings-cards-are-readouts-with-actions.md) | accepted |
| 042 | 2026-09-14 | [Tracking is the bookmark and two switches over one record](user-interface/2026-09-14-042-tracking-is-the-bookmark-and-two-switches.md) | accepted |
| 043 | 2026-09-14 | [One title detail, composed by facts](user-interface/2026-09-14-043-one-title-detail-composed-by-facts.md) | accepted |
| 044 | 2026-09-20 | [One control to ask TMDB again: Refresh from TMDB](user-interface/2026-09-20-044-refresh-from-tmdb.md) | accepted |
