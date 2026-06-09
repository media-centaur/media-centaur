---
status: planning
started: 2026-05-31
last_updated: 2026-06-09
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

## Next steps

Phased rollout, sequenced to de-risk: each phase ships a real improvement
without depending on the harder logic that follows. Each phase must not break
the seven risks below.

1. **Pursuit core + migrate file search onto it.** Grow `Pursuit` into a
   composite (parent + leaves + covered units, per the Vocabulary —
   unit-based progress from day one); collapse brace-expanded
   `prowlarr_query` grabs into one pursuit; build the parent/leaf progress +
   drill-down + intervention UI; wire the search corpus + living-intent
   re-resolution. No TMDB, no planner. Proves the core on the simplest,
   already-working case. **Write the composite-pursuit ADR here** (includes
   the overlap-check identity rule).
2. **Pack strategy + coverage ladder.** The matcher work (`TitleMatcher`
   recognizing complete-series / season packs, not just one S/E) and the
   pack→episode **accounting** (one pack download satisfies many wanted
   units; partial packs; dedup against library and within the corpus).
3. **Media-search front door.** TMDB targeting UI (series / season /
   episode picker with library + tracked overlays and quick actions:
   *Everything aired*, *Continue from where my library ends*, *Latest
   season*), the autonomous planner driving the ladder, the **durable draft
   plan** + coverage board + activity feed, and plan feedback (swap release
   / force re-search / approve). Rich TMDB card on the pursuit. Settle the
   downloads-page restructure here: media search primary, naked search's
   standalone placement.
4. **Release-tracking handoffs + polish.** "Grab future" opt-in →
   on-completion spin-up of a release-tracking entry; **gap handoff at
   approval** (track the units planning couldn't find); dedup so a
   media-search pursuit and an existing track don't double-grab;
   freshness-policy tuning.

## Risk surface

Seven independent ways to ship something subtly broken — guardrails for every
phase. `(exists)` = works today, `(extends)` = grows existing code,
`(net-new)` = new mechanism.

1. **Pack → episode accounting** *(net-new)* — one pack satisfies many units; partial packs are the normal case. Wrong → re-grab what we have, or "done" with holes. *(2026-06-09: restated as a schema-level rule — leaves are per-release, progress is per-unit; see Vocabulary.)*
2. **Ladder redundancy within the current corpus** *(net-new, reduced)* — don't grab the pack *and* singles for the same episodes. Now a pure dedup problem (no timers, per the best-available-now decision).
3. **Fuzzy pack detection** *(extends)* — `S01-S05`, `Complete`, `Season.2`, `S02.COMPLETE`. `TitleMatcher` validates one S/E today; false-positives grab wrong, false-negatives never fall back.
4. **Overlap with release tracking** *(extends)* — "whole series" media-search + an existing track = double pursuits. `find_by_tmdb_recipe` dedup only knows per-episode recipes. *(2026-06-09: the composite-identity overlap check is the designated mechanism; gap handoff and "grab future" both depend on it.)*
5. **Per-episode model strain** *(extends)* — `TitleMatcher`, `AutoGrabPolicy`, `PursueTarget`, the reactor all assume one target = one episode.
6. **Composite-pursuit lifecycle** *(net-new)* — parent/child progress, "X of N / partial / cancelled" semantics, reconciliation against what's already on disk.
7. **(retired)** — interacting patience timers; dissolved by the best-available-now / no-upgrades decision. Left numbered so the risk list maps to the design discussion.

## Completion criteria

* A user can search TMDB, pick at any granularity (series / season / episode), review an auto-generated coverage plan, steer it, and submit — landing one composite pursuit that grabs the planned releases.
* File search produces the *same* composite-pursuit shape (one pursuit per brace-expanded query) with the new progress / drill-down / intervention UI — no parallel pursuit system remains.
* The planner honors the objective hierarchy and the automatic ladder; pack downloads correctly satisfy their covered episodes (no re-grabs, no false "done").
* Unfound units are reported at plan time, never as perpetually-seeking pursuit leaves.
* "Grab future" opt-in creates a release-tracking entry on completion, with no double-grabbing against existing tracks.
* Progress everywhere is unit-based (a failed pack leaf shows as its covered units missing, not one failed item).
* A browser refresh or app restart mid-planning loses nothing — the draft plan resumes from Downloads.
* Plan gaps offer the one-click release-tracking handoff at approval.
* No unit of a title is ever claimed by two active pursuers (pursuit×pursuit or pursuit×track) — enforced, not best-effort.
* Downloads page presents media search as the primary path; naked search has a settled secondary placement.
* Wiki updated (new acquisition flow + the media-search/naked-search distinction).

## Pointers

* **Acquisition** — `lib/media_centaur/acquisition.ex` (facade, `enqueue`), `acquisition/pursuits/pursuit.ex` (the aggregate to grow), `acquisition/target.ex` (grab attempt), `acquisition/reactor.ex` + `reactor/handlers.ex` (release-ready → pursuit), `acquisition/auto_grab_policy.ex`, `acquisition/auto_grab_settings.ex`.
* **Search** — `lib/media_centaur/search/prowlarr.ex` (search/grab API; note the `POST /api/v1/search` grab gotcha), `search/search_result.ex`. Release-title parsing: `MediaCentaur.Parser` + `TitleMatcher` (the S/E-only validator to extend for packs).
* **TMDB** — `lib/media_centaur/tmdb/client.ex` (`search_movie`, `search_tv`, `get_tv`, `get_movie`, `get_collection`) + `Mapper`.
* **Release tracking** (the forward-monitor sibling + handoff target) — `lib/media_centaur/release_tracking.ex`, `release_tracking/item.ex`, `release_tracking/refresher.ex`, `components/track_modal.ex` (TMDB search UI to mirror for the select phase).
* **Existing acquisition UI** — `lib/media_centaur/acquisition_live.ex`, `lib/media_centaur_web/live/acquisition_live/search.ex` (the file-search page to adapt).
* [ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md) — campaign convention.
* A scratch visual model of the design exists at `~/.agent/diagrams/media-search-architecture.html` — **partially superseded** (it draws an unfound "re-resolving" leaf, which the search-vs-pursuit decision later removed). Treat as a session artifact, not the spec; this file is the spec.
