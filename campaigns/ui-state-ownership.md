---
status: in-progress
started: 2026-09-28
last_updated: 2026-09-28
---
# UI state ownership: one owner per kind of state, one mechanism per idiom

## Glossary

* **Round trip.** One client event sent to the LiveView process, plus the
  diff it sends back.
* **Owner.** The one place a piece of UI state is held and changed. Every
  other appearance of it is a rendering of that value.
* **JS command.** A `Phoenix.LiveView.JS` operation that runs in the browser
  without a server event. LiveView keeps its DOM changes across later
  patches ("sticky"), keyed by element id.
* **Nav graph resync.** The input system rebuilding its zones and
  reconciling focus (`_syncState`, `_reconcileFocus`). It runs only from the
  LiveView hook's `updated()` (`assets/js/input/index.js`), so a change made
  by a JS command does not trigger it. Nav items inside an existing zone are
  queried live and filtered by visibility, so showing or hiding items there
  works without a resync. Creating a zone or a modal does not.
* **Disclosure.** A head that shows or hides a body (WAI-ARIA disclosure
  pattern). The input system's TREE navigation reads its state from
  `aria-expanded` on the head and its extent from `data-nav-group`.
* **Arm gesture.** MC0027's inline two-click confirmation, drawn by
  `armed_button`. The first click arms; the second click on the same button
  fires; any other interaction disarms.

## Goal

A review on 2026-09-28 of every `handle_event` in `lib/media_centaur_web/`
asked which interactions should move to front-end JavaScript. It found that
very few should, and that the real problem is different. The same UI idioms
(disclosures, arm gestures, text-input events, filters) are implemented once
per page, each with its own state names and rules. That duplication is where
the bugs are. This campaign gives each kind of UI state one owner and each
idiom one mechanism, and fixes the bugs the review found.

## Status

In progress on branch `ui-state-ownership` (worktree
`../media-centaur-app-ui-state`, isolated from other agents working in the
main checkout). Design approved 2026-09-28. Phases 1 to 3 done; Phase 4
next. Line numbers are
from commit `d7ecc8b5` and will drift.

## Design (approved 2026-09-28)

### Core idea

Every piece of UI state has one owner, chosen by what the state is:

| State | Owner | Examples |
|---|---|---|
| Where the user is | URL | page, tab, filter, sort, open title, drill-in |
| What is rendered, or what a handler reads | LiveView process | disclosures, arm gestures, open menus and modals, selection, loaded pages |
| Device and viewport | Browser | focus position, scroll, hover, input method, sidebar collapse |

The browser never decides what is rendered. This matches the input system,
which learns about structure only from patches, and the app's deployment:
one user on localhost, so a round trip costs a local render, not network
latency. Each recurring idiom is one component plus at most one shared hook,
not one implementation per page.

### Disclosures

**Today, three mechanisms:**
* *Server-owned toggles with `:if`*, about eight state sets under different
  names (`expanded_seasons`, `expanded_item_details`, `expanded_file_groups`,
  `board_expanded_seasons`, `plan_expanded_seasons`,
  `expanded_pursuit_groups`, `expanded_group`, `opened_people`), each with
  its own handler. Only `season_list.ex`, `manage_panel.ex` and
  `health_components.ex` render `aria-expanded`, so TREE LEFT/RIGHT works on
  those and nowhere else.
* *Native `<details>`*, 11 sites including the Settings kit's
  `settings_disclosure`. Browser-owned. **Confirmed bug:** a LiveView patch
  closes a user-opened `<details>`. On `/status?subsystem=pipeline`, opening
  `#subsystem-logs` and waiting 25 s, the next patch collapsed it. No site
  uses `JS.ignore_attributes`. The `<summary>` heads carry no `aria-expanded`.
* *JS commands*, one site: the subtitle language fold
  (`detail/subtitles_row.ex:64`). It hides a focused nav item and leaves
  focus on it.

**Greenfield:** one `<.disclosure>` function component, owned by the
LiveView. The head renders `aria-expanded`, `data-nav-group`, the chevron
and one toggle event. The body is behind `:if`, so a long season list costs
nothing while closed. A shared `attach_hook` holds the open set for the page
and handles the toggle event, so most hosts write no handler. A host whose
other handlers read the state keeps its own set and passes it in:
`Title.ModalState` resets on subject change, and `SearchSession` persists
Incoming's result groups across navigation. The owner is the LiveView in
both cases. `settings_disclosure` is rebuilt on it.

