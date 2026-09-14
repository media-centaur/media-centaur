# Emitter inventory (subagent report, 2026-09-14)

## Host contracts

| Host | Event / URL param | Handler | Notes |
|---|---|---|---|
| `EntityModal` | `select_entity` `%{"id" => entity_uuid}` | `entity_modal.ex:114-120` | toggles; `push_patch(build_modal_path(%{selected: id, movie: nil}))` |
| `EntityModal` | `select_movie` `%{"id" => member_uuid}` | `entity_modal.ex:124-126` | re-anchors an open collection modal via `?movie=` |
| `EntityModal` | `close_detail` | `entity_modal.ex:128-132` + `close_detail_target/1` `:1338-1346` | nested view → returns to root view; root → `selected: nil` |
| `EntityModal` | `select_detail_view` `%{"view" => ...}` | `entity_modal.ex:134-137` | `?view=info\|cast` |
| `EntityModal` | URL `selected`, `view`, `movie` | `apply_modal_params/2` `entity_modal.ex:659-692`; emitted by `modal_query_params/2` `:806-817` | |
| `TitleDetailHost` | `open_title` `%{"ref" => "<media_type>-<tmdb_id>", "activity" => id?}` | `title_detail_host.ex:473-481` | `push_patch(title_detail_path(socket, [title: ref, activity: id]))` |
| `TitleDetailHost` | `close_title` | `title_detail_host.ex:483`, `push_close/1` `:638` | |
| `TitleDetailHost` | URL `title`, `activity` | `apply_title_params/3` `title_detail_host.ex:159-173`; `TitleRef.parse/1` | unknown ref → TMDB fetch (`open_from_tmdb` `:228-240`) |

## 1. Emitters

| file:line | Page | Surface | Mechanism | Identity held | Opens |
|---|---|---|---|---|---|
| `components/hero_card.ex:130-131` (home_live.ex:158) | Home | hero card "More info" | `select_entity` `id=@item.entity_id` | entity uuid only (`HeroCard.Item`) | library modal |
| `components/continue_watching_row.ex:71-72` (home_live.ex:184) | Home | continue-watching card | `select_entity` `id=item.entity_id` | entity uuid only | library modal |
| `components/poster_row.ex:63-64` (home_live.ex:203) | Home | Recently Added poster | `select_entity` `id=item.entity_id` | entity uuid only | library modal |
| `components/coming_up_marquee.ex:253-254` (home_live.ex:233) | Home | Coming up marquee tile | `select_entity` `id=@item.entity_id` when binary; else `<.link navigate="/incoming">` `:273` | entity uuid only in `ComingUpMarquee.Item` (source `ComingUpItemRef` has `tmdb_id`/`media_type`, dropped by builder) | library modal (or Incoming) |
| `components/library_cards.ex:48-49` (library_live.ex:436-445) | Library | poster card in grid stream | `select_entity` `id=@entry.id` | entity uuid only (`Library.Views.BrowseItem`) | library modal |
| `components/detail/collection_rail.ex:97-98` | inside library modal | rail member tile | `select_movie` `id=@movie.id` → `?movie=` | member entity uuid | re-anchors |
| `components/detail/view_controls.ex:169,192` | inside library modal | Info / Cast tabs | `select_detail_view` `view=` → `?view=` | none | sub-view |
| `home_live.ex:285-297` | Home deep link | `/?zone=library\|upcoming&...` forwarder | `push_navigate` to `/library` or `/incoming` with remaining query | whatever URL carried | library modal via `/library?selected=` |
| `components/title/row.ex:52-53` (discovery_live.ex:607-627) | Discovery Watchlist | title row | `open_title` `ref={TitleRef.param(Title.ref(@title))}` | tmdb ref; host row also holds `library_owner_id` but the component does not receive it | title modal |
| `components/title/row.ex:52-53` via `acquisition/media_results.ex:156-163` (incoming_live.ex:874-884) | Incoming omnibox media mode | search result row | `open_title` + `ref` | tmdb ref; `in_library_refs` known to the list not the row | title modal |
| `components/discovery/feed_entry_card.ex:53-55` (discovery_live.ex:545) | Discovery Feed | feed entry card | `open_title` `ref` + `activity={@entry.activity_id}` | tmdb ref + activity id; struct also carries `library_owner_id` | title modal |
| `components/discovery/person_card.ex:89-92` (discovery_live.ex:565-569) | Discovery Friends | Recently watched poster strip | `open_title` `ref` + `activity` | tmdb ref + activity id (`Person.Entry`) | title modal |
| `components/discovery/person_card.ex:196-199` | Discovery Friends | Wants to watch / Reviewed text row | `open_title` `ref` + `activity` | tmdb ref + activity id | title modal |
| `components/incoming/shelf.ex:119-120` (incoming_live.ex:944) | Incoming Coming up shelf | shelf row | `select_event` `item-id={@card.item_id}` → `incoming_live.ex:1653-1661` `ReleaseTracking.get_item/1` → `push_patch(incoming_path(%{"title" => TitleRef.param(...)}))` | neither: a `ReleaseTracking.Item` id; server resolves to tmdb ref (Item also has `library_container_id`, unused) | title modal |
| `title_detail_host.ex:159-173` | Discovery, Incoming | deep link `?title=<ref>[&activity=]` | handle_params hook | tmdb ref (+ activity) | title modal |
| `entity_modal.ex:659` via `home_live.ex:303-304`, `library_live.ex:99-122` | Home, Library | deep link `?selected=<uuid>[&movie=][&view=]` | `apply_modal_params/2` | entity uuid | library modal |
| `assets/js/input/core/orchestrator.js:1205-1227` | any | keyboard/gamepad SELECT | `focused.click()` on the focused `[data-nav-item]`; `_recordOrigin(focused.dataset.entityId)` `:1217` | whatever `data-entity-id` holds (entity uuid on cards, `TitleRef.param` on title rows/feed/person entries) | whichever |
| `layouts.ex:119-179` + `root.html.heex:73-95` | sidebar | `data-nav-remember` links | restores `sessionStorage["nav:<path>"]` saved minus `data-nav-transient-params` | none | never reopens by design (but see Discovery bug) |

