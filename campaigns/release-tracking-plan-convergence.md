---
status: design complete (ADR-056 accepted; all 9 Phase-0 questions settled; NEXT = Phase 1 want ledger)
started: 2026-06-10
last_updated: 2026-06-10
---
# Release tracking → plan-based pursuits (convergence)

## Goal

Make release tracking emit the **same kind of pursuit media search does**.
Today a tracked release that airs becomes a legacy single-unit pursuit via
the Reactor → `Arm` path: an open-ended seeker whose worker re-searches
indexers until something appears, with no planner, no pack consolidation,
plain cards, and ADR-039 key-equality dedup. This campaign routes release
tracking's materialization through the corpus → planner → durable plan →
composite pursuit core built by the media-search campaign — one
acquisition machinery, two intents (now vs. time) — and then retires the
open-ended seeker.

**Coherence principle (the one-sentence spec):** a track is a *standing
targeting intent*; every materialization of that intent runs through the
same corpus → planner → plan machinery; every grab is a plan-provenance
composite pursuit. "Waiting for something to appear" is release
tracking's job (a search act on a cadence), never a pursuit's.

## Status

Design COMPLETE 2026-06-10 (ADR-056, all nine Phase-0 questions);
**Phase 1 SHIPPED 2026-06-10** (commit `1cb4e0a5`, unpushed) — the want
ledger is live and dark: every seam syncs it, nothing consumes it yet.
Subsumes media-search campaign Phase 4. Next: Phase 2 — the drop→plan
pipeline + cutover.

## The model

**Why B (per-drop plans), decided over two alternatives:**

* **A — per-event, modernized in place** (keep one pursuit per aired
  episode; add identity + overlap dedup): cheapest, and the strict
  `matches?/2` worker can never mis-grab a pack — but it leaves the
  open-ended seeker alive forever (two answers to "who waits?"), keeps
  `prefer_season_packs` dead (the worker is *forbidden* from pack
  decisions by design), turns a season drop into ten pursuits, and means
  Phase-4 handoffs feed tracks whose output is the legacy machinery.
* **C — one rolling pursuit per tracked title**: maximal card coherence
  but breaks ADR-055's bounded lifecycle (the pursuit never terminates;
  the fold's terminal states stop meaning anything). Per-title rollup
  belongs in tracking-page presentation, not the pursuit model.
* **B — per-drop plans (chosen)**: each cadence tick batches a title's
  newly-ready wants into a **plan**; RunPlan solves it through the
  corpus/ladder; auto-grab policy decides auto-approve vs.
  awaiting-approval; found units → one composite pursuit per drop;
  unfound units stay **wants on the track** and re-plan on cadence.
  Weekly shows emit small bounded single-unit pursuits (fine); batch
  drops consolidate into packs; every grab gets plan provenance, the
  TMDB identity card, and the board/intervention vocabulary.

**The keystone: a per-unit want ledger on the track.** The item's
`last_library_season/episode` watermarks + wholesale-replaced `releases`
rows can't carry this. The track needs durable per-unit wants
(wanted / claimed-by-plan-or-pursuit / satisfied / dismissed) with
provenance (calendar-derived vs. gap-handoff) and `first_wanted_at`
(patience + back-off anchor). The ledger is what makes the gap handoff,
per-unit pursuit×track dedup, per-unit targeting subtraction, and
aired-but-unfound retries all fall out of one structure.

**Patience moves from the worker loop into plan criteria.** The planner
stays best-available-now (no patience — campaign invariant); instead, a
want inside its patience window (from `wanted_since`) has its quality
floor elevated to the ceiling (`min := max`) when criteria are built, so
nothing below target is ever assigned while patience holds — and every
solved plan is commit-clean. *(Q4 superseded the earlier "commit gate"
framing: a post-solve gate forces partial-commit rules and a pack
ALL/ANY dilemma that criteria elevation dissolves.)*

