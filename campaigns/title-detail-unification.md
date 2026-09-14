---
status: active
started: 2026-09-14
last_updated: 2026-09-14
---
# One title detail modal, composed by facts, on every page

Branch: `title-detail-unification` (rebased onto `main` at v1.29.0, 2026-09-14).
The owner wants this on a branch so it can be reverted if the result is not
good. Nothing merges to `main` until the completion criteria hold.

## Glossary

Existing terms are in [`docs/GLOSSARY.md`](../docs/GLOSSARY.md): *title*
(the `TMDB.Title` snapshot), *title detail modal*, *title intent*, *rung*,
*tracked title*, *deep link*, *page facts*, *fetched snapshot*, *glass
menu*. This campaign uses these, defined before first use:

* **Library modal** — the depth surface for a title with files as it exists
  today: `Components.DetailPanel` rendered by the `Live.EntityModal` trait on
  Home and Library, addressed by `?selected=<entity uuid>` (plus `movie` for
  a collection member and `view` for Cast / Manage). UIDR-035 calls it
  *library detail*.
* **Title modal** — the depth surface for a title without files as it exists
  today: `Components.Title.DetailModal` rendered by the `Live.TitleDetailHost`
  trait on Discovery and Incoming, addressed by `?title=<media_type>-<tmdb_id>`
  (plus `activity`). UIDR-035 calls it *title detail*.
* **Unified modal** — what this campaign builds: one depth surface for one
  TMDB identity, on all four pages, whose sections are present or absent by
  facts. When done it takes the glossary's *title detail modal* name and the
  two terms above retire.
* **Presentation bar** — the library modal's current look and behaviour. The
  owner's constraint (2026-09-14): the library modal is the more refined of
  the two and its quality must not take a hit. Every section the unified
  modal renders for an owned title is judged against it.
* **Library half** — the facts that exist only when the library owns the
  title: the entity view, progress and resume target, the typed content list
  (`SeriesDetail` seasons / `CollectionDetail` movies / extras), the files.
  Today the library modal's `selected_entry` plus its loose assigns.
* **Residue** — a library entity with no TMDB *title* identity: a video
  object, an entity never matched, and a collection (its `tmdb_collection`
  id is not a title id — today `EntityModal.find_tmdb_id/1` stamps it as a
  `:movie`, recorded as incoherence 12 in the 2026-09-14 tracking-controls
  spec). The residue must keep a modal.
* **Subject** — what the modal is open on. A TMDB ref for a title; for the
  residue, whatever address form the planning phase decides.
* **Local fact** — a read from an owning context by identity, synchronous on
  open (ADR-051: local reads are milliseconds and load synchronously).
* **Remote fact** — a TMDB fetch: the detail payload that yields the snapshot
  and the *preview*, and the calendar a rung raise needs. Always an owned
  async (`start_async`, Credo `OwnedAsyncInWeb`) that lands into the open
  detail by identity and never blocks the open.
* **Section** — one block of the modal that a fact turns on: play card,
  hairline, download control, acquisition state, note, content list, cast,
  manage, collection rail, tracking block, pennants.
* **Layer** — one of four: *sources* (contexts and the TMDB client),
  *composition* (the pure build of the view-model from facts), *host* (the
  LiveView trait: URL, events, asyncs, PubSub), *presentation* (the renderer,
  its sub-components, the nav overlay, the story).

## Goal

Two modals render one idea. UIDR-035 split the depth surface by source table
— files → library modal, no files → title modal — as a step, and the
`title-detail-deep-links` campaign (2026-09-14) then made the TMDB identity
the title modal's subject, with every fact read by identity. The split now
survives only in code: an owned title opens one way from Home and another
from Discovery, with an "In library" link as the bridge; the same seven fact
loads are written in both hosts; two addresses, two view-models, two
renderers, two nav overlays. When this is done there is one modal for one
TMDB identity on every page that hosts one, its sections present by what the
app knows — files, a rung, a calendar, a friend's act, a plan in flight —
and the library modal's refinement is the floor, not a casualty.

## Status

