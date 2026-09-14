---
status: planning
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

Research and spec drafted 2026-09-14 (second session, autonomous); awaiting
the owner's decisions before phase 0. No implementation code on the branch.

* Reconciled: branch is one commit ahead of `main` (this file); pointers and
  line counts verified against `77714ea4`.
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

Recorded with recommendations in the spec (§ Open decisions). The owner
decides each in the app's terms; the phase plan assumes the recommendation.

1. The residue's address — `?entity=<uuid>`, canonicalised to `?title=`; no `:collection` media type in this campaign.
   1b. Collection tracking — delete the collection-level block now; migration for the orphaned `(collection_id, :movie)` intents; a follow-up design for a collection identity or for deleting the upcoming-parts rail path.
2. The preview for an owned title — none; one metadata builder per source; the facet strip goes for both.
3. Collection member selection — the member ref is the subject; `?movie=` goes.
4. Where the library half's state lives — host state, one `Title.ModalState` struct, reset on subject change.
5. Event naming — library names kept, `title_` prefix dropped, `set_rung` / `review_open` / `close_title` shared.
6. Nav overlay merge — one `detail` overlay with `detail_menu`; absent-zone skipping verified.
7. Tests under ADR-027 — not covered; stricter self-rule: re-address 1:1, delete only tests of deleted behaviour, named per commit.
8. Emitters — entity emitters keep `select_entity`, the host canonicalises; rail tile → `open_title`.
9. Subscriptions — the host owns seven topics, pages piggyback, `IntentAware` deleted, MC0011 extended.
10. Cast for an unowned title — out of scope, follow-up.

## Decisions made

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

## Next steps

1. **Owner reviews the spec's ten decisions** and the UIDR-043 draft; corrections go into the spec and this file's Decisions made.
2. **Phase 0** (hygiene) once decided — tests first per the spec's Tests table; skills first: `automated-testing`, `elixir:phoenix-thinking`, `input-system`.
3. Phases 1–5 as the spec's Phase plan, each closed by `mix precommit` and, for phases 2–4, the bar check (same titles, 1920×1080, `page-shot`, judged by the owner).

## Deferred (bucket at closure)

* Collection identity — a `:collection` media type across `TitleRef`, `TitleIntent`, `ReleaseTracking.Item`, or deletion of the upcoming-parts rail path (`MovieRow.Upcoming`, `list_relevant_releases_for_library_container(_, :movie)`). Separate design.
* Cast view for an unowned title, fed by the preview's ten people.
* Hint-bar legend for overlay regions (`app.css:2472–2521` names none of them).
* One-patch cursor leak when the region holding the cursor empties (`orchestrator.js:195–217, 380–382`); not runtime-verified.
* The Offline placeholder in the play card is not focusable (`play_card.ex:53–63`).

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
* Specs: `docs/superpowers/specs/2026-09-14-tracking-controls-design.md`
  (incoherence 12: the collection identity), `2026-09-07-tracking-is-a-persons-act-design.md`.
* Campaign `title-detail-deep-links` — the identity resolution this builds on.