**Rejected alternative:** browser-owned `<details>` everywhere. It needs
`JS.ignore_attributes(["open"])` on each site, a change to the orchestrator
so TREE reads `details[open]`, and every body rendered up front. It still
cannot serve the host-read cases, so a second mechanism would remain.

**Cost:** about 20 sites across 10 files, their stories, and tests. It is
larger than moving four toggles to JS, and it removes three mechanisms
instead of adding a fourth.

### Arm gestures

**Today:** one component (`armed_button`) but about a dozen state assigns
(`delete_confirm`, `dismiss_confirm`, `remove_confirm`,
`controls_reset_armed`, `cancel_armed_id`, `dismiss_all_armed`,
`confirming_image_refresh`, `cancel_pursuit_armed`, `cancel_confirm`,
`media_dir_delete_confirm`, `rematch_confirm`, `plan_discard_armed?`,
`import_armed?`) and at least five disarm rules:
* Incoming: a hook disarms on any other event
  (`disarm_gestures_on_other_events`, `incoming_live.ex:184`), but it
  misses `cancel_pursuit_armed`.
* Watch history: disarms on reload.
* Review: disarms on `select_item`.
* Reconcile: does not disarm on selecting another show, so Dismiss all
  armed on one show fires on the next.
* Settings: never disarms.

Hand-rolled armed buttons remain in `detail/manage_panel.ex` and
`settings_live/social_section.ex`.

**Greenfield:** one armed slot per LiveView. The slot holds nothing, or the
fire event plus its target. A shared hook, generalised from Incoming's,
disarms on every event except that gesture's own arm and fire, and on
`handle_params`. `armed_button` takes the slot and its own key. One gesture
can be armed at a time, which the "any other interaction disarms" rule
already implies.

**Cost:** about 15 sites. It fixes the Reconcile and Settings bugs by
construction.

### Text-input events

**Today:** the review found four text or range inputs without
`phx-debounce` (not a full count): Incoming
history search (SQL per keystroke), Settings ignore rule (`Repo.all` per
keystroke), Review search (a `File.dir?` probe per keystroke), and the
Console buffer slider (a stream reset per step). Settings media-dir
validation hand-rolls a server debounce with `Process.send_after`.

**Greenfield:** `phx-debounce` is the only debounce, enforced by a Credo
check. A text, search or range input that sends `phx-change` or `phx-keyup`
must carry `phx-debounce`, or be exempted with a comment. The existing checks
that scan HEEx for raw button classes are the precedent.

### Console search

**Today, two owners:** the `ConsolePage` hook hides rows in the browser by
`data-message`, and the Console Buffer stores the query for copy, download,
reload and the insert gate. The hook header gives the reason: resetting a
stream of thousands of rows per keystroke is a large diff. The server copy
has drifted. `Logic.set_search/2` never recomputes `search_lower`, so copy,
download and the insert gate match a stale query. Nothing visible exercises
the server copy, so nobody noticed.

**Greenfield:** one owner. The rows are already in the DOM and the stated
diff-size reason holds, so the browser owns it. The server drops `search`
from the filter. Copy and download receive the query in their event payload.
Reload persistence moves to `localStorage`, which the app already uses for
per-viewer state such as the sidebar. The alternative is server ownership
with a stream reset per debounced change.

### Kept as they are, with the reason

* **Glass menus and modals** stay LiveView-owned. Opening one creates a nav
  zone or a modal context, which needs a resync, and BACK pushes their close
  events to the server.
* **The Library filter and the cast filter** stay on the server. The
  server's visible set decides PubSub inserts, and a client-side cast filter
  was measured at 1.6 MB of HTML (`CastSelection` moduledoc).
* **Handlers that only `push_patch`** stay. A `<.link patch>` would save one
  local hop. Either way the URL is the single owner, so no state is
  duplicated.
* **Relative-time labels** refresh on re-render. `time_ago/1` already
  delegates to `Format.relative_ago/2`. A page that needs a live clock ticks
  only while the label is on screen, so the Settings tick is scoped to the
  System section.
