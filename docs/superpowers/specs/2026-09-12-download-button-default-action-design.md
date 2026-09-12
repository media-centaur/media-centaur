# Download button default action — design

Date: 2026-09-12. Builds on the one-click download spec
(`2026-09-05-one-click-download-design.md`), which introduced the
approval policy column and the split Download control it amends.

## Glossary

- **Approval policy** (existing) — the per-plan value naming who commits the plan once it has solved: `automatic` (the gate commits a clean plan) or `review` (a person approves it on Incoming). Column `approval_policy` on `acquisition_plans`.
- **Clean plan** (existing) — a solved plan in which every wanted unit was found within its quality bounds. The only kind an `automatic` manual plan commits.
- **Plan board** (existing) — the live display of a draft plan on Incoming, opened by `?plan=<id>`: episode grid, kept releases, the swap picker per episode, exclude, offers, Approve plan.
- **Download scope** (existing) — what a series Download covers: `first_season` or `everything`. Movies have one scope.
- **Download action** — what the Download button does when pressed: *auto-select* or *choose releases*. One of the two is the person's default, held by the download action preference; the other is in the button's menu.
- **Auto-select** — the download action that creates the plan with approval policy `automatic`, closes the modal and flashes. A clean plan commits with nobody looking; anything else parks on Incoming.
- **Choose releases** — the download action that creates the plan with approval policy `review` and lands the person on its plan board, where they swap, exclude and approve.
- **Download action preference** — the Settings entry naming the default download action. Key `download_action`; absent means choose releases.
- **Split button** — a control with a main segment that performs one action and a chevron segment that opens a menu of the other actions. `MediaCentaurWeb.Components.SplitButton`.
- **Scope select** — the native `<select>` beside a series' Download button holding the download scope.
- **Title detail modal** (existing) — the depth surface for a TMDB title the library does not own, hosted by Discovery and Incoming through `TitleDetailHost`. Every verb on such a title lives here.
- **Nav zone** (existing) — a `data-nav-zone` container of nav items; one focus-context instance. This spec changes the rule that zones must not nest.

## Problem

The Download button on a title the library does not own creates an `automatic` plan: a clean plan commits with nobody looking. The person wants the opposite default — they choose the releases — with the automatic path one click away, and a proper reusable control for it rather than the bespoke pair of buttons the title detail modal carries today. The series button also folds the scope choice ("Download all") into its menu, so adding the approval choice there would put two axes in one list.

## Decisions

### Controls

1. **A series shows a split button reading "Download" and, to its right, a scope select** with "Season 1" selected and "All seasons" as the other option. A movie shows the split button alone.
2. **The main segment performs the default download action on the selected scope.** The chevron opens a one-item menu naming the other action: "Choose releases" when the default is auto-select, "Auto-select best release" when the default is choose releases.
3. **The feed row's compact Download performs the default action with no chevron.** That row's verbs are text links; the full control is in the modal.
4. **Events.** The menu's open state stays LiveView-owned on the host: `title_menu_toggle` and `title_menu_close` (renamed from the scope-menu events). The scope select sits in a form with `phx-change="title_scope"`; the host holds `download_scope`, default `:first_season`, reset whenever a title opens. `title_download` carries `action` (`auto_select` | `choose_releases`) from the menu item, and no `action` from the main segment, which means the default.

### Actions

5. **Auto-select is today's path unchanged:** `Plans.plan_title/2` with `approval_policy: "automatic"` and the scope, close the modal, flash "Finding a release for <title>".
6. **Choose releases plans in the host and lands on the board.** The host runs `Plans.create_title_plan/2` (decision 17) with `approval_policy: "review"` and the scope under `start_async`; while pending the split button is disabled and its main segment reads "Planning…". On `{:ok, plan}` the host navigates to Incoming's board: `push_navigate` to `/incoming?plan=<id>` when the host page is Discovery, `push_patch` when it is Incoming. On `{:error, reason}` the host flashes on the modal and clears the pending state; copy names the cause in plain words (nothing to download, TMDB unreachable) and is settled with the writing-copy skill at implementation.
7. **The action-to-policy mapping is one function on `TitleDetailHost`,** used by the modal's Download and by the feed row's Download: `auto_select` → `"automatic"`, `choose_releases` → `"review"`. Acquisition keeps speaking approval policy; the action vocabulary is the web layer's.
8. **The gate is untouched.** A `review` plan waits; an `automatic` plan commits when clean and parks otherwise, exactly as the one-click spec decided.

