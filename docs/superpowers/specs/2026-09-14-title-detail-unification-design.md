# Title detail unification — design

Date: 2026-09-14. Campaign `campaigns/title-detail-unification.md`, branch
`title-detail-unification`. Supersedes the two-surface split of UIDR-035
(files → library modal, no files → title modal) with one title detail
modal on Home, Library, Discovery and Incoming, composed by facts. Owner's
constraints, verbatim: the library modal is "BEAUTIFUL" and its quality
must not take a hit; architecture in layers (sources → composition → host
→ presentation); local facts synchronous on open, remote facts as owned
asyncs landing by identity; research and a spec before any code.

Research inputs (2026-09-14, this session): a section matrix, an event /
async / PubSub inventory of both hosts, an emitter inventory, a nav-overlay
inventory, a test and story inventory, and a residue count on the dev
database read through context functions. Their findings are folded into
the tables below; file:line references are to the branch at `77714ea4`.

## Glossary

Working terms, defined before use. Existing terms keep their
`docs/GLOSSARY.md` meaning; the campaign file's terms are repeated where
this document depends on them.

- **Title** (existing) — the `TMDB.Title` snapshot; identity `(tmdb_id, media_type)`, `media_type :: :movie | :tv_series`.
- **Title ref** (existing) — that identity as a tuple; `MediaCentaurWeb.TitleRef` is its URL spelling `<media_type>-<tmdb_id>`.
- **Subject** — what the modal is open on. A title ref, or for the residue an entity id.
- **Owner** — the library container that owns a title: `Library.ExternalIds.tmdb_owners/1` maps a ref to a presentable container id. An owned title has an owner; an unowned title has none.
- **Library half** — the facts that exist only for an owned title: the entity view, progress and resume target, the typed content list (`SeriesDetail` / `CollectionDetail` / the leaf entry), the files. One struct, `Title.Detail.Library`, nil for an unowned title.
- **Residue** — a presentable library entity with no title ref: a video object, a container never matched. On the dev database today: none. A collection is not residue (below).
- **Title address** — `?title=<media_type>-<tmdb_id>` plus `view` and `activity`. The one address for one identity on every hosting page.
- **Entity address** — `?entity=<uuid>` plus `view`. The residue's address, and the address an entity emitter (a library card) hands the host, which canonicalises it to the title address when the entity has a ref. Replaces `?selected=` (which on Incoming already names the pursuit modal).
- **Modal state** — the per-opening UI state the host owns and the renderer reads: which view, which seasons are expanded, which confirm is armed, which menu is open, which plan is in flight. One struct, `Title.ModalState`, reset whenever the subject changes.
- **Local fact** (existing) — a read from a context by identity, synchronous on open (ADR-051).
- **Remote fact** (existing) — a TMDB fetch: the detail payload (snapshot + preview) and, through `ReleaseTracking`, the calendar. Always an owned `start_async` landing by identity.
- **Section** (existing) — one block a fact turns on.
- **Presentation bar** (existing) — the library modal's look and behaviour for an owned title, verified before and after on the same titles at the same viewport.
- **Unified modal** — the result: `Components.DetailPanel` rendering a `Title.Detail`, hosted by `Live.TitleDetailHost` on all four pages. When done it takes the glossary's *title detail modal* name; *library modal* and *title modal* retire.

## Core idea

A title is a TMDB identity, and the detail modal is the one surface that
composes everything the app knows about that identity. Files are one more
fact about the title — like a rung, a calendar, a friend's review, a plan in
flight — not a different surface. One subject, one view-model built by one
pure function from facts, one host that loads local facts on open and lets
remote facts land by identity, one renderer whose sections are present by
what the facts say.

Everything below follows from that: one address per identity, one event
vocabulary, one nav overlay, one story, and the library modal's block
structure as the trunk every section hangs on.

## Greenfield shape

### The subject and its addresses

| Address | Means | Resolution on open |
|---|---|---|
| `?title=<media_type>-<tmdb_id>` | a TMDB title, owned or not | owner by `ExternalIds.tmdb_owners([ref])` → if owned, `Presentable.resolve(owner)` → the library half; snapshot by the order below; every other fact by ref |
| `?title=…&view=info\|cast` | the same, on a sub-view | `Detail.Logic.resolve_view/2` narrows to a renderable view; forced to `:main` on subject change |
| `?title=…&activity=<uuid>` | the same, opened from a friend's or own activity | the page supplies the activity's facts (`page_facts/3`, unchanged) |
| `?entity=<uuid>` | a library entity | `Presentable.resolve(uuid)`; if the resolved subject has a ref (`EntityView.title_ref/1`), the host patches to the title address; else the residue opens on the entity address |