* **No client-side resync signal for the input system.** Under the ownership
  rule, nothing browser-owned changes navigable structure.

## Decisions made

* `2026-09-28` — Review of all `handle_event` handlers complete. It found few
  presentation-only events worth moving, two confirmed bugs, three
  unverified bugs, three dead handlers, and several avoidable round trips.
* `2026-09-28` — The first plan moved four toggles to JS commands. The
  design pass replaced it: those moves would have added a fourth disclosure
  mechanism and a second owner for disclosure state.
* `2026-09-28` — **Owner approved the design and all four recommendations:**
  the ownership rule (nothing moves to JS commands); disclosures owned by the
  LiveView through one component; console search owned by the browser, with
  the query passed to copy and download; a Credo check enforces
  `phx-debounce`.
* `2026-09-28` — Phase 1: dead `change_target` handler removed, but the
  `ChangeTarget` command it called is left in place. The owner kept it on
  purpose in `8ab1ec7f`, so its retirement is the owner's call (Phase 1
  leftover).
* `2026-09-28` — Phase 2 as built. `Live.ArmGesture` is registered first in
  the `:default` live session's `on_mount`, so its `handle_event` hook runs
  before every page's own hooks (the title detail host's included). A
  gesture sends one event; `ArmGesture.press/3` answers arm or fire. The
  Settings Confirm/Cancel swaps (media directory, image refresh) and the
  Manage sheet's Delete-all Cancel are gone: any other interaction disarms.
  The identity import arms on the pasted secret, so editing it between the
  clicks re-arms. The idle import button is `risky`, not `neutral`, since
  `armed_button` has no neutral variant.
* `2026-09-28` — **The Manage sheet's three delete buttons keep their own
  markup.** They share the slot and the rule, but they draw a third state
  (*Deleting…* while the async delete runs) and a row tint that
  `armed_button` does not. Scheduled convergence: `armed_button` gains a busy
  state, then the three buttons move onto it (Phase 3b or later, named here
  so it is not orphaned).
* `2026-09-28` — Phase 3a as built. A disclosure body renders only while
  open, so tests that read a collapsed body now open it first (Status logs,
  the plan board, Settings' secret key). The subtitle fold is not a
  disclosure (a one-way reveal whose head is its content), so it keeps its
  own markup; only its owner moved. The `.settings-disclosure` CSS became
  `.disclosure-head[aria-expanded="true"] .disclosure-caret`.
* `2026-09-28` — Seen during Phase 3a, not caused by it:
  `Nostr.ConnectionTest` "the first failed attempt logs once" failed once
  under full-suite load (the line never reached `capture_log`) and passed
  six times alone. A log-capture race; left to its owner.
* `2026-09-28` — Phase 3b as built. **Where no other handler read a
  disclosure's state, the page's `DisclosureState` took it over** and the
  host's assign and handler went (unit board, plan seasons, pursuit groups,
  Review files). Ids carry the owning record (pursuit, title) because a
  page-level id outlives the record it was opened on. Pursuit groups also
  lose a `String.to_existing_atom/1` on a client value.
* `2026-09-28` — **Two title-detail disclosures keep their own markup.**
  The Manage ledger's folder head is a nav item that owns a sub-item
  (Delete), and the input system finds sub-items inside the focused item,
  so the head cannot be a `<button>`. The episode details toggle is a
  sub-item inside an episode row whose body sits below the row. Both
  already follow the contract (`aria-expanded`, `data-nav-group`).
* `2026-09-28` — **`ModalState` keeps its per-kind sets.** Folding seasons,
  details and file groups into one toggled-over-default set was considered
  and declined: a season's default is the oriented season, which can move
  during an opening (playback advances it), and a toggle recorded against
  the old default would then invert. The per-opening sets do not have that
  failure.
* `2026-09-28` — The Playwright spec `detail-backdrop.spec.js` selected the
  season header by its chevron icon and would have skipped silently; it
  reads `aria-expanded` now.

## Next steps

### Phase 1 — Bugs and dead code (done 2026-09-28)

Done: the Controls remap crash, the Review type mismatch (it had a second
path: a tied candidate for a TV file was saved as a movie, and the chooser's
cards shared one DOM id), and the three dead handlers. Left for the owner:

