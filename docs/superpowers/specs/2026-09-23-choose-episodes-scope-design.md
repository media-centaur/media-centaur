# Choose episodes — the third download scope — design

Date: 2026-09-23. Builds on the download button default action spec
(`2026-09-12-download-button-default-action-design.md`), which put the
scope select beside a series' Download, and on the series-gap download
spec (`2026-09-13-series-gap-download-design.md`), which linked an owned
series to the picker.

## Glossary

- **Title detail modal** (existing) — the one detail view for owned and unowned titles, hosted on Home, Library, Discovery and Incoming through `TitleDetailHost`.
- **Download control** (existing) — on an unowned, released title with an indexer ready: a split button (`GlassMenu.split_button`) whose main segment performs the default planning mode and whose chevron offers the other, plus, for a series, the **scope select** (`GlassMenu.menu_select`) beside it.
- **Download scope** (existing) — what a series Download covers, resolved to episode units by `Plans.DownloadScope`: `:first_season` or `:everything`. This spec adds a third value to the *select*, **Choose episodes**, which is not a `DownloadScope` — it resolves to no units; it says the picker decides.
- **Planning mode** (existing) — *auto-select best release* (approval policy `automatic`: a clean plan commits itself) or *manually select release* (approval policy `review`: the plan's board opens). The person's default is `Settings.Preferences.PlanningMode`.
- **Picker** (existing) — the plan modal's targeting stage on Incoming: seasons with tri-state checkboxes, per-episode checkboxes, In library / Tracked / Unaired chips, the presets Everything aired / Continue from my library / Latest season / None, and a footer reading "Download N episodes". Logic in `IncomingLive.PlanLogic`.
- **Board** (existing) — the plan's live coverage display on Incoming.
- **Plan modal query** — the URL params that open the plan modal on Incoming: `plan=<id>` for the board; `plan=new&tmdb_id=<id>&tmdb_type=tv|movie` for the picker or the movie confirm. This spec adds `mode`.

## Problem

The scope select offers Season 1 and All seasons. The picker that lets a person choose the exact episodes exists on Incoming, is complete, and is tested, but from an unowned series there is no way into it: the only links are the omnibox and, for an owned series, "Download more of this show". Before the one-click download design (2026-09-05) the watchlist row linked straight to the picker; that design replaced the link with the two scopes, and the picker lost its entry from a title. The person wants it back as the third answer to the select's question, "which episodes?".

Two smaller facts surfaced in research. The picker ignores the planning mode: it always creates a `review` plan and lands on the board, so under an auto-select default the picker would be the one Download that does not auto-select. And two documents have drifted: the glossary says the All seasons scope tracks the title afterwards (ADR-066 says no download follows a series), and `PlanFlow`'s moduledoc names an EntityModal on Library and Home that no longer exists.

## Decisions

### Controls

1. **The scope select gains a third value, "Choose episodes"**, after Season 1 and All seasons. `ModalState.download_scope` is `:first_season | :everything | :choose_episodes`; `Title.Logic.download_scope_label/1` names it; the `download_scope` event accepts `choose_episodes`. The default stays `:first_season` and the value still resets whenever a title opens: no scope persists, and the picker is one trip.
2. **The split button keeps reading "Download"** with Choose episodes selected. UIDR-014's rule stands: verbs name the goal, not the step, and the goal is still a download. The chevron's other-mode item stays, because the mode travels with the person to the picker (decision 5).
3. **Pressing Download with Choose episodes selected opens the picker instead of planning.** `TitleDetailHost.Acquisition.start_download/4` with scope `:choose_episodes` resolves the click's mode (main segment: the default; chevron item: the other) and asks the host to open the plan modal with the picker query. Nothing is pending and nothing runs async: the picker's own Download makes the plan.

### The trip

4. **One host callback opens the plan modal.** `open_plan_board/2` becomes `open_plan/2` (socket, query map). Home, Library and Discovery `push_navigate` to `/incoming` with the query; Incoming `push_patch` through `incoming_path/2`, which swaps the title detail for the plan modal the way the board already does. The board hand-off after a manual plan calls it with `%{"plan" => id}`; Choose episodes calls it with `%{"plan" => "new", "tmdb_id" => …, "tmdb_type" => "tv", "mode" => …}`.
5. **The mode is a URL param.** `mode` is `auto_select_best_release` or `manually_select_release`. Incoming's `open_plan_targeting/2` reads it into `plan_mode`; an absent param means `PlanningMode.value()`, the person's default; any other value is a malformed plan link, the existing error stage. Only the title detail sends the param. The omnibox path and "Download more of this show" send none and get the default, so every Download in the app performs the planning mode.

### The picker performs the mode

6. **`plan_create` stamps the approval policy from `plan_mode`** (`PlanningMode.approval_policy/1`) for both the targeting stage and the movie confirm. The hard-coded `review` goes.
7. **Endings follow the mode.** Manual: patch to the board, as today. Auto-select: the patch that drops the plan params (the modal's close) and the flash `PlanFlow.download_flash(title)`. The omnibox resets on success as today. The person stays on Incoming, where the pursuit appears.
8. **The picker opens on the Everything aired preset**, as today. Opening empty for Choose episodes was considered and rejected: the common case is "all but a few", and None is one press away.

### Unchanged

9. `DownloadScope` and its two scopes; `Plans.create_title_plan/2`; the picker's presets, tri-state checkboxes and chips; the missing-episode row's one-unit plan; tracking (no download follows the series, ADR-066); the input system (the scope menu's items are already nav items, and the picker already has its `plan_body` zone).

## Rejected

- **Choose episodes as a chevron item.** Two axes in one list; the 2026-09-12 rejection stands.
- **A link under the action strip.** A second way of saying scope beside a control that already says it.
- **The picker inside the title detail modal.** A second picker surface and a second nav model for one idea.
- **The picker always parks for review.** Then the chevron's other-mode item would have to hide while Choose episodes is selected, and the picker would be the one Download that ignores the person's default.
- **Carrying the mode in session state instead of the URL.** The plan modal is URL-driven and refresh-safe by construction (UIDR-014); a param keeps it that way and costs nothing.

## Data changes

None. The mode is a URL param, not a column.

## Testing

- `ModalState` and `Title.Logic`: the third value and its label; the fresh state's default.
- `TitleDetailHost` (one host; the callback bodies are one-liners): Download with Choose episodes opens the picker query with the default mode; the chevron item sends the other mode; nothing is pending afterwards.
- Incoming: no `mode` uses the default; `auto_select_best_release` creates an `automatic` plan, closes the modal and flashes; `manually_select_release` creates a `review` plan and patches to the board; a bad value is a malformed link; the movie confirm follows the mode; "Download more of this show" still reaches the picker.
- Stories: `detail_panel` gains the select's Choose episodes state; `plan_modal` is unchanged.
- Real browser before done: select the third value, press Download, land in the picker; the picker's Download under each mode.

## Documentation

- Moduledocs: `Title.ModalState`, `Plans.DownloadScope` (the select's third value is not a scope), `TitleDetailHost` (the callback), `TitleDetailHost.Acquisition`, the plan-flow comment in `IncomingLive`, and `PlanFlow` (the title detail modal on all four pages; EntityModal is gone).
- `docs/GLOSSARY.md`: the download scope row adds Choose episodes and drops "after which the title is tracked"; the approval policy row says the picker stamps from the planning mode, not always `review`; the planning mode row says the picker performs it.
- Dated amendments: the 2026-09-12 spec (decision 21, the picker is no longer unchanged) and the 2026-09-13 spec (decision 12, the picker performs the default mode).
- Wiki: Watchlist (the Download paragraph names the third value); Searching-and-Downloading (a title's Download opens the plan to steer, and the picker performs your planning mode); Browsing-Your-Library ("Download more of this show" performs your default planning mode).
- CHANGELOG at ship.
