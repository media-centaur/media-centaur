# Incoming Page — Implementation Plan

> Executable plan for `docs/plans/2026-07-11-incoming-page-design.md` (DDR-015).
> Visual reference: `mockups/incoming-page/` (local, gitignored). Read the design plan
> first for the what; this document is the how. Test-first per the `automated-testing`
> skill; component changes bundle their story updates in the same change (MC0009).

## Shape of the change

`AcquisitionLive` (2,188 lines) holds the machinery that must survive intact — plan flow,
pursuit modal, optimistic queue reconciliation, `SearchSession`. `UpcomingLive` (552
lines) is thin. Therefore: **evolve `AcquisitionLive` into `IncomingLive`** (`git mv`, keep
history) and port the forecast concerns into it, rather than building a third LiveView
and porting both. `UpcomingLive` is deleted. The shelf and ledger are new pure
presentations over *existing* view-models (`UpcomingFeed`, `PursuitRow` VMs) — no new
data paths.

Key mount change: the Prowlarr gate stops being a redirect (`acquisition_live.ex:132,187`)
and becomes conditional subscriptions + forecast-only render. `handle_info(:capabilities_changed)`
rebuilds instead of navigating away.

## Coherence pass (unify_design)

Core idea: **every section is a projection of the same "incoming item" story at a
different zoom level.** Greenfield diff against the planned code shape produced four
dispositions (all folded into the steps below):

1. **One composition point** — a pure `IncomingLive.View` builder produces one struct with
   named sections (`shelf`, `in_flight`, `ledger`, `drafts`) composed from the existing
   view-models; the LiveView holds one view assign, not two pages' worth of assign soup.
   The underlying VMs (`UpcomingFeed`, `PursuitWithDownload`, history rows) are not merged —
   they aren't duplicates. Deliberate exception: render-time queue pairing
   (`QueueMatcher.match/2` in `render/1`) stays — documented perf seam, not incoherence.
2. **One pill implementation** — a shared `status_pill` component with a typed status
   union; forecast statuses and pursuit statuses both map into it. Domain VMs stay
   separate (merging them would be speculative abstraction).
