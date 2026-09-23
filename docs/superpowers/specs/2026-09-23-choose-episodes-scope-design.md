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

The scope select offers Season 1 and All seasons. The picker that lets a person choose the exact episodes exists on Incoming, is complete, and is tested, but from an unowned series there is no way into it: its only link is "Download more of this show" at the end of an owned series' season list (the omnibox no longer opens it — a search row opens the title detail, and every act lives there). Before the one-click download design (2026-09-05) the watchlist row linked straight to the picker; that design replaced the link with the two scopes, and the picker lost its entry from a title. The person wants it back as the third answer to the select's question, "which episodes?".

Two smaller facts surfaced in research. The picker ignores the planning mode: it always creates a `review` plan and lands on the board, so under an auto-select default the picker would be the one Download that does not auto-select. And two documents have drifted: the glossary says the All seasons scope tracks the title afterwards (ADR-066 says no download follows a series), and `PlanFlow`'s moduledoc names an EntityModal on Library and Home that no longer exists.

## Decisions

### Controls

1. **The scope select gains a third value, "Choose episodes"**, after Season 1 and All seasons. The select's value is one named type, `ModalState.scope_choice/0` — `DownloadScope.scope() | :choose_episodes` — which `Title.Logic.download_scope_label/1` and the `download_scope` event's closed set both take; `DownloadScope` itself stays the rule resolver and gains nothing (coherence pass, 1). The default stays `:first_season` and the value still resets whenever a title opens: no scope persists, and the picker is one trip.
2. **The split button keeps reading "Download"** with Choose episodes selected. UIDR-014's rule stands: verbs name the goal, not the step, and the goal is still a download. The chevron's other-mode item stays, because the mode travels with the person to the picker (decision 5).
3. **Pressing Download with Choose episodes selected opens the picker instead of planning.** `TitleDetailHost.Acquisition.start_download/5` with scope `:choose_episodes` resolves the click's mode (main segment: the default; chevron item: the other) and asks the host to open the plan modal with the picker query. Nothing is pending and nothing runs async: the picker's own Download makes the plan. The act owns its ending: the fifth argument is the surface's close (`push_close/1` on the modal, `& &1` on the feed row), so the host no longer re-derives from mode and scope whether to close (post-review, 2026-09-23).

### The trip

4. **One host callback opens the plan modal.** `open_plan_board/2` becomes `open_plan/2` (socket, query map). Home, Library and Discovery `push_navigate` to the query's path; Incoming `push_patch` through `incoming_path/2`, which swaps the title detail for the plan modal the way the board already does. Every board hand-off goes through it — the manual download's landing, the missing-episode landing (which navigates by a hand-built path today), and Incoming's own picker ending (decision 7). The query itself is built and parsed by one module (coherence pass, 2).
5. **The mode is a URL param.** `mode` is `auto_select_best_release` or `manually_select_release`, parsed by the one wire-form parser the Download event already needs (coherence pass, 3). Incoming reads it into `plan_mode`; an absent param means `PlanningMode.value()`, the person's default; any other value is a malformed plan link, the existing error stage. Only the title detail sends the param. "Download more of this show" sends none and gets the default, so every Download in the app performs the planning mode.

### The picker performs the mode

6. **`plan_create` stamps the approval policy from `plan_mode`** (`PlanningMode.approval_policy/1`) for both the targeting stage and the movie confirm. The hard-coded `review` goes.
7. **Endings follow the mode, in one function.** `PlanFlow.land_plan/5` (socket, mode, plan, label, close) ends any plan a surface has just created: manual selection opens the board through `open_plan/2` (decision 4); auto-select flashes `download_flash(label)` and leaves the surface as `close` says. The picker's close is the patch that drops the plan params; the missing-episode landing, which has the same two endings today, stays put. The omnibox resets on success as today. The person stays on Incoming, where the pursuit appears (coherence pass, 5).
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
- `IncomingLive.PlanQuery`: build and parse round-trip for the board and the picker, with and without `mode`; a bad `mode` or `tmdb_type` parses as malformed; `mode` absent parses as nil.
- `PlanningMode.parse_mode/1`: both wire forms, and `:error` for anything else; the Download event on the host resolves through it.
- The missing-episode landing patches on Incoming and navigates elsewhere (it navigates everywhere today).
- Stories: `detail_panel` gains the select's Choose episodes state; `plan_modal` is unchanged.
- Real browser before done: select the third value, press Download, land in the picker; the picker's Download under each mode.

## Documentation

