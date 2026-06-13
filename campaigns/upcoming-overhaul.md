---
status: planning
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

**Phase A in progress.** Planning + design complete (UI direction #6, deps verified,
clarifications answered). Core `UpcomingFeed` view-model shipped green and pure —
`lib/media_centaur/release_tracking/upcoming_feed.ex` + `..._test.exs` (18 async
tests): relative-time bucketing (today/this_week/next_week/later/beyond),
status derivation (`:in_library | :theatrical_info | :unscheduled | :under_pursuit |
:armed | :upcoming`) with honest auto-grab gating, hero flagging (nearest 2), and
same-(item,season,date) season-drop collapse. Uncommitted (precommit gates the
phase boundary). **Next: A2 — mini-month per-day marks + "nothing scheduled yet"
stragglers; then B (Capabilities).**

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

## Next steps

Build is **test-first** (repo policy) and lands in reviewable phases on `main`.

1. **A — `UpcomingFeed` view-model + tests.** A `ReleaseEvent` struct (title, art,
   date, season/episode, what-drops, `status`, `hero?`, pursuit link target) and a
   pure builder that buckets events by relative time (Today / This week / Next week /
   Later / Beyond), flags heroes (nearest 1–2), derives status
   (`:armed | :under_pursuit | :in_library | :theatrical_info | :upcoming | :unscheduled`),
   collapses same-(item,season,air_date) episodes into one season-drop event, and
   produces mini-month per-day marks for the visible month. Inputs: `list_releases/0`,
   `Acquisition.statuses_for_releases/1`, open-wants, item `auto_grab_mode` + global
   auto-grab setting, images. Unit-tested in isolation (no DB/network).
2. **B — `Capabilities` value.** One explicit struct (`acquisition?`, `tmdb?`,
   `auto_grab_global?`) passed into components, replacing scattered
   `acquisition_ready`/`tmdb_ready` reads.
3. **C — Components (+ Storybook story + typed attrs each; MC0008/MC0009).**
   `UpcomingRail`, `UpcomingEventCard` (`:hero`/`:compact` variants), `MiniMonth`,
   `TrackingStragglers`, `UpcomingDetailPanel`. Reuse glass/title/status idioms.
4. **D — `UpcomingLive` rewrite.** Assigns from the view-model; keep the debounced
   PubSub reload pattern; reuse `TrackModal`; wire detail open/close, stop-tracking,
   mini-month month-nav + day-jump, scroll-driven focused-day; pursuit deep-link.
   Retire calendar-grid / active-shows / recent-changes / unscheduled sections.
5. **E — Full input treatment.** Replace the WIP no-op `createUpcomingBehavior()`;
   real rail/grid nav, drill-in, modal dismissal, mini-month nav + jump; update
   `assets/js/input/config.js` zones/graph; drop `withWipNotice`.
6. **F — Verify + ship.** `mix precommit` green; `upcoming_live_test.exs` (gated +
   ungated wiring); stories render; input nav verified via chromium-probe recipe;
   showcase review at 4K / 1080 / half-screen; wiki sync; CHANGELOG.

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
