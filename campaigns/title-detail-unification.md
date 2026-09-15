---
status: complete
started: 2026-09-14
last_updated: 2026-09-15
closed: 2026-09-15
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

* **Library modal** (retired by phase 4) — the depth surface for a title
  with files as it was before this campaign: `Components.DetailPanel`
  rendered by the `Live.EntityModal` trait on Home and Library, addressed
  by `?selected=<entity uuid>` (plus `movie` for a collection member and
  `view` for Cast / Manage). UIDR-035 called it *library detail*. The
  name survives here only as the bar's source.
* **Title modal** (retired by phase 3) — the depth surface for a title
  without files as it was before this campaign:
  `Components.Title.DetailModal` rendered by the `Live.TitleDetailHost`
  trait on Discovery and Incoming, addressed by
  `?title=<media_type>-<tmdb_id>` (plus `activity`). UIDR-035 called it
  *title detail*.
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

Phases 0 to 5 landed on the branch 2026-09-14 (one session, after the
spec's approval), each `mix precommit` clean (last run: 7183 tests, credo
clean, 828 JS tests, zero warnings). **The owner's review pass is in
progress from 2026-09-15** — see § Review below, which is the tracker:
every item to judge, the deviations from the spec made in code, and the
revision loop. Revisions land in place on the branch. After the pass:
merge to `main`, `/ship minor`, wiki push (`../media-centaur.wiki`
commit `4a7c5ff`, unpushed).

* Reconciled 2026-09-15: branch is ten commits ahead of `main` (four
  docs commits, six phase commits `dce0cf6b` → `bcbbf940`); working tree
  clean; nothing pushed.

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
* **Phase 5**: UIDR-043 accepted (with implementation notes); UIDR-019
  amended (one overlay, `detail_menu`, the nested dismissal reads the
  attribute); UIDR-023 amended (the member is the subject, `?movie=`
  retired, a rail pick keeps the view); UIDR-035 marked superseded in
  part; `decisions/README.md` regenerated. Glossary: *title detail
  modal* rewritten for both halves, new rows *library half*, *residue*,
  *modal state*, *subscribe door*. `docs/input-system.md` (one overlay,
  `data-detail-mode` one value, the attribute examples),
  `docs/architecture.md` (the door), the `user-interface` and
  `input-system` skills, the wiki (Watchlist, Social, Searching and
  Downloading, Keyboard and Gamepad — committed, unpushed), and the
  CHANGELOG's Unreleased entry.
* **Bar checks** captured after phases 2, 3 and 4 — the inventory and
  the pairs to compare are in § Review.
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

## Review (owner's pass, from 2026-09-15)

The owner judges the branch against the bar and the spec; each revision
lands in place on the branch. This section is the tracker for a review
that spans sessions: an item's state moves `open` → `accepted`, or
`revise: <what>` → `done <commit>`. A session resuming the review reads
this section first and updates it before touching code.

### The shots

`mockups/title-detail-unification-bar/` (git-ignored), every shot at
1920×1080 on the same dev-database titles. `capture <set-name>` in that
directory recaptures the whole set against the dev server on the unified
addresses (owned: Library movie / series main, Cast, Manage / collection,
Home series, Discovery series and movie, Incoming series main and
Manage; unowned: a listed movie on Discovery and seven `detail_panel`
story variations). Pairs to compare:

| Judged | File(s) | Against |
|---|---|---|
| Owned on Library and Home | `after-phase4/{library-movie,library-series,library-series-cast,library-series-manage,library-collection,home-series}.png` | `before/` same names (the bar). `after-phase2/` is the intermediate. |
| Owned on Discovery and Incoming | `after-phase3/{discovery-series,discovery-movie,incoming-series,incoming-series-manage}.png` | `before/library-series.png`, `before/library-movie.png` — no prior surface; the bar is the library modal's look. |
| Unowned | `after-phase2/storybook-{dressed,from_friend,listed,movie_download,own_review,series_split,tracked_watch}.png`, `after-phase3/discovery-unowned-listed-movie.png` | The retired title modal (no shot kept; judged on its own). |

One deliberate difference from `before/` in the owned shots: no glass
box under the content list at Off (item 5).

### Items to judge

