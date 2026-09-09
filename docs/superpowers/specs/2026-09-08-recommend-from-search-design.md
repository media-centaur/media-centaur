# Recommend from search results — design

Date: 2026-09-08 (unify passes 2026-09-08, 2026-09-09)
Status: approved (design); implementation not started

## Glossary

Terms are defined here before first use. Code names are in backticks.

- **Title** — the app-wide TMDB title snapshot: identity (`tmdb_id`,
  `media_type`) plus render fields. `MediaCentaur.TMDB.Title`. A title
  may or may not have files; the library owns the ones that do.
- **Ref** — the `{tmdb_id, media_type}` identity pair, serialized for the
  wire by `MediaCentaurWeb.TitleRef`. The one representation of "which
  title" every row and every modal query uses.
- **Recommendation** — one signed activity stating "this title, from me,
  with a sentiment and an optional note", stored and published by
  `Activities.recommend/3`. It takes a `Title`, not a library entity.
- **Recommend modal** — the sentiment + note form. Its state is
  `Live.RecommendFlow`; a host opens it on a subject and supplies the
  artwork it paints.
- **Library detail panel** — `EntityModal`'s modal for a title the
  library owns. Hosts Recommend today.
- **Title detail modal** — the depth surface for a title *without* files
  (UIDR-035). Hosted through `Live.TitleDetailHost` by `DiscoveryLive`
  and `IncomingLive`.
- **Action strip** — the title detail modal's row of verbs, nav zone
  `title_detail_body`: the primary control, then the `ml-auto` tertiary
  group.
- **Title row** — one title in a list, as identity plus quiet state
  markers, the whole card opening the title detail modal. Carries no
  verbs.
- **Media search** — the Incoming page omnibox in media mode (UIDR-014):
  typing searches TMDB and `Components.Acquisition.MediaResults` renders
  the answer flat below the hero.
- **Rung** — the title's position on the one `TitleIntent` ladder
  (ADR-065): Off · List · Follow · Ask · Grab · Default.
- **Plan flow** — the Incoming download-plan modal, opened by
  `?plan=new`.

## Purpose

Let the user recommend a title from media-search results. Today
Recommend exists only on the library detail panel (`view_controls.ex`),
so only a title the library already owns can be recommended — which
excludes exactly the titles a person is most likely to press on a friend.

## The organizing idea

**A title without files has one depth surface; a row that names such a
title shows state and carries no acts; and that surface is nobody's
page.** Recommending is an act on a title, so it belongs on the depth
surface. Everything else here is the codebase not yet being that idea.

