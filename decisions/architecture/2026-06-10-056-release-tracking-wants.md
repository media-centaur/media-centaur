---
status: accepted
date: 2026-06-10
---
# Release-tracking wants — tracks emit plan-based pursuits

## Context and Problem Statement

Two acquisition philosophies run side by side. Media search
([ADR-055](2026-06-09-055-composite-pursuits.md), media-search campaign)
resolves a bounded selection through corpus → planner → durable plan →
composite pursuit, under the invariant *search discovers, pursuit
executes*. Release tracking still materializes through the legacy path:
each `release_ready` event arms one single-unit pursuit whose worker
re-searches indexers open-endedly, with a 4K-patience window elevating
its quality floor while young. Consequences:

* The **open-ended seeker** survives — a pursuit armed with zero known
  candidates, contradicting the search-vs-pursuit boundary, with its
  own re-search loop and rate behavior beside the corpus freshness
  policy.
* **No consolidation** — a full-season drop arms ten pursuits;
  `prefer_season_packs` is a dead field because the auto-grab worker is
  deliberately forbidden from pack decisions.
* **Dedup is key-equality** (`find_by_tmdb_recipe/1`), not ADR-055's
  overlap check; pursuit×track dedup has no mechanism at all.
* The media-search campaign's Phase-4 handoffs ("grab future", gap
  handoff) would create tracks that feed the legacy machinery.

The campaign assigned the roles: media search owns *best available
now*; release tracking owns *the passage of time*. Release tracking
doesn't act like it — time lives in the pursuit worker.

## Decision Outcome

**A track is a standing targeting intent.** Every materialization runs
through the same corpus → planner → plan machinery; every grab is a
plan-provenance composite pursuit; *waiting* belongs to release
tracking, never to a pursuit. Concretely:

### The want ledger

New RT-owned table `release_tracking_wants` — durable per-unit
acquisition intent. `release_tracking_releases` stays what it is: the
wholesale-replaced TMDB **calendar** projection.

* A want opens when a unit becomes **acquirable** (aired ∧ not in
  library); pre-air schedule never enters the ledger. Gap-handoff wants
  are created directly with `gap` provenance.
* Statuses: `open | satisfied | dismissed` — nothing else. **Claim
  state is derived in Acquisition** from active plan/pursuit units
  (unit-identity overlap, the ADR-055 check) — no dual-write, one
  enforcement point at `CommitPlan`. This is the concrete
  release-tracking side of ADR-055's "no two active pursuers" rule.
* Fields: unit identity (`season/episode`, or `part_tmdb_id`/title for
  movies and collection parts), `provenance` (`calendar | gap`),
  `wanted_since` (patience/back-off anchor), `last_searched_at`,
  `satisfied_at` + `satisfied_quality` (the one upgrades hook — see
  below), `dismissed_at`.
* Ownership/deps unchanged: RT owns wants and library-arrival
  satisfaction; Acquisition (already RT-dependent) reads open wants.
* Movies collapse to one want per film, opening at the earliest
  released date; the quality floor keeps theatrical-window junk out.

### Per-drop plans

Per cadence tick, per title: wants that are **open ∧ unclaimed ∧
search-due** → one drop plan, solved by the existing planner. Batch is
**state, not delta** — everything re-derives from open-want state, so
the pipeline is self-healing and the mid-season backlog case is the
weekly case with more wants. Search-due gates *searches*; the
assignment may opportunistically cover any open unclaimed want from the
fresh corpus. At most one active RT-born draft per title; wants opening
mid-draft wait one tick (a plan under review is never mutated).

### Modes

`off / ask / auto` (today's `all_releases` ↦ `auto`, which stays the
default; same global + per-item inheritance). `ask` lands drop plans as
ready drafts on the existing media-search draft/plan-modal surfaces —
zero new steering UI. Packs auto-commit in `auto` (no `ask_on_packs`
dial in v1).

### Patience = plan-time quality-floor elevation

Not a commit gate. A want inside its window (`now − wanted_since <
patience_hours`) gets `min := max` in plan criteria; aged wants use the
normal floor. Nothing below a want's effective floor is ever assigned,
so every solved plan is commit-clean — no partial-commit rules, no
pack ALL/ANY dilemma (an under-quality pack can't cover young wants;
if grabbed for aged ones, its landed files satisfy young wants by
library arrival — best-available-now winning by side effect). Expiry =
first due tick after the window; re-plans never reset `wanted_since`.