| # | Item | Where it lives | State |
|---|---|---|---|
| 1 | **Bar: owned titles on Library and Home** — every section renders as `before/` does | `DetailPanel`, `Components.Detail.*` | accepted |
| 2 | **Bar: owned titles on Discovery and Incoming** — Play, seasons, Cast, Manage with files, the rail, identical to Library | same | accepted |
| 3 | **Unowned titles' look** — Download split + scope, the note line, acquisition state, tracking card, the seven story variations | same; `detail_panel.story.exs` | accepted |
| 4 | **Spec decision 2** — no facet strip and no preview for an owned title (owner's "i guess?", judged at this look; reversible in `DetailPanel` alone) | `DetailPanel` hero/prose facts | accepted |
| 5 | **No tracking card at Off** for an owned title — the library modal drew an empty glass box holding a hidden control shell; one rule (`Detail.Logic.tracking_card?/1`) draws nothing until the title is listed | `Detail.Logic`, two assertions in `library_live_tracking_test.exs` | accepted |
| 6 | **The residue's view-model** — a `Title.Detail` with `ref` and `title` nil, the library half its one fact: Play only, no bookmark, no tracking card, no Download | `Title.Logic.title_detail/2`, `Detail.Logic` | accepted |
| 7 | **A rail pick keeps the modal state and the sub-view** — a member of the open collection is the same document (`same_document?/2`, `kept_view/2`), so Cast stays Cast; a different container resets | `TitleDetailHost` | accepted |
| 8 | **Unopenable address abandoned with a flash** on both forms; on the dead render that is a redirect (a deep link to an entity without a present file lands on the page with the flash, where the old code silently drew no modal). A titled `?entity=` opens in place on the dead render and canonicalises to `?title=` on the join | `TitleDetailHost`, `LibraryHalf.address/1` | accepted |
| 9 | **The entity snapshot carries no art paths** — a library image is a local file, not a TMDB path (the spec assumed a TMDB image record); an owned title's poster / backdrop / logo come from the library half in the host | `Title.Logic.snapshot_from_entity/1`, host | accepted |
| 10 | **The note line's sources** — only the `activity` address param (read by identity via `Activities.get_row/1`) or the person's own intent note. Discovery's former implicit inference (the newest friend review with text) is gone; the activity's embedded title is a snapshot source, so a `?title=…&activity=…` link opens on Incoming without a fetch | `Title.Logic`, `TitleDetailHost` | accepted |
| 11 | **`play` handled by the host with or without an open modal** — the Home hero's Play no-op'd once the host owned the event | `TitleDetailHost` | accepted |
| 12 | **MC0011 is `LiveSubscriptions`** and every page and trait under `live/` was converted to the door in phase 4 (the spec named the host and five subscriptions; the sweep grew to all of `live/`, plus `Pipeline.Stats.subscribe/0`) | `credo_checks/live_subscriptions.ex`, `Live.Subscriptions` | accepted |
| 13 | **Test addresses migrated `?selected=` → `?entity=`** (canonicalised on join) rather than to `?title=`; the two `?movie=` tests deleted as deleted behaviour (the stricter-than-ADR-027 rule from decision 8) | `library_live_test.exs`, `home_live_test.exs`, `library_live_tracking_test.exs` | accepted |
| 14 | **Element ids** — the tracking controls keep `detail-*`; the title modal's tests were re-pointed `#title-*` → `#detail-*` (`#detail-download`, `#detail-scope`, `#detail-watchlist-toggle`, `#detail-review`, `#detail-note`, `#detail-activity-delete`, `#detail-tracking*`) | `DetailPanel`, `ViewControls`, tests | accepted |
| 15 | **The lower-quality note showed twice on an owned title** (owner, 2026-09-15) — the tracking card read `lower_quality_accepted?` directly, so the note sat under the episode list *and* behind the cog. One rule now (`Detail.Logic.lower_quality_note?/1`): the card carries it only for a title with no Manage sheet | `Detail.Logic`, `DetailPanel`, `Title.LowerQualityNote` | fixed |
| 16 | **The synopsis was cut at 2/5 of the panel** (owner, 2026-09-15) — the 2/5–3/5 grid gave it ~62ch and `line-clamp-6` cut a 546-character series overview mid-sentence. The prose is its own full-width band under the action row now, same clamp; measured at 1920×1080, Murphy Brown's overview lands in 4.02 of the 6 lines with nothing clipped. Clamp kept deliberately — the band is inside the *pinned* block, so its height is the episode list's ceiling | `DetailPanel` orientation block | fixed |

Already deferred, not for this pass: the `set_rung` name, `?view=info`
for Manage, `TrackingDetail.today` (§ Deferred).

### Revision loop

1. Fix in place on the branch. Presentation: `DetailPanel` and
   `Components.Detail.*`; composition: `Title.Logic`, `Detail.Logic`;
   host: `TitleDetailHost` and its three modules.
2. A visual change edits the story variation first (`storybook` skill);
   a behaviour change gets its failing test first.
3. `~/scripts/agents/agent-mix precommit` (never bare `mix`).
4. `mockups/title-detail-unification-bar/capture after-r<N>` and compare
   with `before/` and `after-phase3/` per the table above.
5. Commit on the branch (no push), update the item's state, add a row
   below.

### Revision log

| Date | Item(s) | Change | Commit |
|---|---|---|---|
| 2026-09-15 | 15, 16 | Lower-quality note gated on the absence of a Manage sheet; synopsis moved to a full-width band under the action row | `5ae68638` |

**Pass closed 2026-09-15.** The owner reviewed the branch, raised items
15 and 16, and on their fix said "merge back to main and ship minor" —
which accepts every remaining row.

## Open decisions

Every row of § Review / Items to judge is open until the owner marks it.
The ten planning decisions were approved 2026-09-14 (below); items 5–14
are the calls made in code where the spec was silent or the code
disagreed with it, and are the owner's to accept or send back.

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
* `2026-09-14` — **The note line reads two sources only**: the
  `activity` param by identity, or the intent note. Discovery's
  implicit "newest friend review" inference is deleted; the activity's
  embedded title joins the snapshot resolution order so a
  `?title&activity` link opens on Incoming without a fetch. (this
  session; review item 10)
* `2026-09-14` — **`play` is the host's whether or not a modal is
  open** — the Home hero fires it with no modal. (this session; item 11)
* `2026-09-14` — **Test addresses migrate to `?entity=`**, the
  canonicalised form, not `?title=`; the `?movie=` tests go with the
  behaviour. (this session; item 13)
* `2026-09-14` — **One id family, `detail-*`**: the tracking controls'
  ids stay, the title modal's `title-*` ids are re-pointed. (this
  session; item 14)

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

