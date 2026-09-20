---
status: planning
started: 2026-09-15
last_updated: 2026-09-15
---
# What a collection is, in a model that only has titles

## Goal

`title-detail-unification` (shipped v1.30.0) settled that one TMDB
identity gets one detail view. It did not settle what a **collection**
is in that model: a collection has a TMDB id but is not a title, and
v1.30.0's migration deleted the rows that had been pretending otherwise.
Decide whether a collection becomes a first-class identity or the code
stops carrying the half of one it still has — and close the four small
items the same campaign deferred while the file is open.

## Glossary

Existing terms are in [`docs/GLOSSARY.md`](../docs/GLOSSARY.md): *title*,
*title detail modal*, *title intent*, *rung*, *tracked title*, *release*.
This campaign adds:

* **Collection** — TMDB's grouping of films into a series (its
  `belongs_to_collection`). In the library it is a `MovieSeries`
  container holding `Movie` entities, carrying a `tmdb_collection`
  external id. It is **not** a `TMDB.Title`: `Title.media_type/0` is
  `:movie | :tv_series` and nothing else.
* **Collection-linked tracked title** — a `ReleaseTracking.Item` with
  `media_type: :movie` whose `library_container_type` is `:movie_series`,
  so its `tmdb_id` is a *collection* id rather than a film's. The one
  place the code treats a collection as a trackable thing.
* **Upcoming part** — a `ViewModel.MovieRow.Upcoming` row: an announced
  film of a collection that is not in the library yet. Drawn as a tile on
  the collection rail in the title detail.
* **Upcoming-parts path** — the whole chain that produces those tiles:
  `ReleaseTracking.list_relevant_releases_for_library_container(id, :movie)`
  → `ViewModel.CollectionDetail.upcoming_items/2` → `MovieRow.Upcoming` →
  `Detail.CollectionRail.rail_tile/1`, plus the collection branch of
  `ReleaseTracking.Refresher.fetch_for_item/1`.

## Status

Planning. Nothing started. The opening finding below is measured but its
consequence is undecided — that decision is step 1.

## The question

**The upcoming-parts path looks unreachable as of v1.30.0.** Measured
2026-09-15 on the dev instance: 7 tracked titles, **0** with
`library_container_type: :movie_series`. Migration
`20260914200000_drop_collection_title_intents` deleted the rows, and the
surface that wrote them — the library detail's collection-level tracking
block — was deleted in the same campaign.

Nothing appears able to create another. `ReleaseTracking.set_rung/3` is
the one write path and takes a `TMDB.Title`, whose `media_type` admits
only `:movie | :tv_series`; the later linking step
(`ReleaseTracking.LibraryLinks.link_unlinked_items/1`) only ever sets
`library_container_type: :tv_series`. So the collection branch of
`Refresher.fetch_for_item/1` and every tile the rail draws from it are
dead code.

**This is not yet confirmed** — `Refresher.fetch_for_item/1`'s comment
credits "the Scanner" with writing those ids, which contradicts the
migration's account. One of the two is stale. Settle that before
choosing, because it decides which question is being answered:

* If the path is genuinely dead → **delete it.** A collection is filing,
  not content (UIDR-025), and the rail can show the films the library
  has without pretending the collection is trackable.
* If something still writes those ids → the model owes collections a
  real identity: a `:collection` media type across `TMDB.Title`,
  `TitleRef`, `TitleIntent` and `ReleaseTracking.Item`, with what a rung
  on a collection *means* defined before any of it is written.

Recorded in UIDR-043's consequences.

## Also closing

The same campaign's remaining deferred items. Each is small; none is the
reason this file exists. **Droppable** ones are marked — if they are
still untouched when the question above is settled, close the campaign
without them rather than manufacturing work.

