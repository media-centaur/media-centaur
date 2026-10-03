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
* **Next release** — for a followed title, its next release still to
  come, as `ReleaseTracking.UpcomingFeed.next_per_title/1` picks it:
  which release (an episode, a season drop, a film's date type) and
  when. A release the app is still searching for counts as still to
  come; a release already in the library leads the row, as Landed, only
  while nothing else is scheduled. A listed-only title has none.
* **Release status** — the `UpcomingFeed` status of a next release
  (`:armed`, `:upcoming`, `:under_pursuit`, `:in_library`, …), drawn
  with the `StatusPill` vocabulary (Will grab, Tracked, In pursuit,
  Searching, In theaters, Landed). Not to be confused with a row's
  *acquisition state* (Planning / Downloading / Needs review), which
  every watchlist row carries from `Acquisition.TitleStates`.
* **Coming up** — retired as a tab and as a list. Home keeps its *Coming
  up* shelf (`coming_up_marquee` over `ReleaseTracking.Views.ComingUp`,
  unchanged); the words stay for that shelf only.

## Goal

Two sidebar groups where the pages are grouped by what they are for.
**Social** is friends: the Feed and the Friends roster. **Incoming** is
getting titles: the watchlist, search, downloads and their history.
Before this campaign the watchlist was a tab of the Discovery page, so it
was reachable only while the social preference was on, and the same
records were listed twice — the Watchlist tab showed every listed title,
Incoming's Coming up tab the followed ones by date. One list on Incoming
replaces both, and the page that is left is named for what it holds.

## Status

**Phases 1–3 done on branch `social-and-watchlist` (2026-10-03),
precommit clean, nothing pushed, not merged. Phase 4 next.**

* Phase 1 (the watchlist on Incoming, UIDR-050): commits `a04bef5c`,
  `5c254c47`, `54052d63`, `9707fb89`, `05158152`, `39f9c9f7`, `366db3c4`;
  plan `docs/superpowers/plans/2026-10-02-watchlist-on-incoming.md`.
* Phase 2 (the Discovery page is the Social page, UIDR-051): commits
  `464cdef4`, `1314a8b5`, `b7b108ae`, `d84b433f`, `043827a3`; plan
  `docs/superpowers/plans/2026-10-03-discovery-page-becomes-social.md`.
* Phase 3 (the `Discovery` context is `Watchlist`, ADR-075): commits
  `7e0891f3` (code), `19e01df7` (context-map tests + snapshot, droppable),
  `eb55677e` and its docs follow-up (records, glossary); plan
  `docs/superpowers/plans/2026-10-03-discovery-context-becomes-watchlist.md`.
* Wiki (`../media-centaur.wiki`): three local commits, unpushed —
  `f2b8bd1`, `fca9ad2`, `f15fe34`. Push them when the release ships, not
  before (they describe the branch, not the released app).

## Resuming in a new session

Read this file, then reconcile against `git log main..social-and-watchlist`
before writing code. What a new session needs to know:

1. **The branch is forked from the `context-map` branch, not `main`.**
   Its first commit `d6668d0e` sits on `7544b939` (context-map's tip);
   `main` is at `e0bac217`. `git log main..HEAD` therefore shows ~35
   context-map commits plus this campaign's. The campaign's commits
   touch no context-map file except two droppable ones: `b7b108ae`
   (`test/context_map/fixture_instances_test.exs`, one module name) and
   `19e01df7` (`test/context_map/*` and `docs/context-map/context-map.json`
   after the Phase 3 rename). Owner's choice, not yet made: `git rebase
   --onto main 7544b939 social-and-watchlist` (drop both; rerun
   precommit), or merge
   `context-map` first and keep it. An agent must not do the rebase (the
   harness declined it as a history rewrite); ask.
2. **The `media-centaur-dev` service runs this checkout**, so whatever
   branch is checked out is what `http://127.0.0.1:2160` serves. Never
   run `mix` directly; `~/scripts/agents/agent-mix` only (CLAUDE.md).
3. **`show_social` is on by default** since the afternoon of 2026-10-03
   (UIDR-051 amendment); its switch is **Show Social in the sidebar**
   under Settings → Social. The morning's reset-to-off is history.
4. **Owner items open** (Next steps 5–7): the desktop/TV check, the
   screenshot re-shoot, the Settings wording question.
5. The two decisions taken from the final review on 2026-10-02 (next
   release still to come; no pill anchor across tabs — below) were taken
   without the owner present; confirm before building on them.

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
* `2026-10-02` — A row's next release is the next one still to come
  (`UpcomingFeed.next_per_title/1`): a Landed release leads only when
  nothing later is scheduled; a release still being searched for counts
  as still to come. The shelf's old rule (earliest event, Landed kept
  seven days) would have shown "Landed · 3 days ago" on every weekly
  series. (agent, from the final review — confirm; commit `39f9c9f7`)
* `2026-10-02` — The in-pursuit pill on a watchlist row does not anchor
  to `#pursuit-<id>`: the pursuit row renders on the Activity tab only,
  so the link went nowhere. `StatusPill`'s `anchor` attr went with it
  (no other caller); UIDR-015 §6's anchor is retired. (agent, from the
  final review — confirm; commit `39f9c9f7`)
