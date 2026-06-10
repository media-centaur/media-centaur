---
status: COMPLETE 2026-06-10 (Phases 1–3 shipped here; Phase 4 shipped via release-tracking-plan-convergence; wiki synced — Searching-and-Downloading page, wiki commit 9fc15a4; residual dispositions recorded in the convergence campaign's closure reconciliation)
started: 2026-05-31
last_updated: 2026-06-10
---
# Media search (TMDB-first acquisition)

## Goal

Make media search the **primary acquisition path**. Today you acquire by
typing a release-name query, searching indexers, and grabbing a file ("file
search"). Media search inverts that: you start from **what you want to
watch** — a TMDB title — pick the seasons/episodes you want, and Media
Centaur autonomously figures out *how* to satisfy that from what's currently
available across indexers (complete-series packs, season packs, per-episode
releases), shows you the resulting **plan**, lets you steer it, and only
then executes it as a single rich pursuit.

File search remains, repositioned as the **naked search** — the
release-name-first tool, secondary to the TMDB-first door. Its natural
embedded home is as the unit-scoped override instrument inside plan feedback
and pursuit intervention; the prominence/placement of its standalone entry
is a Phase 3 call.

The deeper goal is a **unified pursuit model**. Both searches route through
one composite-pursuit core; file search is adapted onto it (gaining the new
model + UI) and media search layers TMDB-specific enrichments on top. We are
not building a second parallel acquisition system.

**North star:** the automation exists so the *user's preference can win*
while the complexity stays hidden. Settings, asking, and plan-time override
are all legitimate — the bar is "best experience, complexity concealed," not
"fewest knobs."

## The model

Settled across the 2026-05-31 and 2026-06-09 design sessions. Resumable
context — read this before writing code.

**Vocabulary (load-bearing — schema and progress semantics follow it):**
* **Unit** — one wanted thing (an episode, or the movie). Targeting produces
  a set of units.
* **Candidate** — a corpus entry: one release known to cover ≥1 units at
  some quality/health.
* **Assignment** — the plan: every covered unit mapped to exactly one chosen
  candidate (many units may share one candidate).
* **Leaf** — one grab attempt of one assigned candidate. Leaves are
  **per-release, not per-unit** — a season pack is one leaf covering ten
  units. Progress is always **units satisfied / units wanted**, never
  "leaves done" (a failed pack leaf is ten missing episodes, not one
  failure).

**Four phases (media search):**
1. **Select** ("targeting") — spec builder: TMDB title → series / seasons /
   episodes, quality prefs, and a "grab future releases too?" opt-in. A UI
   surface in its own right. Defaults: aired-to-date, minus what's already
   on disk, minus what release tracking covers — subtractions **shown**
   (grayed "in library" / "tracked" rows), not silently applied. Quality
   defaults from settings with per-search override. Movies: pick + quality
   and you're done (a movie is a single unit; TMDB collections deferred).
2. **Search & Plan** — an autonomous, **visualized** process that searches
   (politely) and solves a coverage plan over what's available *now*. Two
   synchronized views: a **coverage board** (units as a grid; cells move
   through searching → found → assigned, visibly consolidating when a pack
   covers a row) and a live **search activity feed**. The in-progress plan
   is a **durable draft** (planning → awaiting-approval → committed /
   discarded): refresh-safe, resumable from Downloads, and the pursuit's
   provenance.
3. **Plan feedback** — the user steers: swap a chosen release (unit-scoped
   naked search), exclude, force a re-search, approve. Loops back into
   planning. Nothing grabs until approval. Unfound units render as explicit
   gaps; approval offers a one-click **release-tracking handoff for the
   gaps**.
4. **Pursuit** — the approved plan executes as **one composite pursuit**.
   Card on Downloads: backdrop + logo, "N of M units landed." Modal: the
   same coverage board showing per-unit satisfaction with leaf-level
   drill-down; intervention on a failed leaf is the unit-scoped naked
   search.

**One core, two front doors.** There is one pursuit system:
* **Shared core** (both doors): the composite pursuit (parent + leaf
  attempts), the search corpus, living-intent re-resolution, leaf-level
  intervention, and the progress / drill-down UI.
* **File search (door A)** is a **fast path** — the user already picked the
  releases, so the selection *is* the plan; it skips the autonomous plan +
  feedback phases but still lands in the composite-pursuit core. Its
  brace-expansion (`Sample Show S01E{01-10}`) collapses into **one** pursuit
  with ten leaves — a real model + UX upgrade.
* **Media search (door B)** adds TMDB-only enrichments: the selection UI, the
  coverage planner, the rich TMDB backdrop card, and the release-tracking
  handoff.

**Composite pursuit = the existing `Pursuit` grown children.** One pursuit =
the whole request (parent with unit-based overall progress) → many leaf
attempts (per-release grabs, each covering ≥1 units — see Vocabulary). No
separate aggregate. Today's per-attempt intervention becomes the leaf-level
interaction, reused. **Identity is an overlap check, not key equality**: a
composite parent covers many episodes, so ADR-039's
`(tmdb_id, type, season, episode)` idempotency key gives way to the rule
that no two active pursuits — or a pursuit and a release-tracking item — may
claim the same unit of the same title. One mechanism covers idempotency and
risk #4.

**The planner is a coverage optimizer.** Wanted units to cover + a corpus of
candidate releases (each covering one-or-more units at some quality/health).
Objective priority: **Coverage → User preference → Consolidation → Health.**
The complete-series → season-pack → per-episode **ladder** is just the
*granularity* axis of that optimization, applied automatically; the user
picks *what* they want, not *how* to search.

**Best available now — no time dimension.** Media search plans from what's in
the corpus *now*. No quality patience (won't wait for a 4K that isn't there),
no upgrades (re-grabbing a better version later). The passage of time —
future episodes, later-appearing better releases — is **release tracking's**
job, not media search's.

**Search vs pursuit is a hard boundary.** Search *discovers* and reports its
gaps ("found 9 of 10; S2E7 unavailable"). Pursuit is strictly what happens
*after* a plan exists and only contains units the search found a release for.
An unfound unit is a **search result, not a pursuit leaf** — the pursuit is
never an open-ended seeker. Re-discovery is always a *search* act (initial, a
bounded freshness refresh, or user intervention); the pursuit executes known
candidates, falls back among already-found ones if a pick dies, and **reports
a failure** when they're exhausted.

**The corpus** is durable and shared by planner + pursuer. It serves two
masters: **indexer citizenship** (consult it first; a freshness policy gates
re-searches so an automated system doesn't thrash indexers) and
**current-alternative fallback** (swap a dead pick for another already-known
candidate). It is *not* a wait-for-something-better mechanism.

**Bounded, not forward.** Media search covers a fixed selection. The future
is opt-in: chosen at *select* time, the release-tracking handoff fires **on
completion** (once every selected unit has landed), so the two systems never
contend over the same episode.

## Decisions made

Append-only log.

* `2026-05-31` — **Two front doors, one composite-pursuit core.** File search and media search are entry points onto a single pursuit system, not parallel systems.
* `2026-05-31` — **File search is adapted onto the core as a fast path** (selection = plan; skips autonomous plan/feedback) and gains the model + UI upgrades. Brace-expanded fan-out collapses into one composite pursuit.
* `2026-05-31` — **Composite pursuit extends `Pursuit`** (parent + leaf attempts); no new aggregate. Per-attempt intervention reused at the leaves. *(ADR candidate — supersedes the per-episode `tmdb`-recipe pursuit shape; write the ADR in Phase 1.)*
* `2026-05-31` — **Plan-before-pursue lifecycle** for media search (four phases); planning is interactive and visualized, not a spinner.
* `2026-05-31` — **Planner = coverage optimizer**; objective priority **Coverage → User preference → Consolidation → Health**. Pack-vs-quality conflict defaults toward user preference, surfaced as an override when close.
* `2026-05-31` — **Coverage ladder is automatic** (complete-series → season pack → per-episode); the granularity axis of the optimizer. User picks *what*, not *how*.
* `2026-05-31` — **Best-available-now: no quality patience, no upgrades.** The time dimension belongs to release tracking. Kills the interacting-patience-timers risk.
* `2026-05-31` — **Search vs pursuit is a hard boundary.** Search discovers + reports gaps; pursuit is post-plan and only holds found units. Unfound units are never pursuit leaves; the pursuit is not an open-ended seeker. *(Supersedes the earlier "bounded but patient / keep seeking" idea.)*
* `2026-05-31` — **Living intent is scoped**: at grab time the pursuit re-resolves only among already-found corpus candidates for that unit; exhausting them = leaf failure → user intervention. The pursuit never autonomously re-discovers.
* `2026-05-31` — **Corpus = citizenship rate-limiter + current-alternative fallback**, governed by an explicit freshness policy. Not a wait-for-better mechanism.
* `2026-05-31` — **Bounded, not forward**; "grab future" opt-in at select time hands off to a release-tracking entry **on completion**.
* `2026-06-09` — **Media search is the primary acquisition path.** File search is repositioned as the secondary **naked search** (release-name-first); embedded as the unit-scoped override tool in plan feedback / pursuit intervention; standalone-entry placement is a Phase 3 call. *(Supersedes the "second entry point alongside" framing.)*
* `2026-06-09` — **Vocabulary: unit / candidate / assignment / leaf.** A leaf is a grab of one *release* covering ≥1 units; progress counts **units satisfied**, never leaves done. *(Supersedes the earlier "leaf = per-unit grab" phrasing; makes risk #1 a schema-level rule.)*
* `2026-06-09` — **Composite identity = overlap check, not key equality.** No two active pursuits — or a pursuit and a release-tracking item — may claim the same unit of the same title. Goes in the Phase 1 composite-pursuit ADR.
* `2026-06-09` — **Durable draft plan.** Lifecycle planning → awaiting-approval → committed / discarded; survives refresh/restart, resumable from Downloads, becomes pursuit provenance. (Fits ADR-023 durable-process design.)
* `2026-06-09` — **Gap handoff at approval.** "Found 9 of 10" offers a one-click release-tracking entry for the missing units; depends on the overlap-check dedup.
* `2026-06-09` — **Targeting defaults**: aired-to-date minus library minus tracked, subtractions shown not silent; quality from settings with per-search override.
* `2026-06-09` — **Movies are a single unit; TMDB collections deferred** (the client's `get_collection` keeps the door open).
* `2026-06-09` — **Core-first phasing confirmed** despite the primary repositioning — Phase 1 still proves the composite core on file search before any TMDB UI.
* `2026-06-09` — **ADR-055 written and accepted** (`decisions/architecture/2026-06-09-055-composite-pursuits.md`): units carry the attempt thread; parent state is a transactional fold (`State.fold_units/1` via `Commands.Refold`); target↔unit coverage is a join table; `partial` is the mixed-outcome terminal state.
* `2026-06-09` — **Phase 1 core SHIPPED** (3 commits, unpushed): schema + backfill (`b92e8433`), thread flip onto units (`8c7705ef`), batch-grab collapse (`4f43e7ec`). Every existing pursuit migrated losslessly to a single-unit composite; `Sample Show S01E{01-02}`-style batch grabs now land as ONE pursuit with per-term units (verified end-to-end in `acquisition_live_test`).
* `2026-06-09` — **Interim unit resolution for pursuit-scoped surfaces**: `Units.lead_of/1` (awaiting-decision unit → active w/ target → active → first) is the single definition of which thread the modal/decision-card/ChangeTarget act on until per-unit drill-down lands. `Units.single!/1` remains only where single-unit is a true invariant (TMDB `Arm`) — it raises on multi-unit pursuits as a deliberate tripwire.
* `2026-06-09` — **Unit-scoped search**: `Recipe.for_unit/2` overrides `manual_query` with the unit's concrete term — worker re-search and decision-card alternatives stay scoped to the unit, never re-expanding the whole braced query.
* `2026-06-09` — **`matches?/2` stays the strict want-equality gate; `coverage/2` is the planner's reader.** The auto-grab worker must never silently pull a season pack for one episode — pack-vs-episode is exclusively the planner's decision. Pack identity is verified by prefix-before-scope-token (trailing-year tolerant); classification is conservative (inverted ranges = `:unknown`; `COMPLETE` reads as series only with no season token) per risk #3.
* `2026-06-09` — **Plan-wide exclusions.** "Not this release" on one unit removes the release from the whole plan's option pool — a release the user rejected for one episode is almost never what they want for another (especially packs). The exclusion is still *stored* per unit for future refinement.
* `2026-06-09` — **Exclusion re-solve is corpus-only.** Swapping resolves among already-known candidates with zero new indexer traffic; a live re-search is a separate, explicit user act (`replan(force_search: true)`).
* `2026-06-09` — **Commit degradation.** A failed grab at commit time degrades that release's units to `seeking` targets handled by the regular `PursueTarget` machinery — the plan's promise survives an indexer hiccup rather than dropping units.
* `2026-06-09` — **Corpus constants:** 30-minute freshness window, 14-day retention (pruned per watcher tick), result-affecting opts (`type`, `year`) in the key, empty result sets recorded as fresh negative knowledge, failures never recorded.
* `2026-06-09` — **Phases 2 + 3-backend SHIPPED** (commits `2b44d136`, `3d9d1e0a`, `b4066cf2`): ReleaseCoverage + TitleMatcher.coverage; Targeting; pure Planner; durable Plans + RunPlan + feedback verbs + CommitPlan with the generalized overlap check. Full lifecycle proven in `plans_test.exs` (create → solve w/ pack consolidation → steer → approve → one composite pursuit; overlap rejection; movie path).
* `2026-06-10` — **Phase 4 re-homed and expanded** into [`release-tracking-plan-convergence.md`](release-tracking-plan-convergence.md): release tracking's whole materialization path converts onto the plan→composite-pursuit core (per-drop plans; want ledger; patience as commit gate), not just the handoffs. Gap handoff, grab-future, pursuit×track dedup, and per-unit tracked subtraction all land there. This campaign's remaining scope: wiki sync, then closure reconciliation.

## Next steps

Phased rollout, sequenced to de-risk: each phase ships a real improvement
without depending on the harder logic that follows. Each phase must not break
the seven risks below.

1. **Pursuit core + migrate file search onto it.** Status 2026-06-09:
   * ✅ ADR-055 written/accepted (composite shape, fold, overlap-check rule).
   * ✅ Schema: `acquisition_pursuit_units` + `acquisition_target_units`,
     backfilled; thread columns dropped from pursuits (2 migrations,
     backfill dry-run-verified against a prod DB copy).
   * ✅ Thread flip: commands / PursueTarget / Watcher loop
     (Observations → Snapshot → Policy, now per-unit) / view-models /
     LiveView re-pointed; `partial` state live; unit-based fold is the
     only writer of pursuit state.
   * ✅ Batch-grab collapse: one composite pursuit per brace-expanded
     grab, one unit per term (`Acquisition.pick_targets/2`,
     batch `StartFromPick`).
   * ✅ **Parent/leaf UI** (2026-06-09, commit `457f4df6`) — "N of M"
     unit-progress chip on `PursuitRow` (both densities), the
     **UnitBoard** drill-down in the pursuit modal (one row per unit:
     state, covering release, unit-scoped Change-target via
     `ChangeTarget` `unit_id`), `partial` state badge. Stories:
     composite axis on pursuit_row, new unit_board story, composite
     modal variation. Remaining lead-interim: the pursuit-level
     Change-target button and the decision card still act on the
     awaiting-or-lead unit — fine while the board carries the per-unit
     affordances; revisit with the Phase 3 coverage board.
   * ✅ **Search corpus + living-intent re-resolution** (2026-06-09,
     commit `03cc07ca`) — `Acquisition.Corpus`: durable
     searches+candidates keyed by term + result-affecting opts;
     consult-first (`Corpus.search/2`, 30-min freshness, empty results
     = fresh negative knowledge, failures never record) wired into the
     worker loop, the alternatives path (user refresh passes
     `force: true`), and manual-zone recording; 14-day retention pruned
     per watcher tick. A pivoted unit re-resolves among already-known
     candidates with zero search traffic (worker test poisons the
     search route to prove it).

   **Phase 1 is COMPLETE.** All five sub-items shipped across commits
   `b92e8433` → `03cc07ca`; the composite-pursuit core, its UI, and the
   corpus are live for the query door. Next: **Phase 2 — pack strategy
   + coverage ladder.**
2. **Pack strategy + coverage ladder.** ✅ machinery shipped 2026-06-09
   (commit `2b44d136`): `Search.ReleaseCoverage` classifies release
   scope (episode / span / season / season-range / series; conservative
   against risk #3) and provides the accounting primitives
   (`covers?/3`, `covered_units/2` — partial packs are the normal
   case); `TitleMatcher.coverage/2` verifies show identity for pack
   shapes and returns the scope. `matches?/2` deliberately keeps strict
   want-equality — pack-vs-episode is the planner's call, so the
   auto-grab worker can't silently pull a season pack for one episode.
   *Dedup-against-library and within-corpus dedup are planner
   constraints by construction (subtract present units from the want
   list; assignment maps each unit to exactly one candidate) — they
   land with Phase 3's planner.*
3. **Media-search front door.** Backend spine ✅ SHIPPED 2026-06-09
   (commits `3d9d1e0a` + `b4066cf2`):
   * `Acquisition.Targeting` — TMDB series → unit universe (aired per
     season, specials excluded, library-presence + tracked flags shown
     not silent; `default_units/1` = aired-minus-library).
   * `Acquisition.Planner` — pure coverage optimizer; objective
     hierarchy Coverage → User preference → Consolidation → Health;
     broad-first ladder judged against per-unit-best ensembles.
   * `Acquisition.Plans` + `Jobs.RunPlan` — the durable draft plan
     (planning → ready → committed/discarded), ladder searches through
     the corpus, assignments/unfound on plan units, feedback verbs
     (exclude_release plan-wide + corpus-only re-solve, exclude_unit,
     replan w/ force), `PlanEvents` broadcasts for the live board.
   * `Plans.CommitPlan` — the approval gate: **generalized ADR-055
     overlap check** (unit-level + legacy pursuit-key fallback), found
     units → ONE composite pursuit (per-release grabs covering their
     units; failed grabs degrade to seeking + PursueTarget), unfound
     never crosses the search→pursuit boundary. Pursuit units now carry
     season/episode identity; `Recipe.for_unit` narrows tmdb re-search
     to the unit's episode.

   ✅ **UI SHIPPED 2026-06-10** (commits `6e4def2f` omnibox,
   `7935ff61` plan flow, `cafddc49` identity banners) — built exactly
   to UIDR-014: omnibox hero w/ release-mode flip (search zone now
   headless; an active session auto-resumes release mode); URL-driven
   plan modal (?plan=new&tmdb_id=… → ?plan=<id>) with picker
   (PlanLogic pure selection + presets), live board (PlanBoard VM via
   `Plans.board_for/1`, capsule consolidation, gap row, activity
   ticker over PlanEvents), approve → patches straight to the pursuit
   modal; resumable draft cards; identity banners (synthetic per-title
   hue + scrim; query door stays plain w/ door chip); segmented
   unit-progress on composite cards. Whole door verified end-to-end in
   LV tests. **Phase 3 is COMPLETE.**

   *(original design approval note follows)* ✅ **UI DESIGN APPROVED 2026-06-10** —
   [UIDR-014](../decisions/user-interface/2026-06-10-014-media-search-front-door.md)
   is the spec (mockups at `~/.agent/mockups/media-search-front-door/`,
   session artifacts): omnibox hero w/ release-mode flip; one
   continuous URL-driven plan modal (picker → unit-grid board →
   approval footer, no wizard); one cell vocabulary across plan board /
   segmented pursuit-card progress / UnitBoard; imagery =
   title-doored identity w/ scrim discipline + gradient-logotype
   fallback (no TMDB hot-linking in v1).

4. **Release-tracking handoffs + polish.** → **Re-homed 2026-06-10** to
   [`release-tracking-plan-convergence.md`](release-tracking-plan-convergence.md),
   which subsumes and expands this phase: the handoffs only make sense
   once tracks emit plan-provenance pursuits, so the conversion of
   release tracking's materialization path and the handoffs ship as one
   campaign. Remaining in *this* campaign: wiki sync (carve-out
   expired), then closure reconciliation per the
   closure-by-destination convention.

## Risk surface

Seven independent ways to ship something subtly broken — guardrails for every
phase. `(exists)` = works today, `(extends)` = grows existing code,
`(net-new)` = new mechanism.

1. **Pack → episode accounting** *(✅ mechanism shipped)* — schema-level rule (leaves per-release, progress per-unit; Vocabulary) + `ReleaseCoverage.covered_units/2`; `Satisfy` satisfies exactly the covered units of the landed target. Real-world pack grabs (Phase 3 UI usage) will be the live proof.
2. **Ladder redundancy within the current corpus** *(✅ by construction)* — the planner's assignment maps each unit to exactly one candidate; a pack and singles can never both claim the same unit (`plans_test` exercises the pack↔singles flip).
3. **Fuzzy pack detection** *(✅ shipped, conservative)* — `ReleaseCoverage.classify/1` with append-only parser-class tests; inverted ranges = `:unknown`, `COMPLETE` reads as series only without a season token. Extend the test table as real-world shapes appear (ADR-027 append-only).
4. **Overlap with release tracking** *(½ shipped)* — pursuit×pursuit overlap is enforced in `CommitPlan` (unit-level + legacy pursuit-key fallback). Pursuit×**track** dedup remains Phase 4 (gap handoff + "grab future" both depend on it); targeting currently surfaces tracked-ness as a series-level flag only.
5. **Per-episode model strain** *(✅ resolved)* — units carry season/episode identity; `Recipe.for_unit/2` narrows tmdb re-search per unit; the watcher loop is per-unit. *Known residual:* see resumption note on multi-unit tmdb satisfaction matching.
6. **Composite-pursuit lifecycle** *(✅ resolved)* — fold semantics (`partial`), unit-based progress everywhere, reconciler runs per (pursuit, unit, target). The residual (reconciler tmdb match read pursuit-level season/episode, nil on multi-unit parents) was closed 2026-06-10 by the downloads-debt-retirement work: `LibraryReconciler.tmdb_match/2` reads the unit's identity (commit `8e733a57`), and unit identity is complete everywhere (Arm stamps it; `BackfillUnitIdentity` covered legacy rows — commit `b43a1e2b`).
7. **(retired)** — interacting patience timers; dissolved by the best-available-now / no-upgrades decision. Left numbered so the risk list maps to the design discussion.

## Completion criteria

* A user can search TMDB, pick at any granularity (series / season / episode), review an auto-generated coverage plan, steer it, and submit — landing one composite pursuit that grabs the planned releases.
* File search produces the *same* composite-pursuit shape (one pursuit per brace-expanded query) with the new progress / drill-down / intervention UI — no parallel pursuit system remains.
* The planner honors the objective hierarchy and the automatic ladder; pack downloads correctly satisfy their covered episodes (no re-grabs, no false "done").
* Unfound units are reported at plan time, never as perpetually-seeking pursuit leaves.
* ~~"Grab future" opt-in creates a release-tracking entry on completion, with no double-grabbing against existing tracks.~~ → re-homed to [`release-tracking-plan-convergence.md`](release-tracking-plan-convergence.md) (2026-06-10).
* Progress everywhere is unit-based (a failed pack leaf shows as its covered units missing, not one failed item).
* A browser refresh or app restart mid-planning loses nothing — the draft plan resumes from Downloads.
* ~~Plan gaps offer the one-click release-tracking handoff at approval.~~ → re-homed to `release-tracking-plan-convergence` (2026-06-10).
* No unit of a title is ever claimed by two active pursuers — pursuit×pursuit enforced here; the pursuit×**track** direction re-homed to `release-tracking-plan-convergence` (ADR-056 want ledger).
* Downloads page presents media search as the primary path; naked search has a settled secondary placement.
* Wiki updated (new acquisition flow + the media-search/naked-search distinction).

## Resumption state (written 2026-06-09, end of the build sessions)

> **2026-06-10 note:** the UI design session below HAPPENED (UIDR-014;
> Phase 3 UI shipped — see the decisions log). The Phase-4 residuals in
> this section (pursuit×track dedup, gap handoff, "grab future",
> per-unit tracked subtraction) are re-homed to
> [`release-tracking-plan-convergence.md`](release-tracking-plan-convergence.md)
> / ADR-056. Treat the rest of this section as a historical snapshot.

**Where things stand.** Sixteen-ish commits on `main`, `947c7bd4..e9b63dcf`,
**unpushed** (push when the user says so; release-tagging is reasonable —
5 release-safe migrations pending, all additive or expand/contract,
backfill dry-run-verified against a prod-DB copy). `mix precommit` green
at every commit (4,671 tests at the last gate). Per ADR-042, **reconcile
this file against `git log` before any new work.**

**The very next step is a UI design session WITH the user** — explicitly
reserved decisions, do not build first:

1. **Downloads-page restructure** — media search as the primary door;
   where the naked search's standalone entry lives. Everything else
   hangs off this.
2. **Targeting picker** — TMDB search → series view; season rows w/
   tri-state checkboxes + episode drill-in; have/aired counts; quick
   actions (*Everything aired* = `Targeting.default_units/1`, *Continue
   from where my library ends*, *Latest season*); quality override +
   "grab future" opt-in (field already on the plan).
3. **Coverage board + activity feed** — render over
   `PlanEvents.Changed` / `PlanEvents.SearchActivity` (already
   broadcast on `acquisition:updates`); plan rows are the state of
   record so the board is just a re-read. The existing `UnitBoard`
   component is the embryo (pursuit-side); the plan board is its
   sibling surface.
4. **Approval screen** — assignments grouped by release (consolidation
   visible), gaps listed, approve/discard; Phase 4's gap-handoff
   affordance lands here too.

Load `user-interface` + `storybook` skills first; `track_modal.ex` is
the TMDB-search UI to mirror for the picker.

**Backend API the UI consumes (all tested):**
`Targeting.series_selection/1` + `default_units/1` →
`Plans.create_series_plan/3` / `create_movie_plan/2` (inline RunPlan
solves; plan lands `ready`) → reads via `Plans.get/1`, `units_for/1`,
`list_drafts/0` → feedback `Plans.exclude_release/2`, `exclude_unit/1`,
`replan/2 (force_search:)` → `Plans.approve/1` (→ `{:error,
{:overlap, units}}` | `{:error, :nothing_to_grab}` possible) /
`Plans.discard/1`.

**Known residuals / deferred (each deliberate, none blocking):**
* Multi-unit tmdb satisfaction matching: reconciler/inbound rely on
  content-path + release-name per target; add per-unit tmdb-identity
  matching when multi-unit tmdb pursuits are common (risk #6 note).
* Pursuit×track dedup + gap handoff + "grab future" = Phase 4 (the
  approval screen is their surface).
* Targeting marks tracked-ness series-level only (per-unit tracked
  subtraction folds into Phase 4 dedup).
* `Units.lead_of/1` interim on pursuit-scoped surfaces (decision card,
  pursuit-level change-target) — fine while the UnitBoard carries
  per-unit affordances; revisit with the plan board.
* `Units.single!/1` tripwire: raises on multi-unit pursuits at call
  sites that still need unit-scoped args (`Arm` is legitimately
  single-unit). Don't swallow raises — grow `unit_id` args.
* Wiki update — ✅ DONE 2026-06-10 (wiki commit `9fc15a4`): new
  `Searching-and-Downloading` page covers the omnibox, plans,
  pursuits, and both handoffs.
* TMDB collections; per-search quality-pref UI (plan.criteria accepts
  min/max already — falls back to AutoGrabSettings).

**Gotchas rediscovered this build (cost time once already):**
* `"acquired"` is terminal-**success** in `TargetStatus` — pivots
  don't fail acquired targets.
* ~~The worker's 4K-patience window elevates young pursuits' quality
  floor (test fixtures need `:uhd_4k`)~~ — the window was deleted in
  the convergence Phase 4 sweep; the planner deliberately has NO
  patience (best-available-now; patience is plan-time floor
  elevation).
* Prowlarr grabs POST to `/api/v1/search` — stubs must discriminate by
  method.
* LV tests that fire a command then assert on the DB must settle with
  `_ = render(view)` first (broadcast-triggered handle_info races
  teardown otherwise).
* `ReleaseTracking.Item.media_type` is the enum `:movie | :tv_series`
  (not `"tv"`).
* `TmdbStubs.stub_routes/1` matches by path substring — season routes
  before the bare `/tv/<id>` route.

## Pointers

* **Plans / planner / targeting (new, Phase 3 spine)** — `acquisition/plans.ex` (context + feedback verbs), `plans/plan.ex` + `plans/plan_unit.ex` (durable draft), `plans/commit_plan.ex` (approval gate + overlap check), `jobs/run_plan.ex` (ladder runner), `acquisition/planner.ex` (pure optimizer), `acquisition/targeting.ex` (TMDB → unit universe), `acquisition/plan_events.ex` (board/feed broadcasts).
* **Corpus (new, Phase 1)** — `acquisition/corpus.ex` (consult-first `search/2`, `record!/3`, `prune_stale!/0`), `corpus/search_record.ex`, `corpus/candidate.ex`.
* **Pack machinery (new, Phase 2)** — `search/release_coverage.ex` (classify + accounting primitives), `TitleMatcher.coverage/2`.
* **Composite core (new, ADR-055)** — `acquisition/pursuits/unit.ex` (thread carrier; now with season/episode), `units.ex` (read side; `lead_of/1`, `single!/1`, `covered_by/1`), `target_unit.ex` (coverage join), `unit_state.ex`, `commands/refold.ex` (parent fold), `Acquisition.pick_targets/2` + `commands/start_from_pick.ex` (batch collapse), `Recipe.for_unit/2` (unit-scoped search).
* **Composite UI (Phase 1)** — `components/acquisition/unit_board.ex` (+ story), unit-progress chip in `pursuit_row.ex`, `Pursuits.unit_board_for/1`.
* **Acquisition** — `lib/media_centaur/acquisition.ex` (facade, `enqueue`), `acquisition/pursuits/pursuit.ex` (the composite parent), `acquisition/target.ex` (grab attempt), `acquisition/reactor.ex` + `reactor/handlers.ex` (release-ready → pursuit), `acquisition/auto_grab_policy.ex`, `acquisition/auto_grab_settings.ex`.
* **Search** — `lib/media_centaur/search/prowlarr.ex` (search/grab API; note the `POST /api/v1/search` grab gotcha), `search/search_result.ex`. Release-title parsing: `MediaCentaur.Parser` + `TitleMatcher` (the S/E-only validator to extend for packs).
* **TMDB** — `lib/media_centaur/tmdb/client.ex` (`search_movie`, `search_tv`, `get_tv`, `get_movie`, `get_collection`) + `Mapper`.
* **Release tracking** (the forward-monitor sibling + handoff target) — `lib/media_centaur/release_tracking.ex`, `release_tracking/item.ex`, `release_tracking/refresher.ex`, `components/track_modal.ex` (TMDB search UI to mirror for the select phase).
* **Existing acquisition UI** — `lib/media_centaur/acquisition_live.ex`, `lib/media_centaur_web/live/acquisition_live/search.ex` (the file-search page to adapt).
* [ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md) — campaign convention.
* A scratch visual model of the design exists at `~/.agent/diagrams/media-search-architecture.html` — **partially superseded** (it draws an unfound "re-resolving" leaf, which the search-vs-pursuit decision later removed). Treat as a session artifact, not the spec; this file is the spec.
