---
status: active
started: 2026-10-02
last_updated: 2026-10-03
---
# Social and Watchlist

## Glossary

Existing terms are in [`docs/GLOSSARY.md`](../docs/GLOSSARY.md): *title
intent*, *rung*, *Ignored* (rung), *tracked title*, *following*,
*bookmark*, *tracking controls*, *title detail modal*, *listing*, *Feed*,
*Social* (the subsystem). This campaign changes the meaning of two and
adds three.

* **Social** (page) — the page at `/social`: the Feed and the Friends
  tab. What the Discovery page was, less the watchlist. Everything named
  for the Discovery page is renamed with it: the route, `SocialLive`,
  `components/social/`, the `show_social` preference, the JS page
  behaviour, the docs. The subsystem keeps its name; page and subsystem
  are one context's two faces, so the shared word is correct, not a
  collision.
* **Watchlist** — every title intent at List or above, as before. Now
  also the name of the bounded context that holds title intents
  (`MediaCentaur.Watchlist`, formerly `Discovery`; ADR-075 rule 3: a
  context carries its surface's name) and of Incoming's first tab, the
  one place the list is shown whole.
* **Next release** — for a followed title, the earliest release event
  `ReleaseTracking.UpcomingFeed` forecasts for it: which release (an
  episode, a film's digital or physical date) and when. A listed-only
  title has none.
* **Release status** — the `UpcomingFeed` status of a next release
  (`:armed`, `:upcoming`, `:under_pursuit`, `:unscheduled`, …), drawn
  with the `StatusPill` vocabulary Coming up used. Not to be confused
  with a row's *acquisition state* (Planning / Downloading / Needs
  review), which every watchlist row carries from `Acquisition.TitleStates`.
* **Coming up** — retired as a tab and as a list. Home keeps its *Coming
  up* shelf (`UpcomingFeed`, unchanged); the words stay for that shelf
  only.

## Goal

Two sidebar groups where the pages are grouped by what they are for.
**Social** is friends: the Feed and the Friends roster. **Incoming** is
getting titles: the watchlist, search, downloads and their history.
Today the watchlist is a tab of the Discovery page, so it is reachable
only while the social preference is on, and the same records are listed
twice — the Watchlist tab shows every listed title, Incoming's Coming up
tab shows the followed ones by date. One list on Incoming replaces both.

## Status

Phases 1–2 done on branch `social-and-watchlist`, awaiting merge; Phase 3
next. Phase 1: commits a04bef5c, 5c254c47, 54052d63, 9707fb89, 05158152,
39f9c9f7 and the final-review docs commit; plan
`docs/superpowers/plans/2026-10-02-watchlist-on-incoming.md`. Phase 2:
commits 464cdef4, 1314a8b5, b7b108ae and the UIDR-051 docs commit; plan
`docs/superpowers/plans/2026-10-03-discovery-page-becomes-social.md`. The
retired `watchlist-single-entry-point` campaign's owner check is carried
here, open.

## Decisions made

* `2026-10-02` — The Discovery page becomes the Social page: route,
  LiveView, component directory, preference key (`show_discovery` →
  `show_social`), JS behaviour, docs. No data migration: the preference
  resets to its default (off), per the no-migrations rule. (owner)
* `2026-10-02` — The watchlist leaves the Social page and becomes
  Incoming's first tab; `/discovery/watchlist` goes away. (owner)
* `2026-10-02` — Watchlist and Coming up are one list: every title at
  List or above; a followed title's row carries its next release and its
  release status; sorted by nearest dated next release, then followed
  titles with no date, then listed-only titles newest first. Incoming's
  Coming up shelf (`Components.Incoming.Shelf`) goes; Home's shelf
  (`coming_up_marquee`, over `Views.ComingUp`) stays. (owner, on recommendation)
* `2026-10-02` — The page keeps the name Incoming. Renaming it is a
  separate decision, taken, if at all, once the merged list exists. (owner)
* `2026-10-02` — The `Discovery` context is renamed `Watchlist`. The
  `title_intents` table keeps its name. `Pipeline.Discovery` (file
  discovery) is a different context and is untouched. (owner)
* `2026-10-02` — `:ignored` stays on the ladder: it is a stance on a
  title, and listing a title must replace it, which one record gives for
  free. Its "Ignored" marker leaves search results (the marker labels a
  Feed filter in a list where it reads as an acquisition state; see
  `d93e051b` for its origin). The title detail modal's "Hidden from the
  Feed…" line gains the way out — un-ignore, back to no record — since
  the Undo toast is today the only one. (owner, on recommendation)

## Next steps

Four phases, each a plan under `docs/superpowers/plans/` and one or more
commits. Each phase is test-first and ends green on `mix precommit`.

1. **Merge the watchlist into Incoming** — done 2026-10-02 (UIDR-050), awaiting merge. A `Watchlist` tab replaces
   `Coming up` as the default (`?zone=watchlist`): `Title.Row` per
   listed title with poster, markers, social glyphs and acquisition
   state (as the Discovery tab draws it today), plus next release and
   release status for followed titles; the sort above; the empty state
   (UIDR-034) saying the omnibox is where titles come from; the
   watchlist's `title_rows` nav zone moved with it. Remove
   `Components.Incoming.Shelf` and `View.ShelfSection`; `Views.ComingUp*`
   stays, Home reads it.
   Remove the Watchlist tab and route from Discovery. A UIDR records the
   merged list and amends UIDR-015 (Coming up tab) and UIDR-035 (the
   watchlist as the arming surface — unchanged in substance, moved).
   Wiki: `Watchlist.md`, `Release-Tracking.md`,
   `Searching-and-Downloading.md`, `Social.md`; the guide pages
   `watchlist-and-tracking.md` and `release-tracking-and-upcoming.md`.
2. **Rename the Discovery page to Social** — done 2026-10-03 (UIDR-051;
   commits 464cdef4, 1314a8b5, b7b108ae and the docs commit). Routes `/social`,
   `/social/friends`; `SocialLive` and `live/social_live/`;
   `components/social/`; stories; `show_social` /
   `Preferences.SocialVisibility` (and the Settings row's copy — the
   gate now hides the Social entry and the Review control only);
   `discovery_behavior.js` and its `config.js` zones; `.discovery-rail`;
   sidebar label and icon; the glossary's *Discovery* row;
   `docs/social.md`, `docs/architecture.md`, `docs/storybook.md`,
   `docs/input-system.md`; the UIDRs that name the page get a dated
   amendment where the claim would mislead (010, 038, 043, 045, 046);
   wiki pages and the guide.
3. **Rename the `Discovery` context to `Watchlist`.**
   `MediaCentaur.Watchlist`, `Watchlist.TitleIntent`, `.Titles`,
   `.Events`, `.TmdbReferences`; the Boundary `deps` of every context
   that names it (`ReleaseTracking`, `Acquisition`, `Activities`,
   `Review`, `EpisodeMapping`, `Library`, `Social`, `Pipeline`); the
   `discovery:updates` topic (`Topics.discovery_updates/0`) becomes
   `watchlist:updates`; the `Log` component is not named for it;
   `docs/context-map/`; ADR-066 and ADR-075 amendments; glossary rows
   *title intent* and *rung*.
4. **Ignored.** Drop `rung_marker(:ignored)` from `Title.Logic`
   (search results); add the un-ignore control to `TrackingControls`'
   `:ignored` form (sets the record off, through `ReleaseTracking.set_rung`);
   delete the stale "Ignored items are skipped" paragraph in
   `ReleaseTracking.Wants`' moduledoc.
5. **Owner check, desktop and TV, mouse and gamepad** (carried from
   `watchlist-single-entry-point` Phase 4, open): search a title, list it
   (Add to watchlist), turn on **Track release dates** from its detail,
   see it on Incoming's Watchlist tab, download from the title view and
   confirm the rung did not move.
6. **Re-shoot `upcoming-calendar.png`** (README l.35, docs-site l.726)
   with the Watchlist tab — `screenshot-showcase`, manual.

## Completion criteria

* The sidebar's Watch group reads Home, Library, Social, Incoming, Apps;
  Social is gated by `show_social`, Incoming is not.
* `/incoming` defaults to the Watchlist tab (the first-load smart default
  to Activity while something is in flight stands); every listed title is
  on it once; a followed title's row shows its next release and status; no
  Coming up tab or marquee exists on Incoming; Home's shelf is unchanged.
* No route, module, directory, preference, CSS class or doc names the
  Discovery page; `MediaCentaur.Discovery` does not exist;
  `Pipeline.Discovery` is untouched.
* A search result never says Ignored; an ignored title's detail modal
  offers un-ignore and it works.
* Wiki and guide describe the two groups; CHANGELOG entry drafted at
  ship time.
* The owner has used the flow (list, track, download; the rung stays)
  on the desktop and the TV, mouse and gamepad.

## Pointers

* [ADR-075](../decisions/architecture/2026-09-29-075-bounded-context-naming.md)
  — context naming (rule 3 drives the `Watchlist` rename).
* [ADR-066](../decisions/architecture/2026-09-07-066-one-ladder-per-title.md)
  — one ladder per title; `set_rung/3` the one write path.
* [UIDR-015](../decisions/user-interface/2026-07-11-015-incoming-page.md)
  — Incoming's tabs; amended by Phase 1.
* [UIDR-042](../decisions/user-interface/2026-09-14-042-tracking-is-the-bookmark-and-two-switches.md)
  — the tracking controls Phase 4 extends.
* `lib/media_centaur_web/live/social_live.ex` (the Social page),
  `lib/media_centaur_web/live/incoming_live/view.ex`
  (the page's single composition point),
  `lib/media_centaur/release_tracking/upcoming_feed.ex` (next release and
  status), `lib/media_centaur_web/components/title/logic.ex`
  (`row_markers/2`).
* `watchlist-single-entry-point.md` (retired 2026-10-02; git history
  holds it) left the owner check that is Next steps 5.
