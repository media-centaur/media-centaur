---
status: active
started: 2026-09-11
last_updated: 2026-09-11
---
# The watchlist is the single entry point

## Glossary

Existing terms are in [`docs/GLOSSARY.md`](../docs/GLOSSARY.md): *title
intent*, *rung*, *following*, *tracked title*, *title detail modal*. This
campaign adds none until Phase 2 settles, because which words it needs
depends on the rule chosen there (see Open decisions).

* **Watchlist** — every title intent at List or above. Not a tab: the
  Watchlist tab on Discovery is one view of it, Coming up and the Library
  are others.
* **Bookmark** — the two-way form of the tracking control: List and Off
  (and Ignore on the Feed). It puts a title on the watchlist and takes it
  off; it never raises a title to Follow.
* **Ladder** — the full seven-way tracking control, Ignore through Default.
  The only thing that raises a title to Follow or above.

## Goal

Adding a title to the watchlist and enabling release tracking for it are
two acts, in that order, and the second happens only on the watchlist.
Today the record already works that way — one title intent per title, one
write path, List and above is the list, Follow and above is tracked — but
four download-side controls raise a title straight to Follow or Grab as a
side effect of a download, and the full ladder is mounted on every title
view, so a search result reaches Grab without the title ever being "on the
list" as a step of its own. This campaign removes the four controls and
makes the ladder appear only where the watchlist is being looked at.

## Status

**Phase 1 shipped to main 2026-09-11 (unpushed, unreleased).** The four
download-side controls and their machinery are gone: `TrackingHandoffs`,
`Plans.plan_title/2`'s `:track`, `Plan.grab_future`, `Want.provenance`,
`Wants.open_gap_wants/2`, the `plan_track_only` / `plan_toggle_grab_future`
/ `plan_track_gaps` events and the `tracked_plan_identity` / `gap_rung` /
`gap_flash` helpers behind them. Migration `20260911150000` drops both
columns (down re-adds them at their defaults); it has run on the real
database. Tests pin each door: the scope menu is *Download all* only and
leaves the rung at List; the picker and the movie confirm carry no tracking
control and creating a plan leaves the rung at nil; the gaps banner has no
*Track these*; satisfying a pursuit born from a plan leaves the rung alone.

The Phase 3 docs that named the removed controls are done in the same
change: wiki `Watchlist.md`, `Release-Tracking.md`,
`Searching-and-Downloading.md`, `Social.md`, `Keyboard-and-Gamepad.md`
(committed in the wiki repo, unpushed), and the in-app guide pages
`watchlist-and-tracking.md` and `release-tracking-and-upcoming.md`, which
were rewritten outright — they still described the pre-v1.17 world (a
*Watch* rung, owned series tracked on their own, Off remembered). What
remains of Phase 3 is the ladder-form wording, which waits on Phase 2.

Phase 0 and Phase 2 wait on decision A (below). Phase 4 waits on Phase 2.

### Audit (2026-09-11)

What already holds since v1.17.0 (`tracking-is-a-persons-act`, completed and
removed — see git history):

* One record per title, `Discovery.TitleIntent`, rung Ignore · List · Follow ·
  Ask · Grab · Default; Off is no record.
* `ReleaseTracking.set_rung/3` is the only write path; a tracked title is
  derived from the rung and nothing in the library scan or import raises one.
* A search-result row adds nothing itself. It opens the title view, and List
  there is the watchlist add.

What still raises a title to Follow or above without a watchlist act:

| # | Control | Where | Sets |
|---|---|---|---|
| 1 | **Download all and track** in the title view's download menu | `components/title/detail_modal.ex`, `live/title_detail_host.ex` (`track` param), `acquisition/plans.ex` (`plan_title/2` `:track`) | Follow |
| 2 | **Watch for releases** / **Watch for release** in the episode picker and the movie confirm | `components/acquisition/plan_modal.ex`, `live/incoming_live.ex` (`plan_track_only`) | Follow |
| 3 | **Also grab future episodes** checkbox in the episode picker | `plan_modal.ex`, `incoming_live.ex` (`plan_toggle_grab_future`), `Plans.Plan.grab_future`, `acquisition/tracking_handoffs.ex` (`maybe_grab_future/1`, called from `Pursuits.Commands.Satisfy`) | Grab, when the download completes |
| 4 | **Track these** on a plan board's missing units | `plan_modal.ex`, `incoming_live.ex` (`plan_track_gaps`), `tracking_handoffs.ex` (`track_plan_gaps/1`), `ReleaseTracking.Wants.open_gap_wants/2`, `Want.provenance :gap` | Follow, plus gap wants |
| 5 | The full ladder on every title view | `components/title/intent_control.ex`, mounted by `title_detail_host.ex` (Discovery, Incoming) and `entity_modal.ex` (Library) | any rung, from a search result or a Feed entry |

The wiki names 1–4 as the exceptions under "Nothing sets this but you"
(`Watchlist.md`, `Release-Tracking.md`).

## Decisions made

