# Recommend from search results — design

Date: 2026-09-08
Status: approved (design); implementation not started

## Glossary

Terms are defined here before first use. Code names are in backticks.

- **Title** — the app-wide TMDB title snapshot: identity (`tmdb_id`,
  `media_type`) plus render fields. `MediaCentaur.TMDB.Title`.
- **Ref** — the `{tmdb_id, media_type}` identity pair, serialized for the
  wire by `MediaCentaurWeb.TitleRef`. The one representation of "which
  title" every row and every modal query uses.
- **Recommendation** — one signed activity stating "this title, from me,
  with a sentiment and an optional note", stored and published by
  `Activities.recommend/3`. It takes a `Title`, not a library entity.
- **Recommend modal** — `DiscoveryLive.RecommendModal`, the sentiment +
  note form. Its state is `Live.RecommendFlow`; a host opens it on a
  subject and resolves the artwork it paints.
- **Library detail panel** — `EntityModal`'s modal for a title the
  library owns (has files). Hosts Recommend today.
- **Title detail modal** — `Components.Discovery.TitleDetailModal`, the
  depth surface for a title *without* files (UIDR-035). Hosted through
  `Live.TitleDetailHost` by `DiscoveryLive` and `IncomingLive`.
- **Title row** — `Components.Discovery.TitleRow`: one TMDB title in a
  list, as identity plus quiet state markers, the whole card opening the
  title detail modal. Carries no verbs.
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

**A title without files has one depth surface, and a row that names such
a title shows state and carries no acts.** Recommending is an act on a
title. It is on the library detail panel already; it is missing from the
title detail modal. Everything else in this spec is the codebase not yet
being that idea.

