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

Planning. Diagnosis done in conversation on 2026-09-14 (recorded below);
branch cut; no code. Next session: reconcile, research, spec, UIDR, phase
plan — in that order, no implementation before the owner approves the spec.

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

## Open decisions for the planning phase

Each is decided explicitly with the owner (define the working terms as the
app's controls first), recorded under Decisions made, then enacted. None is
worked around.

1. **The residue's address.** Video objects, unmatched entities and
   collections have no TMDB title identity. Recommendation from the
   diagnosis: keep an entity-address form (`?selected=<uuid>`) for the
   residue, resolved by the same host to the same view-model — one modal,
   two address forms, the second stating honestly that the residue exists.
   A library card with a TMDB identity emits the title address. Open: does
   `TitleRef` learn a `:collection` media type instead, and what does that
   do to intent, tracking and activities, which key on `:movie | :tv_series`?
2. **The preview for an owned title.** The scraped entity is local and
   richer (cast with images, facets from the entity). Recommendation: no
   preview fetch when the library half is present; the metadata row and facet
   strip have one builder per source, replacing today's two
   (`Detail.Logic.facets_for` from the entity, `TitlePreview` from the
   payload).
3. **Collection member selection** (`?movie=`, `subject_rung` vs `rung`, the
   member subject for the bookmark and Review) is library-only. It lives
   inside the library half. Confirm nothing on the detail needs it.
4. **Where the library half's state lives.** The per-selection state
   (`expanded_seasons`, `cast_filter`, `detail_view`, `delete_confirm`, …) is
   host state today. Decide whether it stays loose on the socket under one
   namespaced assign, or rides on the view-model. Bias: host state, one
   struct, reset on subject change — not on the view-model, which is facts.
5. **Event naming.** Two vocabularies (`close_detail` / `close_title`,
   `modal_watchlist_toggle` / `set_rung`, `modal_review_open` /
   `title_review_open`). One set; the `EventChokepoint` check and the input
   system's `data-dismiss-event` follow.
6. **Nav overlay merge.** One overlay; zones absent from the DOM must be
   skipped by `entry` order (verify in `assets/js/input/config.js` and the
   `input-system` skill before relying on it).
7. **Tests under ADR-027** (regression tests append-only). The library
   modal's tests address `?selected=`; the unified address is `?title=` for
   titled entities. Decide how a test whose URL form changes is migrated
   without deleting a regression.
8. **Home's Coming up cards and any other surface** that opens a modal today
   — inventory every `select_entity` / `open_title` emitter and what
   identity it holds.

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

For the fresh session, in order. Skills first: `unify_design`,
`elixir:phoenix-thinking`, `user-interface`, `storybook`, `input-system`,
`automated-testing`.

1. **Reconcile** this file against `git log` and the code (ADR-042 rule).
2. **Research, producing tables in the spec, not prose:**
   * *Section matrix* — every section of both modals: the facts it needs, the
     source of each fact, local or remote, which modal has it today, and
     what turns it on in the unified modal.
   * *Event inventory* — every `handle_event` clause of both hosts, its
     params, what it writes, and whether it needs the library half.
   * *Emitter inventory* — every place that opens a modal (cards, rows,
     omnibox, feed, plan board, Coming up) and the identity it holds.
   * *Async and PubSub inventory* — every `start_async` name and every
     message either hook reacts to, and the refresh it triggers.
   * *Nav inventory* — the two overlays' zones, contexts, entry order and
     defaults.
   * *Test and story inventory* — the LiveView test files for each modal
     (library: `entity_modal_test`, `entity_modal_refresh_test`,
     `entity_modal_tracking_test`, `entity_modal_delete_folder_safety_test`,
     `library_live_test`, `library_live_leaf_hairline_test`,
     `library_live_tv_orientation_test`, `home_live_test`; title:
     `discovery_live_test`, `incoming_live_test`, `components/title/logic_test`;
     both: `page_smoke_test`, `no_db_on_render_test`) and the stories
     (`storybook/detail_panel/detail_panel.story.exs`, `storybook/detail/*`,
     `storybook/title/title_detail_modal.story.exs`).
   * *Residue inventory* — how many library entities of each kind carry no
     TMDB title identity on the dev database, read through context functions.
3. **Decide the open decisions** with the owner, in the app's terms.
4. **Write the spec** —
   `docs/superpowers/specs/2026-09-14-title-detail-unification-design.md`:
   glossary; the four layers with the module that owns each; the section
   matrix; the view-model shape; the address forms; the diff against the
   code with every incoherence and its disposition; the phase plan with
   tests first per phase; the honest scope cost.
5. **Draft the UIDR** superseding UIDR-035 (one title surface, composed by
   facts; the residue's address; the presentation bar).
6. **Phase plan** — each phase leaves a working product, tested first, and
   the library modal's look verified against the bar before the phase
   closes (same owned titles, same viewport, side by side, judged by the
   owner). Provisional order, to be confirmed by the spec: (a) the
   view-model gains the library half and the one snapshot mapping, rendered
   by nothing yet; (b) the presentation trunk renders the title-only
   sections for an unowned title, behind the library hosts, verified at the
   bar; (c) Discovery and Incoming adopt the unified host and renderer, the
   "In library" bridge goes; (d) the title modal, its host, its overlay and
   its story are deleted; the contract check names the one trait; (e) docs,
   wiki, changelog, merge.

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