Adjacent, not emitters: `release_tracking/release_dates.ex:105` `navigate="/incoming?selected=#{pursuit_id}"` opens the **pursuit** modal (`incoming_live.ex:593-615`, `select_pursuit` `:1700-1706`) — `?selected=` on `/incoming` is a pursuit id; `detail/season_list.ex:112` `navigate=~p"/incoming?plan=new&tmdb_id=…&tmdb_type=tv"` opens the plan board; `title/detail_modal.ex:277` `navigate="/incoming"` (Needs review); `title_download` → `open_plan_board/2` (`discovery_live.ex:160` push_navigate `/incoming?plan=`, `incoming_live.ex:466-467` push_patch `plan=`).

Storybook renders emitting components with `phx-click` intact, no host: `storybook/composites/hero_card.story.exs:19`, `poster_row/poster_row.story.exs:33`, `library_cards/poster_card.story.exs:34`, `detail/collection_rail.story.exs:21`, `title/title_row.story.exs:15`, `discovery/feed_entry_card.story.exs:15`, `discovery/person_card.story.exs:17`, `acquisition/media_results.story.exs:16`, `incoming/shelf.story.exs:13`, `title/title_detail_modal.story.exs:26`, `detail_panel/detail_panel.story.exs:159` (passes `title_ref: "tv_series-42"` at `:730`). `ContinueWatchingRow` and `ComingUpMarquee` are `@storybook_status :skip`.

## 2. Page-root declarations

| LiveView | `data-page-behavior` | `data-nav-transient-params` | Host traits `use`d |
|---|---|---|---|
| `HomeLive` `home_live.ex:126-127` | none (`data-nav-default-zone="home"`) | `"selected,view"` | `EntityModal`, `SpoilerFreeAware`, `CardPlayButtonAware`, `LetterboxdLinksAware`, `IntentAware` (`:10-14`) |
| `LibraryLive` `library_live.ex:328-330` | `library` | `"selected,view"` | `EntityModal`, `SpoilerFreeAware`, `LibraryCardInfoAware`, `CardPlayButtonAware`, `LetterboxdLinksAware`, `IntentAware` (`:32-37`) |
| `DiscoveryLive` `discovery_live.ex:504-506` | `discovery` | `"title activity"` — space-separated, but `root.html.heex:83` splits on `","`, so neither is stripped; sidebar's remembered Discovery URL reopens the title modal | `TitleDetailHost` (`:58`) |
| `IncomingLive` `incoming_live.ex:839-841` | `incoming` | `"selected,title,plan,prowlarr_search"` (`selected` = pursuit modal) | `TitleDetailHost`, `IntentAware` (`:84-85`) |
| Status/Guide/Review/Setup/WatchHistory/Apps/Reconcile/Console | own behaviors | none | none |
| `SettingsLive` `settings_live.ex:1755` | `settings` | none | `SpoilerFreeAware`, `LibraryCardInfoAware`, `CardPlayButtonAware`, `LetterboxdLinksAware` |

