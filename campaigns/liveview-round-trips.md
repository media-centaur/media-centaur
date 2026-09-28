---
status: planning
started: 2026-09-28
last_updated: 2026-09-28
---
# LiveView round trips: fix, trim, move, or keep

## Glossary

* **Round trip.** One client event sent to the LiveView process, plus the
  diff it sends back.
* **Presentation-only event.** A `handle_event` whose handler only sets
  assigns that no other server code reads. It makes no write, no process
  call, no broadcast and no data load.
* **JS command.** A `Phoenix.LiveView.JS` operation that runs in the browser
  without a server event. LiveView keeps its DOM changes across later
  patches ("sticky"), keyed by element id.
* **Nav graph resync.** The input system rebuilding its zones and
  reconciling focus (`_syncState`, `_reconcileFocus`). It runs only from the
  LiveView hook's `updated()` (`assets/js/input/index.js`), so a change made
  by a JS command does not trigger it. Nav items inside an existing zone are
  queried live and filtered by visibility, so showing or hiding items there
  works without a resync. Creating a zone or a modal does not.
* **Armed button.** MC0027's inline two-click gesture. The first click sets
  an armed flag, and the server's fire handler checks that flag before the
  destructive step.
* **Disarm on other event.** `IncomingLive`'s `handle_event` hook
  (`disarm_gestures_on_other_events`) that clears armed flags on any server
  event other than the gesture events. An event that moves to the client no
  longer passes through it.

## Goal

Act on the 2026-09-28 review of every `handle_event` in
`lib/media_centaur_web/`. The review asked which LiveView interactions should
move to front-end JavaScript. It found that very few should, because the app
runs on localhost for one user, and because the input system depends on
server patches. It also found two confirmed bugs, several unverified ones,
dead handlers, and round trips that are cheaper to fix on the server. This
campaign fixes the bugs, trims the round trips, and moves the four clean
candidates to JS commands.

## Status

Planning. The review is complete; no code has changed. Line numbers below are
from commit `d7ecc8b5` and will drift.

## Decisions made

* `2026-09-28` — **LiveView stays the default owner of UI state.** Latency
  and per-connection memory, the usual reasons to move state to the client,
  do not apply to a single-user localhost app. A move to JS commands must
  have a presentation-only event, markup that can be rendered up front, and
  no dependence on a nav graph resync.
