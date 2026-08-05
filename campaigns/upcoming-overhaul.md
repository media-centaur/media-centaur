---
status: complete
status_note: shipped — v0.94.0 (+ v0.94.1 backdrop/alignment polish)
started: 2026-06-14
last_updated: 2026-06-14
---
# Upcoming section overhaul

## Goal

Overhaul the `/upcoming` page following the section-overhaul house style
(Home → Library → Downloads already done): a **time-first forecast** of tracked
media releases for an enthusiast who looks forward to theatrical releases and
wants new movies/episodes auto-grabbed when they drop. The page is a *forecast,
not a console* — it answers "what's coming and when?" first, surfaces confidence
that automation will grab things unattended, and gives a closure beat at release
that links to Downloads. The data layer (`ReleaseTracking`, ADR-056) is already
mature; this overhaul is the **page**, plus a final full keyboard/gamepad input
treatment. Chosen UI: an **editorial timeline rail with a quiet sticky mini-month
companion** (mockup #6).

## Status

**Shipped.** `/upcoming` is the editorial rail + sticky mini-month + per-title
detail. Released as **v0.94.0** (overhaul) and **v0.94.1** (ambient page backdrop,
slot 3, + mini-month top-alignment polish the user requested live) — both
GitHub-release-verified; wiki `Release-Tracking.md` pushed.

**Residual (deferred):** regenerate the `upcoming-calendar` marketing screenshot
(user said skip for now — it still shows the old calendar), and a live
keyboard/gamepad nav spot-check on the running app.

Commits: view-model → EventCard/Present → Rail/MiniMonth/Stragglers → TitleDetail
→ LiveView rewrite → input treatment → backdrop/alignment polish.

## Decisions made

* `2026-06-14` — **Primary axis = TIME.** Page leads with a date-ordered forecast;
  tracking status is drill-in detail, not the spine.
* `2026-06-14` — **Forecast form = editorial rail spine + quiet sticky mini-month
  companion** (mockup #6). Rail beauty leads; calendar is a quiet overview+jump
  companion, never a competing band. Rejected: calendar-hero, loud band on rail.
* `2026-06-14` — **List unit = release EVENT** (episode / season-drop / movie
  theatrical date / movie digital date). Proximity = prominence: nearest 1–2 are
  21:9 hero cards; farther-out events compact.
* `2026-06-14` — **Time/thing resolves as overview/detail.** Per-title "tracking
  card" becomes the drill-in detail slide-over (automation config + pursuit status
  + release timeline + stop-tracking).
* `2026-06-14` — **Seam with Downloads = pursuit linkage + indicator.** At release,
  show "under pursuit" status linking to the pursuit; management stays in Downloads.
  No duplicated downloads list. Deep-link via existing `/download?selected=<uuid>`.
* `2026-06-14` — **Movie multi-date = both, labeled.** Theatrical = info-only
  anticipation event ("we'll grab the digital release", not actionable); digital/
  physical = the grab event. Already separate `Release` rows.
* `2026-06-14` — **Control demoted.** "Track something" action by the title;
  remove/tune in the detail panel; quiet "Tracking — nothing scheduled yet"
  stragglers list for undated trackers.
* `2026-06-14` — **Acquisition gating (Prowlarr).** Gate all grab-related UI on a
  capability value passed into components (not scattered global reads). When
  unavailable, page degrades to pure-info forecast.
* `2026-06-14` — **Armed honesty.** `:armed` shown only when a grab will actually
  fire (Prowlarr ready + global auto-grab on + item `auto_grab_mode` not opted out);
  otherwise neutral "Releases <date>".
* `2026-06-14` — **Activity history → per-title detail panel.** Drop the global
  "Recent Changes" feed; per-title events show on drill-in.
* `2026-06-14` — **Verified:** pursuit deep-link needs no Downloads-page change
  (`apply_pursuit_modal_params` + `statuses_for_releases/1`); view-model is pure
  functions over existing reads — **no domain/schema changes expected.**

## Built (all on `main`, test-first)

- **A — `UpcomingFeed` view-model** (`lib/media_centaur/release_tracking/upcoming_feed.ex`,
  23 async tests): relative-time bucketing, status derivation with honest auto-grab
  gating, hero flagging, season-drop collapse, mini-month marks, stragglers.
- **B — capability gating folded into D** — the LiveView reads `Capabilities`
  (`acquisition_ready?`/`tmdb_ready?`) and bakes acquisition gating into each event's
  status; `Detail.acquisition?` gates the panel automation section. No separate struct
  was needed once status carried the gate.
- **C — components** (`lib/media_centaur_web/components/upcoming/`, each with a story):
  `EventCard` (+ pure `Present` + `MonthGrid` helpers, unit-tested), `Rail`, `MiniMonth`,
  `Stragglers`, `TitleDetail` (+ `Detail` VM). Named `title_detail` to dodge a
  storybook-coverage basename collision with the existing `Components.DetailPanel`.
- **D — `UpcomingLive` rewrite** + `ReleaseTracking.list_events_for_item/2`; reuses
  `TrackModal`; dead `UpcomingCards` (component/story/test) deleted.
- **E — input treatment**: `config.js` `actions`/`rail`/`stragglers` MENU + `mini-month`
  TOOLBAR; WIP wrapper dropped; real-config nav-graph tests in `index.test.js`.
- **F — verify**: full `mix precommit` green; wiki `Release-Tracking.md` updated.

## Next steps (ship)

1. **Live nav spot-check** on the running app (Playwright doesn't provision here):
   rail up/down, SELECT → detail, BACK closes it, left → sidebar, mini-month paging.
2. **Release tag** — `scripts/ship` (version bump + CHANGELOG) when the user is ready;
   push then triggers the release workflow.
3. **Push the wiki commit** (held; publishes on push).
4. **Regenerate the `upcoming-calendar` marketing screenshot** (`scripts/screenshot-tour`)
   — it now shows the rail, not a calendar.

## Build-time decisions

* `2026-06-14` — Stop-tracking is **immediate** (delete + flash) from the detail panel;
  the old confirm-modal was dropped (the detail drill-in is already a deliberate step).
* `2026-06-14` — Mini-month **day cells are mouse-only** jump affordances; the rail is
  the keyboard spine, so only the month-paging buttons are nav items (`mini-month`
  TOOLBAR). Reconsider if couch users want calendar-driven jumping.
* `2026-06-14` — Added `ReleaseTracking.list_events_for_item/2` for the per-title
  activity feed (the one flagged data gap).

## Completion criteria

* `/upcoming` is the editorial-rail + mini-month design, working at 4K, 1080
  fullscreen, and half-screen.
* All status states render correctly (armed/under-pursuit→Downloads/in-library/
  theatrical-info/upcoming/unscheduled), with honest auto-grab gating.
* Per-title detail slide-over carries automation config, pursuit status, release
  timeline, per-title events, stop-tracking.
* Fully keyboard/gamepad navigable; WIP notice removed.
* Old upcoming sections retired; every new component has a passing story; full
  `mix precommit` green; wiki + CHANGELOG updated.

## Pointers

* Design record + mockups: `~/.claude/plans/let-s-start-the-planning-floofy-seahorse.md`,
  `~/.claude/plans/upcoming-mockups/6-editorial-rail-plus-mini-month/` (chosen),
  siblings 1–5 for rejected directions.
* Data layer: `lib/media_centaur/release_tracking.ex` (reads),
  `lib/media_centaur/acquisition/pursuits.ex` (`statuses_for_releases/1`),
  [ADR-056](../decisions/architecture/2026-06-10-056-release-tracking-wants.md).
* Current page (to retire/rewrite): `lib/media_centaur_web/live/upcoming_live.ex`,
  `lib/media_centaur_web/components/upcoming_cards.ex`,
  `lib/media_centaur_web/components/track_modal.ex` (reuse).
* Downloads deep-link: `lib/media_centaur_web/live/acquisition_live.ex`
  (`apply_pursuit_modal_params`, `?selected=<uuid>`).
* Input system: `assets/js/input/upcoming_behavior.js` (WIP no-op),
  `assets/js/input/config.js`.
* Convention: [ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md).