Phases 0 to 4 landed on the branch 2026-09-14 (one session, after the
spec's approval), each `mix precommit` clean. Phase 5 (records) is next;
then the merge and the ship.

* **Phase 0** (`dce0cf6b`): Discovery's transient params comma-separated;
  MC0011 refreshed (dead key gone, `TitleDetailHost` and `IntentAware`
  covered, qualified `MediaCentaur.X.subscribe()` matched, own test);
  `facets_for(:movie_series, …)` and `list_tmdb_entities/0` deleted.
* **Phase 1** (`dafe1a5d`): `Title.Detail` reshaped to facts only, with
  `Title.Detail.Library` (entry / subject / member / files / available),
  `ViewModel.LeafDetail`, `Title.ModalState`, `EntityView.title_ref/1`,
  `Activities.get_row/1`, `Title.Logic.snapshot_from_entity/1`,
  `Detail.Logic.primary_action/2`, `tracking_card?/1`, `release_dates?/1`,
  `controls_entity/1`. The title host reads the activity by identity on
  every page and loads the library half by ref
  (`TitleDetailHost.LibraryHalf`, started early — the phase-3 module with
  only its loader); Discovery's `page_facts/3` keeps the snapshot alone.
* **Phase 2**: `DetailPanel` renders a `Title.Detail` + `Title.ModalState`
  for both halves — the action row (Play / Download split + scope /
  acquisition state / nothing, the view controls, the member Watched
  toggle, Delete <noun>), the note line, the preview-fed metadata and
  overview, one tracking card by one rule, content-fit height by
  `body?/2`. `PlayCard` is the button alone; `ViewControls` takes the
  detail; the rail tile emits `select_entity`; `EntityModal` is the
  bridge (`detail/1`, `state/1`, `set_rung/2` through the shared
  `TitleDetailHost.Acquisition.apply_rung/4`); Home and Library drop
  `IntentAware`. Stories: `detail_panel` rewritten (28 owned + 22 unowned
  variations), `view_controls` and `play_card` re-pinned.
* **Phase 3**: `Live.Subscriptions` is the one subscribe door (keyed by
  context, or `{context, function}` for a second door like
  `Acquisition.subscribe_queue`); `TitleDetailHost` is the unified host —
  `?title=` and `?entity=` (canonicalised, or the residue), `ModalState`,
  every event of both modals, the asyncs keyed by subject, eight declared
  topics with reactions by identity — split into `LibraryHalf` (load by
  ref or entity id, reload, the playback merges, the files load),
  `LibraryEvents` (the library sections' events, the delete gesture) and
  `Acquisition` (rung, Download, the missing-episode plan). Discovery and
  Incoming render `DetailPanel` and declare their topics through the door;
  Incoming keeps its own `title_rungs` clause. Deleted: `Title.DetailModal`
  and its story, `IntentAware`, the `title_detail` overlay. The JS
  nested-view dismissal reads `data-dismiss-event`. Tests re-pointed
  `#title-*` → `#detail-*`; new: owned title plays in place on Discovery,
  import turns Download into Play, owned series' seasons on Incoming, a
  friend's note by identity on Incoming, a rung set elsewhere refreshes
  Incoming's bookmark and rows; `subscriptions_test`.
* **Phase 4**: Home and Library `use TitleDetailHost`; `EntityModal`
  deleted with its unit tests moved to `title_detail_host/` (the
  "episode list vanished on player close" regression now pins
  `LibraryHalf.reload/1`; the folder-delete safety pins
  `LibraryEvents.run_delete/1`; `entity_modal_tracking_test` is
  `library_live_tracking_test` on the title address). `?selected=` and
  `?movie=` are gone from Home and Library: a titled entity opens on
  `?title=`, the residue on `?entity=`, a collection through its member.
  The migration `20260914200000_drop_collection_title_intents` deletes
  the intents and tracked titles the collection block wrote (run on the
  dev database this session). MC0011 is `LiveSubscriptions`: every
  subscribe under `live/` goes through the door — every page and trait
  converted (`Pipeline.Stats.subscribe/0` added for the stats topic);
  the doors registry names `TitleDetailHost.Acquisition.plan_missing_episode`.
  New tests: a titled card opens on its title address, the residue on
  its entity address without a bookmark, a deep link to a titled entity
  opens the title, a collection card opens on the resume-target member
  and a rail tile on the member it names, a subject switch resets the
  per-opening state, an owned series' switches follow its calendar while
  an owned film is complete; `LibraryHalf.address/1`, `apply_files/3`,
  `LibraryEvents.apply_delete_result/3` drops a moved-on subject.
* **Bar check 3** captured, not yet judged: `after-phase4/` — the same
  six shots as `before/`, on the new addresses.
* **Bar check 2** captured, not yet judged: `after-phase3/` — the owned
  series on Discovery, Incoming (main and Manage) and Library side by
  side, the owned movie on Discovery, and an unowned listed movie.
* **Bar check 1** captured, not yet judged: `mockups/title-detail-unification-bar/`
  (git-ignored) — `before/` from `main`+phase 0, `after-phase2/` the same
  six shots (movie, series main / cast / manage, collection, Home series)
  plus `storybook-*.png` for seven unowned variations. Owner judges in
  the morning; phase 3 does not wait on it (fixable in place).
* Reconciled 2026-09-14 (end of session): branch is seven commits ahead
  of `main`.
* Research done as six inventories (sections, host events / asyncs / PubSub,
  emitters, nav overlays, tests and stories, residue). Findings that changed
  the plan: four `Title.new!` mints, not two; the collection tracking block
  writes a `{collection_id, :movie}` ref that nothing reads
  (`ReleaseTracking.LibraryLinks` links `tv_series` only); Incoming never
  refreshes an open title modal on activity or plan events; `IntentAware`
  exists on Home and Library only to feed the modal's bookmark; `?selected=`
  is a pursuit on Incoming; Discovery's `data-nav-transient-params` is
  space-separated against a comma-splitting reader; ADR-027 does not cover
  the modal's LiveView tests.
* Residue on the dev database (context functions, 2026-09-14): 15 series
  (all with a TMDB id), 30 movies (all with one; 26 presentable), 14
  collections (0 title ids, 14 `tmdb_collection` ids; 3 presentable, one
  hoisted to its sole movie), 0 video objects. The residue in practice is
  the collection, which the spec addresses through its members.
* Spec: `docs/superpowers/specs/2026-09-14-title-detail-unification-design.md`
  — glossary, four layers with module owners, view-model and modal-state
  shapes, host contract (events, subscriptions), presentation table, one
  overlay, emitters, 27 incoherences with dispositions, ten decisions with
  recommendations, tests per phase, six-phase plan, scope cost.
* UIDR-043 drafted as `proposed`:
  `decisions/user-interface/2026-09-14-043-one-title-detail-composed-by-facts.md`.

Note: the `title-detail-deep-links` campaign shipped as v1.29.0 on
2026-09-14 and is retired; this branch is rebased onto that release and
builds on its Phase 3 code (identity resolution in `TitleDetailHost`).

## Diagnosis (2026-09-14)

What is written twice today:

| Concern | Library modal | Title modal |
|---|---|---|
| Host trait | `Live.EntityModal`, 2020 lines, Home + Library | `Live.TitleDetailHost`, 691 lines, Discovery + Incoming |
| Address | `?selected=<uuid>` + `movie` + `view` | `?title=<media_type>-<tmdb_id>` + `activity` |
| View-model | entry map, or `ViewModel.SeriesDetail` / `ViewModel.CollectionDetail`, plus ~15 loose assigns (`tracking`, `rung`, `friend_activity`, `lower_quality_accepted?`, `approval_policy`, `acquisition?`, `detail_view`, `cast_*`, `expanded_*`, `delete_*`, …) | one `Components.Title.Detail` struct built by `Title.Logic.title_detail/2` |
| Renderer | `Components.DetailPanel`, 802 lines, + `Components.Detail.*` (cast, manage, season list, extras, rail, play card, view controls, hairline) | `Components.Title.DetailModal`, 406 lines |
| Nav overlay | `detail`: `detail_actions`, `detail_rail`, `manage_tools`, `manage_list`, `detail_list`, `detail_cast`, `detail_tracking` | `title_detail`: `title_detail_body`, `title_detail_menu`, `title_detail_tracking` |
| Fact loads written in both | tracking half (`TrackingDetail.load/2`), rung (`Discovery.rung/2`), pennants (`Activities.friend_activity_for/1`), quality acceptance (`TitleDownloadParams`), approval policy (`PlanningMode`), acquisition readiness (`Capabilities`), review flow (`ReviewFlow`) | the same seven |
| Snapshot for a library title | minted ad hoc with `Title.new!` in two places (`open_review/1`, `handle_set_rung/2`) | resolved by identity: open detail → intent → page copy → TMDB (`Title.from_tmdb/2`) |
| PubSub subscriptions | Library, Playback, ReleaseTracking, Activities, Acquisition | ReleaseTracking (Discovery/Incoming subscribe the rest themselves) |

What each has that the other lacks:

* **Library modal only:** play card + progress hairline + resume; the
  two-column orientation block (facts and controls left, prose right); view
  controls (Episodes / Cast / Overview, Letterboxd, the bookmark, the Manage
  cog); the content list — `SeasonList` with `EpisodeRow.{Library, Missing,
  Upcoming}` (library + calendar already blended, `download_missing_episode`
  on gaps), `ExtrasSection`, `CollectionRail` with the member watched toggle
  (UIDR-023); `CastPanel` with filter and paging; `ManagePanel` (files with
  delete + inline confirm, rematch, refresh artwork, external ids, track
  override); playback-aware delete protection; the content-fit panel for a
  bare movie vs the full panel; the tracking block under the list.
* **Title modal only:** the Download split button with the series scope
  select (`GlassMenu`); the acquisition state as a fact (Planning /
  Downloading / Needs review); the note under the hero (a friend's review
  words, or the person's own); the overview from snapshot until the preview
  lands; the facet strip from the preview; the fetched open (deep link to a
  title nothing holds) and the live preview; `Delete <noun>` on an own
  activity; the "In library" bridge to `/library?selected=`.
* **Shared already:** `CinematicShell`, `Pennant`, `TitleLayer.lockup`,
  `MetadataRow`, `WatchlistToggle`, Review, `TrackingControls`,
  `ReleaseDates`, `ReviewFlow`.

## Design direction (pre-planning, to be tested by the spec)

The core idea: **a title is a TMDB identity, and the detail modal is the one
surface composing everything the app knows about that identity. Files are one
more fact, like a rung or a friend's review, not a different surface.**

In layers:

1. **Sources.** Local facts by identity: the library owner
   (`Library.ExternalIds.tmdb_owners/1` → `Presentable.resolve/1` → the
   existing loaders), the intent (`Discovery.get_intent/2`, `rung/2`), the
   tracked half (`TrackingDetail.load/2`), friend activity, acquisition state
   and params, artwork (`TmdbArtwork.urls/2`), capabilities, planning mode.
   Remote facts: the TMDB detail payload (snapshot + preview) and the
   calendar. The rule: local facts load synchronously on open; remote facts
   are owned asyncs that land by identity.
2. **Composition.** One view-model for one identity — `Title.Detail` gaining
   the library half (nil without files) — built by one pure function from
   facts. It carries facts, not rules (spec 2026-09-14 item 8); each
   section's rule is derived at the mount (ADR-030). The snapshot resolution
   order gains one source: the library entity's own metadata, between the
   intent and the page copy, so the ad hoc `Title.new!` mints go.
3. **Host.** One trait on all four pages: URL → open by identity; PubSub →
   refresh by identity; every event of both hosts, the library ones no-ops
   without a library half; asyncs land by identity. The Credo contract
   (`EntityModalContract`, MC0011) names the one trait and its five
   subscriptions.
4. **Presentation.** One renderer at the presentation bar: the library
   modal's block structure, with the title-only sections added where the
   facts call for them (Download control in the play card's slot when there
   are no files; acquisition state; the note; the preview-fed overview and
   facets while there is no library half). One nav overlay with the union of
   zones. One story whose variation matrix covers both halves.

Which modules survive by name is a planning decision, not a design one. The
*presentation* trunk is `DetailPanel`'s; the *host* trunk is
`TitleDetailHost`'s identity resolution; the *library half* is
`EntityModal`'s loading and events, moved, not rewritten.

## Open decisions

None. The ten planning decisions were approved 2026-09-14 (below); the
spec's § Decisions carries each with the owner's words.

## Decisions made

* `2026-09-14` — **The residue's view-model** (spec gap): a `Title.Detail`
  with `ref` and `title` nil and the library half as its one fact; every
  rule tolerates it (no action but Play, no tracking card, no bookmark).
  Renderer and bridge handle it; `?entity=` addressing is phase 4. (this
  session, under the spec's "one modal, one view-model")
* `2026-09-14` — **A rail pick keeps the view.** The tile is an entity
  emitter (`select_entity`), so in the library host a member switch is a
  selection change; the document changes only when the resolved
  *container* does, so Cast follows the member instead of resetting to
  the main view (the library modal's behaviour, the bar). The unified
  host keeps this rule in phase 3/4. (this session)
* `2026-09-14` — **No tracking card at Off** for an owned title: the
  library modal drew an empty glass box holding a `data-form="none"`
  shell; the one rule (`Detail.Logic.tracking_card?/1`) draws nothing
  until the title is listed (UIDR-039), as the title modal already did.
  Two `entity_modal_tracking_test` assertions re-addressed to "no card".
  (this session)
* `2026-09-14` — **An address the library cannot open is abandoned**
  with a flash on both forms (`?entity=` to an entity without a present
  file, `?title=` to a title nothing holds and TMDB cannot fetch), the
  spec's one abandon path; a titled `?entity=` deep link opens the title
  in place on the dead render and canonicalises its URL on the join
  (a patch needs a live socket). (this session)
* `2026-09-14` — **`snapshot_from_entity/1` carries no art paths**: a
  library image is a local file, not a TMDB path (the spec assumed a
  TMDB image record). An owned title's artwork comes from the library
  half's images in the host. (this session)

* `2026-09-14` — Unify the two modals into one, composed by facts, on all
  four pages. Owner's call after the diagnosis above. (conversation)
* `2026-09-14` — On a branch (`title-detail-unification`), revertable;
  nothing merges until the completion criteria hold. (owner)
* `2026-09-14` — **The library modal's refinement is the floor.** Its
  presentation is the bar for every section of the unified modal for an
  owned title. The sequencing follows: the library modal's presentation is
  the trunk the title-only sections graft onto, not the reverse. (owner)
* `2026-09-14` — Architecture in layers: sources → composition → host →
  presentation, with local facts synchronous on open and remote facts as
  owned asyncs landing by identity. (owner's brief; ADR-049, ADR-051)
* `2026-09-14` — Done right, not fast: research and a spec with a glossary
  precede any code; a UIDR supersedes UIDR-035. (owner)
* `2026-09-14` — **The ten planning decisions approved as recommended**
  (owner): residue on `?entity=`, no `:collection` media type; the
  collection-level tracking block goes with a migration for its orphaned
  intents; no preview for an owned title and no facet strip ("i guess?" —
  judged at the phase-2 bar check, reversible there); the member movie is a
  collection modal's subject; one `Title.ModalState`; library event names
  kept, `title_` prefix dropped, `set_rung` shared ("a lame name, but fine");
  one `detail` overlay; tests re-addressed 1:1 under a stricter-than-ADR-027
  rule; entity emitters keep `select_entity`; the host declares its topics
  and `IntentAware` goes; cast for unowned titles deferred. (owner)
* `2026-09-14` — **Unify pass on the spec (iteration 2)**, owner-requested:
  the view-model carries facts only (`primary`, `scoped?` and five activity
  fields leave it; `Detail.Logic.primary_action/2` and `tracking_card?/1`
  derive the rules); the activity is read by identity
  (`Activities.get_row/1`); the library half is `entry` (`LeafDetail` new) +
  `subject` + `member` + `files` + `available`; subscriptions go through one
  idempotent door (`Live.Subscriptions`) and every consumer declares its own,
  `title_rungs` moves to `IncomingLive`; `detail_presentation` and the
  `select_entity` toggle go; the rail tile is an entity emitter. (this
  session; spec § Iteration 2)

## Next steps

1. **Owner:** judge the bar checks (`mockups/title-detail-unification-bar/before` vs `after-phase2`, `after-phase3`, `after-phase4`, and the `storybook-*` unowned shots).
2. **Phase 5** — UIDR-043 accepted, UIDR-019 and UIDR-023 amended,
   glossary, `docs/input-system.md`, `docs/architecture.md`, wiki,
   CHANGELOG; campaign closed; merge to `main`; `/ship minor`.

## Deferred (bucket at closure)

* Collection identity — a `:collection` media type across `TitleRef`, `TitleIntent`, `ReleaseTracking.Item`, or deletion of the upcoming-parts rail path (`MovieRow.Upcoming`, `list_relevant_releases_for_library_container(_, :movie)`). Separate design.
* Cast view for an unowned title, fed by the preview's ten people.
* Hint-bar legend for overlay regions (`app.css:2472–2521` names none of them).
* One-patch cursor leak when the region holding the cursor empties (`orchestrator.js:195–217, 380–382`); not runtime-verified.
* The Offline placeholder in the play card is not focusable (`play_card.ex:53–63`).
* `?view=info` names the Manage view; rename to `manage` once the address migration lands.
* `TrackingDetail.today` duplicates the host's `today`; pass it once.
* A better name than `set_rung` for the one intent event (owner).
* **TMDB caching policy** (owner, 2026-09-14, later follow-up, not this
  campaign): cached TMDB data is refreshed only when the app is seeking
  *new* information — whether release dates have been announced, a
  season landed — never on open for its own sake. Touches the preview
  fetch, `TmdbArtwork`, the calendar refresh. Separate campaign.

## Completion criteria

* One modal component, one host trait, one view-model, one address per
  TMDB identity (plus the residue's form) on Home, Library, Discovery and
  Incoming. No parallel path remains: the second host, renderer, overlay and
  story are deleted.
* For an owned title, every section renders at the presentation bar: the
  same titles captured before and after on the same viewport, judged by the
  owner. No visual or behavioural regression on Home or Library.
* A deep link to any TMDB title opens the modal on every hosting page; an
  owned title shows Play on Discovery and Incoming; an unowned title shows
  Download on Home and Library where such a title can be opened.
* The residue keeps its modal.
* `mix precommit` clean; UIDR superseding 035 accepted; glossary rows for
  *title detail modal* and the retired terms; wiki and CHANGELOG updated.
* Merged to `main` and shipped, or abandoned with the branch deleted — in
  either case this file removed.

## Pointers

* `lib/media_centaur_web/live/entity_modal.ex`,
  `lib/media_centaur_web/components/detail_panel.ex`,
  `lib/media_centaur_web/components/detail/` — the library modal.
* `lib/media_centaur_web/live/title_detail_host.ex`,
  `lib/media_centaur_web/components/title/detail_modal.ex`,
  `lib/media_centaur_web/components/title/detail.ex`,
  `lib/media_centaur_web/components/title/logic.ex` — the title modal.
* `lib/media_centaur_web/components/cinematic_shell.ex` — the shared frame.
* `lib/media_centaur_web/view_model/series_detail.ex`,
  `collection_detail.ex`, `episode_row.ex`, `orientation.ex` — the library
  half's composers.
* `lib/media_centaur/library/modal_entry.ex`, `presentable.ex`,
  `external_ids.ex` (`tmdb_owners/1`) — the library half's sources.
* `lib/media_centaur_web/title_ref.ex` — the title address.
* `assets/js/input/config.js` — the two overlays.
* `credo_checks/entity_modal_contract.ex` — MC0011.
* Decision records: UIDR-035 (two surfaces; amended 2026-09-14), UIDR-019
  (two nav regions), UIDR-021 (artwork ladder), UIDR-023 / UIDR-025
  (collections), UIDR-036, UIDR-037, UIDR-039, UIDR-042; ADR-030 (logic
  hoisting), ADR-038 (traits), ADR-049 (owned async), ADR-051 (sync local
  loads), ADR-066, ADR-067.
* Spec: `docs/superpowers/specs/2026-09-14-title-detail-unification-design.md`;
  research inventories beside it in `2026-09-14-title-detail-unification-research/`.
* Specs: `docs/superpowers/specs/2026-09-14-tracking-controls-design.md`
  (incoherence 12: the collection identity), `2026-09-07-tracking-is-a-persons-act-design.md`.
* Campaign `title-detail-deep-links` — the identity resolution this builds on.
