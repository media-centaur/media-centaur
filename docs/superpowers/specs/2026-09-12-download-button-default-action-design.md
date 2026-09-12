# Download button default action — design

Date: 2026-09-12. Builds on the one-click download spec
(`2026-09-05-one-click-download-design.md`), which introduced the
approval policy column and the split Download control this spec
replaces. Revised the same day after a unify_design pass (see
"Coherence pass" at the end) and once more for the owner's preference
for named modes over a boolean (decision 9).

## Glossary

- **Approval policy** (existing) — the per-plan value naming who commits the plan once it has solved: `automatic` (the gate commits a clean plan) or `review` (a person approves it on Incoming). Column `approval_policy` on `acquisition_plans`.
- **Clean plan** (existing) — a solved plan in which every wanted unit was found within its quality bounds. The only kind an `automatic` manual plan commits.
- **Plan board** (existing) — the live display of a draft plan on Incoming, opened by `?plan=<id>`: episode grid, kept releases, the swap picker per episode, exclude, offers, Approve plan.
- **Download scope** (existing) — what a series Download covers: `first_season` or `everything`. Movies have one scope.
- **Planning mode** — what the Download button does when pressed: *auto-select best release* or *manually select release*. One of the two is the person's default, held by the default planning mode preference; the other is in the button's menu.
- **Auto-select best release** — the planning mode (`:auto_select_best_release`) that creates the plan with approval policy `automatic`, closes the modal and flashes. A clean plan commits with nobody looking; anything else parks on Incoming.
- **Manually select release** — the planning mode (`:manually_select_release`) that creates the plan with approval policy `review` and lands the person on its plan board, where they swap, exclude and approve.
- **Default planning mode** — the Settings entry naming the person's default planning mode. Key `default_planning_mode`; absent means manually select release. `Settings.Preferences.PlanningMode`.
- **Glass menu** — the house dropdown idiom (`.glass-menu*` in `app.css`): a trigger with a chevron and an anchored glass list beneath it, open state owned by the LiveView. `MediaCentaurWeb.Components.GlassMenu` is its component module.
- **Menu list** — the anchored list itself: `GlassMenu.menu_list/1`. Its own nav zone; its items are nav items.
- **Split button** — a glass-menu tenant whose trigger is two joined segments: a main segment that performs one action and a chevron segment that opens the menu list. `GlassMenu.split_button/1`.
- **Menu select** — a glass-menu tenant whose trigger shows the current value and whose menu list holds the options, the current one marked. `GlassMenu.menu_select/1`. The scope select beside a series' Download and the library sort control are both instances.
- **Title detail modal** (existing) — the depth surface for a TMDB title the library does not own, hosted by Discovery and Incoming through `TitleDetailHost`. Every verb on such a title lives here.
- **Nav zone** (existing) — a `data-nav-zone` container of nav items; one focus-context instance. This spec lets zones nest and lets a zone declare what BACK pushes when it leaves.

## Problem