**The search-vs-pursuit boundary finally holds everywhere.** An aired
episode with nothing on indexers is an **open want visible on the
tracking surface** ("watching for S03E05") — not a seeking pursuit on
Downloads. A pursuit comes into existence only when there's something
concrete to grab. Re-discovery is a release-tracking search act, gated
by the corpus freshness policy plus a back-off schedule for stale wants.

**What retires when this lands:** the Reactor → `AutoGrabPolicy` →
`Arm` per-event path, `ArmAll` (`enqueue_all_pending_for_item`), the
worker's open-ended re-search + 4K-patience window for auto pursuits,
and `find_by_tmdb_recipe` key-equality dedup. The naked-search `Arm`
path (query door) stays — it's the fast path, not a seeker.

## Use-case inventory

The circumstances the design must cover. Each maps to a phase below;
none may regress silently.

**Materialization triggers**
1. *Weekly airing* (steady state) — sweep marks a release available →
   one single-unit drop plan. Ceremony is cheap; provenance is the point.
2. *Multi-episode drop* (streaming full season; finale + back-catalog) —
   one plan over N units → pack consolidation; `prefer_season_packs`
   becomes a live planner preference instead of a dead field.
3. *New track with aired backlog* (manual track mid-season; auto-tracked
   new library series) — initial backfill plan replaces
   `enqueue_all_pending_for_item`'s N individual pursuits.
4. *Movie release* — single-unit drop when the movie becomes available.
5. *Movie collection* (`/collection` fallback in the refresher) — a new
   film in the collection is one new want/unit.

**Time & quality**
6. *Airs but nothing on indexers yet* (the common case — availability
   lags air time by hours/days) — plan finds nothing → **no pursuit**;
   want stays open; re-plan on cadence through the corpus.
7. *4K patience* — best find below the quality ceiling → commit gate
   defers (re-plans may find better) until patience expires, then
   settles. Must reach parity with the worker's current window.
8. *Quality floor unmet* — nothing ≥ `min_quality` → same as unfound.
9. *Stale wants* — a want unfound for weeks must not search every sweep;
   decaying re-search cadence (back-off) on top of corpus freshness.

**Modes & dials**
10. *Auto-grab modes* — `off` / `global` / `all_releases`, plus the new
    possibility: an **ask** posture where drop plans land
    awaiting-approval with the full plan board to steer. Conservative
    dial worth considering: auto-approve single-episode assignments,
    ask when the planner wants a pack.