1. **`Pursuits.Commands.ChangeTarget` has no caller.** Commit `8ab1ec7f`
   removed the UI verb and kept the command "for programmatic pivots (worker
   fallback)". No worker calls it now; its only caller was the dead
   `change_target` handler, removed here. `PursuitStatus` still offers
   `:change_target` in `available_actions`, and no component renders it.
   Retire the command, the action and their tests (keeping the rendering of
   historical `target_changed` events and the `replaced_by_user_pivot` cancel
   reason), or name the caller it is waiting for.

### Phase 2 — Arm gestures (done 2026-09-28)

One slot, one shared hook, one rule, as designed above. Regression tests for
the Reconcile leak and the Settings never-disarm cases. Move the hand-rolled
sites onto `armed_button`. Incoming's hook is removed in favour of the shared
one.

### Phase 3a — The component and the browser-owned sites (done 2026-09-28)

`Components.Disclosure.disclosure/1` (story under `core_components`) and
`Live.DisclosureState` (an `on_mount` on the `:default` live session: the
set of ids the user toggled; open is the default flipped by it). Every
native `<details>` is gone: Status' technical logs, recent requests and
release history; the plan board's How we searched; Settings' secret key
(`settings_disclosure/1` removed from the kit), Prefer the terminal?, the
media directory dialog's Advanced (`keep_body`, its field must submit);
the report modal's final text (a LiveComponent, so it keeps its own set).
Show service details is host-owned (its first open runs `systemctl`). The
subtitle fold is per-opening state (`ModalState.all_subtitles`). Verified
in a browser on a worktree server (showcase data, port 4003): the recent
requests list stayed open through 174 DOM mutations from strip-chart ticks,
the logs panel through a patch, and Enter on a focused head toggles it.

### Phase 3b — Host-owned disclosures onto the component (done 2026-09-28)

Page-owned now (the host's assign and handler removed): the unit board's
season groups (id per pursuit and season, `expanded_default?` as the
default), the plan picker's seasons (id per title), pursuit groups on
Activity and History (`Logic.pursuit_group_id/1`), the Review file list.
Host-owned on the component: the Status journal, Incoming search groups
(`SearchSession`), the title detail's seasons (`ModalState`). The
component gained `:leading` / `:trailing` slots, `row_class` and
`caret_class`. `armed_button` gained `busy` / `busy_label` and `nav`, and
the Manage sheet's three delete buttons moved onto it.

### Phase 4 — Input events and round trips

1. Debounce Credo check, then the four undebounced sites, then the
   hand-rolled media-dir debounce.
2. Console search to its one owner. This also removes the stale
   `search_lower` bug.
3. Discovery "N new": scroll on the client and let `feed_at_top` land the
   queue, instead of two projections per click.
4. Incoming "Show all" (`expand_shelf`): re-cap from the held feed instead
   of `build_view`, which re-reads the database.
5. `setup:dismiss_banner`: assign directly instead of re-running every
   setup probe. Check the "called after any config save" comment on
   `assign_setup_banner_state`.
6. Scope the Settings `:refresh_update_schedule` tick to the System section.

### Owner check

Keyboard and gamepad pass over every changed surface on the dev server,
including BACK and TREE LEFT/RIGHT inside each disclosure.

## Completion criteria

* Each idiom (disclosure, arm gesture, text-input debounce, console search)
  has one owner and one mechanism in the code, and no page-specific variant
  remains.
* The confirmed bugs have regression tests: the Controls remap crash, the
  `<details>` collapse, the stale console search, the Reconcile arm leak and
  the Settings never-disarm.
* The three dead handlers are removed.
* The debounce rule is enforced by Credo, or declined in Decisions made.
* `mix precommit` passes. The wiki is updated for any user-visible change,
  and the new vocabulary is added to `docs/GLOSSARY.md`.

## Pointers

* `docs/input-system.md`: DOM contract, focus memory, post-patch
  reconciliation, single-owner projection.
* `credo_checks/native_confirm_dialog.ex` (MC0027): the arm gesture rule.
* `lib/media_centaur_web/components/core_components.ex`: `armed_button`.
* `lib/media_centaur_web/components/settings.ex`: `settings_disclosure`
  (UIDR-041).
* `assets/js/hooks/console_page.js`: the client half of the console search.
