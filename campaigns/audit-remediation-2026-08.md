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

**Resuming after Stages 1–2 (2026-08-06).** Stage 1 rewrote the `Library`
context into 18 modules, so anything you remember about `library.ex`
being one big file is stale. Before starting a stage:

* Read `MediaCentaur.Library`'s moduledoc first — it is now a table
  naming which module owns which concern, and it is the fastest way back
  into the context.
* Stage 4 is the one Stage 1 changed materially — it moved that stage's
  targets and introduced one contract violation. Read its *Stage 1 moved
  these targets* block before planning.
* Stage 2 changed only Boundary declarations and moduledocs, so it moved
  no other stage's numbers. Confirmed by re-measuring all of them after
  it landed (see below) — nothing downstream needs re-deriving on account
  of it.

**Numbers you can trust as of 2026-08-06, post-Stage-2.** Every figure
below was re-run against `main` after Stage 2's commit; each stage
records the command that produced it.

| Stage | Claim | Verified |
|---|---|---|
| 3 | `console_page_live.ex` has zero nav attributes | 0 |
| 3 | `*_behavior.js` files / behavior tests | 11 / 9 |
| 4 | `Repo.*` calls in `test/` | 301 |
| 4 | `=~` assertions in `*_live_test.exs` | 345 |
| 4 | `ProgressRecords.fetch_for_extra/1` still returns `nil` | yes (`progress_records.ex:271`) |
| 5 | `MediaCentaur.PubSub` literals in `lib/` | 134 |

**Two lessons from Stage 2, worth applying to the stages below.**

* **Verify that a recorded command actually produces the recorded
  number.** Stage 2 carried a hatch count of 26, then 31, and the truth
  was 30 — neither earlier figure was reproducible from the command
  written beside it (`grep -rc` prints one line per *searched* file, not
  per match). A number with a command next to it still needs the command
  run.
* **Derive costs from the tool, not from a table.** Stage 2's real
  dependency lists came from removing each hatch and reading the
  compiler. That is what surfaced the `in:`-side cost the stage had not
  costed at all — a stage that only counts one direction will be wrong
  about its size.

Recommended next: **Stage 3** (`/console` input wiring) or **Stage 4**
(policy reconciliation). Stage 4 carries a known contract regression that
Stage 1 introduced (`ProgressRecords.fetch_for_extra/1`), so it has a
concrete defect to anchor on; Stage 3 is self-contained and touches no
Elixir. Both have open questions that need answering before code.

## Status

**Stages 1 and 2 done** (both 2026-08-06). Stage 1 took `library.ex` from
2779 → 127 lines across six commits (`5b2d3510`…`f91f61ce`); the 21 `# ---`
section dividers are gone. Stage 2 closed two of the three Boundary
hatches and documented the third as a permanent, decided exception.
Stages 3–5 not started. The 2026-08-05 audit sweep's Critical and
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

* `2026-08-06` — **Stage 1 complete.** `library.ex` 2779 → 127 lines
  across six commits; 18 new modules plus merges into five that already
  existed. The remaining facade is `subscribe/0`, the change broadcast,
  three HomeFeed delegators, and a moduledoc table naming where each
  concern lives.

  The facade policy landed *more* aggressively than agreed: the plan was
  to keep delegators for functions with 3+ call sites, but the
  `Containers` collapse changed the shape of nearly every remaining
  function (`create_tv_series!/1` → `Containers.create!(:tv_series, …)`),
  so a delegator would have preserved the old name and defeated the
  collapse. Call sites moved instead — ~93 for containers, ~27 for
  progress, ~35 files for the file domain.

  Defects found and fixed during the move, beyond the planned ones:
  - `list_seasons_by_owner_id/1` and `list_seasons_for_tv_series/1` were
    byte-identical bodies — two public functions, one query.
  - `list_images/2` and `logo_urls_for_entities/1` survived in
    `library.ex` after the Image extraction, leaving two implementations
    each with only one reachable.
  - `find_by_external_id/2`'s spec named
    `ExternalIds.owner_type()`, a type that never existed; it compiled
    only because Elixir doesn't resolve remote types eagerly.
  - `MovieSeries.update_changeset/2` and `VideoObject.update_changeset/2`
    had zero callers, unreachable behind missing per-type wrappers. The
    dispatched `Containers.update/2` makes them reachable.
  - The owner-key translation had **four** implementations (three in
    `library.ex`, one independently written in the test factory); all
    now route through `Library.OwnerRef`.
  - `link_file/1` and `create_extra_file/1` were the same function apart
    from the schema; now one `upsert_by_path/2`.
  - The two progress-summary builders differed only in grouping key;
    their shared tail is now one `summarise/2`.

  Deliberately **not** done: the `@owner_types` lists on the sidecar
  schemas still each declare their own `Ecto.Enum` values. `OwnerRef`
  now owns the translation and could own those too, but changing an
  `Ecto.Enum` values list is a schema-level change with migration
  implications and belongs in its own commit.

