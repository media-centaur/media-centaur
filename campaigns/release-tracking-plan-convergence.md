---
status: planning (direction settled — option B; Phase 0 design questions open)
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

Design direction settled 2026-06-10 (option B below). Phase 0 design
questions open — **do not write code before settling them with the
user.** Subsumes media-search campaign Phase 4 (handoffs + dedup).

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

**Patience moves from the worker loop to a commit gate.** The planner
stays best-available-now (no patience — campaign invariant). The *track*
owns time: re-plan on cadence; commit when the quality target is met or
the want's patience window (from `first_wanted_at`) expires. 4K patience
becomes a policy about *when to commit a plan*, not a quirk inside an
already-armed pursuit.

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

## Open design questions (Phase 0 — settle with the user first)

1. **Want-ledger schema** — new table keyed `(item, season, episode)` /
   movie-unit with status + provenance + `first_wanted_at`, vs. evolving
   `release_tracking_releases` (currently wholesale-replaced per refresh,
   so likely unsuitable as-is). Relationship to the watermark fields.
2. **Drop batching boundary** — one plan per title per cadence tick over
   all currently-open plannable wants? May a new want join a
   still-planning draft, or wait for the next tick? At most one active
   drop plan per title?
3. **Auto-approve dial** — full-auto vs. ask vs. auto-singles/ask-packs;
   how it maps onto the existing `auto_grab_mode` values and Settings.
4. **Patience commit-gate semantics** — exact rule, per-want anchor,
   interaction with quality floor and with "found some units at target,
   others below" mixed drops (commit partial now vs. hold the drop).
5. **Failed-want re-open policy** (use case 20).
6. **Re-search back-off schedule** for stale wants (use case 9), layered
   on the 30-min corpus freshness window.
7. **Where "watching for" lives in the UI** — tracking page owns the
   waiting state (coming-up zone is the natural surface); does Downloads
   show any trace of open wants, or only plans + pursuits?
8. **Cutover migration** for in-flight legacy auto pursuits (use case 22).
9. **Retirement scope** — confirm the full legacy kill-list and what the
   query door keeps (`Arm` stays for naked search; worker re-search
   scope after auto pursuits stop using it).

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

## Next steps

Phased; each phase ships a real improvement and must not regress the
use-case inventory.

0. **Design sessions** — settle the nine open questions above; write the
   ADR (release tracking as standing targeting + want ledger + commit
   gate; supersedes the Reactor→Arm shape and amends ADR-055's
   overlap-rule wording to name the want ledger as the track side).
1. **Want ledger** — schema + backfill (from releases/watermarks +
   in-library state) + satisfaction wiring (library arrivals close
   wants; schedule churn maintains calendar wants; dismissals). Ships
   dark: ledger shadows the existing path, no grab-behavior change.
   Per-unit targeting subtraction in media search can land here (read
   side of the ledger).
2. **Drop → plan pipeline** — cadence tick batches open wants per title
   → `Plans` draft → RunPlan → commit gate (patience + quality + mode)
   → auto-approve or awaiting-approval; unfound wants recycle; overlap
   check covers track-born plans both directions. Cutover: reactor stops
   arming; migration for in-flight legacy auto pursuits. The multi-unit
   tmdb satisfaction-matching residual (media-search risk #6 note)
   becomes due here — multi-unit tmdb pursuits are now common.
3. **Handoffs** — gap handoff at plan approval (unfound → gap-provenance
   wants); "grab future" opt-in → track on pursuit completion. Closes
   media-search Phase 4.
4. **Retirement + surfaces** — delete the legacy auto path
   (Reactor/Handlers arm, `AutoGrabPolicy`, `ArmAll`, worker patience
   window + auto re-search, `find_by_tmdb_recipe`); tracking-page
   "watching for" states; awaiting-approval drop-plan surface on
   Downloads; wiki sync (auto-grab behavior, modes, new flow).

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
   home before the seeker dies (question 7).
6. **Want churn from TMDB schedule churn** — reschedules/removals must
   update wants idempotently, not generate event/want noise (the
   `:removed_from_schedule` history is the cautionary tale).
7. **Grab-fail-regrab loop** — failed pursuit units re-opening as wants
   could re-grab the same dead release forever; exclusions/corpus
   knowledge must inform re-plans (question 5).

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
* 4K patience reaches behavioral parity as a commit gate (covered by
  tests that encode today's worker semantics).
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