* `2026-10-02` — Incoming's `title_rows` nav zone is a MENU, not a TREE:
  a `Title.Row` is one nav item with no sub-items. (agent; `9707fb89`)
* `2026-10-03` — Sidebar icon for Social: `hero-users`. (agent, flagged)
* `2026-10-03` — Phase 2 was a pure rename; Phase 3 (the context) was
  kept separate because the context-map branch's tests name the
  context's file paths (`lib/media_centaur/discovery.ex`,
  `discovery/title_intent.ex`) and the two renames sequence differently
  against that merge. (agent)
* `2026-10-03` — Phase 3 ran inline (sed-driven rename, test files
  first, then `lib`), with one whole-slice review at the end instead of
  per-task subagents: a mechanical rename has no design per task to
  review. The context-map test changes are a separate commit so either
  merge path (rebase or merge) stays clean. (agent)
* `2026-10-03` — Phase 2 left two stale moduledoc references
  (`Discovery.FeedRow` in `title/row.ex`, `Discovery.PersonCard` in
  `switch.ex`); fixed in Phase 3's code commit as `Social.*`. (agent)
* `2026-10-03` — `show_social` defaults on; its switch lives on the
  Social settings section (card *Sidebar*, row *Show Social in the
  sidebar*), not under Preferences. The Review control follows it as
  before. No migration: an install that had it off keeps its stored
  value. (owner)

## Next steps

Each phase is a plan under `docs/superpowers/plans/`, test-first, green on
`mix precommit`, executed subagent-driven with a spec review and a code
quality review per task and a whole-branch review at the end (Phases 1–2
ran that way; it worked).

1. **Merge the watchlist into Incoming** — done 2026-10-02 (UIDR-050).
2. **Rename the Discovery page to Social** — done 2026-10-03 (UIDR-051).
3. **Rename the `Discovery` context to `Watchlist`** — done 2026-10-03
   (ADR-075 second application; plan
   `docs/superpowers/plans/2026-10-03-discovery-context-becomes-watchlist.md`).
   Context-map's tests and snapshot followed in a separate, droppable
   commit (see *Resuming*, item 1).