| # | Item | Anchor |
|---|---|---|
| 1 | **Cast view for an unowned title.** `Detail.Logic.secondary_view/2` offers Cast only when the library half has a cast; `Detail.TitlePreview` already carries ten `Library.Person` structs (`@cast_preview_limit`) that nothing renders | `Detail.Logic`, `Detail.TitlePreview`, `Detail.CastPanel` |
| 2 | **Overlay regions have no hint-bar legend.** `app.css`'s `[data-nav-context=…] .hint-group` block names none of the overlay regions, so the gamepad hint bar is blank inside them | `assets/css/app.css` (Gamepad hint bar) |
| 3 | **Cursor leak when a region empties.** One patch where the cursor's region disappears under it; suspected, never runtime-verified | `assets/js/input/core/orchestrator.js` |
| 4 | **The Offline pill is not focusable.** The play card's disabled Offline state takes no `data-nav-item`, so gamepad/keyboard walks past a control that explains itself on hover only | `Detail.PlayCard` |
| 5 | *(droppable)* **`?view=info` names the Manage view.** Rename to `manage` | `TitleDetailHost.parse_view/1`, `view_query/1`, tests |
| 6 | *(droppable)* **`TrackingDetail.today` duplicates the host's `today`** | `Components.ReleaseTracking.TrackingDetail` |
| 7 | *(droppable)* **A better name than `set_rung`** — owner's call; four call sites | `ReleaseTracking.set_rung/3` and its `phx-click` sites |

Items 2–4 are input-system work and may be better handed to that backlog
than done here; decide when one is next touched.

## Decisions made

Append-only.

* `2026-09-14` — **A collection is filing, not content.** Activity
  surfaces speak in movies. ([UIDR-025](../decisions/user-interface/))
* `2026-09-14` — **The collection-wide tracking switches go.** They wrote
  a title intent against a collection id that nothing read. (migration
  `20260914200000_drop_collection_title_intents`, shipped v1.30.0)
* `2026-09-15` — **Collection identity is deferred to its own design,**
  not decided inside the unification campaign. ([UIDR-043] consequences)

## Next steps

1. **Settle the contradiction.** *2026-09-20: the refresher and its
   collection branch were deleted by `tmdb-fetch-policy` Phase 2 — no
   `:movie_series` item existed on the owner's instance, and a tracked
   item now reads the TMDB store, which holds movies and series only. A
   collection cannot be refreshed by any path now; what remains of this
   step is the rail tiles.* Read the Scanner against
   `LibraryLinks.link_unlinked_items/1`: can any current path create a
   `library_container_type: :movie_series` item? Write the answer here
   before touching code.
2. **Decide** on that answer — delete the upcoming-parts path, or design
   collection identity. If the latter, it needs a UIDR before code: what a
   rung on a collection means, and what `Coming up` does with it.
3. Execute the decision. A deletion is one commit plus the view-model and
   rail tests; a design is its own phase.
4. Pick up the *Also closing* table, cheapest first, or hand items 2–4 to
   the input-system backlog.

## Completion criteria

* The upcoming-parts path is either deleted outright or reachable by a
  real, tested write path — no third state where the code carries a
  branch nothing can enter.
* If collection identity is designed: a UIDR records what a rung on a
  collection means, and `TMDB.Title`, `TitleRef`, `TitleIntent` and
  `ReleaseTracking.Item` agree on it.
* Every row of *Also closing* is shipped, handed to a named backlog, or
  dropped on the record — none silently forgotten.
* `mix precommit` clean; CHANGELOG entry if any of it is user-visible;
  this file removed ([ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md)).

## Not this campaign

**TMDB caching refresh policy** (owner, 2026-09-14): cached TMDB data
should be refreshed only when the app is seeking *new* information — a
release date announced, a season landed — never on open for its own sake.
Touches the title preview fetch in `TitleDetailHost`, `TmdbArtwork`'s TTL
sweep, and the release-tracking calendar refresh. The owner named it a
separate campaign; it stays unopened until they say otherwise.

Groundwork already landed in v1.30.0: `HttpClient.Cache.outcome/1` puts
the cache outcome on the response, and the TMDB console line now reads
*from cache* / *from TMDB* / *revalidated with TMDB* — so the fetch
behaviour that campaign wants to change is now observable before it
starts.

## Pointers

* Predecessor campaign: `title-detail-unification` (shipped v1.30.0) —
  its closed state, with every review item's verdict, is commit
  `daf90e40`; the file was removed in `b0cdb4da`.
* Spec: `docs/superpowers/specs/2026-09-14-title-detail-unification-design.md`
  (point-in-time, not maintained).
* Records: UIDR-043 (one title detail), UIDR-025 (collections are
  filing), ADR-063 (per-title quality bounds).
* Key modules: `MediaCentaur.ReleaseTracking` (`set_rung/3`,
  `list_relevant_releases_for_library_container/2`),
  `ReleaseTracking.{Refresher,LibraryLinks,Item}`,
  `MediaCentaurWeb.ViewModel.{CollectionDetail,MovieRow}`,
  `MediaCentaurWeb.Components.Detail.CollectionRail`.
