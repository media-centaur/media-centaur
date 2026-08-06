---
status: in-progress
started: 2026-08-05
last_updated: 2026-08-06
---
# Audit remediation — August 2026

## Goal

Work off the structural debt surfaced by the four-audit sweep of
2026-08-05 (engineering, performance, documentation, design). The
critical items already shipped; what remains is debt with real
consequences that no single feature ticket would ever justify fixing.
Each stage below is scoped to be discussable in one sitting and
resolvable in the next.

## Working agreement

**Discuss a stage before resolving it.** Each stage carries an *Open
questions* block — those are for the owner, not for the agent to
decide unilaterally. The loop per stage is:

1. Read the stage. Verify its facts still hold (`git log` + the
   evidence commands given) — the reconciliation rule applies here as
   much as to the campaign as a whole.
2. Bring the open questions to the owner and agree an approach.
3. Implement, test-first, `mix precommit` green.
4. Update this file — move the stage to **Done**, append to
   *Decisions made* — and stop. Do not roll into the next stage.

Stages are independent. Order below is recommended, not required.

## Status

Stage 1 discussed and its approach agreed (2026-08-06) — see the stage
for the reconciled evidence and module map; implementation not started.
Stages 2–5 not started. The 2026-08-05 audit sweep's Critical and
Moderate-with-user-impact findings are already fixed and pushed to
`main` (see *Decisions made*); this campaign is the tail.

## Decisions made

* `2026-08-05` — Four-audit sweep run (engineering / performance /
  documentation / design). 53 findings; 2 Critical (perf), 1 Critical
  (design).
* `2026-08-05` — Detail projection split: entity payload (`:cast`,
  `:crew`, `:seasons`, `:movies`, `:images`, `:external_ids`) stored
  once per entity in `:library_view_detail_shared` instead of once per
  row. **219 MB → 5 MB** on a 765-row library; per-row read 330 µs →
  4.7 µs. Full rebuild now emits one `{:library_view_updated, :detail,
  :all}` instead of 765 per-row messages; availability flips patch
  `:present?` in place instead of a 276 ms rebuild. (commit `f1050227`)
* `2026-08-05` — Watch-history delete gated with `data-confirm` and
  made keyboard-reachable; duration column moved to the app-wide
  `Xh Ym` vocabulary; `.text-on-image` and `.image-scrim-*` extracted.
  (commit `a0668da7`)
* `2026-08-05` — 35 unreferenced public functions deleted, 3 narrowed
  to `defp`. (commit `18950c88`)
* `2026-08-06` — `ex_code_view` path dependency removed; it made
  `mix setup` fail on any fresh clone, breaking CONTRIBUTING's own
  documented setup for every external contributor. Its six agent
  scripts retired; `viz-screenshot`'s general `--url` mode survives as
  `~/scripts/agents/page-shot`. (commit `7c91a459` + dotfiles sync)
* `2026-08-06` — ADR-012 citations retargeted. The record was retired
  on purpose in `9e3fd7a4`; 15 sites still cited it and all but three
  meant **UIDR-012**, a different record sharing a number. ADR-042
  amended: permanent documents must never *link* a campaign, only name
  it — the removal-on-completion rule guaranteed dead links, and five
  had already accumulated. `decisions/README.md` is now a generated
  index. (commit `7c91a459`)
* `2026-08-06` — Continue Watching was rendering **empty**, not merely
  short: the SQL `limit` ran before the unfinished test. Both halves of
  "in progress" now run in SQL. `Playback.SessionRecovery` (boot path,
  zero prior test references) covered. (commit `914e94c9`)

---

## Stage 1 — Split the `Library` context

**Why first.** Every other Library-touching finding is downstream of
this file being too large to hold in one head. It is where 27 of the
35 dead functions lived, and where the `fetch_`/`get_` contract
inconsistency hides.

**Evidence.** `lib/media_centaur/library.ex` is 2779 lines with 21
`# ---` sections, each a distinct domain:

    TVSeries · MovieSeries · VideoObject · PlayableItem ·
    Search-index source · WatchedFile · FileMediaInfo · Image ·
    ExternalId · Movie · Extra · ExtraFile · Season · Episode ·
    WatchProgress · HomeLive facade

The repo's own `coding-guidelines` skill names this exactly: *"`# ---`
section dividers separating distinct domains — that's a smell, and the
new code is the cheapest moment to fix it."*

**Reconciled 2026-08-06.** The facts hold (2779 lines, 21 sections, 163
public / 63 private functions), but two section headers understate their
contents:

* **`FileMediaInfo`** (612 lines, 28 pub / 20 priv) is five domains, not
  one: media-info probing · watched-file path queries · `relink_moved_files`
  · `populate_content_urls` (view shaping) · `resolve_presentable` ·
  `load_modal_entry` (detail-modal builder).
* **`HomeLive Facade`** (343 lines, 11 pub / 14 priv) is three lines of
  actual delegators, then `stats/0` plus ~330 lines of progress-record
  and progress-summary aggregation that has nothing to do with the home
  page.

Call sites: **189** in `lib/`, **471** in `test/`. The `lib/`
distribution is lopsided — 62 of 104 distinct functions have exactly one
caller, 84 have ≤2, only 6 have ≥5.

**Approach (agreed 2026-08-06).**

* **Cadence:** one campaign of N mechanical commits, precommit green per
  commit. Split-on-next-touch was already tried implicitly — `HomeFeed`
  and `EntityCascade` came out and the file is still 2779 lines, so it
  demonstrably does not converge.
* **Facade:** delegate only functions with 3+ call sites (~20). For the
  84 called once or twice, move the call site and delete the delegator.
  A facade of 163 delegators for an API where 60% of functions have a
  single caller is a phone book, not an entry point.
* **Naming:** plural sibling modules, following the existing
  `ExternalId` (schema) / `ExternalIds` (queries) precedent. Schema
  modules here are lean — changesets and pure helpers — and stay that
  way; folding queries into them would make every schema moduledoc say
  "the shape *and* the queries."
* **Stage 4 stays separate.** Only five functions are affected by the
  naming unification and Stage 4 also carries policy rewrites unrelated
  to the split. Renaming while moving makes no commit reviewable as a
  pure move.

### Greenfield pass (`unify_design`, 2026-08-06)

**Core idea.** Every operation in `library.ex` acts on an *addressable
library entity* — `(type, id)` — or on data hanging off one. The
codebase already knows this in pieces: `PlayableItem` (canonical leaf
identity, Schema v2 Phase 2), the `(owner_type, owner_id)` discriminator
on four sidecar tables, `TypeResolver`, `EntityShape`. What is left in
`library.ex` is the layer that never got told.

**Module map — organised by role, not by table.**

| Role | Modules |
|---|---|
| Records | `Containers` (4 types, dispatched) · `Seasons` · `Episodes` · `Extras` · `PlayableItems` |
| Files | `Files` (WatchedFile **+** ExtraFile) · `MediaInfo` · `Relink` |
| Progress | `ProgressRecords` (WatchProgress **+** ExtraProgress **+** aggregation) |
| Sidecars on `(owner_type, owner_id)` | `Images` · `ExternalIds` · `MediaTrackOverrides` |
| Derived / read | `SearchIndex` · `Stats` · `ContentUrls` · `ModalEntry` |

Merges into modules that already exist: `ExternalId` (225L) →
`Library.ExternalIds`; `ChangeEntry` (25L) → `Library.ChangeLog`;
`resolve_presentable` family → `Library.PresentableQueries`; `Helpers`
(87L, all private) → `Library.Helpers`; `relink_moved_files` family →
new `Library.Relink`, pairing with the existing `Library.MoveMatcher`.

`ProgressRecords` is named to avoid colliding with both the
`WatchProgress` schema and `Library.Progress` (the ETS projection API);
it is the DB side. `ModalEntry` and `ContentUrls` are view-shaping, not
queries, but are called from the context, so they stay at `Library.*`.

**Containers collapse.** The TVSeries / MovieSeries / VideoObject /
Movie sections repeat the same eight-function CRUD shape four times
(~200 lines of near-duplicate). They collapse into one type-dispatched
`Library.Containers` — `fetch(:tv_series, id)`, `create!(:movie, attrs)`
— mirroring the `(owner_type, owner_id)` discriminator the schema
already uses and the existing `Library.TypeResolver`. `Containers` also
becomes the owner of *what a container is*: the type list is currently
hand-written in `ExternalId` and implicit in `TypeResolver`'s
try-each-table order.

### Incoherences and their disposition

**(a) `WatchProgress`'s API speaks a schema that no longer exists — fix
in Stage 1.** Schema v2 Phase 2 Task C collapsed three FKs into one
`playable_item_id`; the schema has exactly one FK. The API still offers
`fetch_watch_progress_by_fk(:movie_id, id)` — a column name that does not
exist, translated to `(:movie, id)` on the first line of the body — and
three `find_or_create_watch_progress_for_{movie,episode,video_object}`
that accept "the legacy `:movie_id` key" and then
`Map.drop([:movie_id, :episode_id, :video_object_id])`. That is a
compatibility layer for a completed migration. Converges to
`ProgressRecords.fetch_for_container/2` and
`find_or_create_for_container/3`; the only real per-type difference —
canonical position (`Movie.position` / `Episode.episode_number` / `1`) —
moves to `PlayableItems.canonical_position/2`. 12 lib + 15 test sites.