* `2026-08-06` — **Stage 2 complete.** Two of the three Boundary hatches
  closed (`Status`, `Diagnostics`); the third (`Showcase`) kept and
  documented as a decided permanent exception.

  **Owner decision — `Showcase` stays hatched.** Seeding is the one job
  that legitimately reaches past every facade: 45 cross-context
  references over eleven contexts, four `Acquisition` schema structs the
  context deliberately does not export, and six direct `Repo` writes that
  exist to force states (a mid-flight pursuit, a backdated watch event)
  the public APIs correctly refuse to produce. Closing it would mean
  `Acquisition` exposing a seeding API whose only caller is the demo
  instance — a real widening of the production surface to satisfy a
  declaration on a module nothing in production loads. The second open
  question (`Acquisition` proper vs a dev-only `Acquisition.Seeds`) is
  moot as a result. `WatcherStatus` already set the precedent for a
  documented hatch.

  **Owner decision — the 62-name `Library` `exports:` list is deferred.**
  Recorded as a question for later rather than folded into this stage;
  Stage 2 added only the two names it actually needed.

  Corrections to the recorded evidence: the hatch count is **30**, and
  neither 26 nor 31 was ever produced by the command the file recorded
  (`grep -rc` prints one line per searched file). The stage also
  under-scoped itself — it costed out-refs only, but re-enabling `in:`
  required `Status` to gain an `exports:` list and `MediaCentaurWeb` to
  declare a `MediaCentaur.Status` dep it had never needed.

---

## Stage 1 — Split the `Library` context  ✅ **DONE 2026-08-06**

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

*Realised.* Grouping paid immediately on the file side: `link_file/1`
and `create_extra_file/1` turned out to be the same function apart from
the schema and collapsed to one `upsert_by_path/2`. On the progress
side it collapsed the public surface (`mark_completed/1` and
`mark_incomplete/1` now dispatch on the struct) but not the storage —
that still waits on Extra becoming a PlayableItem.

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

## Stage 2 — Close the Boundary escape hatches  ✅ **DONE 2026-08-06** (`3ff6a4ac`)

**Why.** [ADR-029](../decisions/architecture/2026-03-26-029-data-decoupling.md)
makes `use Boundary, deps: [...]` the canonical inter-context
dependency list. Where checking is off, that list is fiction.

**Evidence** (re-measured 2026-08-06, at the start of the stage).
**30** files declare `check: [in: false, out: false]` — not 26 (the
original text) and not 31 (the first reconciliation pass). Both earlier
figures came from `grep -rc`, which prints one line per *searched* file
including non-matches, so it never produced either number. The command
that does:

    grep -rl "check: \[in: false, out: false\]" lib/ --include='*.ex' | wc -l

Most are legitimate leaf utilities (`Format`, `DateUtil`, `Iso8601`,
`Log`, `Topics`, `Secret`, `Version`, `Repo`) or documented exceptions
(`WatcherStatus`, which exists to break a Boundary cycle and says so).
Three were not — and the real cost was derived by removing each hatch
and reading the compiler, not from the original table:

| Module | Out-refs | Contexts reached |
|---|---|---|
| `diagnostics.ex` | 18 | 2 — `ErrorReports` (+`Bucket`, `Incident`), `Playback` (+`Sessions`, `SessionRegistry`) |
| `status.ex` | 11 | 4 — `Acquisition`, `Library` (+`Completeness`, `ChangeLog`, `FilePresence`, `Stats`, `AbsenceSweeper`, `Availability`), `Maintenance`, `Review` |
| `showcase.ex` | 45 | 11, incl. 4 unexported `Acquisition` schema structs and 6 direct `Repo` writes across 1351 lines |

**What the original stage text missed.** It scoped the work as out-refs
only. Turning `in:` back on has its own cost: 10 references reach *into*
`Status` from the web layer, so `Status` needed its own `exports:` list
**and** `MediaCentaurWeb` needed `MediaCentaur.Status` added to its
`deps:` — that dep had simply never been declared, because `in: false`
made it unnecessary. Any future hatch closure should budget for both
directions.

**Resolved.**

* `Status` — hatch replaced with
  `deps: [Acquisition, Library, Maintenance, Review]` and
  `exports: [LibraryOverview, Views]`. Its moduledoc carried a
  "Boundary follow-up" note calling the hatch a stale holdover; the note
  is gone because the follow-up is done.
* `Diagnostics` — hatch replaced with
  `deps: [ErrorReports, Playback]`. Nothing references into it, so it
  needs no `exports:`. `ErrorReports` already exported `Bucket` and
  `Incident`; `Playback` exported `Sessions` but not `SessionRegistry`,
  now added.
* `Library` — `ChangeLog` and `Completeness` added to `exports:`. The
  original text named only `Completeness`.
* `Showcase` — **hatch kept, documented as permanent** (owner decision,
  see *Decisions made*). Its moduledoc now carries a *"Why the Boundary
  check is off, permanently"* section with the numbers and the reasoning,
  cross-referencing `WatcherStatus` as the existing precedent for a
  documented exception.