### Preference

9. **`Settings.Preferences.DownloadAction`**, a string preference beside the boolean ones: key `download_action`, value `%{"action" => "choose_releases" | "auto_select"}`, `default/0` returning the atom (`:choose_releases` when the entry is absent or malformed), `set/1` the only write, `setting_key/0` for the live-update trait. Exported from `Settings.Preferences`.
10. **Settings → Acquisition gains a card "Download button"**, subline "On a title you don't own yet.", shown when Prowlarr is ready like the auto-acquisition defaults. One select labelled "Default" with options "Choose releases" and "Auto-select best release", saving on change, with the description "The button's main action. The other choice is in its menu."
11. **The host reads the preference on mount and on `{:setting_changed, "download_action", _}`** into a `download_action` assign, which the modal takes as an attr to label the menu item. A click resolves the default from the same assign.

### Split button component

12. **`MediaCentaurWeb.Components.SplitButton.split_button/1`** at `lib/media_centaur_web/components/split_button.ex`. Attrs: `id` (required), `variant` (default `"primary"`), `size` (default `"sm"`), `open` (boolean, required), `on_toggle` (event name the chevron pushes), `on_close` (event name for click-away), `menu_zone` (the menu's `data-nav-zone`, required), `menu_label` (the chevron's accessible name, default "More options"), `disabled` (boolean), `rest` (global, applied to the main segment: `phx-click`, `phx-value-*`). Slots: `inner_block` (the main label), `item` (required; attrs `id`, `event`, `values` map; content is the label). Ids: main `<id>`, chevron `<id>-toggle`, menu `<id>-menu`, items by their own ids.
13. **Rendering reuses what exists:** two `.button`s with the current `rounded-r-none` / `rounded-l-none` joining, the `.glass-menu` anchor wrapper, `.glass-menu-list--content` list, `.glass-menu-item` items, the chevron rotation. Both segments are nav items in the surrounding zone; the menu list carries `data-nav-zone={@menu_zone}` and its items are nav items. `aria-expanded` on the chevron.
14. **Story `storybook/core_components/split_button.story.exs`** with variations: closed, open with one item, open with two items, disabled (pending). The title detail modal story's variations follow the new control: movie split, series split with scope select, menu open showing the other action, the auto-select default flipping the label, and pending.

### Input system

15. **Zones may nest; an item counts once, for its nearest zone.** `queryContextItems` in `assets/js/input/core/dom_adapter.js` drops any item whose nearest `[data-nav-zone]` ancestor is not the zone the context's selector names (the selector's first compound, `[data-nav-zone='X']`). Selector strings keep their shape; no config entry changes. `docs/input-system.md` replaces the "must not nest" rule with this one. A bun test covers a zone inside a zone.
16. **The scope select is a nav item in the strip.** SELECT opens it natively, as the Settings selects do. The menu keeps its zone name `title_detail_menu` and the overlay layout in `config.js` is unchanged.

### Acquisition API

17. **`Plans.create_title_plan(Title.t(), keyword()) :: {:ok, Plan.t()} | {:error, term()}`** — the body of today's `do_plan_title/3`, synchronous: movie plan attrs or series targeting plus `DownloadScope.units/2`, then `create_movie_plan/2` or `create_series_plan/3`. Errors: `:nothing_to_plan` when the scope yields no units; the targeting or creation error otherwise. `plan_title/2` keeps its contract and calls it inside the supervised task, logging as it does now.