**(b) Three container-type dispatches for progress, three signatures —
fix in Stage 1.** `fetch_progress_for_container/2`,
`find_or_create_watch_progress_for_container/4`, and
`list_progress_records_for_container/2` (filed 500 lines away under
"HomeLive Facade"). Same idea, three shapes, two sections. Free once (a)
lands.

**(c) `MediaTrackOverride` owner types — fix in Stage 1.**
`[:tv_series, :movie]` excluded `:video_object` with no stated reason; a
standalone video's remembered track selection is the same use case as a
movie's. Add `:video_object`.

**(d) `Extra` is a parallel playable — scheduled convergence, not now.**
`ExtraFile ∥ WatchedFile` and `ExtraProgress ∥ WatchProgress` are the
same seven operations twice, differing only in key (`extra_id` vs
`playable_item_id`). Converging means making `Extra` a `PlayableItem`;
the ExtraFile unification shipped in v0.95.4 and left this deliberately.
**Disposition:** group `Files` and `ProgressRecords` by role so both
parallels sit in one file each — the duplication becomes visible and
pressurised instead of filed apart. Convergence point: the next change
that touches Extra playback.

**(e) `ReleaseTracking.Item.@container_types` duplicates the container
universe across a context boundary — deferred to Stage 2**, which is
already the Boundary stage.

**(f) Generic CRUD macro — refused.** `create_X` / `create_X!` /
`fetch_X` / `destroy_X` / `destroy_X!` repeats across ~10 tables and a
`use Library.Record, schema: X` macro would collapse it. Refused: it
manufactures ~50 generated functions in a codebase that just deleted 35
unreferenced public functions (commit `18950c88`) and relies on grep to
find them. Codegen makes that class of dead code undetectable. The
`Containers` collapse is different — runtime dispatch on an explicit
atom, four real bodies to one.

**Target.** `Library` facade at 300–400 lines.

**Verification.** `mix precommit`; `mix boundaries`; the moduledoc of
each new module names *one* thing.

---

## Stage 2 — Close the Boundary escape hatches

**Why.** [ADR-029](../decisions/architecture/2026-03-26-029-data-decoupling.md)
makes `use Boundary, deps: [...]` the canonical inter-context
dependency list. Where checking is off, that list is fiction.

**Evidence.** 26 of 65 boundaries declare `check: [in: false, out:
false]`. Most are legitimate leaf utilities (`Format`, `DateUtil`,
`Iso8601`, `Log`, `Topics`, `Secret`, `Version`, `Repo`). Three are
not:

| Module | Reaches |
|---|---|
| `lib/media_centaur/status.ex:2` | `Acquisition.Pursuits`, `Library`, `Library.Completeness`, `Library.FilePresence`, `Maintenance`, `Review` |
| `lib/media_centaur/showcase.ex:2` | `Repo` **directly**, plus `Acquisition.Pursuits.{Pursuit, TargetUnit, Unit}` schema structs, `Library`, `ReleaseTracking`, `Review`, `TMDB`, `WatchHistory` |
| `lib/media_centaur/diagnostics.ex:2` | `ErrorReports.Bucket` / `ErrorReports.Incident` internals |

`Status`'s own moduledoc already flags its hatch as a stale holdover
and scopes the fix: export `Library.Completeness`, list the six deps.

**Approach.** `Status` first — it is genuinely composition-only now and
the work is one `deps:` list plus one `exports:` addition. `Diagnostics`
next. `Showcase` last and hardest: it writes through `Repo` into another
context's schemas, so it needs `Acquisition` to expose a seeding API
rather than surrendering its structs.

**Open questions for the owner**
* Is `Showcase` worth the work at all? It is dev/demo-only. A defensible
  alternative is to leave the hatch and add a comment saying *why* it is
  permanent — a documented exception beats an undocumented one.
* Should a seeding API live on `Acquisition` proper, or in an
  `Acquisition.Seeds` module compiled only in dev?

**Verification.** `mix boundaries` with the hatches removed.

---

## Stage 3 — `/console` keyboard and gamepad navigation

**Why.** `/console` is the only routed page with no input-system
wiring. The other ten all declare `data-page-behavior`, and nine have
a behavior test.