**Deliberately not done.** `Library`'s 62-name `exports:` list. It is
worth a look — most entries are schemas that callers need only to
pattern-match a struct, and the honest fix may be a narrower public
surface rather than a longer list — but it is a separate decision and
was explicitly deferred rather than folded into this stage.

**Observed, not acted on.** `lib/media_centaur/library/continue_watching_progress.ex:16`
declares `top_level?: true, check: [in: false, out: false]` — a
`Library.*` module that escapes the `Library` boundary. It is a pure
helper with no dependencies, so the hatch costs nothing today, but the
`top_level?: true` is unexplained and it is the only `Library.*` module
that does this.

**Verification.** `mix compile --force` reports **zero** warnings with
both hatches removed. Full `mix precommit` green — 5670 Elixir tests,
557 JS tests, credo clean, dependency-cruiser clean, sobelow clean.

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
| "never call `Repo` directly from tests" | `.claude/skills/coding-guidelines/SKILL.md` | **301** `Repo.*` calls in `test/` |
| "no `=~` on markup" | `.claude/skills/automated-testing/SKILL.md` | **345** `=~` assertions across `*_live_test.exs` |
| naming: `fetch_*` tuple / `get_*!` raise | de-facto, `Library` | `Review.get_pending_file/1` returns a tuple; `ReleaseTracking.get_item/1` and `WatchHistory.get_event/1` return `nil` |

The first two counts were re-measured 2026-08-06 and differ from the
figures originally recorded (457 / 410). Stage 1 changed neither — its
commits touched **zero** `Repo.` lines in `test/` — so the original
numbers were produced by a different (unrecorded) match. Commands, so
the next reading is comparable:

    grep -rho 'Repo\.[a-z_]*(' test/ | wc -l
    grep -rho '=~' test/**/*_live_test.exs | wc -l

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
  `WatchHistory.get_event/1`, and the two former `Library` stragglers —
  see below for where they went.

**Stage 1 moved these targets, and made one of them worse.** The two
`Library` stragglers this stage named no longer exist under those names:

| Was | Now | Contract |
|---|---|---|
| `Library.get_extra_progress_by_extra/1` | `Library.ProgressRecords.fetch_for_extra/1` | returns `nil` — **violates** the `fetch_*` contract |
| `Library.get_media_track_override/2` | `Library.MediaTrackOverrides.get/2` | returns `nil` — consistent with `get_item` / `get_event` |

`fetch_for_extra/1` is a regression against the contract this stage
proposes: it was honestly named `get_*` returning `nil`, and the
extraction renamed it to `fetch_*` while leaving the return shape alone.
Stage 1 was not applying this stage's contract (they were deliberately
kept separate), so nothing was checking. Fix it here — either restore
`get_` or make it return the tuple — and prefer the tuple, since every
other `fetch_*` in the extracted modules (`Containers.fetch/2`,
`Seasons.fetch/1`, `Episodes.fetch/1`, `PlayableItems.fetch/1`,
`Extras.fetch/1`, `ProgressRecords.fetch_for_container/2`) already
returns one. That makes `fetch_for_extra/1` the single odd one out
rather than the start of a second convention.

This is also evidence for the second open question below: an
arity+prefix Credo check would have caught the rename at the moment it
happened.

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
publication — `MediaCentaur.PubSub` appears as a literal at **134**
sites (re-measured 2026-08-06; was 132). A `Topics.publish/2` +
`Topics.subscribe/1` pair removes all of them and is worth doing
regardless of which idiom wins.

    grep -rho 'MediaCentaur\.PubSub' lib/ --include='*.ex' | wc -l

Stage 1 touched this lightly: the `{:entity_watch_completed, record}`
broadcast moved with `mark_completed/1` into
`Library.ProgressRecords`, so it is now one bare-tuple publisher in a
module with a moduledoc, rather than one buried in a 2779-line context.
The idiom question is unchanged.

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
* **`home_feed.ex` raw-SQL fragments** — `fetch_in_progress_*`
  functions each embed a raw-SQL `fragment` that re-expresses in string
  SQL the join the Ecto `exists` clause already states, naming five
  tables as literals that a rename would break silently. The
  *correctness* bug here is fixed (commit `914e94c9`); the duplication
  is not. A shared `latest_watched_at_subquery(container_type)` built
  with Ecto replaces them. Verified still present 2026-08-06:
  `lib/media_centaur/library/home_feed.ex` lines 246, 343, 439, 537
  (the fragment at 189 is an unrelated `TRIM`). Untouched by Stage 1 —
  `HomeFeed` was already extracted.
* **Preload volume in `fetch_in_progress_tv_series/1`** —
  `Repo.preload([:images, seasons: [:episodes]])` loads every episode of
  every returned series to compute two integers. Now that the
  completeness test is in SQL, those can be `COUNT` aggregates. Verified
  still present 2026-08-06 at `home_feed.ex:358`.

  Note: `Library.ProgressRecords.summaries/1` (extracted in Stage 1)
  already computes exactly these totals as SQL `COUNT` aggregates, in
  `episode_totals_by_tv_series/1`. Whoever picks this up should check
  whether that is directly reusable rather than writing a third version.

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