11. *Mode flipped off mid-flight* — pending drop plan discarded;
    in-flight pursuit cancelled (today's `{:cancel, :user_disabled}`).
12. *Prowlarr unavailable* — capability gate: wants accumulate, no plans
    run; the next healthy cadence plans the backlog. Nothing is lost.

**Satisfaction & dedup**
13. *Unit arrives by another path* (watcher import, naked-search grab,
    manual download) — want satisfied; pending plan re-solved or
    discarded for that unit; generalizes `release.in_library` and
    `complete_movie_tracking_for/1`.
14. *Media search on a tracked show* — targeting subtracts tracked wants
    **per unit** (shown grayed, not silent — closes the series-level-flag
    residual); `CommitPlan` overlap check rejects double-claims in both
    directions (track-born plans must respect active pursuits and vice
    versa). One enforcement point.
15. *Gap handoff at approval* — media-search unfound units become track
    wants with `gap` provenance. Note: these are *already-aired* units —
    the ledger must support arbitrary wants, not just calendar-derived.
16. *"Grab future" opt-in* — on pursuit completion, create/extend a
    track. Both handoffs only make sense once the track emits
    plan-provenance pursuits — which is why this campaign subsumes
    media-search Phase 4.

**Lifecycle & churn**
17. *TMDB schedule churn* — episode rescheduled or removed from schedule
    (differ events; see the one-time `:removed_from_schedule` sweep
    history) — unaired wants follow the calendar; removal drops the
    want without churning events.
18. *Dismissals* — `dismiss_released_before`, item `:ignored` → wants
    dismissed wholesale, pending drop plans discarded.
19. *Track deleted/ignored with a drop pursuit in flight* — drafts
    discarded; the committed pursuit is user-visible work and keeps
    running (user can cancel it on Downloads).
20. *Failed drop pursuit* — leaf alternatives exhausted → pursuit
    reports failure (existing semantics). Does the want re-open for the
    next cadence or hold for user intervention? Must avoid a
    grab-fail-regrab loop. (Phase 0 question.)
21. *Restart mid-anything* — wants are durable rows; plans are durable
    drafts; pursuits already survive restarts. No in-memory state.
22. *Cutover* — in-flight legacy auto pursuits (seeking, snoozed) at
    upgrade time: convert to open wants, or drain under the old worker?
    Either way no unit may be double-claimed during the transition.

## Design questions — ALL SETTLED 2026-06-10

Full detail in the decisions log below; one-line index:

1. **Want ledger** → new `release_tracking_wants` table; calendar table
   untouched; claims derived in Acquisition, never stored.
2. **Batching** → state-not-delta per tick per title; one active draft
   per title; due-ness gates searches, plans cover everything open.
3. **Modes** → `off / ask / auto`; `auto` stays default; packs
   auto-commit; ask reuses the draft/plan-modal surfaces.
4. **Patience** → plan-time quality-floor elevation (`min := max`
   inside the window), NOT a commit gate; anchor `wanted_since`.
5. **Failure** → organic failure re-plans politely (tried-and-failed
   planner exclusion breaks the loop); user cancel dismisses wants.
6. **Back-off** → stepped by age (tick / 4h / daily / weekly-forever),
   corpus-floored; patience expiry forces due; `last_searched_at`.
7. **Visibility** → Tracking = waiting (ledger-driven decoration),
   Downloads = acquiring (count + link only for open wants).
8. **Cutover** → derived claims do the heavy lifting; system-cancel
   seekers w/o dismissal; `wanted_since` = air date in backfill.
9. **Retirement** → full kill-list confirmed; worker re-search loop
   stays (query door + degradation), worker patience window dies.

Bonus settled: **quality upgrades deferred** to a future campaign;
`satisfied_quality` recorded now as the hook.

## Decisions made

Append-only log.

* `2026-06-10` — **Option B: per-drop plans.** Release tracking batches
  newly-ready wants per title into a plan; corpus/planner solve it; the
  drop commits as one composite pursuit. Chosen over per-event
  modernization (A — keeps the open-ended seeker and dead pack prefs)
  and a rolling per-title pursuit (C — breaks ADR-055's bounded
  lifecycle). Design discussion, this session.
* `2026-06-10` — **Coherence principle**: track = standing targeting
  intent; materialization always via corpus → planner → plan; every grab
  is a plan-provenance composite pursuit; waiting belongs to release
  tracking, never to a pursuit.
* `2026-06-10` — **Patience becomes a commit gate** owned by release
  tracking (planner stays best-available-now per the media-search
  campaign invariant).
* `2026-06-10` — **Per-unit want ledger is the keystone schema** —
  prerequisite for handoffs, per-unit dedup, and targeting subtraction.
* `2026-06-10` — **This campaign subsumes media-search Phase 4**
  (grab-future handoff, gap handoff, pursuit×track dedup, per-unit
  tracked subtraction). The media-search campaign file points here.
* `2026-06-10` — **Q1 settled: `release_tracking_wants` is a new
  RT-owned table; the releases table stays the wholesale-replaced
  calendar.** Want = acquirable intent (opens at aired-and-not-in-library;
  pre-air schedule never enters the ledger). Statuses `open | satisfied |
  dismissed` only — **claim state is derived in Acquisition** from active
  plan/pursuit units (no dual-write; CommitPlan stays the one enforcement
  point; failed pursuits release their claim and the still-open want
  re-plans). Provenance `calendar | gap`; `wanted_since` anchors
  patience/back-off. Movies collapse to one want per film opening at the
  earliest released date (quality floor keeps cams out); collection parts
  carry `part_tmdb_id` (extractor must stop discarding it). Boundary deps
  unchanged: RT owns wants + library-arrival satisfaction; Acquisition
  reads open wants. Backfill: released && !in_library && !dismissed
  calendar rows.
* `2026-06-10` — **Q2 settled: batch = state, not delta.** Per tick, per
  title: wants that are open ∧ unclaimed ∧ search-due → one drop plan.
  No newly-ready bookkeeping — everything re-derives from open-want
  state (self-healing; backlog and weekly are the same path). Search-due
  (Q6 back-off) gates *searches*; the assignment may opportunistically
  cover any open unclaimed want from the fresh corpus ("search for
  what's due; plan over everything open"). At most one active RT-born
  draft per title — wants opening mid-draft wait for the next tick
  (never mutate a plan under review; costs seconds in auto mode). Tick
  mechanism (sweep-triggered vs. periodic job + fast paths) is Phase 2
  implementation detail. *(User sign-off was lukewarm — flag for
  re-examination if the opportunistic-coverage refinement complicates
  the planner.)*
* `2026-06-10` — **Q3 settled: modes `off / ask / auto`**, same
  global-default + per-item `"global"` inheritance as today;
  `all_releases` maps to `auto` and **stays the shipped default**
  (automation is the persona's point; ask-by-default = weekly homework).
  `ask` lands drop plans as ready drafts — zero new UI (reuses
  media-search draft cards + plan modal + feedback verbs). **Packs
  auto-commit in auto mode** — no `ask_on_packs` dial in v1 (YAGNI;
  conservative classification + quality floor + inspectable plan
  provenance are the guards; add the boolean later if reality bites).
  Per-item fields map: min/max_quality → plan criteria,
  4k_patience_hours → Q4, prefer_season_packs → planner consolidation
  weight. Parked ask-drafts never expire (visible nag; stale approval
  degrades via existing CommitPlan machinery). Targeting subtraction
  grays tracked wants only when effective mode grabs (`ask`/`auto`) —
  mode `off` means media search is the expected path.
* `2026-06-10` — **Q4 settled: patience = plan-time quality-floor
  elevation, not a commit gate** *(supersedes this campaign's earlier
  "commit gate" phrasing)*. A want inside its window (`now -
  wanted_since < patience_hours`, resolution per-item → global) gets
  `min := max` in plan criteria; aged wants use the normal floor.
  Nothing below a want's effective floor is ever assigned → every
  solved plan is commit-clean (CommitPlan unchanged, no partial-commit
  rules, no pack ALL/ANY dilemma — an under-quality pack simply can't
  cover young wants, and if grabbed for aged wants its files satisfy
  young wants by library arrival: best-available-now winning by side
  effect, documented not fought). Expiry = first due tick after the
  window (Q6 constraint: near-boundary back-off stays minutes-to-hour
  scale). Anchor is `wanted_since` — re-plans never reset the clock.
  Patience 0 or `max == min` → no elevation. Timing parity with the
  worker is tick-granular rather than continuous; accepted.
* `2026-06-10` — **Q5 settled: organic failure re-opens politely; user
  cancel dismisses.** Terminal pursuit → claim releases (derived, Q1) →
  want re-plans on cadence, with the loop-breaker: **planner excludes
  candidates matching terminally-failed targets for that unit**
  (query-time constraint over durable target rows — no new state; same
  flavor as plan-wide exclusions). Re-plans only assign genuinely new
  releases; nothing new → unfound, no pursuit, no grab-fail-regrab
  loop. User cancelling an RT-born pursuit or excluding a unit =
  "stop wanting this" → covered wants **dismissed** (+ event +
  un-dismiss) — unlike today, cancel sticks (the current policy re-arms
  cancelled grabs on later sweeps). Leaf-level swap stays steering, not
  cancelling. No `held` status; ledger keeps its three statuses.
* `2026-06-10` — **Q6 settled: stepped back-off by want age**, floored
  by corpus freshness: 0–48h every tick (~30–60 min effective);
  48h–7d every ~4h; 7–30d daily; 30d+ weekly **forever** (giving up is
  a user act — dismiss — never a timeout). Patience expiry forces
  search-due (floor drop obsoletes the unfound-at-4K negative
  knowledge). One explicit `last_searched_at` column on the want
  (derivation from corpus records rejected: term-shape fiddliness +
  14-day retention leakage). Q2's opportunistic coverage gives stale
  wants free re-checks whenever sibling wants are active.
* `2026-06-10` — **Quality upgrades (settle for 1080p fast, replace
  when 4K appears) acknowledged as release tracking's future job and
  DEFERRED to a future campaign.** The media-search campaign already
  assigned later-appearing-better-releases to RT; the want ledger
  accommodates it later as an `upgrade`-provenance want (eligible only
  above on-disk quality, slow back-off, replace-on-land) with zero
  changes to cadence/corpus/planner/claims. Out of scope here because
  of the downstream costs: file replacement in the library, watch-state
  continuity, seeding, quality-aware satisfaction. **One hook ships
  now: `satisfied_quality` recorded on the want at satisfaction time**
  — the only datum painful to backfill later. Patience and upgrades are
  alternative answers to the same gap; if upgrades land, low patience +
  upgrade wants reproduce the user's described behavior exactly.
* `2026-06-10` — **Q7 settled: Tracking = waiting, Downloads = acquiring.**
  The tracking page owns "watching for": the existing upcoming-zone
  acquisition-status decoration re-reads the want ledger (*aired —
  watching indexers* w/ age + next check, *planned*, *pursued* via
  claim check, *satisfied*) — truer than the perpetual "seeking" card
  it replaces. Downloads shows open wants as a **count + link only**
  (no want cards — that would rebuild the seeking-card lie and blur the
  search-vs-pursuit boundary). RT appears on Downloads exactly when
  acquisition begins: solving draft / ask-mode draft / committed
  pursuit — all existing surfaces, identity banners inherited.
* `2026-06-10` — **Q8 settled: cutover is mostly automatic via derived
  claims** (legacy units already carry identity → they claim wants from
  day one; no double-grab even with zero migration). Policy by status:
  actively-progressing (grabbed / awaiting-decision) → leave alone;
  seeking/snoozed → system-cancel with a new `superseded`-style reason
  that does **not** dismiss wants (Q5 cancel-dismisses applies only to
  user cancels post-cutover) → wants re-plan next tick; terminal
  (failed/cancelled) → wants open (matches today's re-arm behavior;
  Q5 exclusion guards failed releases). Backfill stamps:
  `wanted_since` = air date (no patience restart),
  `last_searched_at` = nil (one immediate first-tick check, then
  back-off). Idempotent migration, dry-run against prod copy.
* `2026-06-10` — **Q9 settled: kill-list confirmed** — Reactor +
  Handlers (release_ready → arm), `AutoGrabPolicy`, `ArmAll` /
  `enqueue_all_pending_for_item` (the bulk button becomes "plan now"),
  `find_by_tmdb_recipe`, the sweep's `release_ready` broadcast (the
  ledger is the signal). **The worker's re-search loop STAYS** (serves
  query-door pursuits + CommitPlan failed-grab degradation); **its
  patience window dies entirely** (RT patience moved to plan criteria
  per Q4; query-door grabs are user-picked releases, quality patience
  meaningless) — `quality_4k_patience_hours` becomes purely a
  want-ledger input; the `:uhd_4k` fixture gotcha evaporates.
* `2026-06-10` — **Phase 0 COMPLETE.**
  [ADR-056](../decisions/architecture/2026-06-10-056-release-tracking-wants.md)
  written and accepted — the repo-wide record of the model (want
  ledger, per-drop plans, derived claims, patience-as-criteria,
  cancel-dismisses, back-off, cutover, kill-list, deferred upgrades).

## Next steps

Phased; each phase ships a real improvement and must not regress the
use-case inventory.

0. ✅ **Design sessions** — COMPLETE 2026-06-10. All nine questions
   settled (one session);
   [ADR-056](../decisions/architecture/2026-06-10-056-release-tracking-wants.md)
   accepted (want ledger as the track side of ADR-055's overlap rule;
   supersedes the Reactor→Arm shape).
1. ✅ **Want ledger** — SHIPPED 2026-06-10 (commit `1cb4e0a5`, dark).
   `release_tracking_wants` + `Wants.sync_item/1` hooked at every seam
   (sweep, refresh commit, track-from-search, watermark updates,
   auto-track); satisfaction by real library presence (episode rows /
   tmdb-id-matched movies — never the watermark, so future gap wants
   can't falsely satisfy); `satisfied_quality` recorded off the
   playable chain (`PlayableItem` → `playable_file_path` →
   `Search.Quality.parse`); `part_tmdb_id` threaded extractor→helpers→
   calendar. **Build discoveries** (each deliberate):
   * **No backfill migration** — the sweep self-backfills the ledger on
     the first post-deploy tick (sync is idempotent, batch = state).
   * **Wants are never auto-dropped on calendar vanish** — collection
     refreshes drop *past* parts from the calendar and the TV fetch
     window moves forward, so set-difference dropping would kill live
     wants. Schedule-churn dismissal lands in Phase 2 as an explicit
     differ-event (`:removed_from_schedule`) hook instead.
   * **`dismiss_released_before` is vestigial** — schema column with no
     setter/reader anywhere in lib or web. The sync guard honors any
     existing data; `dismiss_wants_before/2` is the live API; decide in
     Phase 4 whether the column gets a UI or gets dropped.
   * Legacy collection rows without `part_tmdb_id` are skipped until
     the next refresh stamps them (≤6h window post-upgrade; residual).
   * RT boundary gained the `MediaCentaur.Search` dep (Quality).
   * Per-unit targeting subtraction NOT landed here — it consumes the
     ledger, so it ships with Phase 2/3 alongside mode-awareness (Q3).
2. ✅ **Drop → plan pipeline + cutover** — SHIPPED 2026-06-10 (commits
   `e8075bda` pipeline + `ef407eef` cutover). DropPlanner tick (driven
   by `{:tracking_sweep_completed}` → Reactor), `WantSchedule` (pure
   back-off + patience), per-unit floors as `plan_units.min_quality`
   with **solve-per-floor-group in RunPlan** (planner untouched;
   media-search plans take one pass exactly as before), `Plans.Claims`
   extraction (pursuit half = CommitPlan's check; + live-draft claims
   for the tick), plan `origin`/`tracking_item_id` provenance,
   tracking pursuits/targets land origin `auto`, mode gate in
   `Reactor.Handlers.plan_changed` (auto-approve / ask leaves ready /
   zero-found drafts are **deleted** not discarded — no churn rows),
   user-cancel-dismisses in `Commands.Cancel` (system cancels leave
   wants open), `SupersedeLegacySeekers` data migration (conservative
   per Q8), Upcoming bulk button → `plan_item_now` (ready draft,
   origin manual + tracking provenance, no floors, mode-gate-immune).
   **Build discoveries:**
   * **Differ-event want dismissal is unnecessary, not deferred** —
     wants only exist for aired units; aired-row calendar removals are
     collection parts aging out (must NOT dismiss). Schedule churn
     never touches the ledger. (Closes the Phase-1 deferral.)
   * Hot-window interval set to 30 min (= corpus freshness) rather
     than literal every-tick; zero-found drafts deleted to avoid
     plan-row churn while a fresh want retries.
   * Q2's opportunistic plan-over-everything-open refinement NOT
     implemented (due wants only) — per-unit ladder terms would search
     non-due wants' terms, violating due-gating; and the user was
     lukewarm on it. Revisit only if gap-coverage misses hurt.
   * Tried-and-failed exclusion (Q5 loop-breaker) shipped same-day
     (commit `bb1ac8a9`): drop plans seed unit exclusions from
     terminally-failed pursuit units' `tried_release_guids` — re-plans
     only assign genuinely new releases.
   * Mode-off mid-flight auto-cancel (Q11) deferred to Phase 4 (the
     legacy lazy-cancel died with release_ready; flipping off now only
     stops future planning).
   * The multi-unit tmdb satisfaction residual (media-search risk #6)
     still open — multi-unit tracking pursuits are now common; watch
     reconciler behavior during soak.
3. ✅ **Handoffs** — SHIPPED 2026-06-10 (commit `8a6b8137`).
   `TrackingHandoffs`: gap handoff live on the plan board's pre-built
   "Track these later" button (unfound units → gap-provenance wants;
   track created via supervised TMDB fetch when needed; idempotent);
   grab-future fires post-transaction in `Commands.Satisfy` strictly on
   `satisfied` (never `partial`). Targeting closes the per-unit
   residual: `Episode.tracked?` (open want ∧ mode grabs), picker
   "Tracked" tag, defaults/presets subtract tracked while units stay
   pickable (explicit override). User-initiated "plan now" drafts share
   the cancel-dismisses back-pointer (`tracking_item_id` regardless of
   origin). **Closes media-search campaign Phase 4.**
4. **Retirement + surfaces** — IN PROGRESS.
   * ✅ **`:watching` decoration** (commit `bf488b3e`) — risk #5
     closed: Upcoming tiles layer the want ledger under the
     pursuit-derived status (`with_want_fallback/3`; one resolver
     replaced four duplicated computations); `Wants.sync_item`
     broadcasts `releases_updated` only when the ledger actually
     changed. Open wants now read "watching" (eye icon) instead of
     nothing.
   * REMAINING, in order:
     1. Downloads page open-wants **count + link** to Tracking (Q7's
        second half).
     2. **`ask` mode in the auto-grab settings UI** — the per-item
        selector and the global default need the third option
        (validation + resolution already accept it; mode strings:
        `off | ask | all_releases`, label "all releases" as Auto).
     3. **Deletion sweep**: `Reactor`'s release_ready clause +
        `Handlers.release_ready` + `AutoGrabPolicy`, `ArmAll` +
        `Acquisition.enqueue_all_pending_for_item` +
        `list_pending_acquirable_releases_for_item` (RT), the sweep's
        per-release `release_ready` broadcast +
        `Refresher.broadcast_releases_ready/1`, the worker's
        4K-patience window (find it in PursueTarget/QualityWindow —
        query-door pursuits lose quality patience by design, Q9),
        `Pursuits.find_by_tmdb_recipe`. **Gotcha:**
        `Acquisition.statuses_for_releases/1` lives in `ArmAll` — move
        it to a read module (Targets/Pursuits) before deleting the
        command. Feature tests delete with their features (not
        ADR-027 classes).
     4. **Mode-off mid-flight** (Q11): flipping an item to `off` should
        cancel its active tracking pursuits + discard its drafts (the
        legacy lazy-cancel died with release_ready). Natural seam:
        `update_auto_grab` broadcast → Reactor, or a DropPlanner tick
        reconciliation pass.
     5. **Wiki sync** — auto-grab modes (incl. ask), the drop-plan
        flow, "plan now" replacing queue-all, the watching state,
        media-search pages (the expired carve-out from the sibling
        campaign).

## Risk surface

1. **Unattended planner grabs** — automation + pack decisions is new
   power; a misclassified pack auto-grabbed is the nightmare. Guards:
   conservative classification already shipped (media-search risk #3),
   plus the auto-approve dial (question 3) and plan provenance making
   every decision inspectable after the fact.
2. **Double-grab at cutover** — legacy in-flight pursuits + new wants
   claiming the same unit. Migration must reconcile before the pipeline
   arms (use case 22).
3. **Patience regression** — B must not settle for 1080p instantly where
   today's worker would have waited for 4K. Parity tests against the
   worker's current window semantics.
4. **Indexer thrash** — cadence re-planning across many tracks (most
   library series are auto-tracked) × stale wants. Corpus freshness +
   back-off schedule (question 6); the sweep is the only re-search clock.
5. **Visibility regression** — users currently see "seeking" cards on
   Downloads at air time. The waiting state must have an equally visible
   home before the seeker dies. *(Design settled by Q7 — tracking-page
   ledger decoration + Downloads count-and-link; risk now lives in
   shipping that surface before retirement, i.e. Phase 4 ordering.)*
6. **Want churn from TMDB schedule churn** — reschedules/removals must
   update wants idempotently, not generate event/want noise (the
   `:removed_from_schedule` history is the cautionary tale).
7. **Grab-fail-regrab loop** — failed pursuit units re-opening as wants
   could re-grab the same dead release forever. *(Design settled by Q5 —
   tried-and-failed targets are a query-time planner exclusion; risk now
   lives in the exclusion's release-identity matching being tight enough
   in practice.)*

## Completion criteria

* No auto-grab pursuit is ever minted outside plan provenance; the
  Reactor→Arm path, `ArmAll`, and the worker's auto-pursuit patience
  window are deleted.
* A multi-episode drop lands as **one** composite pursuit, consolidated
  to a pack when the planner judges it right; `prefer_season_packs` is
  honored (or formally replaced by planner preferences).
* An aired-but-unavailable episode is an open want on the tracking
  surface — never a seeking pursuit — and is grabbed within one cadence
  tick of a release appearing.
* 4K patience reaches behavioral parity as plan-time quality-floor
  elevation (covered by tests that encode today's worker semantics;
  timing parity is tick-granular per Q4).
* The ask posture works: a tracked drop can land as a steerable
  awaiting-approval plan.
* Gap handoff and "grab future" ship; no unit is ever claimed by two
  active pursuers (pursuit×pursuit or pursuit×track), enforced at
  `CommitPlan` in both directions.
* Media-search targeting subtracts tracked wants per unit (grayed, not
  silent).
* Media-search campaign Phase 4 is closed by reference to this campaign.
* Wiki updated (auto-grab modes, the new drop-plan flow, tracking
  semantics).

## Pointers

* [`media-search-tmdb-acquisition.md`](media-search-tmdb-acquisition.md) —
  the sibling campaign whose core (corpus, planner, plans, composite
  pursuits, overlap check) this campaign rides on; its "The model"
  section defines the vocabulary (unit / candidate / assignment / leaf).
* [ADR-055](../decisions/architecture/2026-06-09-055-composite-pursuits.md) —
  composite pursuits + the overlap rule this campaign extends to tracks.
* **Release tracking** — `release_tracking.ex` (context),
  `release_tracking/item.ex` (per-item auto-grab prefs incl. the dead
  `prefer_season_packs`), `refresher.ex` (refresh cycle + sweep — the
  cadence anchor; `sweep_now/0` broadcasts `release_ready` per sweep),
  `differ.ex` (schedule-churn events), `helpers.ex` (TMDB → releases).
* **Legacy auto path (to retire)** — `acquisition/reactor.ex` +
  `reactor/handlers.ex` (release_ready → decide → arm),
  `acquisition/auto_grab_policy.ex`, `auto_grab_settings.ex`,
  `Acquisition.enqueue/4` (`Arm`, origin `"auto"`),
  `enqueue_all_pending_for_item/1` (`ArmAll`),
  `Pursuits.find_by_tmdb_recipe/1` (ADR-039 key dedup).
* **Plan machinery (to ride on)** — `acquisition/plans.ex`,
  `plans/commit_plan.ex` (overlap check — the one enforcement point),
  `jobs/run_plan.ex`, `acquisition/planner.ex`, `acquisition/corpus.ex`,
  `acquisition/targeting.ex` (per-unit tracked subtraction lands here).