**Evidence.** `lib/media_centaur_web/live/console_page_live.ex` renders
`<div class="console-fullpage">` — zero `data-page-behavior`,
`data-nav-zone`, or `data-nav-item` in the file. Its source tabs,
filter chips, and action footer are unreachable without a mouse.

Existing behaviors: `assets/js/input/{guide,home,incoming,library,
reconcile,review,settings,setup,status,watch_history}_behavior.js`,
registered in `page_behavior.js`, zone layouts in `config.js`.

**The trap.** The console components (`source_tabs`, `chip_row`,
`action_footer` in `components/console_components.ex`) are **shared
between the `/console` page and the global `` ` `` drawer**. Adding
`data-nav-zone` to the components would inject console zones into every
page's DOM. Zones must be declared by the page, or the components need
a `nav?` attr the drawer sets false.

**Approach.** Zones `console_tabs` → `console_filters` →
`console_actions`, each `left: ["sidebar"]`. The log stream is a
scrolling list, not individually navigable — do not make it a zone.
Add `console_behavior.js` + `assets/js/input/__tests__/
console_behavior.test.js` to match the family.

**Open questions for the owner**
* Should the drawer be navigable too, or is it deliberately
  mouse/keyboard-shortcut only? That decides whether zones live on the
  page or in the shared components.
* Is the log stream ever a navigation target (e.g. to select an entry
  and copy it), or is scroll-only correct?

**Verification.** `bun test assets/js/input/`; drive the page with
`chromium-probe` per `reference-input-nav-runtime-verification`.

---

## Stage 4 — Make the stated policies true again

**Why.** Two written policies now describe a codebase that does not
exist. That erodes the credibility of the policies that *are* followed
— and this repo's are unusually well followed.

**Evidence.**

| Policy | Location | Reality |
|---|---|---|
| "never call `Repo` directly from tests" | `.claude/skills/coding-guidelines/SKILL.md` | **457** `Repo.*` calls in `test/` |
| "no `=~` on markup" | `.claude/skills/automated-testing/SKILL.md` | **410** `=~` assertions across ~40 `*_live_test.exs` |
| naming: `fetch_*` tuple / `get_*!` raise | de-facto, `Library` | `Review.get_pending_file/1` returns a tuple; `ReleaseTracking.get_item/1` and `WatchHistory.get_event/1` return `nil` |

Most `Repo` uses in tests are legitimate — asserting a row landed, or
forcing a state the public API deliberately won't produce (20 sites use
`Ecto.Changeset.change(...) |> Repo.update!()` to backdate or force a
pursuit state).

**Approach.**
* Reword to what is actually intended: no `Repo` for *setup*; `Repo`
  for *assertion* is fine. Scope the markup rule to *structural* markup
  (class names, tag nesting), not user-visible copy.
* Add the missing factory affordances so the setup cases have somewhere
  legitimate to go: `TestFactory.backdate(record, field, datetime)` and
  `TestFactory.force_state(pursuit, state)` in `test/support/factory.ex`.
* Unify the lookup contract: `fetch_*` → `{:ok, _} | {:error,
  :not_found}`, `get_*!` → raises, nothing else. Rename
  `Review.get_pending_file/1`, `ReleaseTracking.get_item/1`,
  `WatchHistory.get_event/1`, and the two `Library` stragglers
  (`get_extra_progress_by_extra/1`, `get_media_track_override/2`).

**Open questions for the owner**
* Amend the policies to match practice, or hold the line and fix the
  457/410? (Recommendation: amend — the practice is defensible and the
  policies over-reached.)
* Is a Credo check for the naming contract worth it, given this repo's
  code-as-spec preference? It would need to know each function's return
  type, so probably arity+prefix heuristics only.

**Verification.** `mix precommit`. If a Credo check lands, it must go
red on a deliberately-wrong function first.

---

## Stage 5 — Pick one event-publication idiom

**Why.** Two idioms coexist repo-wide. This is a convention decision,
not a refactor — it needs an ADR before any code moves.

**Evidence.**
* **Typed structs behind an `Events` module** — `library/events.ex`,
  `library/progress/events.ex`, `playback/events.ex`,
  `acquisition/pursuits/events.ex` (+20 event modules, an
  `event_behaviour.ex`, and a `define.ex` macro).
* **Bare inline tuples** — ~50 modules broadcast directly, roughly 30
  distinct message shapes with no struct, no `@type`, and no single
  place to discover the contract. `Review`, `Settings`,
  `ReleaseTracking`, `Watcher`, `Reconciliation`, `Capabilities`,
  `Controls`, `IntegrationHealth`, `WatchHistory`, `ErrorReports`.

Related but separable: `Topics` centralises topic *names* but not
publication — `MediaCentaur.PubSub` appears as a literal at **132**
sites. A `Topics.publish/2` + `Topics.subscribe/1` pair removes all of
them and is worth doing regardless of which idiom wins.

**Approach.** Write the ADR first; convert per-context on next touch,
not in a sweep.

**Open questions for the owner**
* Is the typed-struct idiom the target, or was it an experiment that
  should be *rolled back* to plain tuples? Twenty event modules for
  `Pursuits` is a lot of ceremony; the answer is not obviously "expand
  it."
* Does `Topics.publish/2` land independently of that decision?
  (Recommendation: yes — it is mechanical and idiom-agnostic.)

**Verification.** ADR merged; one context converted as the worked
example.

---

## Stage 6 — Opportunistic polish (no discussion needed)

Small, independent, each safely done in a spare slot. Not gating
anything.

* **Boolean-setting boilerplate** — `lib/media_centaur/{spoiler_free,
  library_backdrop,library_card_info,incoming_backdrop}.ex` plus their
  four `*_aware.ex` mixins: **8 modules, 285 lines, for 4 flags**.
  `library_backdrop.ex` and `incoming_backdrop.ex` have byte-identical
  bodies apart from the key string. A `use MediaCentaur.BooleanSetting,
  key: "…", default: false` macro collapses them.
* **Cast grid** — `components/detail/more_info/cast_grid.ex:33`
  renders *every* cast member and hides all past `@max_cast_cards 24`
  with `display:none`, so a 900-member series emits 900 cards into the
  DOM and the LiveView diff. The moduledoc justifies it (client-side
  filter with no round-trip) but priced it for a cast of ~40. Cap the
  rendered window, or pass the list as a `data-` attribute.
* **`clear_database` confirmation** —
  `live/settings_live/danger.ex:214` uses the native browser
  `data-confirm` for the single most destructive action in the app,
  while five other flows use the themed, gamepad-navigable
  `ModalShell`. The native dialog ignores the theme and is not
  d-pad reachable.
* **`Topics.publish/2` / `Topics.subscribe/1`** — see Stage 5; can land
  early.
* **`home_feed.ex` raw-SQL fragments** — three `fetch_in_progress_*`
  functions each embed a raw-SQL `fragment` that re-expresses in string
  SQL the join the Ecto `exists` clause already states, naming five
  tables as literals that a rename would break silently. The
  *correctness* bug here is fixed (commit `914e94c9`); the duplication
  is not. A shared `latest_watched_at_subquery(container_type)` built
  with Ecto replaces all three.
* **Preload volume in `fetch_in_progress_tv_series/1`** —
  `Repo.preload([:images, seasons: [:episodes]])` loads every episode of
  every returned series to compute two integers. Now that the
  completeness test is in SQL, those can be `COUNT` aggregates.

## Completion criteria

* Stages 1–5 each either **resolved** or **explicitly declined** with
  the reason recorded in *Decisions made*. A declined stage is a valid
  outcome; an undiscussed one is not.
* `mix precommit` green after each stage, no new Credo suppressions.
* No stage left half-applied — the audit's own headline finding was
  that this repo's defects come from refactors that start well and stop
  at 80%.
* Stage 6 items are droppable; do not let them hold the campaign open.

## Pointers

* Audit sweep and all evidence: this campaign's originating session,
  2026-08-05 → 2026-08-06. Commits `f1050227`, `a0668da7`, `18950c88`,
  `7c91a459`, `914e94c9`.
* [ADR-029](../decisions/architecture/2026-03-26-029-data-decoupling.md) — Boundary as the dependency list (Stage 2)
* [ADR-030](../decisions/architecture/2026-04-02-030-liveview-logic-extraction.md) — LiveViews are thin wiring
* [ADR-041](../decisions/architecture/2026-05-10-041-in-memory-projection-architecture.md) — projection architecture (context for the Detail work already done)
* [ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md) — campaign conventions, amended 2026-08-06
* [UIDR-012](../decisions/user-interface/2026-05-20-012-desktop-app-rendering-defaults.md) — desktop rendering defaults (cited as ADR-012 for months; see *Decisions made*)
* `.claude/skills/coding-guidelines/SKILL.md` — modular-cohesion rule quoted in Stage 1
* `docs/architecture.md` — bounded contexts (Stage 2); PubSub taxonomy now lives in the `MediaCentaur.Topics` moduledoc (Stage 5)