`TitleRow` states the row half outright — *"State is shown, never acted
on here: every verb lives in the modal"* — and the one-click-download
spec decided it for Discovery (2026-09-05 §14, *"rows stop carrying
actions"*). Media-search rows never converged. The third clause is the
one this change forces: the surfaces are shared by two pages but
namespaced after one of them.

## Problem

1. **The title detail modal has no Recommend control**, though it is the
   depth surface for every title without files.

2. **A search row does not reliably reach that modal.** `omnibox_pick`
   (`incoming_live.ex:1609`) branches: upcoming, or no indexer
   configured, opens the modal; released with an indexer ready goes
   straight to the plan flow. The most-clicked rows never see the modal,
   so a control added there would be unreachable from them.

3. **Two components render one row idea.** `TitleRow` and
   `MediaResults`' `result_row`. Strip the verb from the latter and they
   differ only by a bookmark and by how they encode identity.

4. **Two representations of title identity in rows.** `omnibox_pick`
   carries `tmdb-id` and `media-type` as loose fields and the host does
   an `Enum.find` to recover the `Title`; every other row emits a ref.

5. **Search rows have no `data-entity-id`.** `TitleRow` carries it as
   the input system's overlay-restore origin, so closing the modal lands
   focus back on the opening row. Routing every search row through the
   modal without it would drop the cursor on every close.

6. **The shared title surfaces are namespaced after one of their two
   pages.** `Components.Discovery.{TitleRow, TitleDetail,
   TitleDetailModal, IntentControl, Pennant}`, `DiscoveryLive.Logic` and
   `DiscoveryLive.RecommendModal` are consumed by `TitleDetailHost`,
   `IncomingLive`, `HomeLive` and `LibraryLive` as much as by
   `DiscoveryLive` — five of `DiscoveryLive.Logic`'s seven consumer
   files are not the Discovery page, and `RecommendModal` already has
   three non-Discovery hosts. `Person` and `PersonCard` genuinely are
   Discovery's. This change adds Incoming as a further consumer of the
   misnamed ones.

## Decisions

### The namespace split (lands first, on its own)

1. **The shared title surfaces move to `MediaCentaurWeb.Components.Title.*`**,
   a page-neutral namespace matching the glossary's own term:

   | From | To |
   |---|---|
   | `Components.Discovery.TitleRow` | `Components.Title.Row` |
   | `Components.Discovery.TitleDetail` | `Components.Title.Detail` |
   | `Components.Discovery.TitleDetailModal` | `Components.Title.DetailModal` |
   | `Components.Discovery.IntentControl` | `Components.Title.IntentControl` |
   | `Components.Discovery.Pennant` | `Components.Title.Pennant` |
   | `MediaCentaurWeb.DiscoveryLive.Logic` | `Components.Title.Logic` |

   `Components.Discovery.Person` and `.PersonCard` stay: people browsing
   is the Discovery page's own concern.

2. **`DiscoveryLive.RecommendModal` becomes `MediaCentaurWeb.Live.RecommendModal`**,
   beside the `Live.RecommendFlow` whose assigns it renders. It stays
   under `live/` rather than joining `components/`: MC0009 requires a
   story for every function component under `components/**`, and this
   modal's contract is the flow's, not a standalone component's. State
   and view sit together; neither carries a page name.

3. **Storybook follows.** `storybook/discovery/{title_row,
   title_detail_modal, intent_control, pennants}.story.exs` move to
   `storybook/title/` with a new `_title.index.exs`;
   `person_card.story.exs` stays. Story paths mirror component paths
   (MC0009).

4. **This lands as its own commit before the feature**, so the feature
   diff is the feature.

### Recommend

5. **Recommend lives in the title detail modal**, not on a row. It
   mirrors the library detail panel, which has had it since the friends
   work.

6. **The wiring goes in `TitleDetailHost`.** Both its hosts gain the act
   in one change: recommending from media-search results, from the
   Discovery feed, and from Discovery watchlist rows.

7. **`TitleDetailHost.__using__` injects `use RecommendFlow`**; the
   opening event `title_recommend_open` joins the `title_*` events its
   `:handle_event` hook already owns and halts on. No new mounting
   mechanism: `RecommendFlow`'s macro keeps serving its own controls
   exactly as it does for `EntityModal`'s hosts, and the host-specific
   opening clause is what its documented contract already asks for.

8. **The control is a quiet text control labelled `Recommend`**, placed
   in the action strip between the primary control and the `ml-auto`
   tertiary group. Text, not the library panel's paper-plane icon: this
   strip's vocabulary is words (`Download`, `Delete recommendation`)
   where the library panel's controls row is an icon cluster. One act,
   each surface's own control idiom — decided here so it does not read
   later as drift.

9. **The artwork comes from `detail.poster_url`**, which the host has
   already resolved and the live TMDB preview refreshes. Not a second
   `title_poster_url/1` call: one derivation of one value.

10. **Gated on `show_discovery`**, the preference that gates the whole
    friend-network preview. Already an assign in both hosts.

### The search row

11. **The search row becomes the shared title row.** `MediaResults`
    keeps the list shell it owns — the scope chips, the Clear control,
    the searching and empty states — and delegates each row.
    `result_row`, `verb/3`, the bookmark and the `data-nav-grid`
    wrapper are deleted. Rows become one nav item each, and
    `data-entity-id` comes with the component.

12. **The row emits `open_title` with a ref, and `omnibox_pick` is
    deleted.** `IncomingLive.resolve_title/3` already resolves a ref out
    of `omnibox_results` (`incoming_live.ex:455`), so the existing
    `?title=<ref>` machinery carries the whole path. `watchlist_toggle`
    (`incoming_live.ex:1651`) has no other caller and goes with the
    bookmark. Download is reached through the modal's existing
    `title_download`, which already renders the split-button season
    scope.

13. **Markers come from `Logic.row_markers/2`, not a second
    vocabulary.** It only *requires* `library_owner_id` and
    `acquisition_state`; `rung`, `default_grab_mode` and `next_air_date`
    are optional. Incoming passes the facts it has and gets the same
    words Discovery uses. No function is made public that was not
    already.

14. **The List rung becomes a marker: `"On your list"`** —
    `IntentControl`'s own words (`intent_control.ex:156`) — where
    `rung_marker` returned nil. This is the bookmark's information
    relocated, and it also fills a gap Discovery's recommendations tab
    had.

15. **`row_markers/2` takes `list_implied?` (default false).**
    Discovery's watchlist tab passes true: every row there is on the
    list, so saying so adds nothing. A second argument rather than a
    fact in the map, because it is a fact about the *container*, not
    about the title.

16. **Downloading and listing from search both cost opening the modal.**
    One more click than today, in both directions — the surface that
    owns the verbs owns all of them.

## Rejected

- **A third control on the search row** (paper-plane beside the
  bookmark). One click, but it puts a social act at bookmark weight on
  an acquisition page, keeps the row's grid-column arithmetic, and is
  not the flow the owner described.

- **Adding Recommend to the modal and leaving `omnibox_pick` alone.**
  Cheapest, and half a feature: unreachable from released titles with an
  indexer configured, which is most of what a person searches for.

- **Splitting the pick button** so the title area opens the modal while
  a Download verb still fires directly. Preserves the one-click shortcut
  at the cost of three nav items per row — the arrangement §14
  deliberately moved away from.

- **Keeping the bookmark by giving the title row a trailing-action
  slot.** One caller, invented for one caller: speculative generality,
  and it would preserve the second row idiom it was meant to remove.

- **A hook-driven `RecommendFlow` for `TitleDetailHost`** alongside
  `EntityModal`'s macro. Two ways to mount one flow. Decision 7
  instead.

- **Making `rung_marker/2` public** so Incoming could build its own
  marker list. `row_markers/2` is already the builder; widening the API
  would have created a second assembly point for one vocabulary.

- **Renaming all of `Components.Discovery.*`.** `Person` and
  `PersonCard` belong to the Discovery page. The fix is a split, not a
  blanket rename.

## Scheduled convergence

- **Acquisition-state markers on search rows.** `row_markers/2` already
  produces Planning / Downloading / Needs review; Incoming passes
  `acquisition_state: nil` because it does not read
  `Acquisition.title_state/2` per result page. Convergence point: the
  next change that gives Incoming a per-page acquisition read for any
  reason — then it is a one-word edit at the call site. Until then a
  title already planning or downloading shows no such marker in search,
  the same gap as today rather than a new one.

- **Two host-contract modules now inject `RecommendFlow`**
  (`EntityModal` and `TitleDetailHost`), so a LiveView may `use` one or
  the other but never both: the injected clauses and the `init/1` seed
  would collide. No host does today. Recorded in both moduledocs rather
  than guarded in code.

## Changes

### Commit 1 — the namespace split

Module and story moves per decisions 1–3, and the references in the 24
files that name them. Moduledocs that describe the modules as Discovery's
are reworded to name the two pages they serve. No behaviour change; the
test suite is the proof.

### Commit 2 — the feature

#### `MediaCentaurWeb.Live.TitleDetailHost`

- `__using__` gains `use MediaCentaurWeb.Live.RecommendFlow`.
- `on_mount` seeds `RecommendFlow.init/1` alongside `:title_detail` and
  `:scope_menu_open`.
- The `:handle_event` hook gains one halting clause,
  `title_recommend_open` — `RecommendFlow.open/3` on the open detail's
  `Title` with the detail's own `poster_url`.
- Moduledoc: the host-contract table gains the Recommend row and the
  mutual-exclusion note.

#### `MediaCentaurWeb.Live.RecommendFlow`

- Moduledoc only: the host contract names `TitleDetailHost` as the
  second injector, and the mutual exclusion with `EntityModal`.

#### `Components.Title.DetailModal`

- A `Recommend` text control in the action strip, `id`
  `title-recommend`, `phx-click="title_recommend_open"`,
  `data-nav-item` with `tabindex="0"`, rendered between `.primary` and
  `.tertiary` when the new `recommend?` attr is true. No media-type
  guard: `TMDB.Title.media_type` is `:movie | :tv_series` and nothing
  else, so every detail the modal can open is recommendable.
- New attr `recommend?` (boolean, default false) with a `doc:` naming
  the `show_discovery` gate.
- The scope menu's anchor comment still holds: the menu opens under the
  strip's first control, which is unchanged.

#### `Components.Title.Logic`

- `rung_marker/2` returns `"On your list"` for `:list`; its
  nil-for-List comment goes.
- `row_markers/1` becomes `row_markers/2` with `list_implied? \\ false`,
  which suppresses only that marker. Documented with the reason.

#### `Components.Acquisition.MediaResults`

- `result_row/1`, `verb/3`, the bookmark, `toggleable?/1`,
  `bookmark_label/1` and the `release_mode_available` attr are removed.
  The list renders `Components.Title.Row` per result, taking
  `poster_url` and `markers` from the host — the component resolved the
  poster itself before, the row expects the host to.
- `active_query?/1` and `release_status/2` stay; the latter is read by
  `Components.Title.Logic.title_detail/2`.
- Rows keep the `grid` nav zone and the header strip keeps `toolbar`.
  With one nav item per row the zone is a plain list, so the
  `data-nav-grid` column arithmetic and its moduledoc paragraph go.
- Moduledoc: the "each row leads with one verb" contract is replaced by
  the shared one — the row opens the title detail, every verb lives
  there — citing §14.

#### `DiscoveryLive`

- Renders the Recommend modal; passes `recommend?={@show_discovery}` to
  the title detail modal.
- The watchlist tab calls `row_markers/2` with `list_implied?: true`.

#### `IncomingLive`

- Renders the Recommend modal; passes `recommend?={@show_discovery}` to
  the title detail modal.
- Assigns `default_grab_mode: AutoGrabSettings.load().default_mode` at
  mount, as `DiscoveryLive` does (`discovery_live.ex:91`).
- Builds each result's `poster_url` (`title_poster_url/1`) and markers
  (`row_markers/2` over `in_library_refs`, `title_rungs` and
  `default_grab_mode`, with `acquisition_state: nil`).
- `handle_event("omnibox_pick", …)` and
  `handle_event("watchlist_toggle", …)` are deleted. `plan_identity`
  remains for the plan flow's other entry points. Whether `tracked_refs`
  still has a consumer after the `Tracked` marker goes is checked during
  implementation; if not, it goes too.

## Testing

Test-first (`automated-testing`). No network: TMDB stubs per the skill.

- Commit 1 carries no new tests: the existing suite passing after the
  moves is the assertion.
- `incoming_live_test`: clicking a released search result with an
  indexer ready opens the title detail modal, not the plan flow;
  Download from inside the modal still reaches the plan flow.
- `incoming_live_test`: a result already on the list renders
  `On your list`; one at Follow renders `Tracking: Follow`; one the
  library owns renders `In library`.
- `title_detail_modal` render tests: `title-recommend` present when
  `recommend?` is true, absent when false.
- Host test through `IncomingLive`: open the modal on a search result,
  fire `title_recommend_open`, assert the Recommend modal renders the
  result's identity and its poster; fire `recommend_send` and assert
  `Activities.recommend/3` stored the recommendation with the chosen
  sentiment, and that the flash names the relay state.
- `logic_test`: `row_markers/2` yields `On your list` at `:list`, and
  omits it under `list_implied?: true` while keeping `Tracking: Follow`.
- `discovery_live_test`: the watchlist tab renders no `On your list`;
  the recommendations tab does.
- `media_results_test`: a rendered row carries `data-entity-id` and no
  verb text.
- Storybook: the detail modal's story gains a Recommend variation;
  `MediaResults` variations lose the verb and bookmark states (MC0009).
- Real-browser verification of the click path — search, click a
  released result, recommend — and of focus landing back on the opening
  row when the modal closes, before the work is called done.

## Documentation

- Wiki: *Using Media Centaur* Downloads page (a search result opens the
  title detail; download and list from there) and the
  Discovery/Friends page (recommend from search results as well as from
  the library).
- Discovery's watchlist empty state loses its "from a search" clause
  (`discovery_live.ex:473`) — listing now happens in a title's detail
  view.
- No ADR. The row change applies §14's existing decision to the last
  surface that had not adopted it; the namespace split renames modules
  without changing a decision. Both are recorded in the moduledocs they
  touch.
