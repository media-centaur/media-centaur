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
the tables below; the raw inventories are in the sibling folder
`2026-09-14-title-detail-unification-research/`; file:line references are
to the branch at `77714ea4`.

Iteration 2 (2026-09-14, after the owner approved the ten decisions): a
`unify_design` pass over this document itself. What it changed is in the
body and listed at the end.

## Glossary

Working terms, defined before use. Existing terms keep their
`docs/GLOSSARY.md` meaning; the campaign file's terms are repeated where
this document depends on them.

- **Title** (existing) — the `TMDB.Title` snapshot; identity `(tmdb_id, media_type)`, `media_type :: :movie | :tv_series`.
- **Title ref** (existing) — that identity as a tuple; `MediaCentaurWeb.TitleRef` is its URL spelling `<media_type>-<tmdb_id>`.
- **Subject** — what the modal is open on. A title ref, or for the residue an entity id. Inside the library half, *subject* also names the entity the lockup speaks of: the selected member of a collection, else the container.
- **Owner** — the library container that owns a title: `Library.ExternalIds.tmdb_owners/1` maps a ref to a presentable container id. An owned title has an owner; an unowned title has none.
- **Container** — the presentable library entity the owner resolves to (`Library.Presentable.resolve/1`): a series, a collection, a movie or a video object. The `entity` every `Components.Detail.*` part reads.
- **Library entry** — the typed composition of a container's content: `ViewModel.SeriesDetail`, `ViewModel.CollectionDetail`, or `ViewModel.LeafDetail` (new: the movie / video-object entry that is a bare map today). Every entry carries `entity`, `progress`, `progress_records`, `resume_target`.
- **Library half** — the facts that exist only for an owned title: the entry, the subject, the selected member, the files, availability. One struct, `Title.Detail.Library`, nil for an unowned title.
- **Residue** — a presentable library entity with no title ref: a video object, a container never matched. On the dev database today: none. A collection is not residue (below).
- **Title address** — `?title=<media_type>-<tmdb_id>` plus `view` and `activity`. The one address for one identity on every hosting page.
- **Entity address** — `?entity=<uuid>` plus `view`. The residue's address, and the address an entity emitter (a library card, a rail tile) hands the host, which canonicalises it to the title address when the entity has a ref. Replaces `?selected=` (which on Incoming already names the pursuit modal).
- **Activity the modal speaks for** — the friend's or own activity a title was opened from: one `Activities.activity_row` (`%{activity, nickname, own?}`), the same shape the pennants read, or nil. Read by identity from the `activity` param.
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
structure as the trunk every section hangs on. And one corollary the
unify pass made explicit: **the view-model carries facts and nothing
derived from them** — every rule (which primary action, whether the
tracking card shows, whether a series' Download carries a scope) is
computed where its section mounts, from the facts, by one function.

## Greenfield shape

### The subject and its addresses

| Address | Means | Resolution on open |
|---|---|---|
| `?title=<media_type>-<tmdb_id>` | a TMDB title, owned or not | owner by `ExternalIds.tmdb_owners([ref])` → if owned, `Presentable.resolve(owner)` → the library half; snapshot by the order below; every other fact by ref |
| `?title=…&view=info\|cast` | the same, on a sub-view | `Detail.Logic.resolve_view/2` narrows to a renderable view; forced to `:main` on subject change |
| `?title=…&activity=<uuid>` | the same, opened from a friend's or own activity | `Activities.get_row/1` (new) reads the activity by identity; the page supplies nothing |
| `?entity=<uuid>` | a library entity | `Presentable.resolve(uuid)`; if the resolved subject has a ref (`EntityView.title_ref/1`), the host patches to the title address; else the residue opens on the entity address |

A collection is addressed through its members: the subject of a collection
modal is the selected member movie's ref (UIDR-023: the modal *is* the
selected member's panel). A collection card click resolves the resume-target
member and patches `?title=movie-<member>`; a rail tile is an entity
emitter like any card — `select_entity` with the member's id, canonicalised
by the host. `?movie=` goes. A hoisted collection (one present movie)
resolves to that movie as today. A collection whose members carry no ref is
residue on the entity address, member selection by member entity id.

Snapshot resolution order, one function in the host: (1) the open detail's
own title when the ref is unchanged; (2) the title intent's embedded title
(the person's authored record, carries TMDB art paths); (3) **the owner's
entity, mapped by `Title.Logic.snapshot_from_entity/1`** (new — replaces the
four ad hoc `Title.new!` mints in `entity_modal.ex:1412, 1421, 1464, 1671`);
(4) the page's in-memory copy (`page_facts/3`, now only Incoming's omnibox
results and plan title — the sources a page alone holds); (5) TMDB,
fetched. Steps 1–4 are local; step 5 is the fetched open with its
flash-and-drop failure path, unchanged from `title_detail_host.ex:214–240,
640–650`.

### The four layers

| Layer | Owns | Modules after this spec |
|---|---|---|
| Sources | facts by identity | contexts as today: `Library.ExternalIds.tmdb_owners/1`, `Library.Presentable`, `Library.ModalEntry`, `ViewModel.SeriesDetail/CollectionDetail.compose/1`, `Discovery.get_intent/2`, `Discovery.rung/2`, `TrackingDetail.load/2`, `Activities.friend_activity_for/1`, `TitleStates.for_refs/1`, `TitleDownloadParams.get/2`, `ReleaseTracking.complete?/2`, `Capabilities.*`, `PlanningMode.value/0`, `TmdbArtwork.urls/2`, `TMDB.Client`. New: `Library.EntityView.title_ref/1`, `Activities.get_row/1` |
| Composition | the pure build of the view-model | `Components.Title.Detail` (+ `Title.Detail.Library`), `ViewModel.LeafDetail` (new), `Components.Title.Logic.title_detail/2` (extended), `Title.Logic.snapshot_from_entity/1` (new), `Components.Title.ModalState` (new) |
| Presentation rules | the rules derived from facts where a section mounts | `Components.Detail.Logic` gains `primary_action/2` and `tracking_card?/1`; keeps `playback_props/3`, `resolve_view/2`, `secondary_view/2`, `member_playback/1`, …; `Title.Logic.release_ahead?/3` and `TrackingControls.rows/1` unchanged |
| Host | URL, open/close, events, asyncs, subscriptions, refresh by identity | `Live.TitleDetailHost` (dispatch), `TitleDetailHost.LibraryHalf` (loading the owner's entry, files, progress merges — moved from `EntityModal`), `TitleDetailHost.LibraryEvents` (play, watched, delete, rematch, artwork, track override — moved), `TitleDetailHost.Acquisition` (download, missing episode, rung — merged from both), `Live.Subscriptions` (new: subscribe once per process) |
| Presentation | the renderer and its parts, the overlay, the story | `Components.DetailPanel.detail_panel/1` (contract: `detail`, `state`, preferences), `Components.Detail.*` (unchanged), `Components.Title.{WatchlistToggle, TrackingControls, LowerQualityNote, Pennant}` (unchanged), `GlassMenu` (unchanged), one overlay `detail` in `assets/js/input/config.js`, `storybook/detail_panel/detail_panel.story.exs` |

Deleted: `Live.EntityModal`, `Live.IntentAware` (its `title_rungs` map
moves into `IncomingLive`, its only remaining reader), `Components.Title.DetailModal`,
`storybook/title/title_detail_modal.story.exs`, the `title_detail` overlay,
`Title.Detail.primary` and `scoped?`, the `detail_presentation` assign and
the `drawer` value of `data-detail-mode` (never produced), `Detail.Logic.facets_for/3`
(no caller), `Library.ExternalIds.list_tmdb_entities/0` (no caller).

### The view-model

```elixir
%Components.Title.Detail{
  ref: {tmdb_id, media_type},
  title: %TMDB.Title{},                      # snapshot, by the order above
  poster_url: _, backdrop_url: _, logo_url: _, # owned: library images; else TmdbArtwork / CDN
  library: %Title.Detail.Library{} | nil,    # the library half — nil for an unowned title
  acquisition_state: :planning | :downloading | :needs_review | nil,   # TitleStates.for_refs/1
  release_mode_available: boolean,           # Capabilities.prowlarr_ready?/0
  rung: _, tracking: _, acquisition?: _, lower_quality_accepted?: _, complete?: _,
  release_window: _, planning_mode: _,       # as today
  activity: activity_row | nil,              # the activity the modal speaks for
  intent_note: String.t() | nil,             # the person's own watchlist note
  friend_activity: [activity_row],           # the pennants
  preview: %TitlePreview{} | nil             # nil when owned; the entity is the richer source
}

%Components.Title.Detail.Library{
  entry: %SeriesDetail{} | %CollectionDetail{} | %LeafDetail{},   # entity, progress, records, resume inside
  subject: map,                              # the member subject for a collection, else entry.entity
  member: %MovieRow.Library{} | nil,         # the selected member, for the rail and its Watched toggle
  files: :loading | {:ok, [file]} | :failed, # lands by ref
  available: boolean                         # the container's media dir is online
}
```

`title_detail/2` stays the one builder; it takes the library half and the
activity row as two more facts. Nothing on the struct is derived: `primary`
becomes `Detail.Logic.primary_action(detail, today) :: {:play, props} |
{:download, scoped?} | {:state, s} | :none`, computed where the action row
mounts from `library`, `acquisition_state`, `release_mode_available` and the
snapshot's date — the one function that today is split between
`Title.Logic.primary/2` (title side, at build) and
`Detail.Logic.playback_props/3` (library side, at mount). `scoped?` is
`media_type == :tv_series` inside it. The note line is derived too: the
activity's text attributed to its nickname when there is one, else the
intent note. `seasons_view` and `movies_view` are not fields: they were
accessors on the entry (`entity_modal.ex:1060–1070`), and the renderer reads
`entry.seasons` / `entry.movies` by match. `files` is one value, not a list
plus a status.

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
change and on close. `view` is the runtime instance of the `?view=` param —
only `handle_params` writes it. This closes the leaks the inventory found:
`rematch_confirm`, `delete_confirm` and `download_pending` survive an entity
switch today (`entity_modal.ex:130, 279, 1152`), and `download_pending`
survives a subject switch and a successful plan in the title host
(`title_detail_host.ex:229, 375`). `expanded_seasons` is seeded from
`Orientation.initial_expanded_seasons/1` when the entry is a series, as
today.

### The host

**Open.** `handle_params` hook, attached before the page's own, as today
(`title_detail_host.ex:141`). Local facts load synchronously; the library half
included — `SeriesDetail.compose/1` is a projection read, milliseconds
(ADR-051; `no_db_on_render_test` keeps the budget). Remote: `{:title_open,
ref}` for the fetched open, `{:title_preview, ref}` only when there is no
library half, `{:detail_files, ref}` when there is one. Every async lands by
ref and is dropped when the subject moved; `cancel_async` on subject change
and close. The `activity` param is read by identity (`Activities.get_row/1`)
on every hosting page, so a shared `?title=…&activity=` link works on
Incoming as it does on Discovery.

**Events**, one vocabulary. The library side keeps its names (the floor);
title-only controls drop the `title_` prefix; the two duplicated flows take
the identity-based name.

| Event | Fired by | Params | Needs the library half | Replaces |
|---|---|---|---|---|
| `open_title` | title rows, feed entries, person cards, Coming up shelf (after item → ref) | `ref`, `activity?` | no | `open_title` |
| `select_entity` | hero, continue-watching, recently-added, marquee, library grid, rail tiles | `id` | — (host resolves, then patches a title or entity address; idempotent on the open subject — the same-card toggle of `entity_modal.ex:116` goes, nothing can click a card under the backdrop) | `select_entity`, `select_movie` |
| `close_title` | BACK, backdrop, `data-dismiss-event` | — | no | `close_detail`, `close_title` |
| `select_detail_view` | view controls, Manage | `view` | yes | same |
| `play` | play card, episode / extra rows | `id` | yes | same |
| `toggle_watched`, `toggle_extra_watched`, `toggle_season`, `toggle_item_details`, `toggle_all_episode_details`, `toggle_file_group`, `filter_cast`, `show_more_cast`, `rematch`, `refresh_artwork`, `reset_track_override`, `delete_file_prompt`, `delete_folder_prompt`, `delete_all_prompt`, `delete_cancel` | the library sections | as today | yes | same |
| `download_missing_episode` | a series gap row | `season`, `episode` | the list (the plan needs only the ref) | same |
| `set_rung` | bookmark, tracking switches | `choice`, `ref` | no; identity-guarded | `set_rung` ×2, `modal_watchlist_toggle` (owner: "a lame name, but fine" — a rename is welcome outside this campaign) |
| `reset_lower_quality` | lower-quality note | `ref` | no; identity-guarded on both paths | same ×2 |
| `review_open` | the pencil | — | no | `modal_review_open`, `title_review_open` |
| `download` | Download main segment | `mode?` | no | `title_download` |
| `download_mode_toggle`, `download_scope_toggle`, `download_menu_close`, `download_scope` | the glass menus | `choice` for scope | no | `title_mode_toggle`, `title_scope_toggle`, `title_menu_close`, `title_scope` |
| `activity_delete` | Delete <noun> | — | no | `title_activity_delete` |

A library-half event arriving without a library half halts as a no-op, the
way the title host already treats a modal verb with no open modal
(`title_detail_host.ex:584`). `@modal_events` is the union.

**Subscriptions.** Each consumer declares the topics it needs; a process
subscribes each topic once. `Live.Subscriptions.subscribe(socket, Context)`
(new, a dozen lines) is the one door: the first call for a topic subscribes,
a later call by another trait or the page itself is a no-op, so no message
is delivered twice and no trait depends on another having subscribed. The
host declares the seven below; `IncomingLive` declares `Discovery` for its
rows; Home and Library declare `Library.Views` for their grids. MC0011 is
rewritten to say: in `lib/media_centaur_web/live/`, every subscribe goes
through the door. This replaces the asymmetry the inventory found (the
library host subscribes five topics and depends on a sixth the pages
subscribe; the title host subscribes one and depends on two), the
"use TitleDetailHost before IntentAware" ordering rule that existed only
because `IntentAware` halts `:title_intent_changed`, and the prose rules
in `intent_aware.ex` and `library_live.ex:64–66` telling pages what not to
subscribe. The host's hook returns `{:cont, socket}` for every message, so
a page's own clause for a shared topic still runs.

| Topic | Message | Reaction, keyed by |
|---|---|---|
| `library:updates` | `{:entities_changed, ids}` | re-resolve the owner by ref (an import can make an open unowned title owned); reload the library half when the owner ∈ ids |
| `library:views` | `{:library_view_updated, :detail, _}` | reload the library half |
| `playback:events` | `entity_progress_updated`, `extra_progress_updated`, `playback_state_changed`, `track_override_changed` | in-memory merges by entity id, as `entity_modal.ex:413–502` |
| `release_tracking:updates` | `releases_updated`, `item_removed` | reload `tracking` by ref; a series also reloads its library half |
| `activities:updates` | `activity_received/sent/deleted` | `friend_activity` by ref; `activity` by id |
| `acquisition:updates` | `PlanEvents.Changed`, pursuit events | `acquisition_state` by ref; a series recomposes claimed units |
| `discovery:updates` | `title_intent_changed` | `rung` by ref |

`Capabilities` and `Settings` are read on every build (`acquisition?`,
`release_mode_available`, `planning_mode`); the router-level
`CapabilitiesAware` keeps `tmdb_ready`. The mount-time reads that never
refreshed (`entity_modal.ex:634–635`) go.

### The presentation

One block structure — the library modal's — for both halves. Rows are the
`CinematicShell` slots; columns are owned / unowned.

| Block | Owned title | Unowned title |
|---|---|---|
| Hero backdrop, placeholder, pennants | library image ladder (`detail_panel.ex:278–285`) | `TmdbArtwork` → CDN → preview |
| Lockup | subject name, logo, tagline | snapshot name; preview logo and tagline when landed |
| Progress hairline | subject progress | absent — no track; the lockup-to-metadata rhythm must match the owned case at the bar |
| Left column: metadata row | from the subject (`build_metadata_items/2`) | from the preview; the snapshot's type · year line until it lands |
| Left column: action row (`detail_actions`) | `primary_action/2` → play card (Play / Resume / Watch again / Offline) · view control · Letterboxd · bookmark · Review · Manage · member Watched toggle | `primary_action/2` → Download split button + scope select, or the acquisition state, or nothing · Letterboxd (a movie with a ref) · bookmark · Review · Delete <noun> for an own activity |
| Right column: prose | the note (when the modal speaks for an activity with text) above the synopsis | the note above the overview from the preview or the snapshot |
| Rail | collection members (`CollectionRail`), `member` selected | — |
| Body: content list | seasons / extras / cast / Manage by view, from `entry` | — |
| Body: tracking card | one card, one rule: `Detail.Logic.tracking_card?/1` over `tracking`, `release_window`, `rung`, `lower_quality_accepted?`; the switches' inputs (`release_ahead?`, `complete?`) derived from facts on both halves — the library's hard-coded `release_ahead?={true}` / `complete?={false}` (`detail_panel.ex:674–675`) go | the same card |
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
because every `<.modal on_close>` declares its event. `data-detail-mode`
has one value, `modal`; the `drawer` value in `docs/input-system.md` was
never produced and the doc row is corrected.

`data-nav-transient-params` on every hosting page lists `title`, `entity`,
`view`, `activity` (Incoming keeps `selected`, `plan`, `prowlarr_search`).

### Emitters

Every place that opens the modal, and what it hands the host.

| Surface | Identity it holds | Event | Change |
|---|---|---|---|
| Home hero, continue-watching, recently-added; Library grid | entity uuid | `select_entity` | none; the host canonicalises |
| Home Coming up marquee | entity uuid (source `ComingUpItemRef` also holds the ref) | `select_entity` | none |
| Collection rail tile | member entity uuid | `select_entity` | replaces `select_movie`; the tile template is unchanged but for the event name |
| Discovery watchlist row, Incoming omnibox row | ref | `open_title` | none |
| Feed entry, person card | ref + activity | `open_title` | none; the host reads the activity by id |
| Incoming Coming up shelf | tracking item id → ref (server) | `select_event` → patch | none |
| Deep links | ref / entity id | `handle_params` | `?selected=` → `?entity=`; `?movie=` goes |
| Title modal's "In library" | owner id | full navigate to `/library?selected=` | deleted — the owned title shows Play where it is |

## Diff against the code — every incoherence and its disposition

1. **Two hosts, two renderers, two view-models, two addresses, two overlays, two stories** for one idea. *Fix now* — this campaign.
2. **Seven fact loads written twice** (tracking, rung, pennants, quality acceptance, approval policy, acquisition readiness, review flow), with divergences: `today` fresh vs mount-time; refresh on selection vs per build. *Fix now:* one builder, one refresh path.
3. **Four ad hoc `Title.new!` mints** in the library host (campaign said two). *Fix now:* the snapshot order gains the entity source.
4. **A collection's id stamped as a `:movie` ref** (`entity_modal.ex:1655–1659`; tracking-controls spec incoherence 12) flows into `TrackingDetail.load`, `Discovery.rung`, `TitleDownloadParams.get` and `set_rung`, colliding with the movie id space. And the feature it serves has no writer: `ReleaseTracking.LibraryLinks` links tracking items to `tv_series` containers only, so a collection's upcoming-parts rail tiles (`CollectionDetail.upcoming_items/2`) can never be fed by a rung set on the collection. *Fix now:* the collection-level tracking block goes; the subject of a collection modal is the member movie, whose bookmark and switches act on a real ref. *Scheduled convergence:* whether collections get an identity of their own (a `:collection` media type across `TitleRef`, `TitleIntent`, `ReleaseTracking.Item`) or the upcoming-parts path is deleted is a separate design; until then `MovieRow.Upcoming` stays as dead-but-harmless read code, named in the campaign's deferred items. See decision 1b.
5. **Two rung readouts** in the library host (`rung` from `Discovery.rung/2`; `subject_rung` from `IntentAware`'s map) with different subjects and refresh triggers. *Fix now:* one rung by ref.
6. **Mount-time facts never refreshed** (`approval_policy`, `acquisition?`, `entity_modal.ex:634–635`). *Fix now:* read per build.
7. **Per-opening state leaks across subject switches** (`rematch_confirm`, `delete_confirm`, `download_pending` in the library host; `download_pending` in the title host, also left set after a successful plan). *Fix now:* `ModalState`, replaced on every subject change.
8. **Identity guards differ**: the library host guards `set_rung` / `reset_lower_quality` against the open entry; the title host's `reset_lower_quality` accepts any ref. *Fix now:* both guarded.
9. **Subscription asymmetry** and the `IntentAware` ordering hack. *Fix now:* one subscribe door, every consumer declares, MC0011 enforces.
10. **Incoming never refreshes an open title modal on activity or plan events** (zero `refresh_title_detail` calls in `incoming_live.ex`). *Fixed by 9.*
11. **`{:delete, id}` lands without an identity check** (`entity_modal.ex:1894`). *Fix now:* land by ref.
12. **An unknown `?selected=` leaves the id and the URL stale** (`entity_modal.ex:735–738`) while the title host flashes and drops the param. *Fix now:* one abandon path for both address forms.
13. **`data-nav-transient-params="title activity"` on Discovery is space-separated** against a comma-splitting reader (`root.html.heex:83`), so the sidebar remembers an open Discovery modal. *Fix now*, phase 0.
14. **`?selected=` is overloaded**: an entity on Home and Library, a pursuit on Incoming. *Fix now:* the residue takes `?entity=`.
15. **MC0011 is stale**: a dead `WatchlistAware` key, no coverage of the title host or `IntentAware`, and a single-segment alias pattern that misses `MediaCentaur.Library.subscribe()`. *Fix now*, phase 0 and phase 3.
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

Found by the unify pass (iteration 2):

28. **`primary` and `scoped?` are rules stored on the view-model** (`Title.Logic.primary/2` at build), while the library side derives the same decision at mount (`Detail.Logic.playback_props/3`) — two representations of "what is the primary action". *Fix now:* both go from the struct; `Detail.Logic.primary_action/2` derives it from `library`, `acquisition_state`, `release_mode_available` and the snapshot's date, where the action row mounts.
29. **Five loose activity fields** (`kind`, `sender`, `note`, `own?`, `activity_id`) copied out of an `activity_row` by `page_facts/3` (`discovery_live.ex:138–154`), when the pennants already carry the same rows. *Fix now:* one `activity: activity_row | nil` field, read by identity through a new `Activities.get_row/1`; `intent_note` beside it; the note line derived at mount.
30. **`page_facts/3` carries facts a context can serve.** The activity is a DB record; only Incoming's omnibox results and plan title are page-only. *Fix now:* the host reads the activity by id on every page; `page_facts/3` keeps the snapshot sources alone.
31. **`seasons_view` / `movies_view` are copies of `entry.seasons` / `entry.movies`** (`entity_modal.ex:1060–1070`), and the leaf entry is a bare map beside two structs. *Fix now:* `ViewModel.LeafDetail` makes the entry sum three structs with the same four base fields; the half carries `entry`, and the renderer matches on it.
32. **`files` + `files_status` are two fields for one async fact.** *Fix now:* `files :: :loading | {:ok, [file]} | :failed`.
33. **`member_view` bundles `member` with a second copy of `subject`.** *Fix now:* the half carries `subject` once and `member` (a `MovieRow.Library`) once.
34. **The tracking card has two rules** (`detail_panel.ex:652` and `title/detail_modal.ex:396–402`) and the library one hard-codes its inputs (`release_ahead?={true}`, `complete?={false}`, `detail_panel.ex:674–675`) — an owned series' switches ignore the calendar. *Fix now:* one `Detail.Logic.tracking_card?/1`; inputs from facts on both halves.
35. **`detail_presentation` is a dead axis** — only `:modal` is ever assigned (`entity_modal.ex:738`) and `data-detail-mode="drawer"` is documented but never produced. *Fix now:* the assign goes (`open` is `detail != nil`); the doc row is corrected.
36. **`select_entity` toggles** (same id → close, `entity_modal.ex:116`) although no card can be clicked under the open backdrop. *Fix now:* open, idempotent; close is `close_title`.
37. **The piggyback rule of iteration 1** (a page's reaction to a topic depended on the host having subscribed it) was itself a bolt-on. *Fix now:* `Live.Subscriptions`, one idempotent door; each consumer declares.
38. **`title_rungs` on the host** (iteration 1) put row data on the modal's host. *Fix now:* the map lives in `IncomingLive`, its only remaining reader; the host carries only the open title's `rung`.
39. **`?view=info` names the Manage view.** *Recorded;* a URL rename (`manage`) is a one-line change once the address migration lands, not a separate decision.
40. **`TrackingDetail.today` duplicates the host's `today`.** *Recorded;* the readout reads its own copy; a follow-up passes `today` once.

## Decisions — approved 2026-09-14

Recorded here with the owner's answers; the campaign file carries the same
list under Decisions made.

1. **The residue's address** — `?entity=<uuid>`, canonicalised to `?title=`; no `:collection` media type in this campaign. *Approved.*
   1b. **Collection tracking** — the collection-level block goes now; a migration deletes `title_intents` (and derived tracking items) whose `(tmdb_id, :movie)` equals a library collection's `tmdb_collection` external id — rows only the deleted block could have written; the paired down-migration is a no-op; a follow-up design decides a collection identity or the deletion of the upcoming-parts rail path. *Approved.*
2. **The preview for an owned title** — none; one metadata builder per source; the facet strip goes for both. *Approved ("i guess?") — the bar check on an owned title and a storybook look at an unowned one are where this is judged; reversible in phase 2b.*
3. **Collection member selection** — the member ref is the subject; `?movie=` goes. *Approved.*
4. **Where the library half's state lives** — host state, one `Title.ModalState` struct, reset on subject change. *Approved.*
5. **Event naming** — library names kept, `title_` prefix dropped, `set_rung` / `review_open` / `close_title` shared. *Approved; owner: "set_rung is a lame name, but fine".*
6. **Nav overlay merge** — one `detail` overlay with `detail_menu`. *Approved.*
7. **Tests under ADR-027** — not covered; stricter self-rule: re-address 1:1, delete only tests of deleted behaviour, named per commit; rule 3 (never loosen) honoured. *Approved.*
8. **Emitters** — entity emitters keep `select_entity`, the host canonicalises. *Approved; iteration 2 makes the rail tile an entity emitter too.*
9. **Subscriptions** — the host declares its seven topics, `IntentAware` deleted, MC0011 extended. *Approved; iteration 2 refines the mechanism from piggybacking to one idempotent subscribe door, same outcome.*
10. **Cast for an unowned title** — out of scope, follow-up. *Approved.*

## What goes

`lib/media_centaur_web/live/entity_modal.ex` (2020 lines),
`lib/media_centaur_web/live/intent_aware.ex`,
`lib/media_centaur_web/components/title/detail_modal.ex` (406 lines),
`storybook/title/title_detail_modal.story.exs`, the `title_detail` overlay
and its three zones and selectors in `config.js`, `select_movie`,
`modal_watchlist_toggle`, `modal_review_open`, `close_detail`, every
`title_*` event name, `?selected=` and `?movie=` on Home and Library,
`Title.Detail.primary`, `scoped?`, `kind`, `sender`, `note`, `own?`,
`activity_id`, the `detail_presentation` assign, `seasons_view_from_entry/1`,
`movies_view_from_entry/1`, `member_view`, `Detail.Logic.facets_for/3`,
`ExternalIds.list_tmdb_entities/0`, the collection-level tracking block and
`find_tmdb_id/1`, the four `Title.new!` mints, `rung_atom/1`'s second copy,
the "In library" link, the `title_detail_modal` and `entity_modal_*` unit
test files (their tests move with the code to the host's modules).

## Records

- **UIDR-043** — *One title detail, composed by facts* — supersedes UIDR-035's rules 1 and 2 (the split) and its 2026-09-14 amendment's page-membership clause, keeps rules 3–6; records the subject, the two address forms, the bar, the collection-through-member rule and the facts-not-rules corollary. Drafted alongside this spec as `proposed`.
- **UIDR-019** — amended: one overlay with `detail_menu`; the nested-view dismissal reads the DOM attribute.
- **UIDR-023** — amended: the member is the subject; `?movie=` retired.
- **Glossary** — *title detail modal* rewritten for both halves; *library modal*, *title modal*, *library detail*, *title detail* retired; new rows: *owner*, *container*, *library entry*, *library half*, *modal state*, *entity address*, *title address*.
- **`docs/input-system.md`** — the overlay section for one `detail`; `data-detail-mode` has one value.
- **`docs/architecture.md`** — the trait list and the subscribe door.
- **`credo_checks/entity_modal_contract.ex`** — renamed (`LiveSubscriptions` or the owner's choice): every subscribe in `live/` goes through `Live.Subscriptions`.
- **Wiki** — *Using Media Centaur* pages that describe the library modal and the Discovery/Incoming title modal; *Keyboard and Gamepad* (BACK in the modal is unchanged in behaviour; the description drops the second modal).
- **CHANGELOG** — one user-facing entry: "A title opens the same way everywhere. A show or film you own shows Play on Discovery and Incoming; one you don't shows Download on Home and Library where such a title can be opened. Links to a title work on every page."

## Tests

Test-first per phase (`automated-testing`). What each phase writes before
its code:

| Phase | Red first |
|---|---|
| 0 | `discovery_live_test`: the page root's transient params are comma-separated and include `title` and `activity` (`has_element?`); the MC0011 check's own test (add one if none exists) for the qualified-call pattern and the dead key |
| 1 | `components/title/logic_test`: `title_detail/2` with a library half and an activity row; `snapshot_from_entity/1` for movie, series, collection member (name, year, release date, overview, art paths when the entity's TMDB image record carries them); `Library.EntityView.title_ref/1` for each kind; `ViewModel.LeafDetail` built from `ModalEntry.load_resolved/2`; `ModalState.new/1`; `Activities.get_row/1` (own, friend's, unknown id); `components/detail/logic_test`: `primary_action/2` over the owned/unowned × state × readiness matrix, `tracking_card?/1` |
| 2 | `storybook_render_test` over the rewritten `detail_panel.story.exs` (every owned variation moved to `detail:`/`state:`; every title-modal variation merged); `library_live_test` untouched and green |
| 3 | `live/subscriptions_test`: a second subscribe to the same topic by the same process is a no-op and one message arrives; `discovery_live_test` / `incoming_live_test`: every `#title-*` assertion re-pointed to the panel's ids; new: an owned title opened on Discovery shows Play and plays in place; a deep link to an owned series on Incoming renders its seasons; `?title=…&activity=` on Incoming shows the friend's note; an import that lands while an unowned title is open turns Download into Play (`entities_changed`); `title_intent_changed` refreshes the bookmark on Incoming and Incoming's rows without `IntentAware`; JS: `index.test.js` for the `detail` overlay's `detail_menu`, `discovery_behavior.test.js` rewritten, `orchestrator.test.js` nested dismissal reads the attribute |
| 4 | `library_live_test`, `home_live_test`, `library_live_leaf_hairline_test`, `library_live_tv_orientation_test`, `entity_modal_tracking_test`, `page_smoke_test`, `no_db_on_render_test`: `?selected=` → `?title=`, `?movie=` → the member's title address, element ids unchanged where the panel keeps them; new: `?entity=<video object>` opens the residue; `?entity=<titled>` canonicalises; a collection card opens on the resume-target member's address; a rail tile patches the member address; a subject switch resets `ModalState`; `{:delete, _}` for a moved-on subject is dropped; an owned series' Track switch follows its calendar (the hard-coded inputs are gone); the `entity_modal_*` unit tests move to the host modules' test files; e2e `library.spec.js` and `detail-backdrop.spec.js` addresses |
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
1. **Composition** — `ViewModel.LeafDetail`, `Title.Detail.Library`, `Title.Detail` reshaped (facts only), `title_detail/2` extended, `snapshot_from_entity/1`, `EntityView.title_ref/1`, `Activities.get_row/1`, `ModalState`, `Detail.Logic.primary_action/2` and `tracking_card?/1`. Rendered by nothing yet. One session.
2. **Presentation** — (a) `DetailPanel` takes `detail` + `state`; `EntityModal` builds the `Title.Detail` from its assigns through the one builder (a bridge, deleted in phase 4); the story rewritten; bar check 1. (b) `DetailPanel` renders an unowned title: Download control in the action row, acquisition state, note, preview/snapshot metadata and overview, content-fit height; the title story's variations merged in; verified in storybook. Two sessions.
3. **Host, first adoption** — `Live.Subscriptions`; `TitleDetailHost` gains the library half (`LibraryHalf`, `LibraryEvents`, `Acquisition` split out), the subscription set, the activity by id, `ModalState`, the entity address; Discovery and Incoming render `DetailPanel`; `Title.DetailModal`, its story, the `title_detail` overlay and the bridge go; `detail_menu` added; `IntentAware` deleted (Incoming keeps its `title_rungs` in its own clause). Bar check 2: one owned title on Discovery beside the same title on Library. Two sessions.
4. **Host, second adoption** — Home and Library adopt `TitleDetailHost`; `EntityModal` deleted; addresses migrated in tests; the collection-tracking migration; `data-nav-transient-params`; MC0011 renamed and extended. Bar check 3 on Home and Library. One to two sessions.
5. **Records** — UIDR-043 accepted, UIDR-019 and UIDR-023 amended, glossary, `docs/input-system.md`, `docs/architecture.md`, wiki, CHANGELOG; campaign closed; merge to `main`; `/ship minor`. Half a session.

## Scope cost

The coherent path rewrites the two hosts (2711 lines) into one trait and
three concern modules, retargets the 802-line renderer's contract and merges
a 406-line renderer into it, rewrites two stories (51 variations) into one,
re-addresses roughly 180 modal tests across eleven Elixir files and three
Playwright specs, rewrites one overlay and three JS test files, extends one
Credo check, adds one migration, and touches five records, the glossary,
three wiki pages and the changelog. Iteration 2 adds one small struct
(`LeafDetail`), one context read (`Activities.get_row/1`), one subscribe
door (`Live.Subscriptions`) and two pure rules, and removes `member_view`,
`seasons_view`, `movies_view`, `detail_presentation` and five loose fields
— net smaller. Six to eight sessions including the three bar checks. The
cheap path — add a Play button to the title modal for owned titles and keep
both — would leave every duplicated load, both addresses, the
collection-as-movie ref and the mount-time facts in place, and was not
considered.

## Iteration 2 — 2026-09-14, the unify pass

Applied to the iteration-1 design after the owner approved its ten
decisions. The core idea held; its corollary — the view-model carries facts
and nothing derived from them — was stated but not followed everywhere, and
three of iteration 1's own choices were bolt-ons. Changes, each traceable to
an incoherence above:

1. `primary` and `scoped?` leave the view-model; `Detail.Logic.primary_action/2` derives the action row from facts for both halves (28).
2. The activity the modal speaks for is one `activity_row`, read by identity with `Activities.get_row/1`; `page_facts/3` keeps only the sources a page alone holds (29, 30).
3. The library half is `entry` (three typed structs, `LeafDetail` new), `subject`, `member`, `files` as one value, `available` (31, 32, 33).
4. One tracking-card rule from facts; the library's hard-coded switch inputs go (34).
5. `detail_presentation` and the `drawer` value go (35); `select_entity` no longer toggles (36); the rail tile is an entity emitter (decision 8).
6. Subscriptions go through one idempotent door and every consumer declares its own; `title_rungs` lives in `IncomingLive` (37, 38; decision 9's mechanism).
7. Two items recorded, not fixed: the `info` view name and `TrackingDetail.today` (39, 40).