1. **Owner:** work through § Review / Items to judge — the three bar
   checks, spec decision 2, and the ten in-code calls. Each `revise`
   follows the revision loop and is logged.
2. When every item is `accepted` or `done`: fast-forward merge
   `title-detail-unification` into `main`, remove this file (its
   deferred items are bucketed below), push the wiki, `/ship minor`
   (the CHANGELOG's Unreleased entry moves to the release).
3. If the result is not good: delete the branch and this file; `main`
   is untouched at v1.29.0.

## Deferred (bucketed at closure)

Each item's destination, per the closure-by-destination rule:

* **Defer to a design** — Collection identity: a `:collection` media type across `TitleRef`, `TitleIntent`, `ReleaseTracking.Item`, or deletion of the upcoming-parts rail path (`MovieRow.Upcoming`, `list_relevant_releases_for_library_container(_, :movie)`). Recorded in UIDR-043's consequences.
* **Defer to a follow-up** — Cast view for an unowned title, fed by the preview's ten people (UIDR-043 consequence).
* **Defer to the input-system backlog** — Hint-bar legend for overlay regions (`app.css` names none of them); the one-patch cursor leak when the region holding the cursor empties (`orchestrator.js`, not runtime-verified); the Offline placeholder in the play card is not focusable.
* **Ship-adjacent, one line each, when next touched** — `?view=info` names the Manage view (rename to `manage`: `TitleDetailHost.parse_view/1` and the tests); `TrackingDetail.today` duplicates the host's `today`; a better name than `set_rung` (owner's call).
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

## Pointers (as built)