4. **Ignored.** Not started; no plan yet. Drop `rung_marker(:ignored)`
   from `Components.Title.Logic.row_markers/2` (search results on
   Incoming; `media_results.ex` is the caller) and its `logic_test`
   case; add an un-ignore control to `Components.Title.TrackingControls`'
   `:ignored` form (today one line, `ignored_line/0`: "Hidden from the
   Feed. Add it to your watchlist to bring it back.") — a button that sets
   the record off through `ReleaseTracking.set_rung(title, :off, …)` via
   the host's `set_rung` event (`TitleDetailHost`), with a story
   variation and a `title_detail_host` test; delete the stale "Ignored
   items are skipped" paragraph in `ReleaseTracking.Wants`' moduledoc
   (~l.28). The copy and the control's form (a button beside the line;
   label to be chosen with the `writing-copy` skill, e.g. "Show on the
   Feed again") are the owner's call at plan time.
5. **Owner check, desktop and TV, mouse and gamepad** (carried from
   `watchlist-single-entry-point` Phase 4, open): search a title, list it
   (Add to watchlist), turn on **Track release dates** from its detail,
   see it on Incoming's Watchlist tab, download from the title view and
   confirm the rung did not move. Also: turn **Social** on under
   Settings → Preferences and confirm the sidebar entry, the Feed and the
   Friends tab.
6. **Re-shoot `upcoming-calendar.png`** (README l.35, docs-site l.726)
   with the Watchlist tab — `screenshot-showcase`, manual.
7. **Settings wording** — resolved 2026-10-03: the toggle moved into the
   Social section as **Show Social in the sidebar** (card *Sidebar*,
   last in the section) and the preference defaults on. Copy is
   provisional; owner adjusts at the end.
8. **At ship:** CHANGELOG entry (both phases; the preference reset is a
   migration note), push the wiki, `scripts/ship`.

## Completion criteria

* The sidebar's Watch group reads Home, Library, Social, Incoming, Apps;
  Social is gated by `show_social` (default on, switched under
  Settings → Social), Incoming is not. — met on the branch.
* `/incoming` defaults to the Watchlist tab (the first-load smart default
  to Activity while something is in flight stands); every listed title is
  on it once; a followed title's row shows its next release and status; no
  Coming up tab or marquee exists on Incoming; Home's shelf is unchanged.
  — met on the branch.
* No route, module, directory, preference, CSS class or doc names the
  Discovery page — met; `MediaCentaur.Discovery` does not exist — met
  2026-10-03; `Pipeline.Discovery` is untouched.
* A search result never says Ignored; an ignored title's detail modal
  offers un-ignore and it works. — Phase 4.
* Wiki and guide describe the two groups — met (unpushed); CHANGELOG
  entry drafted at ship time.
* The owner has used the flow (list, track, download; the rung stays)
  on the desktop and the TV, mouse and gamepad.
* The branch is on `main` (rebased or merged with context-map by the
  owner's choice) and shipped.

## Pointers

* [ADR-075](../decisions/architecture/2026-09-29-075-bounded-context-naming.md)
  — context naming (rule 3 drives the `Watchlist` rename).
* [ADR-066](../decisions/architecture/2026-09-07-066-one-ladder-per-title.md)
  — one ladder per title; `set_rung/3` the one write path.
* [UIDR-050](../decisions/user-interface/2026-10-02-050-the-watchlist-is-incomings-first-tab.md),
  [UIDR-051](../decisions/user-interface/2026-10-03-051-the-discovery-page-is-the-social-page.md)
  — this campaign's records; UIDR-015/035/042 and 010/038/043/045/046
  carry their amendments.
* [UIDR-042](../decisions/user-interface/2026-09-14-042-tracking-is-the-bookmark-and-two-switches.md)
  — the tracking controls Phase 4 extends.
* `lib/media_centaur_web/live/social_live.ex` (the Social page),
  `lib/media_centaur_web/live/incoming_live/view.ex` (Incoming's single
  composition point), `lib/media_centaur_web/live/incoming_live/watchlist_rows.ex`
  (the rows, pure), `lib/media_centaur/release_tracking/upcoming_feed.ex`
  (`next_per_title/1`, `date_label/2`),
  `lib/media_centaur_web/components/title/row.ex` (`Row.NextRelease`),
  `lib/media_centaur_web/components/title/logic.ex` (`row_markers/2`),
  `lib/media_centaur_web/components/title/tracking_controls.ex`
  (Phase 4's `:ignored` form).
* `watchlist-single-entry-point.md` (retired 2026-10-02; git history
  holds it) left the owner check that is Next steps 5.