3. **One first-paint rule (desktop app)** — everything DB-backed builds on the first
   render, both disconnected and connected (UpcomingLive's `ensure_loaded` pattern
   generalizes; AcquisitionLive's deferred pursuit/history load is retired). Only the
   external qBittorrent queue arrives progressively via PubSub. ADR-012/MC0016 desktop
   defaults are acceptance criteria: `loading="eager" decoding="sync"` on all art, stable
   iterator DOM ids, no entrance animations (the ledger mask-fade is static treatment).
4. **No orphan namespace** — new page-surface components live in `components/incoming/`;
   domain-object components stay domain-named (`acquisition/`); surviving
   `components/upcoming/` modules (MiniMonth, MonthGrid, TitleDetail, Present) rename to
   `components/release_tracking/` in the same sprint, stories moving with them.

Coherence cost: ~a day (View builder + tests, status pill + story, namespace renames).
Accepted over the cheap path (assign absorption + per-section badges), which drifts.

## Implementation Plan

### Test strategy

- **Existing factories**: `create_movie/1`, `create_tv_series/1`, `create_episode/1`,
  `build_*` equivalents; ReleaseTracking item/release fixtures as used by
  `upcoming_feed_test.exs`; pursuit fixtures as used by `acquisition_live_test.exs`.
- **New factory functions**: none expected — shelf/ledger are presentations of existing
  structs.
- **Test types**: pure (`async: true`) for shelf/ledger presentation; ConnCase for
  IncomingLive (migrated from both pages' tests); controller test for redirects; smoke
  entries; bun tests for nav config/behavior; Playwright E2E for real-input nav.
- **Key assertions**:
  - Shelf: nearness order; graduated date labels (Tonight → weekday → "Fri Jul 17" →
    "Aug 6"); season-drop collapse preserved; armed/in-pursuit/in-theaters/tracked states
    match `UpcomingFeed` statuses; cap + horizon terminus; honest degradation (no armed /
    in-pursuit states when `acquisition_ready?: false`).
  - Ledger: newest-first terminal rows, initial cap, show-earlier expansion, storage line
    data separate from rows.
  - IncomingLive: mounts in BOTH capability states (no redirect when Prowlarr missing);
    forecast events (select_event/detail, track modal) and acquisition events (plan,
    cancel, history filters) work on the one page; `?selected=` pursuit deep link still
    opens the modal.
  - Redirects: `/upcoming` → `/incoming`, `/download` → `/incoming` preserving query
    string; `/?zone=upcoming` goes straight to `/incoming`.

### Order of changes

Each step is red → green → commit. Steps 1–2 are pure and independent of everything else.

1. **Shelf presentation (pure, test-first).** Extend `MediaCentaur.ReleaseTracking.UpcomingFeed`
   with shelf functions: `shelf_items(feed, context)` (flatten buckets nearness-first,
   cap with overflow count), `shelf_date_label(release, today)` (graduated explicitness).
   Reuses existing bucketing/status/season-collapse. Tests in `upcoming_feed_test.exs`
   (append; existing assertions untouched).
2. **Ledger presentation (pure, test-first).** Extend `AcquisitionLive.HistoryLogic` with
   `ledger_rows(rows, expanded?)` (newest-first, initial cap ~4, expansion). Tests in
   `history_logic_test.exs`.
3. **Status pill + shelf components + stories.** First
   `components/incoming/status_pill.ex` (typed status union: armed / in_pursuit(percent) /
   in_theaters / tracked / searching / landed / failed / cancelled) with a full-matrix
   story — the shared vocabulary both zoom levels render. Then
   `components/incoming/shelf.ex` (`shelf/1` section with horizon terminus + stragglers
   disclosure; `shelf_card/1` poster card using `status_pill`, progress hairline,
   season-drop stack, date badge). Typed attrs (MC0008), stories in `storybook/incoming/`
   covering the full state matrix incl. acquisition-off variants. Desktop rendering rules
   apply from the first story: eager+sync images, stable ids, no entrance animations
   (MC0016). Visual iteration against `mockups/incoming-page/index.html`.
4. **Ledger component + story.** `components/incoming/ledger.ex` — open fading rows
   (mask), show-earlier, "View all history" affordance, storage foot line (reuses
   `DownloadStorage.calm_summary/1` data). Story with landed/failed/cancelled/empty
   variants.
5. **Hero omnibox mode.** Extend `components/acquisition/media_omnibox.ex` with a
   `hero` attr (centered, prompt line, mode hint per mockup); update its story with the
   hero variation in the same change.
6. **View builder (pure, test-first).** `MediaCentaurWeb.IncomingLive.View` — one
   `build/1` taking `%{releases, pursuit_rows, history_rows, drafts, capabilities, today,
   grab_statuses}` and returning `%View{shelf, in_flight, ledger, drafts, subtitle}` by
   composing `UpcomingFeed` shelf functions, pursuit rows, and `HistoryLogic` ledger
   functions. Owns the status-union mapping both zoom levels feed to `status_pill`.
   Tested `async: true` with `build_*` factories, including the `acquisition_ready?: false`
   projection (sections absent, no grab-implying statuses).
7. **IncomingLive.** `git mv lib/media_centaur_web/live/acquisition_live.ex → incoming_live.ex`,
   `git mv lib/media_centaur_web/live/acquisition_live/ → incoming_live/`; rename modules
   (`AcquisitionLive` → `IncomingLive`, helpers follow). Then, inside it:
   - mount: drop the Prowlarr redirect; subscribe `ReleaseTracking`/`Library` always,
     acquisition topics only when `prowlarr_ready?`; `:capabilities_changed` rebuilds.
   - **one first-paint rule**: DB-backed sections build via the `ensure_loaded` pattern on
     both disconnected and connected renders (retire the deferred pursuit/history load);
     only queue snapshots arrive post-mount via PubSub. No queries in `mount/3` itself —
     loading stays in `handle_params`.
   - all section state flows through the `View` struct (one assign), replacing the
     per-section assign soup; render-time queue pairing stays as-is.
   - port from `UpcomingLive` (then delete it): forecast events (`select_event`/
     `close_detail` + `TitleDetail`, track-modal events + `TrackModal`), calendar state.
     Mini-month becomes the calendar disclosure reusing `MiniMonth`/`MonthGrid`.
   - template per mockup order: hero omnibox → search-results zone (existing, shelf
     recedes while active) → shelf → drafts banner → in-flight (pursuits) → ledger →
     orphan disclosure. Page identity: `data-page-behavior="incoming"`,
     `data-nav-default-zone="incoming"`, hero pool slot 2 (slot 3 freed). Desktop
     rendering: eager+sync art, stable iterator ids, no entrance animations, WS-only.
   - `Upcoming.Rail`, `Upcoming.EventCard`, `Upcoming.Stragglers` deleted with their
     stories; surviving `components/upcoming/` modules (`MiniMonth`, `MonthGrid`,
     `TitleDetail`, `Present`, `Detail`) rename to `components/release_tracking/`,
     stories moving in the same change.
8. **Routing + nav.** Router: `live "/incoming", IncomingLive, :index`; replace both old
   live routes with controller redirects (extend `AcquisitionRedirectController` →
   rename to `LegacyRedirectController`; preserve query string so `/download?selected=…`
   deep-links). Update HomeLive's `/?zone=upcoming` redirect target. Sidebar: one
   unconditional "Incoming" entry (`hero-inbox-arrow-down`, `data-nav-remember`),
   remove the `@acquisition_ready` conditional entry.
9. **Test migration.** `git mv` + rename `acquisition_live_test.exs` →
   `incoming_live_test.exs` and the pursuit-modal test; port `upcoming_live_test.exs`
   cases onto `/incoming` (drop rail-specific ones, keep track-modal/detail/stop-tracking);
   redirect controller test; `page_smoke_test.exs`: replace `/upcoming` + `/download`
   entries with `/incoming` (fixture exercising shelf + pursuits + ledger + drafts) plus a
   capabilities-off smoke asserting the forecast-only render.
10. **Input system.** `config.js`: add `incoming` layout — zones `omnibox`, `coming_up`
   (reuse the existing SHELF instance/selector from home), `grid` (search results),
   `drafts`, `pursuits`, `history`, `other_downloads`; `cursorStartPriority.incoming =
   ["omnibox", "coming_up", "pursuits", …]`; delete `upcoming` + `download` layouts,
   selectors and instance entries that become orphans (`rail`, `stragglers`,
   `mini-month`, `actions`). New `incoming_behavior.js` (onClear = download's cascade:
   omnibox query, then history search). Bun tests: new nav-graph zone tests +
   `incoming_behavior.test.js`; delete the two old behavior tests. Beware the recorded
   TOOLBAR instance-name traps (see `project-input-system-rollout` notes) when the
   calendar disclosure is open — decide MENU vs TOOLBAR for it in the bun tests first.
11. **E2E + real-browser verification.** Rewrite `test/e2e/download.spec.js` →
    `incoming.spec.js` (hero → shelf → pursuits → ledger traversal, both input methods);
    `scripts/input-test incoming`. Drive the live dev page with chromium-probe: shelf
    pill → torrent row anchor, calendar disclosure, acquisition-off state, redirects.
12. **Ship pass.** `mix precommit`; wiki (Using-Media-Centaur pages for
    Upcoming/Downloads → Incoming, `Keyboard-and-Gamepad.md`, `FAQ.md` for the merged-page
    rationale + old-URL note); CHANGELOG entry at release.

### Files to modify

- `lib/media_centaur/release_tracking/upcoming_feed.ex` — shelf presentation functions
- `lib/media_centaur_web/live/incoming_live/history_logic.ex` — ledger functions (post-mv)
- `lib/media_centaur_web/live/incoming_live.ex` — the merged LiveView (post-mv, absorbs forecast)
- `lib/media_centaur_web/live/incoming_live/*` — module renames only
- `lib/media_centaur_web/components/acquisition/media_omnibox.ex` (+ story) — hero mode
- `lib/media_centaur_web/router.ex` — new route + redirects
- `lib/media_centaur_web/controllers/acquisition_redirect_controller.ex` — rename + old-route actions
- `lib/media_centaur_web/components/layouts.ex` — sidebar entry swap
- `lib/media_centaur_web/live/home_live.ex` (or its logic) — `?zone=upcoming` redirect target
- `assets/js/input/config.js` — `incoming` layout, selector/instance cleanup
- `assets/js/input/page_behavior.js` — register `incoming`, drop old two
- `test/media_centaur_web/page_smoke_test.exs`, `test/media_centaur/release_tracking/upcoming_feed_test.exs`,
  `test/media_centaur_web/live/incoming_live/{logic,history_logic,plan_logic}_test.exs` (renames),
  `test/media_centaur_web/live/incoming_live_test.exs` (+ pursuit-modal sibling)

### New files

- `lib/media_centaur_web/live/incoming_live/view.ex` + `test/media_centaur_web/live/incoming_live/view_test.exs` — the one composition point
- `lib/media_centaur_web/components/incoming/status_pill.ex` + `storybook/incoming/status_pill.story.exs` — shared status vocabulary
- `lib/media_centaur_web/components/incoming/shelf.ex` + `storybook/incoming/shelf.story.exs` (+ `shelf_card.story.exs`, `_incoming.index.exs`)
- `lib/media_centaur_web/components/incoming/ledger.ex` + `storybook/incoming/ledger.story.exs`
- `assets/js/input/incoming_behavior.js` + `assets/js/input/__tests__/incoming_behavior.test.js`
- `test/e2e/incoming.spec.js` (replaces `download.spec.js`)
- `test/media_centaur_web/controllers/legacy_redirect_controller_test.exs`

### Deleted

- `lib/media_centaur_web/live/upcoming_live.ex` + `upcoming_live_test.exs` (cases ported first)
- `components/upcoming/{rail,event_card,stragglers}.ex` + their stories
- `assets/js/input/{upcoming,download}_behavior.js` + tests; `upcoming`/`download` layout keys

### Technical decisions

- **Evolve, don't rewrite**: `git mv` AcquisitionLive → IncomingLive preserves the
  reconciliation machinery, its moduledoc contracts, and test lineage.
- **No new data paths**: shelf = presentation of `UpcomingFeed`; ledger = presentation of
  existing history `PursuitRow` VMs. All new logic is pure and unit-tested (ADR-030).
- **Capability gating moves from route-level (redirect) to render-level** — the page is
  the first acquisition surface that renders without Prowlarr, so no `Capabilities` gate
  may remain in mount.
- **Redirects preserve query strings** so `?selected=` pursuit deep links survive.
- **Stragglers** (tracked, nothing scheduled) fold into a quiet disclosure at the horizon
  terminus — not on the shelf (no date), not a dead panel (design gap resolved during
  planning; carried into the shelf component).
- **Shelf nav context reuses the home page's SHELF instance** (`coming_up`) rather than
  minting a new context type.
- **Hero pool slot 2** for the merged page; slot 3 retires with UpcomingLive.