* **Host:** `lib/media_centaur_web/live/title_detail_host.ex` (URL,
  events, asyncs, PubSub reactions; `modal_query/1`,
  `refresh_title_detail/1`) and `title_detail_host/library_half.ex`
  (load by ref or entity id, `address/1`, reload, playback merges, the
  files load), `library_events.ex` (the library sections' events, the
  delete gesture), `acquisition.ex` (`apply_rung/4`, `start_download/4`,
  the missing-episode plan). Home, Library, Discovery and Incoming
  `use TitleDetailHost` and implement `page_facts/3`,
  `title_detail_path/2`, `open_plan_board/2`.
* **Composition:** `components/title/detail.ex` (`Title.Detail`, facts
  only), `title/detail/library.ex` (the library half),
  `title/modal_state.ex`, `title/logic.ex` (`title_detail/2`,
  `snapshot_from_entity/1`), `components/detail/logic.ex`
  (`primary_action/2`, `tracking_card?/1`, `release_dates?/1`,
  `controls_entity/1`), `view_model/leaf_detail.ex`,
  `view_model/series_detail.ex`, `collection_detail.ex`.
* **Presentation:** `components/detail_panel.ex` (`detail`, `state`,
  `today`, `spoiler_free`, `letterboxd_links`, `tmdb_ready`, `review?`,
  `on_play`, `on_close`) and `components/detail/` (`play_card`,
  `view_controls`, `collection_rail`, `cast_panel`, `manage_panel`,
  `season_list`, …); `components/cinematic_shell.ex` the frame.
  Story: `storybook/detail_panel/detail_panel.story.exs` (28 owned + 22
  unowned variations), `storybook/detail/view_controls.story.exs`,
  `play_card.story.exs`.
* **Sources:** `lib/media_centaur/library/modal_entry.ex`,
  `presentable.ex`, `external_ids.ex` (`tmdb_owners/1`),
  `entity_view.ex` (`title_ref/1`); `lib/media_centaur/activities.ex`
  (`get_row/1`).
* **Door:** `lib/media_centaur_web/live/subscriptions.ex`;
  `credo_checks/live_subscriptions.ex` (MC0011).
* **Address:** `lib/media_centaur_web/title_ref.ex`; `?title=<ref>`
  (+ `view`, `activity`), `?entity=<uuid>` (residue; canonicalised when
  titled). `?selected=` remains only for Incoming's pursuit modal.
* **Nav:** `assets/js/input/config.js` — the one `detail` overlay and
  the `detail_menu` TREE; `orchestrator.js` reads `data-dismiss-event`.
* **Tests:** `test/media_centaur_web/live/title_detail_host/`
  (`library_half_test`, `library_events_test`,
  `library_events_delete_folder_safety_test`),
  `live/library_live_tracking_test.exs`, `live/library_live_test.exs`
  ("title addresses (UIDR-043)"), `discovery_live_test.exs`,
  `incoming_live_test.exs`, `home_live_test.exs`,
  `components/detail_panel_test.exs`, `live/subscriptions_test.exs`,
  `test/media_centaur/credo/checks/live_subscriptions_test.exs`.
* **Migration:** `priv/repo/migrations/20260914200000_drop_collection_title_intents.exs`
  (run on the dev database 2026-09-14).
* **Shots and recapture:** `mockups/title-detail-unification-bar/`
  (git-ignored) — `before/`, `after-phase2/`, `after-phase3/`,
  `after-phase4/`, and the `capture` script.
* Decision records: UIDR-043 (accepted 2026-09-14, supersedes 035 in
  part), UIDR-035 (amended), UIDR-019 (one overlay, amended), UIDR-021 (artwork ladder), UIDR-023 / UIDR-025
  (collections), UIDR-036, UIDR-037, UIDR-039, UIDR-042; ADR-030 (logic
  hoisting), ADR-038 (traits), ADR-049 (owned async), ADR-051 (sync local
  loads), ADR-066, ADR-067.
* Spec: `docs/superpowers/specs/2026-09-14-title-detail-unification-design.md`;
  research inventories beside it in `2026-09-14-title-detail-unification-research/`.
* Specs: `docs/superpowers/specs/2026-09-14-tracking-controls-design.md`
  (incoherence 12: the collection identity), `2026-09-07-tracking-is-a-persons-act-design.md`.
* Campaign `title-detail-deep-links` — the identity resolution this builds on.