* `2026-09-11` — Controls 1–4 go. Each replaces a watchlist act with a
  download side effect. Nothing is lost: the wiki already states that a
  followed series at Ask, Grab or Default wants every episode it is missing,
  so the gap handoff (4) is redundant once the rung is set from the list, and
  "grab future" (3) is the Grab rung. (Owner's direction, this session.)
* `2026-09-11` — The removals follow the no-compatibility rule: `grab_future`
  leaves `acquisition_plans`, `provenance` leaves `release_tracking_wants`,
  `TrackingHandoffs` is deleted. One migration drops both columns in the
  same release as the code, the way v1.17's did; `down` restores the shape.
* `2026-09-11` — No Credo check pinning `set_rung` call sites. After Phase 1
  the callers above List are the two `set_rung` event handlers and showcase
  seeding, and each door has a test that says the rung did not move; a
  check that whitelists modules would be brittle and would not catch a new
  handler added to a whitelisted module.

## Open decisions

Two questions the owner answers before Phase 2 is planned. Both are named
here so the next session does not re-derive them.

**A. What decides whether a title view shows the bookmark or the ladder?**

* *By record* — a title at Off or Ignored shows the bookmark; a title at List
  or above shows the ladder, wherever it was opened. No origin tracking, no
  host split, UIDR-036's "one control" keeps its shape as one control with
  a state-dependent form. From a search result: open, List, then the ladder
  appears. Two acts, in order, visible on the same view. **Recommended**:
  it enforces the order without adding a vocabulary for surfaces, and the
  Library question (B) dissolves — an owned title's view follows the same
  rule.
* *By surface* — surfaces that find titles (search results, the Feed, Friends
  cards, the plan modal) show the bookmark only; surfaces that show the
  watchlist (the Watchlist tab, Coming up, the Library view an owned listed
  title is sent to) show the ladder. Literal reading of "the watchlist is
  the place". Costs: the title view must know which host opened it (Incoming
  opens `?title=` from both search results and Coming up), and two new
  surface classes need names, which is a naming act done with the owner.

**B. Does the Library title view keep the ladder for an owned title that is
not on the list?** Only arises under *by surface*. Recommended yes: an owned
series is the common tracking case ("I have S1–S3, follow new episodes"), and
UIDR-035 already sends an owned listed title to the Library, so the Library
is that title's watchlist view.

## Next steps

Phase 1 is done (see Status). Remaining, in order:

1. **Phase 0 — records.** UIDR-039 amending UIDR-036: one ladder, shown in
   two forms, and a download never moves a rung. Glossary: *bookmark* and
   *ladder* as above; surface names only if decision A picks *by surface*.
   Regenerate `decisions/README.md`.
2. ~~**Phase 1 — the four download-side controls go.**~~ Done 2026-09-11.
3. **Phase 2 — two forms of the control.** Per decision A. `IntentControl`
   gains the bookmark form (List / Off, plus Ignore where the host is the
   Feed); the title view and the Library view choose the form. Story
   variations for both forms (MC0009). Real-browser check and `mc-nav-trace`
   for the control's nav items, since the form change alters the zone's
   item count.
4. **Phase 3 — docs, the rest.** The removed-control mentions are done
   (Status). Left: the bookmark/ladder wording per decision A in wiki
   `Watchlist.md` ("Saving a title", "Tracking") and the guide's "Adding a
   title" / "The Tracking control"; Glossary (*bookmark*, *ladder*).
   CHANGELOG entry at ship names the four removed controls and the two
   dropped columns under *Migration safety*.
5. **Phase 4 — owner check.** Desktop and TV, mouse and gamepad: search a
   title, list it, enable tracking from the watchlist, download from the
   title view and confirm the rung did not move. This absorbs the owner
   check `watchlist-and-release-tracking` left open when it was retired
   (2026-09-11).

## Completion criteria

* No control raises a title to Follow or above except the ladder on a
  title view, and no download moves a rung. `Plans.plan_title/2` has no
  `:track` option; `grab_future` and `Want.provenance` are gone from the
  schema and the database; `Acquisition.TrackingHandoffs` does not exist.
* A title not on the watchlist offers List (and, on the Feed, Ignore) and
  nothing higher; a title on the watchlist offers the whole ladder, per
  decision A.
* UIDR-039 landed; wiki, guide and glossary say what the app does; the
  "Nothing sets this but you" list names only the ladder.
* `mix precommit` green; stories cover both forms of the control.
* The owner has used the flow on the desktop and the TV.

## Pointers

* [ADR-066](../decisions/architecture/2026-09-07-066-one-ladder-per-title.md)
  — one ladder per title; [UIDR-036](../decisions/user-interface/2026-09-07-036-one-control-per-title.md)
  — one control per title (amended by this campaign's Phase 0).
* [UIDR-035](../decisions/user-interface/2026-09-07-035-two-title-surfaces.md)
  — an owned title opens in the Library; the reason decision B exists.
* `ReleaseTracking.set_rung/3` moduledoc — the derivation rule.
* Design of the ladder: `docs/superpowers/specs/2026-09-07-tracking-is-a-persons-act-design.md`.