`TitleRow` states the rule outright — *"State is shown, never acted on
here: every verb lives in the modal"* — and the one-click-download spec
decided it for Discovery (2026-09-05 §14, *"rows stop carrying
actions"*). Media-search rows are the one surface that never converged.

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

5. **Two vocabularies for one fact.** A search row says `Tracked`;
   Discovery says `Tracking: Follow` / `Ask` / `Grab` through
   `Logic.rung_marker`. ADR-065 made tracking derived from the rung —
   one fact, two words for it.

6. **Search rows have no `data-entity-id`.** `TitleRow` carries it as
   the input system's overlay-restore origin, so closing the modal lands
   focus back on the opening row. Routing every search row through the
   modal without it would drop the cursor on every close.

## Decisions

1. **Recommend lives in the title detail modal**, not on a row. It
   mirrors the library detail panel, where Recommend is a paper-plane
   icon button after the bookmark in the view-controls row.

2. **The wiring goes in `TitleDetailHost`.** Both its hosts gain the act
   in one change: recommending from media-search results, from the
   Discovery feed, and from Discovery watchlist rows.

3. **Gated on `show_discovery`**, the preference that gates the whole
   friend-network preview. Already an assign in both hosts
   (`incoming_live.ex:791`, `discovery_live.ex:370`).

4. **`TitleDetailHost.__using__` injects `use RecommendFlow`**; the
   opening event `title_recommend_open` joins the `title_*` events its
   `:handle_event` hook already owns and halts on. No new mounting
   mechanism: `RecommendFlow`'s macro keeps serving its own controls
   exactly as it does for `EntityModal`'s hosts, and the host-specific
   opening clause is what its documented contract already asks for.

5. **The search row becomes `TitleRow`.** `MediaResults` keeps the list
   shell it owns — the scope chips, the Clear control, the searching and
   empty states — and delegates each row. `result_row`, `verb/3`, the
   bookmark, and the `data-nav-grid` wrapper are deleted. Rows become
   one nav item each, and `data-entity-id` comes with the component.

6. **The row emits `open_title` with a ref, and `omnibox_pick` is
   deleted.** `IncomingLive.resolve_title/3` already resolves a ref out
   of `omnibox_results` (`incoming_live.ex:455`), so the existing
   `?title=<ref>` machinery carries the whole path. `watchlist_toggle`
   (`incoming_live.ex:1651`) has no other caller and goes with the
   bookmark. Download is reached through the modal's existing
   `title_download`, which already renders the split-button season
   scope.

7. **The bookmark's information moves into a marker.**
   `Logic.rung_marker/2` becomes public and returns **"On your list"**
   for `:list` — the intent control's own words
   (`intent_control.ex:156`) — instead of nil. On Discovery's watchlist
   tab, where every row is on the list, `DiscoveryLive` drops that one
   marker as redundant. The redundancy is a property of that list, not
   of the vocabulary.

8. **Search-row markers are `In library` plus the rung marker.** Not
   full `row_markers/1` parity: acquisition-state markers (Planning /
   Downloading / Needs review) would cost Incoming an
   `Acquisition.title_state/2` read per result page and are not part of
   this change. Recorded below as a scheduled convergence.

9. **Downloading and bookmarking from search both cost opening the
   modal.** One more click than today, and the same trade in both
   directions — the surface that owns the verbs owns all of them.

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

- **Keeping the bookmark by giving `TitleRow` a trailing-action slot.**
  One caller, invented for one caller: speculative generality, and it
  would preserve the second row idiom it was meant to remove.

- **A hook-driven `RecommendFlow` for `TitleDetailHost`** alongside
  `EntityModal`'s macro. Two ways to mount one flow. Decision 4 instead.

## Scheduled convergence

- **Acquisition-state markers on search rows.** `row_markers/1` already
  produces them for Discovery; Incoming does not read
  `Acquisition.title_state/2`. Convergence point: the next change that
  gives Incoming a per-page acquisition read for any other reason. Until
  then a title already planning or downloading shows no such marker in
  search results — the same gap as today, not a new one.

- **Two host-contract modules now inject `RecommendFlow`**
  (`EntityModal` and `TitleDetailHost`), so a LiveView may `use` one or
  the other but never both: the injected clauses and the `init/1` seed
  would collide. No host does today. Recorded in both moduledocs rather
  than guarded in code.

## Changes

### `MediaCentaurWeb.Live.TitleDetailHost`

- `__using__` gains `use MediaCentaurWeb.Live.RecommendFlow`.
- `on_mount` seeds `RecommendFlow.init/1` alongside `:title_detail` and
  `:scope_menu_open`.
- The `:handle_event` hook gains one halting clause,
  `title_recommend_open` — `RecommendFlow.open/3` on the open detail's
  `Title` with `title_poster_url/1` (already imported here) as the
  artwork.
- Moduledoc: the host-contract table gains the Recommend row and the
  mutual-exclusion note.

### `MediaCentaurWeb.Live.RecommendFlow`

- Moduledoc only: the host contract names `TitleDetailHost` as the
  second injector, and the mutual exclusion with `EntityModal`.

### `Components.Discovery.TitleDetailModal`

- A paper-plane icon button in the modal's control row, `id`
  `title-recommend`, `phx-click="title_recommend_open"`, `data-nav-item`
  with `tabindex="0"`, rendered when the new `recommend?` attr is true.
  No media-type guard: `TMDB.Title.media_type` is `:movie | :tv_series`
  and nothing else, so every detail the modal can open is
  recommendable.
- New attr `recommend?` (boolean, default false) with a `doc:` naming
  the `show_discovery` gate.

### `Components.Acquisition.MediaResults`

- `result_row/1`, `verb/3`, the bookmark, `toggleable?/1`,
  `bookmark_label/1` and the `release_mode_available` attr are removed.
  The results list renders `TitleRow` per result.
- `active_query?/1` and `release_status/2` stay — the latter is read by
  `DiscoveryLive.Logic.title_detail/2`.
- The rows keep the `grid` nav zone; the header strip keeps `toolbar`.
  With one nav item per row the zone is a plain list, so the
  `data-nav-grid` column arithmetic and its moduledoc paragraph go.
- Moduledoc: the "each row leads with one verb" contract is replaced by
  the shared one — the row opens the title detail, every verb lives
  there — citing §14.

### `MediaCentaurWeb.DiscoveryLive.Logic`

- `rung_marker/2` becomes public and returns `"On your list"` for
  `:list`. Its `nil`-for-List comment goes.
- `row_markers/1` is unchanged in shape; the List marker now appears in
  its output.

### `DiscoveryLive`

- Renders `<RecommendModal.recommend_modal>`; passes
  `recommend?={@show_discovery}` to the title detail modal.
- Drops the `"On your list"` marker on the watchlist tab.

### `IncomingLive`

- Renders `<RecommendModal.recommend_modal>`; passes
  `recommend?={@show_discovery}` to the title detail modal.
- Assigns `default_grab_mode: AutoGrabSettings.load().default_mode` at
  mount, as `DiscoveryLive` does (`discovery_live.ex:91`), for the rung
  marker.
- Builds each result's markers — `In library` plus
  `Logic.rung_marker/2` — from the `in_library_refs` and `title_rungs`
  it already computes, and passes them to `TitleRow`.
- `handle_event("omnibox_pick", …)` and
  `handle_event("watchlist_toggle", …)` are deleted. `plan_identity`
  remains for the plan flow's other entry points.

## Testing

Test-first (`automated-testing`). No network: TMDB stubs per the skill.

- `incoming_live_test`: clicking a released search result with an
  indexer ready opens the title detail modal, not the plan flow;
  Download from inside the modal still reaches the plan flow.
- `incoming_live_test`: a search result already on the list renders
  `On your list`; one at Follow renders `Tracking: Follow`; one the
  library owns renders `In library`.
- `title_detail_modal` render tests: `title-recommend` present when
  `recommend?` is true, absent when false.
- Host test through `IncomingLive`: open the modal on a search result,
  fire `title_recommend_open`, assert the Recommend modal renders the
  result's identity; fire `recommend_send` and assert
  `Activities.recommend/3` stored the recommendation with the chosen
  sentiment, and that the flash names the relay state.
- `discovery_live_test`: the watchlist tab renders no `On your list`
  marker; the recommendations tab does.
- `media_results_test`: a rendered row carries `data-entity-id` and no
  verb text.
- Storybook: the title detail modal's story gains a Recommend
  variation; `MediaResults` variations lose the verb and bookmark
  states (MC0009).
- Real-browser verification of the click path — search, click a
  released result, recommend — and of focus landing back on the opening
  row when the modal closes, before the work is called done.

## Documentation

- Wiki: *Using Media Centaur* Downloads page (a search result opens the
  title detail; download and list from there) and the
  Discovery/Friends page (recommend from search results as well as from
  the library).
- Discovery's watchlist empty state loses its "from a search" clause
  (`discovery_live.ex:473`) — bookmarking now happens in a title's
  detail view.
- No ADR: this applies §14's existing decision to the last surface that
  had not adopted it rather than superseding anything. The row
  contract change is recorded in the `MediaResults` moduledoc.
