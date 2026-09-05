# One-click download from Discovery — design

**Date:** 2026-09-05
**Status:** approved, not yet implemented
**Builds on:** `2026-08-18-watchlist-foundation-design.md`, `2026-09-02-friends-recommendations-design.md`, ADR-056 (release-tracking wants), UIDR-014 (plan flow modal), UIDR-016 (needs attention)

## Glossary

- **Approval policy** — a per-plan value naming who commits the plan once it has solved: `automatic` (the gate commits it when the result qualifies) or `review` (a person approves it on Downloads). Stored on the plan row as `approval_policy`.
- **Clean plan** — a solved plan in which every wanted unit (every unit not excluded) was found within the plan's quality bounds. No gaps, no below-preference units, no pack offers.
- **Download scope** — what a one-click download of a series covers: `first_season` or `everything`. Movies have one scope and the term is not used for them.
- **Title detail modal** — the Discovery page's detail surface for a TMDB title the library does not own. Opened by clicking a feed row or a watchlist row.
- **Follow-up pill** — a sidebar count of items on that page waiting on a decision from the user. Persists until the items are handled, never merely until the page is visited.
- **Condition dot** — a sidebar dot meaning something is wrong right now. Persists until the condition resolves. Distinct from the follow-up pill.
- **Acquisition state** — the derived per-title fact Discovery rows show: none, planning, downloading, needs review, in library.
- **Gate** — `Acquisition.Reactor.Handlers.plan_changed/1`, the one place a plan that has just become `ready` is committed, parked, or discarded.

## Problem

A friend's recommendation on the Discovery feed offers one action, Add to watchlist. Getting the title into the library from there takes a watchlist detour and then the full Incoming plan flow: targeting picker, wait for the solve, review the board, approve. The user wants the common case to be one click: open the recommendation, press Download, close the modal, and have the pursuit start on its own.

Underneath the presentation:

1. The planning system already delegates approval, but only for tracking-born plans, and the decision is derived from the tracked item's auto-grab mode at gate time rather than recorded on the plan.
2. Discovery has no detail surface for a title the library does not own. The watchlist row links out to the Incoming picker instead.
3. A plan that needs a person's decision is invisible unless the user happens to be on Incoming. The sidebar has counts for Review and Status but nothing for Incoming, and the two existing counts follow different rules.

## Decisions

### Approval policy

1. **`approval_policy` is a column on `acquisition_plans`**, string, values `automatic` and `review`, stamped at creation for every plan. It is never derived from origin at read time.
2. **Who stamps what.** The drop planner stamps from the item's effective auto-grab mode: `ask` gives `review`, every other non-off mode gives `automatic`. Plan-now drafts (`DropPlanner.plan_item_now/2`) and picker drafts (`create_series_plan/3`, `create_movie_plan/2` via Incoming) get `review`. One-click downloads get `automatic`.
3. **The gate reads only the column** for the approve-or-park decision. Its clauses, in order, for a plan that has just become `ready`:
   - Tracking plan with zero found units: delete the draft (unchanged).
   - Tracking plan whose item's effective mode is now `off`: discard (unchanged). This is the one remaining live read, kept because off is a kill switch, not a policy.
   - `review`: leave it `ready`. The draft card on Downloads is the review surface.
   - `automatic`, origin `tracking`: approve when at least one unit was found (unchanged). The want ledger retries the remainder on the next tick.
   - `automatic`, origin `manual`: approve only a clean plan. Anything else stays `ready` for review, because nothing retries a manual plan's remainder.
4. **Clean is decided from the units**, not from the board view-model: every unit with status other than `excluded` has status `found`. `Plans.Board` already computes `wanted` and `covered` the same way; the gate uses the units directly so `Acquisition` does not depend on a view-model.
5. **A flip from ask to an auto mode during a solve is accepted drift.** The parked draft waits for a click. `ModeReconciler` continues to own parked drafts of items flipped to off.
6. **Approval rejections** (`{:overlap, units}`, `:nothing_to_grab`) on an automatic manual plan leave the plan `ready` with the rejection logged, so the draft card shows it. A tracking plan keeps discarding on rejection (unchanged).