Neither `movie` (library) nor `activity` (discovery, given the bug) is declared transient anywhere. Both `EntityModal` and `TitleDetailHost` `use ReviewFlow` (`entity_modal.ex:244`, `title_detail_host.ex:122`); a host may not `use` both (`title_detail_host.ex:26`).

## 3. Bridges

| Direction | file:line | URL / mechanism | Identity source |
|---|---|---|---|
| title → library | `title/detail_modal.ex:260-269` ("In library" primary) | `navigate={"/library?selected=#{@owner_id}"}` (full navigate, loses the page) | `primary: {:in_library, owner}` `title/logic.ex:85`; `library_owner_id: Map.get(ExternalIds.tmdb_owners([ref]), ref)` `title_detail_host.ex:279` |
| library → title | none | — | library modal computes `title_ref` (`entity_modal.ex:1036`, `title_ref/1` `:1495-1500`, `find_tmdb_id/1` `:1648-1662`) only for `set_rung` / tracking controls (`detail_panel.ex:504,526`, `detail/manage_panel.ex:235-237`, `title/tracking_controls.ex:147`). `find_tmdb_id` returns a ref for `:tv_series` (source `"tmdb"`) and `:movie_series` (source `"tmdb_collection"` mapped to `:movie`), nil for a plain `:movie`. |

## 4. Card/row data shapes

| Surface | Struct | entity id | tmdb ref | Built where | Can emit |
|---|---|---|---|---|---|
| Home hero | `HeroCard.Item` `hero_card.ex:18-55` | `entity_id` | no | `HomeLive.Logic.hero_card_item/2` `home_live/logic.ex:186-192` from `Library.Views.HeroCandidatesItem` (no tmdb) | entity only |
| Home continue-watching | `ContinueWatchingRow.Item` `:29-50` | `entity_id` | no | `logic.ex:82-84` from `Library.Views.ContinueWatchingItem` (no tmdb) | entity only |
| Home Recently Added | `PosterRow.Item` `:24-37` | `entity_id` | no | `Logic.recently_added_items/2` `logic.ex:168-172` from `Library.Views.RecentlyAddedItem` (no tmdb) | entity only |
| Home Coming up marquee | `ComingUpMarquee.Item` `:34-62` (`entity_id` nullable) | `entity_id` | no in Item; yes in source `ComingUpItemRef` (`release_tracking/views/coming_up_item_ref.ex:22-28`: `id`, `entity_id`, `tmdb_id`, `media_type`) | `Logic.coming_up_marquee/2` `logic.ex:124,223-225` | entity today; both with a builder change |
| Library grid | `Library.Views.BrowseItem` `browse_item.ex:32` | `id` | no | `Library.Views.browse` | entity only |
| Collection rail | `MovieRow.Library` (`item.movie.id`) | member `id` | no | `EntityModal.member_view/2` `entity_modal.ex:823+` | entity only |
| Discovery Watchlist row | map: `item` = `TitleIntent` (`.title`, `.tmdb_id`, `.media_type`, `.note`), `library_owner_id`, `rung`, `acquisition_state`, `poster_url`, `friend_activity`, `next_air_date` | `library_owner_id` (host row only) | yes | `discovery_live.ex:301-324` from `Discovery.list_watchlist/0` | title; entity available to host |
| Incoming omnibox row | `TMDB.Title` | no (`in_library_refs` at list level `media_results.ex:59`) | yes | omnibox search | title only |
| Feed entry | `Discovery.FeedEntry` `feed_entry.ex:22-40` | `library_owner_id` | `ref` | `FeedEntries.build/2` `discovery_live/feed_entries.ex:37-59` | both |
| Person card entries | `Discovery.Person.Entry` `person.ex:18-31` | no | `ref` | `People.build/3` `discovery_live/people.ex:53-70` | title only |
| Incoming Coming up shelf row | `Incoming.Shelf.Card` `shelf.ex:33-79` (`item_id`, `pursuit_id`, ...) | no | no | `IncomingLive.View` `view.ex:113-115` from `UpcomingFeed.Event.item_id` | neither directly; server resolves Item → tmdb ref; Item's `library_container_id` could yield entity |
| Title modal open state | `TitleDetail` | `library_owner_id` | `ref` | `build_detail/4` `title_detail_host.ex:271-290` | both |
| Library modal open state | `selected_entry` | `entity.id` | via `find_tmdb_id/1`: tv_series and movie_series only; plain movie → nil | `apply_modal_params/2` | entity; title only for series/collections |