A collection is addressed through its members: the subject of a collection
modal is the selected member movie's ref (UIDR-023: the modal *is* the
selected member's panel). A collection card click resolves the resume-target
member and patches `?title=movie-<member>`; a rail pick is `open_title` with
another member's ref. `?movie=` goes. A hoisted collection (one present
movie) resolves to that movie as today. A collection whose members carry no
ref is residue on the entity address, member selection by member entity id.

Snapshot resolution order, one function in the host: (1) the open detail's
own title when the ref is unchanged; (2) the title intent's embedded title
(the person's authored record, carries TMDB art paths); (3) **the owner's
entity, mapped by `Title.Logic.snapshot_from_entity/1`** (new — replaces the
four ad hoc `Title.new!` mints in `entity_modal.ex:1412, 1421, 1464, 1671`);
(4) the page's in-memory copy (`page_facts/3`); (5) TMDB, fetched. Steps 1–4
are local; step 5 is the fetched open with its flash-and-drop failure path,
unchanged from `title_detail_host.ex:214–240, 640–650`.

### The four layers

| Layer | Owns | Modules after this spec |
|---|---|---|
| Sources | facts by identity | contexts as today: `Library.ExternalIds.tmdb_owners/1`, `Library.Presentable`, `Library.ModalEntry`, `ViewModel.SeriesDetail/CollectionDetail.compose/1`, `Discovery.get_intent/2`, `Discovery.rung/2`, `TrackingDetail.load/2`, `Activities.friend_activity_for/1`, `TitleStates.for_refs/1`, `TitleDownloadParams.get/2`, `ReleaseTracking.complete?/2`, `Capabilities.*`, `PlanningMode.value/0`, `TmdbArtwork.urls/2`, `TMDB.Client`. New: `Library.EntityView.title_ref/1` |
| Composition | the pure build of the view-model | `Components.Title.Detail` (+ `Title.Detail.Library`), `Components.Title.Logic.title_detail/2` (extended), `Title.Logic.snapshot_from_entity/1` (new), `Components.Title.ModalState` (new), `Components.Detail.Logic` (unchanged rules) |
| Host | URL, open/close, events, asyncs, subscriptions, refresh by identity | `Live.TitleDetailHost` (dispatch), `TitleDetailHost.LibraryHalf` (loading the owner's entry, files, progress merges — moved from `EntityModal`), `TitleDetailHost.LibraryEvents` (play, watched, delete, rematch, artwork, track override — moved), `TitleDetailHost.Acquisition` (download, missing episode, rung — merged from both) |
| Presentation | the renderer and its parts, the overlay, the story | `Components.DetailPanel.detail_panel/1` (contract: `detail`, `state`, preferences), `Components.Detail.*` (unchanged), `Components.Title.{WatchlistToggle, TrackingControls, LowerQualityNote, Pennant}` (unchanged), `GlassMenu` (unchanged), one overlay `detail` in `assets/js/input/config.js`, `storybook/detail_panel/detail_panel.story.exs` |

Deleted: `Live.EntityModal`, `Live.IntentAware` (its `title_rungs` moves into
the host), `Components.Title.DetailModal`, `storybook/title/title_detail_modal.story.exs`,
the `title_detail` overlay, `Title.Detail.primary`'s `{:in_library, _}` arm,
`Detail.Logic.facets_for/3` (no caller), `Library.ExternalIds.list_tmdb_entities/0`
(no caller).

### The view-model

```elixir
%Components.Title.Detail{
  ref: {tmdb_id, media_type},
  title: %TMDB.Title{},                      # snapshot, by the order above
  poster_url: _, backdrop_url: _, logo_url: _, # owned: library images; else TmdbArtwork / CDN
  library: %Title.Detail.Library{} | nil,    # the library half — nil for an unowned title
  primary: {:state, :planning | :downloading | :needs_review} | :download | nil,
                                             # unowned only; nil when owned (the play card decides)
  scoped?: boolean,                          # a series' Download carries the scope select
  rung: _, tracking: _, acquisition?: _, lower_quality_accepted?: _, complete?: _,
  release_window: _, planning_mode: _,       # as today
  kind: _, sender: _, note: _, own?: _, activity_id: _,   # the activity the modal speaks for
  friend_activity: [row],                    # the pennants
  preview: %TitlePreview{} | nil             # nil when owned; the entity is the richer source
}

%Components.Title.Detail.Library{
  entity: %Library.EntityView{},             # the presented container
  subject: map,                              # the member subject for a collection, else the entity
  entry: %SeriesDetail{} | %CollectionDetail{} | leaf map,
  progress: _, progress_records: _, resume: _,
  seasons_view: [SeasonView] | nil, movies_view: [MovieRow] | nil,
  member_view: %{member: MovieRow.Library, subject: map} | nil,
  files: [file], files_status: :loading | :loaded | :failed,   # lands by ref
  available: boolean                         # the owner's media dir is online
}
```

`title_detail/2` stays the one builder; it takes the library half as one more
fact. It carries facts, not rules: each section's rule is derived where the
section mounts (`Detail.Logic.playback_props/3`, `TrackingControls.rows/1`,
`Title.Logic.release_ahead?/3`), as today. `primary`'s `{:in_library, _}` arm
goes because `library != nil` says it.

### Modal state

```elixir
%Components.Title.ModalState{
  view: :main | :cast | :info,               # URL-driven (?view=)
  expanded_seasons: MapSet.t(), expanded_item_details: MapSet.t(),
  all_episode_details_open: false, expanded_file_groups: MapSet.t() | nil,
  cast_filter: "", cast_limit: nil,
  delete_confirm: nil | :all | {:file, p} | {:folder, p}, deleting: same,
  rematch_confirm: false,
  open_menu: nil | :mode | :scope, download_scope: :first_season | :everything,
  pending: nil | {:download, name} | {:missing_episode, unit}   # the one plan in flight
}
```

One assign on the socket, replaced by `ModalState.new(view)` on every subject
change and on close. This closes the leaks the inventory found:
`rematch_confirm`, `delete_confirm` and `download_pending` survive an entity
switch today (`entity_modal.ex:130, 279, 1152`), and `download_pending`
survives a subject switch and a successful plan in the title host
(`title_detail_host.ex:229, 375`). `expanded_seasons` is seeded from
`Orientation.initial_expanded_seasons/1` when the library half is a series,
as today.

### The host

**Open.** `handle_params` hook, attached before the page's own, as today
(`title_detail_host.ex:141`). Local facts load synchronously; the library half
included — `SeriesDetail.compose/1` is a projection read, milliseconds
(ADR-051; `no_db_on_render_test` keeps the budget). Remote: `{:title_open,
ref}` for the fetched open, `{:title_preview, ref}` only when there is no
library half, `{:detail_files, ref}` when there is one. Every async lands by
ref and is dropped when the subject moved; `cancel_async` on subject change
and close.

**Events**, one vocabulary. The library side keeps its names (the floor);
title-only controls drop the `title_` prefix; the two duplicated flows take
the identity-based name.

| Event | Fired by | Params | Needs the library half | Replaces |
|---|---|---|---|---|
| `open_title` | title rows, feed entries, person cards, rail tiles, Coming up shelf (after item → ref) | `ref`, `activity?` | no | `open_title`, `select_movie` |
| `select_entity` | hero, continue-watching, recently-added, marquee, library grid | `id` | — (host resolves, then patches a title or entity address) | `select_entity` |
| `close_title` | BACK, backdrop, `data-dismiss-event` | — | no | `close_detail`, `close_title` |
| `select_detail_view` | view controls, Manage | `view` | yes | same |
| `play` | play card, episode / extra rows | `id` | yes | same |
| `toggle_watched`, `toggle_extra_watched`, `toggle_season`, `toggle_item_details`, `toggle_all_episode_details`, `toggle_file_group`, `filter_cast`, `show_more_cast`, `rematch`, `refresh_artwork`, `reset_track_override`, `delete_file_prompt`, `delete_folder_prompt`, `delete_all_prompt`, `delete_cancel` | the library sections | as today | yes | same |
| `download_missing_episode` | a series gap row | `season`, `episode` | the list (the plan needs only the ref) | same |
| `set_rung` | bookmark, tracking switches | `choice`, `ref` | no; identity-guarded | `set_rung` ×2, `modal_watchlist_toggle` |
| `reset_lower_quality` | lower-quality note | `ref` | no; identity-guarded on both paths | same ×2 |
| `review_open` | the pencil | — | no | `modal_review_open`, `title_review_open` |
| `download` | Download main segment | `mode?` | no | `title_download` |
| `download_mode_toggle`, `download_scope_toggle`, `download_menu_close`, `download_scope` | the glass menus | `choice` for scope | no | `title_mode_toggle`, `title_scope_toggle`, `title_menu_close`, `title_scope` |
| `activity_delete` | Delete <noun> | — | no | `title_activity_delete` |

A library-half event arriving without a library half halts as a no-op, the
way the title host already treats a modal verb with no open modal
(`title_detail_host.ex:584`). `@modal_events` is the union.

**Subscriptions.** The host owns every topic the modal needs and declares
them; a page that hosts the modal does not subscribe any of them itself. A
page that needs one of these topics for its own state still gets the message
(one subscription per process) and handles it in its own `handle_info`,
because the host's hook returns `{:cont, socket}` for every message it does
not own exclusively. This replaces the asymmetry the inventory found (the
library host subscribes five topics and depends on a sixth the pages
subscribe; the title host subscribes one and depends on two) and the
"use TitleDetailHost before IntentAware" ordering rule that existed only
because `IntentAware` halts `:title_intent_changed`.

| Topic | Message | Reaction, keyed by |
|---|---|---|
| `library:updates` | `{:entities_changed, ids}` | re-resolve the owner by ref (an import can make an open unowned title owned); reload the library half when the owner ∈ ids |
| `library:views` | `{:library_view_updated, :detail, _}` | reload the library half |
| `playback:events` | `entity_progress_updated`, `extra_progress_updated`, `playback_state_changed`, `track_override_changed` | in-memory merges by entity id, as `entity_modal.ex:413–502` |
| `release_tracking:updates` | `releases_updated`, `item_removed` | reload `tracking` by ref; a series also reloads its library half |
| `activities:updates` | `activity_received/sent/deleted` | `friend_activity` by ref |
| `acquisition:updates` | `PlanEvents.Changed`, pursuit events | acquisition state by ref; a series recomposes claimed units |
| `discovery:updates` | `title_intent_changed` | `rung` by ref and the `title_rungs` map (absorbing `IntentAware`); `{:cont}` so Incoming's rows and Discovery's lists refresh in their own clauses |

`Capabilities` and `Settings` are read on every build (`acquisition?`,
`prowlarr_ready?`, `planning_mode`); the router-level `CapabilitiesAware`
keeps `tmdb_ready`. The mount-time reads that never refreshed
(`entity_modal.ex:634–635`) go.

MC0011 (`credo_checks/entity_modal_contract.ex`) names the one trait and its
seven subscriptions, drops the dead `WatchlistAware` entry, and matches
fully-qualified `subscribe` calls too.

### The presentation

One block structure — the library modal's — for both halves. Rows are the
`CinematicShell` slots; columns are owned / unowned.

| Block | Owned title | Unowned title |
|---|---|---|
| Hero backdrop, placeholder, pennants | library image ladder (`detail_panel.ex:278–285`) | `TmdbArtwork` → CDN → preview |
| Lockup | entity name, logo, tagline | snapshot name; preview logo and tagline when landed |
| Progress hairline | subject progress | absent — no track; the lockup-to-metadata rhythm must match the owned case at the bar |
| Left column: metadata row | from the entity (`build_metadata_items/2`) | from the preview; the snapshot's type · year line until it lands |
| Left column: action row (`detail_actions`) | play card (Play / Resume / Watch again / Offline) · view control · Letterboxd · bookmark · Review · Manage · member Watched toggle | Download split button + scope select, or the acquisition state, or nothing (`primary`) · Letterboxd (a movie with a ref) · bookmark · Review · Delete <noun> for an own activity |
| Right column: prose | the synopsis | the note (a friend's words, attributed; or the own watchlist note) above the overview from the preview or the snapshot |
| Right column, owned, with a note | the note above the synopsis — a friend reviewed a title the library owns | — |
| Rail | collection members (`CollectionRail`) | — |
| Body: content list | seasons / extras / cast / Manage by view | — |
| Body: tracking card | switches + release dates readout as today | switches + lower-quality note + readout as today |
| Panel height | `full` when there is a body | content-fit unless a tracking card renders (the bare-movie rule, `detail_panel.ex:776–781`) |

Dropped for both: the facet strip. The library dropped catalog facts on
2026-08-08 ("the main view is for deciding to press Play, not for reference
lookup", `detail_panel.ex:366–369`); the same reasoning holds for deciding to
press Download. `TitlePreview.facets` and `Detail.Logic.facets_for/2` stay
for the plan modal's `PreviewBody`.

Cast for an unowned title: not in this campaign. The preview carries ten
people; the library's `CastPanel` expects the entity's cast with episode
membership. A follow-up may add a cast view fed by the preview; recorded
below.

`DetailPanel.detail_panel/1`'s contract collapses from 35 attrs to:

| attr | type | meaning |
|---|---|---|
| `detail` | `Title.Detail` or nil | nil renders the closed shell |
| `state` | `Title.ModalState` | the per-opening state |
| `today` | `Date` | the host's date |
| `spoiler_free`, `letterboxd_links`, `tmdb_ready`, `review?` | booleans | host preferences, as today |
| `on_play`, `on_close` | strings | `"play"`, `"close_title"` |

### The nav overlay

One overlay, `detail`, the union of today's two. Absent zones are skipped:
`_overlayEntry` takes the first region with items (`orchestrator.js:502–505`)
and every graph edge walks its candidate list past empty zones
(`nav_graph.js:61–76`) — verified in the inventory against the code and
`orchestrator.test.js:3277–3303, 3715`.

| Zone | Type | Holds | up | down | back |
|---|---|---|---|---|---|
| `detail_actions` | TOOLBAR | the action row, both halves | — | `[detail_menu, detail_rail, manage_tools, manage_list, detail_list, detail_cast, detail_tracking]` | — (dismiss) |
| `detail_menu` | TREE | an open glass menu list; `data-nav-dismiss-event="download_menu_close"` | `[detail_actions]` | `[detail_rail, manage_tools, manage_list, detail_list, detail_cast, detail_tracking]` | `[detail_actions]` |
| `detail_rail`, `manage_tools`, `manage_list`, `detail_list`, `detail_cast`, `detail_tracking` | as today | as today | as today | as today | `[detail_actions]` |

`entry`: `[detail_actions, detail_menu, detail_rail, manage_tools, manage_list,
detail_list, detail_cast, detail_tracking]`. `title_detail_body`,
`title_detail_menu`, `title_detail_tracking` go, with
`discovery_behavior.test.js:30` (which asserts the whole `title_detail`
object) rewritten against `detail`. The JS nested-view dismissal reads
`data-dismiss-event` like the flat path instead of hard-coding
`close_detail` (`orchestrator.js:1236`); the `?? "close_detail"` fallback goes
because every `<.modal on_close>` declares its event.

`data-nav-transient-params` on every hosting page lists `title`, `entity`,
`view`, `activity` (Incoming keeps `selected`, `plan`, `prowlarr_search`).

### Emitters

Every place that opens the modal, and what it hands the host.

| Surface | Identity it holds | Event | Change |
|---|---|---|---|
| Home hero, continue-watching, recently-added; Library grid | entity uuid | `select_entity` | none; the host canonicalises |
| Home Coming up marquee | entity uuid (source `ComingUpItemRef` also holds the ref) | `select_entity` | none |
| Collection rail tile | member entity uuid | `open_title` with the member's ref (`MovieRow.Library` gains `ref`) | replaces `select_movie` |
| Discovery watchlist row, Incoming omnibox row | ref | `open_title` | none |
| Feed entry, person card | ref + activity | `open_title` | none |
| Incoming Coming up shelf | tracking item id → ref (server) | `select_event` → patch | none |
| Deep links | ref / entity id | `handle_params` | `?selected=` → `?entity=`; `?movie=` goes |
| Title modal's "In library" | owner id | full navigate to `/library?selected=` | deleted — the owned title shows Play where it is |

## Diff against the code — every incoherence and its disposition

1. **Two hosts, two renderers, two view-models, two addresses, two overlays, two stories** for one idea. *Fix now* — this campaign.
2. **Seven fact loads written twice** (tracking, rung, pennants, quality acceptance, approval policy, acquisition readiness, review flow), with divergences: `today` fresh vs mount-time; refresh on selection vs per build. *Fix now:* one builder, one refresh path.
3. **Four ad hoc `Title.new!` mints** in the library host (campaign said two). *Fix now:* the snapshot order gains the entity source.
4. **A collection's id stamped as a `:movie` ref** (`entity_modal.ex:1655–1659`; tracking-controls spec incoherence 12) flows into `TrackingDetail.load`, `Discovery.rung`, `TitleDownloadParams.get` and `set_rung`, colliding with the movie id space. And the feature it serves has no writer: `ReleaseTracking.LibraryLinks` links tracking items to `tv_series` containers only, so a collection's upcoming-parts rail tiles (`CollectionDetail.upcoming_items/2`) can never be fed by a rung set on the collection. *Fix now:* the collection-level tracking block goes; the subject of a collection modal is the member movie, whose bookmark and switches act on a real ref. *Scheduled convergence:* whether collections get an identity of their own (a `:collection` media type across `TitleRef`, `TitleIntent`, `ReleaseTracking.Item`) or the upcoming-parts path is deleted is a separate design; until then `MovieRow.Upcoming` stays as dead-but-harmless read code, named in the campaign's deferred items. See open decision 1b.
5. **Two rung readouts** in the library host (`rung` from `Discovery.rung/2`; `subject_rung` from `IntentAware`'s map) with different subjects and refresh triggers. *Fix now:* one rung by ref; `IntentAware`'s map moves into the host.
6. **Mount-time facts never refreshed** (`approval_policy`, `acquisition?`, `entity_modal.ex:634–635`). *Fix now:* read per build.
7. **Per-opening state leaks across subject switches** (`rematch_confirm`, `delete_confirm`, `download_pending` in the library host; `download_pending` in the title host, also left set after a successful plan). *Fix now:* `ModalState`, replaced on every subject change.
8. **Identity guards differ**: the library host guards `set_rung` / `reset_lower_quality` against the open entry; the title host's `reset_lower_quality` accepts any ref. *Fix now:* both guarded.
9. **Subscription asymmetry** and the `IntentAware` ordering hack. *Fix now:* the host owns seven topics; pages piggyback; MC0011 enforces.
10. **Incoming never refreshes an open title modal on activity or plan events** (zero `refresh_title_detail` calls in `incoming_live.ex`). *Fixed by 9.*
11. **`{:delete, id}` lands without an identity check** (`entity_modal.ex:1894`). *Fix now:* land by ref.
12. **An unknown `?selected=` leaves the id and the URL stale** (`entity_modal.ex:735–738`) while the title host flashes and drops the param. *Fix now:* one abandon path for both address forms.
13. **`data-nav-transient-params="title activity"` on Discovery is space-separated** against a comma-splitting reader (`root.html.heex:83`), so the sidebar remembers an open Discovery modal. *Fix now*, phase 0.
14. **`?selected=` is overloaded**: an entity on Home and Library, a pursuit on Incoming. *Fix now:* the residue takes `?entity=`.
15. **MC0011 is stale**: a dead `WatchlistAware` key, no coverage of the title host or `IntentAware`, and a single-segment alias pattern that misses `MediaCentaur.Library.subscribe()`. *Fix now*, phase 0 and phase 4.
16. **The nested-view dismissal hard-codes `close_detail`** in JS (`orchestrator.js:1236`). *Fix now:* read the DOM attribute on both paths.
17. **`title_detail_tracking` is documented TOOLBAR, configured TREE** (`docs/input-system.md:308` vs `config.js:137`). *Moot:* the zone goes; the doc is rewritten for the one overlay.
18. **The hint bar has no legend for any overlay region** (`app.css:2472–2521`). *Out of scope; recorded* in the campaign's deferred items.
19. **The cursor can leak to the page for one patch when the region holding it empties** (a glass menu closed by click-away, a ledger emptied by Delete all; `orchestrator.js:195–217, 380–382`). *Out of scope; recorded.* Not runtime-verified.
20. **Dead code**: `Detail.Logic.facets_for/3` (movie series), `ExternalIds.list_tmdb_entities/0`. *Fix now:* deleted, phase 0.
21. **Duplicate root attributes** (`data-detail-mode` on `detail_panel.ex:325` and `modal.ex:74`; `data-dismiss-event` on `detail_modal.ex:116` and `modal.ex:75`). *Fix now:* `modal.ex` is the one source.
22. **The facet strip** shows on unowned titles what the library removed on 2026-08-08. *Fix now:* dropped for both; see the presentation table.
23. **The "In library" bridge** is a full page navigate that loses the Discovery or Incoming page. *Fix now:* deleted; Play renders in place.
24. **`detail_panel.story.exs`'s moduledoc** names a variation that does not exist and omits eight. *Fix now:* the story is rewritten.
25. **`rung_atom/1` and `@rungs`** exist twice, verbatim. *Fix now.*
26. **The Offline placeholder in the play card is not focusable** (`play_card.ex:53–63`). *Out of scope; recorded.*
27. **A duplicate presentable owner for one ref** (two library movies with the same TMDB id) resolves to one of them under the title address. *Accepted:* a library holds one presentable owner per identity; a duplicate is a library defect the Manage panel exposes, not a second address.

## Open decisions — recommendations

Each is decided with the owner before phase 1; the recommendation is what
the phase plan assumes.

1. **The residue's address.** *Recommend:* `?entity=<uuid>`, resolved by the same host to the same view-model; canonicalised to `?title=` when the entity has a ref. `TitleRef` does **not** learn `:collection` in this campaign — a collection is addressed through its member (UIDR-023 already makes the modal the member's panel), which gives the bookmark, the switches and Review a real ref.
   1b. **Collection tracking.** *Recommend:* delete the collection-level tracking block now (incoherence 4); open a follow-up design for a collection identity or for deleting the upcoming-parts rail path; and ship a migration that deletes `title_intents` (and derived tracking items) whose `(tmdb_id, :movie)` equals a library collection's `tmdb_collection` external id — rows only the deleted block could have written. The migration is reversible in the sense that nothing else reads them; the paired down-migration is a no-op.
2. **The preview for an owned title.** *Recommend:* no preview fetch when the library half is present; the metadata row has one builder per source (entity / preview); the facet strip goes for both.
3. **Collection member selection.** *Recommend:* the member ref is the subject; `?movie=`, `selected_member_id`, `subject_rung` and `watchlist_subject/2` go. Nothing else on the detail needs a member concept: the rail reads `member_view` from the library half.
4. **Where the library half's state lives.** *Recommend:* host state, one struct `Title.ModalState`, reset on subject change; not on the view-model. Name is the owner's call.
5. **Event naming.** *Recommend:* the table above — library names kept, `title_` prefix dropped, `set_rung` and `review_open` for the duplicated flows, `close_title` as the one close.
6. **Nav overlay merge.** *Recommend:* one `detail` overlay with `detail_menu` added; verified that absent zones are skipped by entry order and by every edge.
7. **Tests under ADR-027.** ADR-027 names parser and pipeline tests and nothing else (`decisions/architecture/2026-03-07-027-…md:15–17`); the modal's LiveView tests are not append-only by that record. *Recommend* a stricter rule for this campaign anyway: no modal test is deleted; a test whose address form or element id changes is re-addressed 1:1 with its name and assertion intact; the only tests removed are those asserting a deleted behaviour (the "In library" bridge, `?movie=`, the collection tracking block), each named in the phase's commit message. Rule 3 of ADR-027 (never loosen an assertion) is honoured throughout.
8. **Emitters.** *Recommend:* entity emitters keep `select_entity` and the host canonicalises — no projection (hero, continue-watching, recently-added, browse) has to grow a ref. Title emitters are unchanged. The rail tile switches to `open_title`.
9. **Subscriptions** (new). *Recommend:* the host owns the seven topics, pages piggyback, `IntentAware` is deleted, MC0011 enforces. Alternative considered and rejected: keep `IntentAware` and the attach-order rule — it is the smell the inventory named.
10. **Cast for unowned titles** (new). *Recommend:* out of scope; recorded as a follow-up.

## What goes

`lib/media_centaur_web/live/entity_modal.ex` (2020 lines),
`lib/media_centaur_web/live/intent_aware.ex`,
`lib/media_centaur_web/components/title/detail_modal.ex` (406 lines),
`storybook/title/title_detail_modal.story.exs`, the `title_detail` overlay
and its three zones and selectors in `config.js`, `select_movie`,
`modal_watchlist_toggle`, `modal_review_open`, `close_detail`, every
`title_*` event name, `?selected=` and `?movie=` on Home and Library,
`Title.Detail.primary`'s `{:in_library, _}`, `Detail.Logic.facets_for/3`,
`ExternalIds.list_tmdb_entities/0`, the collection-level tracking block and
`find_tmdb_id/1`, the four `Title.new!` mints, `rung_atom/1`'s second copy,
the "In library" link, the `title_detail_modal` and `entity_modal_*` unit
test files (their tests move with the code to the host's modules).

## Records

- **UIDR-043** — *One title detail, composed by facts* — supersedes UIDR-035's rules 1 and 2 (the split) and its 2026-09-14 amendment's page-membership clause, keeps rules 3–6; records the subject, the two address forms, the bar, and the collection-through-member rule. Drafted alongside this spec as `proposed`.
- **UIDR-019** — amended: one overlay with `detail_menu`; the nested-view dismissal reads the DOM attribute.
- **UIDR-023** — amended: the member is the subject; `?movie=` retired.
- **Glossary** — *title detail modal* rewritten for both halves; *library modal*, *title modal*, *library detail*, *title detail* retired; new rows: *owner*, *library half*, *modal state*, *entity address*, *title address*.
- **`docs/input-system.md`** — the overlay section for one `detail`.
- **`docs/architecture.md`** — the trait list.
- **`credo_checks/entity_modal_contract.ex`** — renamed to name the one trait (`TitleDetailContract` or the owner's choice), its seven topics, qualified-call matching.
- **Wiki** — *Using Media Centaur* pages that describe the library modal and the Discovery/Incoming title modal; *Keyboard and Gamepad* (BACK in the modal is unchanged in behaviour; the description drops the second modal).
- **CHANGELOG** — one user-facing entry: "A title opens the same way everywhere. A show or film you own shows Play on Discovery and Incoming; one you don't shows Download on Home and Library where such a title can be opened. Links to a title work on every page."

## Tests

Test-first per phase (`automated-testing`). What each phase writes before
its code:

| Phase | Red first |
|---|---|
| 0 | `discovery_live_test`: the page root's transient params are comma-separated and include `title` and `activity` (`has_element?`); the MC0011 check's own test (add one if none exists) for the qualified-call pattern and the dead key |
| 1 | `components/title/logic_test`: `title_detail/2` with a library half (primary nil; `scoped?`; `library.subject` for a collection member); `snapshot_from_entity/1` for movie, series, collection member (name, year, release date, overview, art paths when the entity's TMDB image record carries them); `Library.EntityView.title_ref/1` for each kind; `ModalState.new/1` and `reset` semantics |
| 2 | `storybook_render_test` over the rewritten `detail_panel.story.exs` (every owned variation moved to `detail:`/`state:`; every title-modal variation merged); `components/detail_panel_test` for the new pure helpers (which half decides the action row; content-fit for an unowned title with no tracking card); `library_live_test` untouched and green |
| 3 | `discovery_live_test` / `incoming_live_test`: every `#title-*` assertion re-pointed to the panel's ids; new: an owned title opened on Discovery shows Play and plays in place; a deep link to an owned series on Incoming renders its seasons; an import that lands while an unowned title is open turns Download into Play (`entities_changed`); `title_intent_changed` refreshes the bookmark on Incoming without `IntentAware`; JS: `index.test.js` for the `detail` overlay's `detail_menu`, `discovery_behavior.test.js` rewritten, `orchestrator.test.js` nested dismissal reads the attribute |
| 4 | `library_live_test`, `home_live_test`, `library_live_leaf_hairline_test`, `library_live_tv_orientation_test`, `entity_modal_tracking_test`, `page_smoke_test`, `no_db_on_render_test`: `?selected=` → `?title=`, `?movie=` → the member's title address, element ids unchanged where the panel keeps them; new: `?entity=<video object>` opens the residue; `?entity=<titled>` canonicalises; a collection card opens on the resume-target member's address; the rail patches the member address; a subject switch resets `ModalState`; `{:delete, _}` for a moved-on subject is dropped; the `entity_modal_*` unit tests move to the host modules' test files; e2e `library.spec.js` and `detail-backdrop.spec.js` addresses |
| 5 | none (records) |

`entity_modal_refresh_test.exs`'s "episode list vanished on player close"
regression moves with `refresh_selected_entry/1` to `LibraryHalf`'s test,
name intact.

## Phase plan

Each phase ends with `mix precommit` clean and a working product; phases 2,
3 and 4 end with the bar check — the same owned titles (a movie with
progress, a series mid-season, a collection) captured before and after at
1920×1080 with `page-shot`, judged by the owner. No phase merges alone; the
branch merges at the end of phase 5 or is deleted.

0. **Hygiene** — the transient-params fix; MC0011 refreshed; dead code deleted. Half a session.
1. **Composition** — `Title.Detail.Library`, `Title.Detail` gains `library` and loses `{:in_library, _}`, `title_detail/2` extended, `snapshot_from_entity/1`, `EntityView.title_ref/1`, `ModalState`. Rendered by nothing yet. One session.
2. **Presentation** — (a) `DetailPanel` takes `detail` + `state`; `EntityModal` builds the `Title.Detail` from its assigns through the one builder (a bridge, deleted in phase 4); the story rewritten; bar check 1. (b) `DetailPanel` renders an unowned title: Download control in the action row, acquisition state, note, preview/snapshot metadata and overview, content-fit height; the title story's variations merged in; verified in storybook. Two sessions.
3. **Host, first adoption** — `TitleDetailHost` gains the library half (`LibraryHalf`, `LibraryEvents`, `Acquisition` split out), the subscription set, `title_rungs`, `ModalState`, the entity address; Discovery and Incoming render `DetailPanel`; `Title.DetailModal`, its story, the `title_detail` overlay and the bridge go; `detail_menu` added. Bar check 2: one owned title on Discovery beside the same title on Library. Two sessions.
4. **Host, second adoption** — Home and Library adopt `TitleDetailHost`; `EntityModal` and `IntentAware` deleted; addresses migrated in tests; the collection-tracking migration; `data-nav-transient-params`; MC0011 renamed and extended. Bar check 3 on Home and Library. One to two sessions.
5. **Records** — UIDR-043 accepted, UIDR-019 and UIDR-023 amended, glossary, `docs/input-system.md`, `docs/architecture.md`, wiki, CHANGELOG; campaign closed; merge to `main`; `/ship minor`. Half a session.

## Scope cost

The coherent path rewrites the two hosts (2711 lines) into one trait and
three concern modules, retargets the 802-line renderer's contract and merges
a 406-line renderer into it, rewrites two stories (51 variations) into one,
re-addresses roughly 180 modal tests across eleven Elixir files and three
Playwright specs, rewrites one overlay and three JS test files, extends one
Credo check, adds one migration, and touches five records, the glossary,
three wiki pages and the changelog. Six to eight sessions including the
three bar checks. The cheap path — add a Play button to the title modal for
owned titles and keep both — would leave every duplicated load, both
addresses, the collection-as-movie ref and the mount-time facts in place,
and was not considered.