### Download scope for series

7. **The Download control on a series is a split button.** The main segment reads "Download season 1"; the chevron segment opens a menu with one item, "Download all". Copy is settled with the writing-copy skill at implementation.
8. **First season** means the lowest season number of 1 or higher that has at least one aired episode not in the library and not tracked, and covers exactly those episodes of that season. Specials (season 0) are never part of a one-click scope. No tracking is started.
9. **Everything** means every aired episode not in the library and not tracked (`Targeting.default_units/1`), then release tracking is started for the title (`ReleaseTracking.track_from_search/2` with the default "all upcoming" options) so new episodes follow. The plan is created before tracking so its units are not excluded as tracked. Tracking an already-tracked title is a no-op.
10. **The menu reuses the library sort dropdown idiom**: LiveView-owned open state, `glass-surface` menu, a highlight index for keyboard and gamepad. The split button is two nav items: the main segment and the chevron. Opening the menu adds one nav item.
11. **A multi-season everything plan will often not be clean.** It parks for review and the follow-up pill and row decoration say so. This is the intended outcome, not a failure.

### Title detail modal

12. **One modal serves both Discovery tabs.** A `CinematicShell` tenant opened by a whole-card click on a feed row or a watchlist row. Rendered from the embedded `TMDB.Title` snapshot: backdrop from `backdrop_path`, lockup from `name`, year, media type, overview. On a feed row it also shows the sender and their note. No network call on open.
13. **Actions are the watchlist row's three-state logic lifted into the modal**, plus the secondary:
    - Library owns the title: "In library" links to the library detail.
    - Released and an indexer is ready (`Capabilities.prowlarr_ready?/0`): Download (split for series, plain for movies).
    - Otherwise: "Track release" (existing `watchlist_track` behaviour).
    - Secondary: "Add to watchlist", replaced by a quiet "On watchlist" once saved.
14. **Rows stop carrying actions.** The feed row and the watchlist row become identity plus state (sender, note, acquisition state) with the whole card as the click target. The watchlist row's link to the Incoming picker is removed. The Remove and Delete verbs move into the modal as quiet tertiary actions.
15. **Open state is URL-driven**, `?title=<media_type>-<tmdb_id>` on the current tab, the same idiom as the tracking title modal's `?title=` and the pursuit modal's `?selected=`. Refresh keeps the modal open; back closes it.
16. **Nav wiring.** The modal is a nav overlay with one body region. Every control in it is a nav item. Closing returns focus to the row that opened it (existing `CinematicShell` behaviour).

### The click path

17. **Download closes the modal, flashes, and calls one Acquisition function.** `Acquisition.Plans.download_title/2` takes a `TMDB.Title` and options `scope: :first_season | :everything` (series only). Movies create the plan synchronously with `approval_policy: "automatic"`. Series run on the context task supervisor (`MediaCentaur.TaskSupervisor`, the `track_from_search_async/2` pattern), because targeting needs a TMDB fetch that must outlive the LiveView. Returns `:ok` once the work is queued or done.
18. **Flash copy** names the wait honestly, in the form "Finding a release for <title>". The pursuit exists when the solve finishes, seconds later, not at modal close.
19. **Failures inside the async series path** (TMDB unreachable, no units in scope) log at warning on `:acquisition` and leave no plan. The row's acquisition state stays none. A later click retries.

### Acquisition state on Discovery rows

20. **`Acquisition.title_state/2`** returns the per-title fact for `(tmdb_id, tmdb_type)`: `:planning` (a draft in `planning`), `:needs_review` (a draft in `ready`), `:downloading` (a pursuit in flight), or `nil`. `Plans.Claims` and the existing draft and pursuit queries are the read seams. The Discovery page reads it for every row in one query per load.
21. **Rows and the modal render the state** as plain text in the markers slot: "Planning", "Downloading", "Needs review" (a link to `/incoming`). "In library" stays the library-derived state and wins over all of them.
22. **DiscoveryLive subscribes to `acquisition:updates`** and re-reads acquisition state on `PlanEvents.Changed` and pursuit events. This is the pursuit-in-flight decoration the watchlist foundation deferred.