### Unchanged

18. The picker and Plan now on Incoming, tracking's Default mode and drop planner, the follow-up pill, the Needs review / Planning / Downloading states on rows, and Incoming's existing `?plan=<id>` handling (`apply_plan_modal_params/2`).

## Rejected

- **A boolean setting named after one action** ("Auto-select best release" as a toggle). The select's two options are the same words as the menu items — one vocabulary in both places.
- **Reading the preference in the gate.** A flip mid-solve would change a plan's fate, and the plan row would no longer say what will happen to it (one-click spec decision 1).
- **Folding the default into tracking's Default mode.** Two ideas in one control, and its default is Grab.
- **Scope inside the menu.** Two axes in one list; the menu would need three near-duplicate items or drop a combination.
- **Park and point for choose releases** (flash plus the pill). Nothing is chosen on click, so the label would be untrue.
- **An Incoming param that opens the draft for a title once it appears.** The synchronous create-then-navigate carries the plan id, and a targeting failure surfaces where the click happened instead of leaving the person on Incoming with nothing.
- **A glass dropdown for the scope select.** The native select gets keyboard and gamepad for free; revisit only if it clashes visually with the primary button.

## Data changes

None. An absent preference row means choose releases.

## Testing

- Storybook: the split button story and the updated title detail modal story compile and render.
- `TitleDetailHost` on both hosts: main click under the choose default shows "Planning…" then navigates to `/incoming?plan=<id>` (Discovery) or patches to it (Incoming); under the auto default it flashes and closes; the menu item performs the other action; the scope select changes the plan's units; a TMDB failure flashes on the modal and leaves no plan; the menu label follows the preference and flips on a setting change.
- Discovery feed row: Download follows the default action.
- Settings: the select persists, round-trips, and defaults to choose releases.
- `Plans.create_title_plan/2`: movie, series first season, series everything, `:nothing_to_plan`, targeting failure. `plan_title/2` keeps its asynchronous tests.
- JS: the DOM adapter counts a nested zone's items once, for the inner zone.
- Real browser before done: the split button by mouse; `mc-nav-trace` on the modal — RIGHT from Download reaches the chevron, then the scope select, then the bookmark; DOWN from the strip enters the open menu; the menu has one item.

## Documentation

- Dated amendment on the 2026-09-05 one-click spec: decisions 7, 10 and 17.
- Moduledocs: `Plans.Plan` (approval paragraph), `Plans` (both doors), `Title.DetailModal`, `TitleDetailHost`, `SplitButton`, `Preferences.DownloadAction`, the `dom_adapter.js` header.
- `docs/GLOSSARY.md`: approval policy and download scope rows updated; download action and split button added.
- Wiki: Settings-Reference (Acquisition: the Download button card), Searching-and-Downloading (the paragraph on drafts from one-click downloads), Social (the Download row), Watchlist (what happens after Download), Keyboard-and-Gamepad (the title detail strip: split button, menu, scope select).
- CHANGELOG at ship: Download now opens the plan for you to choose releases; set Auto-select best release under Settings → Acquisition to restore the one-click behaviour.

## Follow-up: acquisition toasts (separate spec)

Owner request, out of this scope: a toast when a release is picked and the download begins, and one when a download finishes, for every outcome. The events exist in the pursuit log (`Pursuits.Event` kinds): `download_started` (release picked, sent to the client), `pursuit_satisfied` (landed in the library), the Review Queue hold (a downloaded file the importer could not match), "downloaded but not landed", `pursuit_exhausted`, `auto_cancelled` and `pursuit_cancelled`. That spec has to decide: a shell-level toast host subscribed to `acquisition:updates` so a toast appears on any page (flashes today are per-LiveView); batching so a pack landing ten episodes in seconds is one toast; behaviour during playback and on the TV shell; whether a toast carries an action (open the title, open Review).