### Failure and cancellation

Terminal pursuit → claim releases → still-open want re-plans on
cadence. Loop-breaker: the planner **excludes candidates matching
terminally-failed targets for that unit** (query-time constraint over
durable target rows), so re-plans only assign genuinely new releases.
**User cancel dismisses the covered wants** (with event + un-dismiss);
organic failure never does. Leaf-level swap remains steering.

### Back-off

Stepped by want age, floored by corpus freshness: 0–48h every tick;
48h–7d ~4-hourly; 7–30d daily; 30d+ weekly **forever** — giving up is
a dismissal, never a timeout. Patience expiry forces search-due (the
floor drop obsoletes unfound-at-ceiling negative knowledge).

### Visibility

Tracking page owns the waiting state (upcoming-zone decoration reads
the ledger: *watching indexers* / planned / pursued / satisfied);
Downloads shows open wants as a count + link only. RT appears on
Downloads exactly when acquisition begins (draft, ask-draft, pursuit).
Mental model: **Tracking = waiting, Downloads = acquiring.**

### Cutover and retirement

Derived claims make migration mostly automatic (legacy units already
carry identity). Actively-progressing legacy pursuits run to
completion; seeking/snoozed ones are system-cancelled
(`superseded`, does **not** dismiss) and their wants re-plan; terminal
ones leave wants open (matches today's re-arm behavior). Backfill
stamps `wanted_since` = air date (no patience restart) and
`last_searched_at` = nil (one immediate check, then back-off). After
soak: delete Reactor/Handlers, `AutoGrabPolicy`, `ArmAll`,
`find_by_tmdb_recipe`, the sweep's `release_ready` broadcast, and the
worker's **patience window** (quality patience becomes purely a
want-ledger input). The worker's re-search loop itself stays — it
serves query-door pursuits and `CommitPlan`'s failed-grab degradation.

### Deferred: quality upgrades

"Settle for 1080p fast, replace when 4K appears" is acknowledged as
release tracking's future job and deferred to its own campaign (file
replacement, watch-state continuity, seeding, quality-aware
satisfaction). The ledger accommodates it later as an
`upgrade`-provenance want; `satisfied_quality` is recorded now because
it is the one datum painful to backfill.

### Rejected alternatives

* **Per-event modernization in place** (identity + overlap dedup on the
  existing per-episode arm path): keeps the open-ended seeker and dead
  pack prefs forever; a season drop stays ten pursuits; handoffs feed
  legacy machinery; consolidation would eventually rebuild the planner
  inside the reactor.
* **One rolling pursuit per tracked title**: breaks ADR-055's bounded
  lifecycle — the pursuit never terminates, the fold's terminal states
  stop meaning anything. Per-title rollup is presentation, not model.
* **Claim status stored on the want**: dual-write drift against
  plan/pursuit state; the overlap check already knows.
* **Patience as a post-solve commit gate**: forces partial-commit rules
  and a pack ALL-vs-ANY dilemma that criteria elevation dissolves.
* **Evolving `release_tracking_releases` into the ledger**: the table
  is a wholesale-replaced projection; mixing calendar and durable
  intent lifetimes in one table corrupts both (and gap wants fall
  outside the fetch window).

## Consequences

* Good, because one acquisition machinery remains: every grab —
  searched, planned, or tracked — is a plan-provenance composite
  pursuit with the same cards, board, and intervention vocabulary.
* Good, because the search-vs-pursuit boundary finally holds
  everywhere; the open-ended seeker and its patience quirks are
  deleted rather than maintained beside the corpus policy.
* Good, because tracked drops gain consolidation (a season drop is one
  pack grab) and `prefer_season_packs` becomes a real preference.
* Good, because the ledger gives the Phase-4 handoffs, per-unit
  targeting subtraction, and pursuit×track dedup one structure.
* Bad, because automation now exercises the planner unattended —
  guarded by conservative pack classification, quality floors,
  inspectable plan provenance, and the `ask` mode.
* Bad, because patience timing becomes tick-granular rather than
  continuous (bounded by the hot-window cadence; accepted).
* Neutral, because RT's waiting state moves from Downloads "seeking"
  cards to tracking-page want states — a truer presentation that must
  ship before the seeker dies (campaign risk #5).

Rollout, use-case inventory, and phase sequencing:
[campaigns/release-tracking-plan-convergence.md](../../campaigns/release-tracking-plan-convergence.md).
