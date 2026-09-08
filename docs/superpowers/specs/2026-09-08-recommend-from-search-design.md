# Recommend from search results — design

Date: 2026-09-08
Status: approved (design); implementation not started

## Glossary

Terms are defined here before first use. Code names are in backticks.

- **Title** — the app-wide TMDB title snapshot: identity (`tmdb_id`,
  `media_type`) plus render fields. `MediaCentaur.TMDB.Title`.
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
- **Media search** — the Incoming page omnibox in media mode (UIDR-014):
  typing searches TMDB and `Components.Acquisition.MediaResults` renders
  the answer flat below the hero.
- **Search row** — one `MediaResults` result. Today a two-column nav
  grid: a pick button carrying a verb, and a bookmark toggle.
- **Plan flow** — the Incoming download-plan modal, opened by
  `?plan=new`.
- **Rung** — the title's position on the one `TitleIntent` ladder
  (ADR-065). The bookmark reflects it.

## Purpose

Let the user recommend a title from media-search results. Today
Recommend exists only on the library detail panel (`view_controls.ex`),
so only a title the library already owns can be recommended — which
excludes exactly the titles a person is most likely to press on a friend.

## Problem

Two defects, and the second is why the first cannot be fixed in
isolation.

1. **The title detail modal has no Recommend control.** It is the depth
   surface for every title without files, on Discovery and on Incoming
   alike, and it is where the act belongs.

2. **A search row does not reliably reach that modal.** `omnibox_pick`
   (`incoming_live.ex:1609`) branches: an upcoming title, or any title
   when no indexer is configured, opens the title detail modal; a
   released title with an indexer ready goes straight to the plan flow.
   The most-clicked rows never see the modal, so a control added there
   would be unreachable from them.

Behind both: media-search rows are the last surface still carrying their
own action verb. The one-click-download work already decided the
opposite for Discovery — §14, *"rows stop carrying actions"*: a feed or
watchlist row is identity plus state, the whole card opens the modal,
and Download lives inside it. Incoming's search rows kept a verb, so one
idea — *a title without files* — has two row idioms.

## Decisions

1. **Recommend lives in the title detail modal**, not on the row. It
   mirrors the library detail panel, where Recommend is a paper-plane
   icon button after the bookmark in the view-controls row.

2. **The wiring goes in `TitleDetailHost`, not in each host.** Both its
   hosts gain the act in one change: recommending from media-search
   results, from the Discovery feed, and from Discovery watchlist rows.

3. **Gated on `show_discovery`**, the preference that gates the whole
   friend-network preview. Already an assign in both hosts
   (`incoming_live.ex:791`, `discovery_live.ex:370`).

4. **Every search row opens the title detail modal.** `omnibox_pick`
   stops branching. Download is reached through the modal's existing
   `title_download`, which already renders the split-button season
   scope. Media search converges on the Discovery idiom; downloading
   from search costs one more click, exactly as it does on Discovery.

5. **The bookmark stays on the row.** Full convergence would drop it,
   but it is the one act worth doing without opening anything while
   scanning a result list; it keeps the row's documented two-column nav
   grid intact; and Discovery's watchlist empty state points at it
   ("Bookmark a title from a search…", `discovery_live.ex:473`).

6. **`TitleDetailHost` drives `RecommendFlow` through its lifecycle
   hook, not through `RecommendFlow`'s `__using__` macro.** The macro
   serves `EntityModal`'s handle_event-clause hosts; this host is
   hook-based, and `RecommendFlow.open/close/submit` are public. One
   mechanism per host rather than two in the same module.

## Rejected

- **A third control on the search row** (paper-plane beside the
  bookmark). One click, but it breaks the row's two-column nav grid —
  grid navigation is index arithmetic and the pairing is documented —
  puts a social act at bookmark weight on an acquisition page, and is
  not the flow the owner described.

- **Adding Recommend to the modal and leaving `omnibox_pick` alone.**
  Cheapest, and half a feature: unreachable from released titles with an
  indexer configured, which is most of what a person searches for.