The Download button on a title the library does not own creates an `automatic` plan: a clean plan commits with nobody looking. The person wants the opposite default — they choose the releases — with the automatic path one click away, and reusable controls for it rather than the bespoke pair of buttons the title detail modal carries today. The series button also folds the scope choice ("Download all") into its menu, so adding the approval choice there would put two axes in one list. Underneath, the app has one dropdown idiom in CSS and two hand-rolled DOMs wearing it (the library sort control with its own keyboard model, the modal's scope menu), which is the duplication a third instance must not add to.

## Decisions

### Controls

1. **A series shows a split button reading "Download" and, to its right, a menu select for the scope** showing "Season 1" and offering "All seasons". A movie shows the split button alone.
2. **The main segment performs the default planning mode on the selected scope.** The chevron opens a one-item menu naming the other mode by the same words the Settings option uses: "Manually select release" when the default is auto-select, "Auto-select best release" when the default is manual.
3. **The feed row's compact Download performs the default planning mode with no chevron.** That row's verbs are text links; the full control is in the modal.
4. **One open-menu state on the host.** `open_menu` is `nil`, `:action` or `:scope`; at most one menu is open. Events: `title_menu_toggle` with `menu`, `title_menu_close`. Both lists render under the one zone name `title_detail_menu`, since only one exists at a time; the overlay layout in `config.js` needs no new region. The scope item pushes `title_scope` with `choice` (`first_season` | `everything`); the host holds `download_scope`, default `:first_season`, reset whenever a title opens. `title_download` carries `mode` (`auto_select_best_release` | `manually_select_release`) from the menu item and no `mode` from the main segment, which means the default. The two menus' toggles are `title_mode_toggle` and `title_scope_toggle`.

### Actions

5. **Auto-select best release is today's path unchanged:** `Plans.plan_title/2` with `approval_policy: "automatic"` and the scope, close the modal, flash "Finding a release for <title>".
6. **Manually select release plans in the host and lands on the board.** The host runs `Plans.create_title_plan/2` (decision 20) with `approval_policy: "review"` and the scope under `start_async` (name `{:title_download, ref}`); while pending the split button is disabled and its main segment reads "Planning…" (`download_pending?` on the host). On `{:ok, plan}` the host navigates to Incoming's board: `push_navigate` to `/incoming?plan=<id>` when the host page is Discovery, `push_patch` when it is Incoming. On `{:error, reason}` the host flashes on the modal and clears the pending state; copy names the cause in plain words (nothing to download, TMDB unreachable) and is settled with the writing-copy skill at implementation.
7. **One host function starts a download**, `TitleDetailHost.start_download/4` (socket, title, mode, scope), used by the modal's Download and by the feed row's Download. It maps the mode to the policy (`auto_select_best_release` → `"automatic"`, `manually_select_release` → `"review"`) and runs the matching path. Acquisition keeps speaking approval policy; the planning-mode vocabulary is the web layer's. A click while a download is pending is a no-op.
8. **The gate is untouched.** A `review` plan waits; an `automatic` plan commits when clean and parks otherwise, exactly as the one-click spec decided.

### Preference

9. **`Settings.Preferences.PlanningMode`**, a two-valued preference beside the boolean ones: key `default_planning_mode`, value `%{"mode" => "manually_select_release" | "auto_select_best_release"}`, `value/0` returning the atom (`:manually_select_release` when the entry is absent or malformed), `parse/1` for a stored map, `modes/0`, `other/1` for the alternative, `set/1` the only write, `setting_key/0`. Exported from `Settings.Preferences`. `SettingAware` is not involved (see Rejected). Named a *mode*, not a boolean, at the owner's request: the two options are peers with names, and the same names label the button's menu.
10. **The view-model carries it.** `Title.Detail` gains `planning_mode`, read by the host in `build_detail` the way `default_grab_mode` already is. The modal labels the menu item from it and the host resolves a main-segment click from it. Labels live in `Title.Logic.planning_mode_label/1` and `download_scope_label/1`, and the Settings select uses the same function.
11. **Settings → Acquisition gains a card "Download button"**, subline "On a title you don't own yet.", shown when Prowlarr is ready like the auto-acquisition defaults. One native select labelled "Default planning mode" with options "Manually select release" (default) and "Auto-select best release", saving on change (`set_planning_mode`), with the description "The button's main action. The other choice is in its menu." Settings is the reference register and its selects are native; the glass menu is for content surfaces.

### Glass menu components

12. **`MediaCentaurWeb.Components.GlassMenu`** at `lib/media_centaur_web/components/glass_menu.ex` with three function components, each with its own story under `storybook/core_components/`.
13. **`menu_list/1`** — attrs `id` (required), `zone` (required; the list's `data-nav-zone`), `on_close` (required; the event BACK pushes when it leaves the list, rendered as `data-nav-dismiss-event`), `class`. Slot `item` (required) with attrs `id`, `event` (required), `values` (map, `phx-value-*`), `active` (boolean, `.glass-menu-item-active`); content is the label. Renders `ul.glass-menu-list.glass-surface` with `li.glass-menu-item[data-nav-item][tabindex=0]` items and `role="menu"` / `role="menuitem"`.
14. **`split_button/1`** — attrs `id` (required), `open` (required), `on_toggle` (required), `on_close` (required), `menu_zone` (required), `variant` (default `"primary"`), `size` (default `"sm"`), `menu_label` (the chevron's accessible name, default "More options"), `disabled`, `class`, `rest` (global, applied to the main segment: `phx-click`, `phx-value-*`). Slots: `inner_block` (the main label), `item` (the menu list's items, same attrs as decision 13). Renders `span.glass-menu.inline-flex` with `phx-click-away={@on_close}`, two `.button`s joined (`rounded-r-none` / `rounded-l-none` with the hairline divider), `aria-expanded` and `aria-haspopup="menu"` on the chevron, the chevron rotating when open, and `menu_list` beneath with `--content` sizing. Ids: main `<id>`, chevron `<id>-toggle`, list `<id>-menu`.
15. **`menu_select/1`** — attrs `id` (required), `open` (required), `on_toggle` (required), `on_close` (required), `menu_zone` (required), `value_label` (required; the trigger's text), `label` (required; the accessible name, e.g. "Download scope" or "Sort"), `class`, `rest` (global on the wrapper, for data attributes such as `data-sort`). Slot `item` as above. Renders `span.glass-menu` with click-away, a `button.glass-menu-trigger[data-nav-item]` (`aria-haspopup="listbox"`, `aria-expanded`) with the chevron, and `menu_list` beneath. The library sort's `data-captures-keys` styling hook becomes `[aria-expanded="true"]` on the trigger.
16. **The library sort control becomes a `menu_select`.** `LibraryLive` drops `sort_key`, `sort_highlight` and the `data-captures-keys` handling; `toggle_sort`, `close_sort` and `sort` remain. The toolbar's `sort_highlight` attr goes; its story's open-menu variations lose the highlight sweep. This is the convergence the one-click spec scheduled (its amendment to decision 10), done now because the component exists.

### Input system

17. **Zones may nest; an item counts once, for its nearest zone.** `queryContextItems` in `dom_adapter.js` drops an item whose nearest `[data-nav-zone]` ancestor is a different zone nested inside the context's zone element (the element the context selector's first compound names). Selector strings keep their shape. `docs/input-system.md` replaces the "must not nest" rule with this one, and the "one element owns the modal overlay" rule stands.
18. **A zone can say what BACK pushes when it leaves.** `data-nav-dismiss-event` on a zone container names a LiveView event. When BACK leaves a zone along its `back` edge (rung 1 of the BACK order), the orchestrator pushes that event after the transition. The reader gains `getZoneDismissEvent(context)`. This is what closes a menu on BACK: the cursor returns to the trigger's zone and the LiveView closes the list. `docs/input-system.md` gets the attribute row and a sentence in the BACK section.
19. **Layouts.** `title_detail_menu` gains `back: ["title_detail_body"]`, so BACK from the open menu returns to the strip and closes the menu; a second BACK dismisses the modal. The library layout gains a `library_sort_menu` TREE: `toolbar: { down: ["library_sort_menu", "grid"] }`, `library_sort_menu: { up: ["toolbar"], back: ["toolbar"] }`; the grid's edges are unchanged. Both changes are asserted in the bun config tests and walked with `mc-nav-trace` before done.

### Acquisition API

20. **`Plans.create_title_plan(Title.t(), keyword()) :: {:ok, Plan.t()} | {:error, term()}`** — the body of today's `do_plan_title/3`, synchronous: movie plan attrs or series targeting plus `DownloadScope.units/2`, then `create_movie_plan/2` or `create_series_plan/3`. Errors: `:nothing_to_plan` when the scope yields no units; the targeting or creation error otherwise. `plan_title/2` keeps its contract and calls it inside the supervised task, logging as it does now.

### Unchanged

21. The picker and Plan now on Incoming, tracking's Default mode and drop planner, the follow-up pill, the Needs review / Planning / Downloading states on rows, and Incoming's existing `?plan=<id>` handling (`apply_plan_modal_params/2`).

## Rejected

- **A boolean setting named after one mode** ("Auto-select best release" as a toggle; the first draft). The owner prefers named modes to booleans, and the select's two options are the same words as the menu items — one vocabulary in both places.
- **Reading the preference in the gate.** A flip mid-solve would change a plan's fate, and the plan row would no longer say what will happen to it (one-click spec decision 1).
- **Folding the default into tracking's Default mode.** Two ideas in one control, and its default is Grab.
- **Scope inside the menu.** Two axes in one list; the menu would need three near-duplicate items or drop a combination.
- **Park and point for manual selection** (flash plus the pill). Nothing is chosen on click, so the label would be untrue.
- **An Incoming param that opens the draft for a title once it appears.** The synchronous create-then-navigate carries the plan id, and a targeting failure surfaces where the click happened instead of leaving the person on Incoming with nothing.
- **A native `<select>` for the scope** (the first draft of this spec). A bordered form control beside a glass-menu split button is two dropdown idioms in one strip, and the library sort already wears the glass idiom for exactly this shape.
- **Generalising `SettingAware` for a non-boolean preference.** The modal already reads the auto-grab default mode on build; the download action follows that precedent. A live update would matter only for a modal held open across a change made on another page.
- **A menu as its own `data-nav-overlay`.** Overlays are `[data-detail-mode='modal']` elements with focus semantics a dropdown does not want; a `back` edge plus a dismiss event on the zone is the whole of what a menu needs.

## Data changes

None. An absent preference row means manually select release.

## Testing

- Storybook: `menu_list`, `split_button`, `menu_select` stories (closed, open, active item, disabled) and the updated title detail modal and library toolbar stories compile and render.
- `TitleDetailHost` on both hosts: main click under the manual default shows "Planning…" then navigates to `/incoming?plan=<id>` (Discovery) or patches to it (Incoming); under the auto default it flashes and closes; the menu item performs the other mode; the scope select changes the plan's units; a TMDB failure flashes on the modal and leaves no plan; the menu label follows the preference; a second click while pending is ignored.
- Discovery feed row: Download follows the default planning mode.
- Library: the sort menu still patches `?sort=` from a click; no keyboard-model events remain.
- Settings: the select persists, round-trips, and defaults to manually select release.
- `Plans.create_title_plan/2`: movie, series first season, series everything, `:nothing_to_plan`, targeting failure. `plan_title/2` keeps its asynchronous tests.
- JS: the adapter counts a nested zone's items once, for the inner zone; BACK along a `back` edge pushes the zone's dismiss event; config tests for both layouts.
- Real browser before done: the split button and both menu selects by mouse; `mc-nav-trace` on the modal (RIGHT from Download reaches the chevron, then the scope trigger, then the bookmark; DOWN from the strip enters the open menu; BACK closes it and lands on the strip) and on the library toolbar (SELECT on Sort opens it, DOWN enters, BACK closes and returns to Sort).

## Documentation

- Dated amendment on the 2026-09-05 one-click spec: decisions 7, 10 and 17.
- Moduledocs: `Plans.Plan` (approval paragraph), `Plans` (both doors), `Title.DetailModal`, `Title.Detail`, `TitleDetailHost`, `GlassMenu`, `LibraryCards.toolbar`, `Preferences.PlanningMode`, the `dom_adapter.js` and `orchestrator.js` headers.
- `docs/input-system.md`: nesting rule, `data-nav-dismiss-event` row, the BACK section, the library and title-detail layouts.
- `docs/GLOSSARY.md`: approval policy and download scope rows updated; planning mode, glass menu, split button, menu select added.
- Wiki: Settings-Reference (Acquisition: the Download button card), Searching-and-Downloading (the paragraph on drafts from one-click downloads), Social (the Download row), Watchlist ("What happens after Download"), Keyboard-and-Gamepad (the title view: split button, menu, scope select, BACK closing a menu; the library sort menu).
- CHANGELOG at ship: Download now opens the plan for you to select releases; set the default planning mode to Auto-select best release under Settings → Acquisition to restore the one-click behaviour.

## Coherence pass (unify_design, 2026-09-12)

**Core idea.** A dropdown is a trigger plus an anchored list of nav items with LiveView-owned open state; the split button is one whose trigger also performs an action, the menu select one whose trigger shows its value. Every dropdown on a content surface is an instance of that one idiom.

**Greenfield shape.** One component module for the idiom; tenants compose it; the input system treats a menu as a zone that can live inside another zone and that BACK closes on the way out.

**Diff against the code.** The CSS idiom already existed with two hand-rolled DOMs (library sort, modal scope menu) and a third (the scope select) about to be added as a native form control. The input system forbade nested zones and had no way to close a menu on BACK, which is why the library sort grew a private keyboard model.

**Dispositions.** Native scope select → replaced (fix now). Library sort keyboard model → converged onto `menu_select` (fix now; it was already scheduled). Nested zones and BACK-closes-menu → two small contracts at the seam (fix now). `SettingAware` generalisation → not needed; precedent (`default_grab_mode`) followed. Two `Plans` doors → accepted: the async door is a thin wrapper whose only reason is outliving the LiveView.

**Cost.** The library toolbar is a daily-driver surface, so its convergence is the last task, verified with `mc-nav-trace` and a real browser before the work is called done; if it fails verification that task alone is reverted and the scheduled note stays.

## Follow-up: acquisition toasts (separate spec)

Owner request, out of this scope: a toast when a release is picked and the download begins, and one when a download finishes, for every outcome. The events exist in the pursuit log (`Pursuits.Event` kinds): `download_started` (release picked, sent to the client), `pursuit_satisfied` (landed in the library), the Review Queue hold (a downloaded file the importer could not match), "downloaded but not landed", `pursuit_exhausted`, `auto_cancelled` and `pursuit_cancelled`. That spec has to decide: a shell-level toast host subscribed to `acquisition:updates` so a toast appears on any page (flashes today are per-LiveView); batching so a pack landing ten episodes in seconds is one toast; behaviour during playback and on the TV shell; whether a toast carries an action (open the title, open Review).