* `2026-09-28` — **Kept on the server, with the reason, so later sessions
  don't re-litigate them:**
  * *Glass menus* (Library sort, title-detail Download mode and scope, the
    plan's Download split menu). Opening one creates a nav zone, and BACK
    and click-away push `close_sort` / `download_menu_close` /
    `plan_menu_close` to the server.
  * *Modals* (`Components.Modal` tenants). `data-detail-mode`, the Escape
    binding and the backdrop close are computed on the server from `open`,
    and entering the modal context needs a resync.
  * *Armed buttons.* The flag is the server's guard for the fire handler.
  * *URL-driven state* (tabs, filters, drill-ins, `?view=`, `?title=`).
  * *Library filter and sort.* `visible_ids` decides whether a PubSub update
    inserts or deletes a card, and the URL carries the filter.
  * *Cast filter.* The `CastSelection` moduledoc records that the client-side
    version shipped 1.6 MB of HTML for an 899-member cast.
  * *Console component and level filters.* Excluded entries never leave the
    buffer by design.
  * *Discovery person card open* (`toggle_person`) and *Apps manage mode*
    (`toggle_manage`, `set_add_tab`). Both add or remove nav items that need
    a resync.
  * *Incoming `toggle_group`.* It is persisted in the `SearchSession`
    singleton so expansion survives navigation and reconnect.
* `2026-09-28` — **A client-side resync signal for the input system is not
  built.** It would unlock the menus and the title-detail disclosures, but it
  splits state ownership against the single-owner projection rule in
  `docs/input-system.md`. Revisit only if the owner asks.

## Next steps

### Phase 1 — Bugs

1. **Controls remap crash (confirmed by reading).** `controls:listen`
   replies with `push_event("controls:listen", %{kind: kind})` and omits
   `id` (`settings_live.ex:1309`). The client destructures `{kind, id}`
   (`assets/js/input/index.js:137`) and pushes `controls:bind` with no id.
   The only `controls:bind` clause requires `"id"`, so the LiveView should
   crash. The tests call `render_hook` with an id and miss it. Reproduce in
   the browser first, then write a test through the listen path.
2. **Console search matches a stale query (confirmed by reading).**
   `Logic.set_search/2` (`console_page_live/logic.ex:84`) sets `search`
   without recomputing `search_lower`, which `Filter.search_passes?` reads.
   New-entry gating, copy, download and the first paint after reload use the
   old query. `View.only_search_query_differs?` hides it. Route the update
   through `Filter` so `search_lower` can't be set apart from `search`.
3. **Verify, then fix:**
   * Reconcile: `select/2` does not reset `dismiss_all_armed`, so Dismiss all
     armed on one show fires on the next.
   * Review: changing the type select after a search sets `search_type`, but
     the results are still of the old type; `select_match` then saves the
     new `tmdb_type` against a TMDB id of the old type.
   * Settings: `controls_reset_armed`, `confirming_image_refresh` and
     `media_dir_delete_confirm` are never cleared, so a button stays armed
     after the user leaves the section and returns.
4. **Delete dead handlers.** `change_target` in `IncomingLive` (no emitter;
   `PursuitModal`'s `on_change_target` defaults to `request_decision`),
   `setup:test_connection` in `SetupLive`, and `delete_cancel` in
   `ReviewLive`. Confirm no emitter with grep before each removal.

### Phase 2 — Trim round trips on the server

1. **Add debounces.**
   * Incoming history search (`set_history_search`, `incoming/ledger.ex`)
     runs SQL per keystroke.
   * Settings ignore rule (`ignore_rule:validate`) runs
     `Library.Files.all_linked_paths/0`, a `Repo.all`, per keystroke. Its
     comment at `settings_live.ex:1782` understates this; correct it.
   * Review search (`update_search`) re-renders the detail panel, including
     a `File.dir?` probe, per keystroke.
   * Console buffer size (`resize_buffer`) resets the stream on every slider
     step.
2. **Replace the hand-rolled media-dir debounce** (`Process.send_after` plus
   `cancel_timer`, `settings_live.ex:2866`) with `phx-debounce`.
3. **Console search.** The browser already hides rows (`ConsolePage` hook).
   The server keeps the query only for reload persistence and copy/download.
   Send it on blur or carry it in the copy and download events, instead of a
   `GenServer.call` plus broadcast per keyup. Depends on Phase 1 step 2.
4. **Discovery "N new".** `feed_show_new` projects, pushes a scroll, and the
   scroll makes `FeedHead` push `feed_at_top`, which projects again. Scroll on
   the client and let `feed_at_top` land the queue.
5. **Incoming "Show all"** (`expand_shelf`) calls `build_view`, which re-reads
   releases from the database. Re-cap from the feed already held.
6. **Settings `:refresh_update_schedule`** runs every 60 s on every section
   to recompute two labels. Scope it to the System section or format the
   times on the client from a timestamp.
7. **`setup:dismiss_banner`** re-runs every setup probe to compute `false`.
   Assign it directly; check whether `assign_setup_banner_state` still has
   the "after any config save" caller its comment claims.
8. **Optional, low value.** Handlers that only `push_patch` (`switch_zone`,
   `resume_plan`, `select_pursuit`, `setup:back`, `setup:skip_tour`,
   `open_person` as `JS.navigate`) could be `<.link patch>` from the markup,
   saving one hop each. Do it only where a file is already being touched.

### Phase 3 — Move to JS commands

Each move renders the hidden markup up front with a stable id, toggles it
with `JS.toggle` / `JS.toggle_attribute`, and moves chevrons and labels to
CSS keyed on `aria-expanded`. If the focused element can be hidden, the move
must place focus itself (`JS.focus`), because no resync will.

1. **Review file list** (`toggle_files`, `review_live.ex:301`). Cleanest
   case. Give the list a per-group id so sticky state doesn't carry to the
   next group. `expanded_group` is also never set in mount.
2. **Pursuit unit board season** (`toggle_board_season`,
   `incoming_live.ex:1824`). The groups already have stable ids. The
   server-side default (`expanded_default?`) becomes the initial `hidden`.
3. **Plan targeting season expand** (`plan_toggle_season_expand`,
   `incoming_live.ex:1274`). Needs an id on the episode `ul`.
4. **Omnibox upcoming/released scope** (`omnibox_scope`,
   `incoming_live.ex:1632`). The only filter over data already on the page.
   Needs a data attribute on the section, CSS filtering, and a CSS-driven
   empty state and count.
5. **Subtitle languages fold** (`detail/subtitles_row.ex:64`). Already a JS
   command, but it hides a focused nav item and leaves focus on it. Add the
   focus move.

For items 2 to 4, decide how each keeps disarm on other event: either the
toggle also pushes a no-op, or the armed flags are cleared some other way.
Record the choice here.

### Owner check

Run through each changed surface with keyboard and gamepad on the dev
server, including BACK from inside each moved disclosure.

## Completion criteria

* Phase 1 bugs fixed with a regression test each, or recorded here as not
  reproducible.
* The three dead handlers removed.
* Every Phase 2 item done or declined with a reason in Decisions made.
* The four Phase 3 candidates moved, or declined with a reason.
* `mix precommit` passes; wiki updated for any user-visible change.

## Pointers

* `docs/input-system.md` — DOM contract, focus memory, post-patch
  reconciliation, single-owner projection.
* `credo_checks/native_confirm_dialog.ex` (MC0027) — the armed-button rule.
* [ADR-044](../decisions/architecture/2026-05-14-044-no-blocking-io-in-liveview-handlers.md)
  — no blocking IO in LiveView handlers.
* Existing JS-command precedent: `acquisition/needs_attention.ex`
  (`JS.toggle_attribute` pin), `detail/subtitles_row.ex` (`JS.show`/`JS.hide`).