- **Splitting the pick button** so the title area opens the modal while
  a Download verb still fires directly. Preserves the one-click
  shortcut at the cost of three nav items per row — the arrangement
  §14 deliberately moved away from.

- **Dropping the bookmark from the row** for full §14 parity. See
  decision 5.

## Changes

### `MediaCentaurWeb.Live.TitleDetailHost`

- `on_mount` seeds `RecommendFlow.init/1` alongside `:title_detail` and
  `:scope_menu_open`.
- The attached `:handle_event` hook grows three halting clauses beside
  the existing modal controls:
  - `title_recommend_open` — `RecommendFlow.open/3` on the open
    detail's `Title`, with `title_poster_url/1` (already imported here)
    as the artwork.
  - `recommend_cancel` — `RecommendFlow.close/1`.
  - `recommend_send` — `RecommendFlow.submit/3`.
- Moduledoc: the host-contract table gains the Recommend row.

### `MediaCentaurWeb.Live.RecommendFlow`

- Moduledoc only: the host contract names both entry paths — the
  `__using__` macro for `EntityModal`'s hosts, direct
  `open/close/submit` calls for `TitleDetailHost`'s hook.

### `Components.Discovery.TitleDetailModal`

- A paper-plane icon button in the modal's control row, `id`
  `title-recommend`, `phx-click="title_recommend_open"`, `data-nav-item`
  with `tabindex="0"`, rendered when the new `recommend?` attr is true.
  Unlike the library's control there is no media-type guard:
  `TMDB.Title.media_type` is `:movie | :tv_series` and nothing else, so
  every detail the modal can open is recommendable.
- New attr `recommend?` (boolean, default false) with a `doc:` naming
  the `show_discovery` gate.

### `DiscoveryLive` and `IncomingLive`

- Each renders `<RecommendModal.recommend_modal>` beside its existing
  modals, and passes `recommend?={@show_discovery}` into the title
  detail modal.

### `IncomingLive.handle_event("omnibox_pick", …)`

- The `cond` collapses to one path: resolve the picked result, then
  `push_patch` to `?title=<ref>`. The `Capabilities.prowlarr_ready?/0`
  and `release_status/2` fork and the `plan_identity` /
  `?plan=new&tmdb_id=…` push are removed. `plan_identity` remains for
  the plan flow's other entry points.

### `Components.Acquisition.MediaResults`

- The row's verb span and `verb/3` are removed; `release_mode_available`
  is removed from the component and from the `IncomingLive` call site.
  `release_status/2` stays — `DiscoveryLive.Logic.title_detail/2` reads
  it.
- Moduledoc: the "each row leads with one verb" paragraph is replaced by
  the row's new contract — the row opens the title detail, the bookmark
  toggles the rung — citing the Discovery idiom it now shares.

## Testing

Test-first (`automated-testing`). No network: TMDB stubs per the skill.

- `incoming_live_test`: picking a released result with an indexer ready
  opens the title detail modal, not the plan flow; picking an upcoming
  result still opens the modal (unchanged behaviour, now the only path).
- `title_detail_modal` render tests: `title-recommend` present when
  `recommend?` is true, absent when false.
- `TitleDetailHost` host test through `IncomingLive`: open the modal on
  a search result, fire `title_recommend_open`, assert the Recommend
  modal renders the result's identity; fire `recommend_send` and assert
  `Activities.recommend/3` stored the recommendation with the chosen
  sentiment, and that the flash names the relay state.
- `media_results_test`: no verb text in a rendered row.
- Storybook: the title detail modal's story gains a variation with the
  Recommend control (MC0009), and the `verb`-bearing `MediaResults`
  variations lose it.
- Real-browser verification of the click path — search, click a
  released result, recommend — before the work is called done.

## Documentation

- Wiki: *Using Media Centaur* Downloads page (a search result opens the
  title detail; download from there) and the Discovery/Friends page
  (recommend from search results as well as from the library).
- No ADR: this applies §14's existing decision to one more surface
  rather than superseding anything. UIDR-014's row contract change is
  recorded in the `MediaResults` moduledoc.