- Moduledocs: `Title.ModalState` (the `scope_choice` type), `Plans.DownloadScope` (the select's third value is not a scope), `TitleDetailHost` (the callback), `TitleDetailHost.Acquisition`, `IncomingLive.PlanQuery` (new: the plan modal's address, both shapes), `Preferences.PlanningMode` (the wire form), the plan-flow comment in `IncomingLive`, and `PlanFlow` (`land_plan/5`; the title detail modal on all four pages; EntityModal and the `download_pending` assign are gone — the modal state's `pending` is what is in flight).
- `docs/GLOSSARY.md`: the download scope row adds Choose episodes and drops "after which the title is tracked"; the approval policy row says the picker stamps from the planning mode, not always `review`; the planning mode row says the picker performs it.
- Dated amendments: the 2026-09-12 spec (decision 21, the picker is no longer unchanged) and the 2026-09-13 spec (decision 12, the picker performs the default mode).
- Wiki: Watchlist (the Download paragraph names the third value); Searching-and-Downloading (a title's Download opens the plan to steer, and the picker performs your planning mode); Browsing-Your-Library ("Download more of this show" performs your default planning mode).
- CHANGELOG at ship.

## Coherence pass (unify_design, 2026-09-23)

**Core idea.** Every Download performs the person's planning mode on a set of episode units. The scope select names *who picks the units*: a rule (Season 1, All seasons) or the person, in the picker. The picker is the plan modal's targeting stage, and the plan modal is addressed by URL.

**Greenfield shape.** Four value types, each with one owner:

1. **The select's value** is a web-layer type, `ModalState.scope_choice/0`: a `DownloadScope.scope()` or `:choose_episodes`. `DownloadScope` resolves rules to units and knows nothing of the third value, which resolves to nothing — the picker does. Widening `DownloadScope.scope()` and letting `units/2` fail on the third value would have been the bolt-on.
2. **The plan modal's address** is one contract, built and parsed in one place: `MediaCentaurWeb.IncomingLive.PlanQuery`. `board(plan_id)` and `picker(tmdb_id, tmdb_type, mode \\ nil)` return query maps; `path/1` renders one as `/incoming?…` for a navigate; `parse/1` reads Incoming's params into `:closed`, `{:board, id}`, `{:picker, tmdb_id, tmdb_type, mode}` or `{:error, :malformed}`, with `mode` nil when absent. Today the address is hand-built at eight sites — the season list's link, the three hosts' `push_navigate`, Incoming's `push_patch`, `plan_create`, `resume_plan`, and the missing-episode landing — and parsed by `apply_plan_modal_params/2` plus `open_plan_targeting/2`'s guards. Adding `mode` would have made a ninth builder and a second parser.
3. **The mode's wire form** — the strings `auto_select_best_release` and `manually_select_release` — is parsed once, `PlanningMode.parse_mode/1` (`{:ok, mode} | :error`). The host's Download event hand-maps the same two strings today, and `PlanningMode.parse/1` (the stored map) maps them a second time; the URL param would have been a third. `parse/1` delegates; each caller decides what absent means (the event: the detail's default; the URL: `PlanningMode.value()`).
4. **The board hand-off** is one host callback, `open_plan/2`, taking a query map from `PlanQuery`. Every landing on the board uses it — the manual download's, the missing-episode's, and the picker's on Incoming.
6. **Post-review (2026-09-23).** The code review after execution found the plan's own leftovers, all fixed: `start_download/5` takes the surface's close instead of the host re-deriving the ending; the manual download's landing goes through `land_plan/5` and clears `pending` like its missing-episode sibling; the picker's mode is held once, in the plan param identity; a malformed plan link (bad mode or type, or a plan id that is not a UUID) closes the modal and flashes instead of assigning a stage the closed modal never shows; the two closed-set parsers derive from their lists; Settings parses the mode through the one parser; the picker query's type comes from the title through `ReleaseTracking.tmdb_type_for/1`. Left alone: the double reload on a picker Download (pre-existing shape, a performance pass's call) and the private copy of TMDB's two type strings.
5. **The ending of a created plan** is one function, `PlanFlow.land_plan/5`: manual selection opens the board through `open_plan/2`; auto-select flashes and closes as the surface says. The missing-episode landing has these two endings today; the picker would have been the second copy. The scoped title download's auto path cannot share it — it hands the title to the supervised door and has no plan in hand — and flashes directly; `PlanFlow`'s moduledoc says so instead of claiming one place for all three.

**Diff against the code and dispositions.**

| Gap | Kind | Disposition |
|---|---|---|
| `open_plan_board/2` on four hosts, board-only | clean seam | Generalise to `open_plan/2` (fix now). |
| Plan modal address built at eight sites, parsed at two | duplication | `PlanQuery` (fix now). |
| Mode strings mapped by hand on the host and in `PlanningMode.parse/1` | duplication | `parse_mode/1` (fix now). |
| The missing-episode landing bypasses the host callback and navigates even on Incoming | incoherence in the slice | Route through `open_plan/2` (fix now). |
| `plan_create` hard-codes `review` | incoherence — the feature | Stamp from `plan_mode` (fix now). |
| The picker's ending would be a second copy of the missing-episode landing's | duplication (introduced by the first plan draft) | `PlanFlow.land_plan/5`, used by both (fix now). |
| `plan_identity` carries a picked search result into the loading stage, for an omnibox path that no longer opens the picker | orphan outside the slice | Leave; note for the next Incoming touch. Removing it is a separate, unrelated cleanup. |
| `PlanFlow` moduledoc names EntityModal and a `download_pending` assign | stale doc | Rewrite (fix now). |
| Glossary: All seasons "then tracks the title"; approval policy says the picker always stamps `review` | stale doc | Rewrite (fix now). |

**Cost.** Against the bolt-on (a third clause, a hand-built URL, a hand-read param, a third copy of the board patch): one small module with its tests (`PlanQuery`), one function on `PlanningMode`, the callback rename across four hosts, and eight call-site edits. Everything is inside the slice the feature touches; nothing is scheduled for later.