## 5. Client-side

| file:line | What |
|---|---|
| `root.html.heex:73-95` | capture-phase click on `[data-nav-item]` saves `sessionStorage["nav:"+pathname]` minus transient params (`split(",")` `:83`) |
| `assets/js/nav_reselect.js:8-26` | same-path sidebar click: preventDefault only when query matches |
| `dom_adapter.js:24-26` | `activeModalElement()` = first `[data-detail-mode='modal']` |
| `dom_adapter.js:370-372` | `isDetailNested()` reads `data-detail-nested` (`detail_panel.ex:326`) |
| `dom_adapter.js:379-380` | overlay name from `data-nav-overlay` (`detail_panel.ex:327` `"detail"`, `title/detail_modal.ex:115` `"title_detail"`, `plan_modal.ex:190` `"plan"`) |
| `dom_adapter.js:387-389` | `getDismissEvent()` reads `data-dismiss-event` (`title/detail_modal.ex:116` `"close_title"`; `detail_panel.ex` sets none → fallback) |
| `dom_adapter.js:396-401` | `getZoneDismissEvent()` reads `data-nav-dismiss-event` on a zone (`glass_menu.ex:54`) |
| `dom_adapter.js:285-289, 425-431, 542-549` | `originOf`, `getEntityIndex`, `focusByEntityId` keyed on `data-entity-id` |
| `orchestrator.js:1230-1250` | `_executeDismiss()`: nested → `pushEvent("close_detail")`; else `pushEvent(dismissEvent ?? "close_detail")`, then `_restoreOriginFocus()` |
| `orchestrator.js:698-705` | BACK along a `back` edge pushes the zone's `data-nav-dismiss-event` |
| `orchestrator.js:546-565` | `_restoreOriginFocus()` by `data-entity-id` |
| `orchestrator.js:571-590` | `_onClick`/`_recordOrigin` record origin entity id for mouse opens |
| `config.js:17` | `MODAL` selector `[data-detail-mode='modal'] [data-nav-item]` |
| `config.js:36-38, 128-137` | `title_detail_body`/`title_detail_menu`/`title_detail_tracking` zones and types |
| `config.js:159-225` | overlay layouts `detail`, `plan`, `title_detail` |
| `config.js:229` | `entryDefaults: { detail_list: "[data-resume-target]", detail_rail: "[data-selected]" }` |
| server attrs | `entity_modal.ex:1049` `on_close="close_detail"`; `detail_panel.ex:95` `attr :on_close default "close_detail"`, `:325-327`; `title/detail_modal.ex:110-116` `on_close="close_title"`, `dismiss={:ephemeral}` |

## Notable findings
1. Every Home/Library emitter holds only an entity uuid; only the marquee's source data already carries a tmdb ref.
2. Every Discovery/Incoming emitter holds only a tmdb ref, except the feed entry (both) and the Coming up shelf (neither; a release-tracking item id).
3. The only bridge is title → library via a full navigate; the library modal cannot address a plain movie as a title (`find_tmdb_id/1` covers tv_series and movie_series only).
4. `DiscoveryLive`'s `data-nav-transient-params="title activity"` is space-separated against a comma-splitting reader, so Discovery modals are remembered by the sidebar. (bug)
5. `?selected=` on `/incoming` names a pursuit, so the entity param name is already overloaded across hosts.