### Follow-up pill

23. **The sidebar has two named idioms and no others.** The follow-up pill (a count, persists until the items are handled) and the condition dot (persists until the condition resolves). Every current badge maps to one of them:
    - Incoming: follow-up pill, count of plans in `ready` (new).
    - Review: follow-up pill, pending files plus mappings (existing count, new variant).
    - Status: follow-up pill, unseen incidents (existing count); condition dot, error buckets (existing dot).
24. **One component renders every follow-up pill**, one variant (`error`), one size. Expanded rail: count at the row's end. Collapsed rail: count at the icon's corner, so the pill survives both rail widths. The Status count badge and the Review count badge are replaced by this component.
25. **The pill is domain state, not attention tracking.** It counts what is waiting regardless of which page or modal is open. On Incoming with the plan modal open it shows 1 on the highlighted entry and drops on approve. This is the rule Review follows today and it avoids a second source of truth about what the user is looking at.
26. **`ShellBadges` gains the source.** A new count `plans_awaiting_review` from `Plans.count_awaiting_review/0`, refreshed on `PlanEvents.Changed` via the existing `MediaCentaur.Cache` projection. The moduledoc's "one concept, four counts" becomes the two-idiom vocabulary above.
27. **The convention is a UIDR.** "Follow-up pill and condition dot" records the two idioms, the persistence rules, the one-variant decision, and the rule that a new page with pending decisions adds a source rather than new chrome.

## Rejected

- **Auto-approving partial manual plans.** A committed plan drops its unfound units silently; only tracking has a ledger that retries.
- **A live TMDB fetch on modal open** for tagline, cast, facets. The snapshot answers "what is this and do I want it". Depth belongs to the library detail once the title lands.
- **Making the pill aware of the open modal.** Second source of truth.
- **A second colour for non-fault follow-ups.** One idiom, one variant. Revisit only if the red Review count proves too loud in daily use.
- **Adding the recommendation id to the plan.** No reader needs it; the watchlist item already carries provenance.
- **Auto-adding a downloaded title to the watchlist.** A pursuit is stronger intent than a watchlist entry; the row flips to In library when the file lands.

## Data changes

- Migration: add `approval_policy` (string, not null, default `review`) to `acquisition_plans`. Existing rows are all either committed, discarded, or user-facing drafts, so `review` is correct for every one. Paired with a data-safe rollback per the release convention.
- No other schema change. Download scope is an argument, not a column.

## Testing

- Gate: manual plan with `automatic` commits when clean, parks when a unit is unfound, parks when only below-preference candidates exist, parks on overlap rejection; `review` never commits; tracking rules unchanged (existing tests still pass).
- `download_title/2`: movie creates an automatic plan; series `first_season` picks the right season and skips specials, library episodes, and tracked episodes; `everything` creates the plan then tracks; TMDB failure leaves no plan and logs once.
- `title_state/2`: each state from fixture rows; `nil` when nothing is in flight.
- DiscoveryLive: card click opens the modal with the URL param; the action matrix (in library, download, track, watchlist states); Download closes the modal and creates the plan; split menu opens and fires; decoration updates on `PlanEvents.Changed`.
- ShellBadges: Incoming count follows plan status transitions; the component renders both rail modes.
- Stories: title detail modal (each action state), follow-up pill (expanded and collapsed), split button (closed and open).
- Real-browser verification of the card click, the split menu, and the collapsed-rail pill before the work is called done.

## Documentation

- Wiki: Discovery page (modal, one-click download, download scope), Downloads page (drafts parked for review, the Incoming pill), Keyboard-and-Gamepad (split button), Settings reference unchanged.
- UIDR for the follow-up pill and condition dot; `decisions/README.md` regenerated.
- ADR-056 gets a note pointing at the approval policy column.
- Moduledocs: `Plans.Plan`, `Reactor.Handlers`, `ShellBadges`, `DiscoveryLive`, the new modal and pill components.
- `docs/GLOSSARY.md` receives the glossary terms above.
