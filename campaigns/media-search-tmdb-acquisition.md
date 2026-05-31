---
status: planning
started: 2026-05-31
last_updated: 2026-05-31
---
# Media search (TMDB-first acquisition)

## Goal

Add a **second acquisition entry point** alongside today's file search.
Today you acquire by typing a release-name query, searching indexers, and
grabbing a file ("file search"). Media search inverts that: you start from
**what you want to watch** — a TMDB title — pick the seasons/episodes you
want, and Media Centaur autonomously figures out *how* to satisfy that from
what's currently available across indexers (complete-series packs, season
packs, per-episode releases), shows you the resulting **plan**, lets you
steer it, and only then executes it as a single rich pursuit.

The deeper goal is a **unified pursuit model**. Both searches route through
one composite-pursuit core; file search is adapted onto it (gaining the new
model + UI) and media search layers TMDB-specific enrichments on top. We are
not building a second parallel acquisition system.

**North star:** the automation exists so the *user's preference can win*
while the complexity stays hidden. Settings, asking, and plan-time override
are all legitimate — the bar is "best experience, complexity concealed," not
"fewest knobs."

## The model

Settled across the 2026-05-31 design session. Resumable context — read this
before writing code.

**Four phases (media search):**
1. **Select** — spec builder: TMDB title → series / seasons / episodes,
   quality prefs, and a "grab future releases too?" opt-in. A UI surface in
   its own right.
2. **Search & Plan** — an autonomous, **visualized** process that searches
   (politely) and solves a coverage plan over what's available *now*.
3. **Plan feedback** — the user steers: swap a chosen release, force a
   re-search, approve. Loops back into planning. Nothing grabs until approval.
4. **Pursuit** — the approved plan executes as **one composite pursuit**.

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
the whole request (parent with overall progress) → many leaf attempts (the
per-unit grabs). No separate aggregate. Today's per-attempt intervention
becomes the leaf-level interaction, reused.

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

## Next steps

Phased rollout, sequenced to de-risk: each phase ships a real improvement
without depending on the harder logic that follows. Each phase must not break
the seven risks below.

1. **Pursuit core + migrate file search onto it.** Grow `Pursuit` into a
   composite (parent + leaves); collapse brace-expanded `prowlarr_query`
   grabs into one pursuit; build the parent/leaf progress + drill-down +
   intervention UI; wire the search corpus + living-intent re-resolution.
   No TMDB, no planner. Proves the core on the simplest, already-working
   case. **Write the composite-pursuit ADR here.**
2. **Pack strategy + coverage ladder.** The matcher work (`TitleMatcher`
   recognizing complete-series / season packs, not just one S/E) and the
   pack→episode **accounting** (one pack download satisfies many wanted
   units; partial packs; dedup against library and within the corpus).
3. **Media-search front door.** TMDB selection UI (series / season /
   episode), the autonomous planner driving the ladder, live plan
   visualization, and plan feedback (swap release / force re-search /
   approve). Rich TMDB card on the pursuit.
4. **Release-tracking handoff + polish.** "Grab future" opt-in → on-completion
   spin-up of a release-tracking entry; dedup so a media-search pursuit and an
   existing track don't double-grab; freshness-policy tuning.

## Risk surface

Seven independent ways to ship something subtly broken — guardrails for every
phase. `(exists)` = works today, `(extends)` = grows existing code,
`(net-new)` = new mechanism.

1. **Pack → episode accounting** *(net-new)* — one pack satisfies many units; partial packs are the normal case. Wrong → re-grab what we have, or "done" with holes.
2. **Ladder redundancy within the current corpus** *(net-new, reduced)* — don't grab the pack *and* singles for the same episodes. Now a pure dedup problem (no timers, per the best-available-now decision).
3. **Fuzzy pack detection** *(extends)* — `S01-S05`, `Complete`, `Season.2`, `S02.COMPLETE`. `TitleMatcher` validates one S/E today; false-positives grab wrong, false-negatives never fall back.
4. **Overlap with release tracking** *(extends)* — "whole series" media-search + an existing track = double pursuits. `find_by_tmdb_recipe` dedup only knows per-episode recipes.
5. **Per-episode model strain** *(extends)* — `TitleMatcher`, `AutoGrabPolicy`, `PursueTarget`, the reactor all assume one target = one episode.
6. **Composite-pursuit lifecycle** *(net-new)* — parent/child progress, "X of N / partial / cancelled" semantics, reconciliation against what's already on disk.
7. **(retired)** — interacting patience timers; dissolved by the best-available-now / no-upgrades decision. Left numbered so the risk list maps to the design discussion.

## Completion criteria

* A user can search TMDB, pick at any granularity (series / season / episode), review an auto-generated coverage plan, steer it, and submit — landing one composite pursuit that grabs the planned releases.
* File search produces the *same* composite-pursuit shape (one pursuit per brace-expanded query) with the new progress / drill-down / intervention UI — no parallel pursuit system remains.
* The planner honors the objective hierarchy and the automatic ladder; pack downloads correctly satisfy their covered episodes (no re-grabs, no false "done").
* Unfound units are reported at plan time, never as perpetually-seeking pursuit leaves.
* "Grab future" opt-in creates a release-tracking entry on completion, with no double-grabbing against existing tracks.
* Wiki updated (new acquisition flow + the file-search/media-search distinction).

## Pointers

* **Acquisition** — `lib/media_centaur/acquisition.ex` (facade, `enqueue`), `acquisition/pursuits/pursuit.ex` (the aggregate to grow), `acquisition/target.ex` (grab attempt), `acquisition/reactor.ex` + `reactor/handlers.ex` (release-ready → pursuit), `acquisition/auto_grab_policy.ex`, `acquisition/auto_grab_settings.ex`.
* **Search** — `lib/media_centaur/search/prowlarr.ex` (search/grab API; note the `POST /api/v1/search` grab gotcha), `search/search_result.ex`. Release-title parsing: `MediaCentaur.Parser` + `TitleMatcher` (the S/E-only validator to extend for packs).
* **TMDB** — `lib/media_centaur/tmdb/client.ex` (`search_movie`, `search_tv`, `get_tv`, `get_movie`, `get_collection`) + `Mapper`.
* **Release tracking** (the forward-monitor sibling + handoff target) — `lib/media_centaur/release_tracking.ex`, `release_tracking/item.ex`, `release_tracking/refresher.ex`, `components/track_modal.ex` (TMDB search UI to mirror for the select phase).
* **Existing acquisition UI** — `lib/media_centaur/acquisition_live.ex`, `lib/media_centaur_web/live/acquisition_live/search.ex` (the file-search page to adapt).
* [ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md) — campaign convention.
* A scratch visual model of the design exists at `~/.agent/diagrams/media-search-architecture.html` — **partially superseded** (it draws an unfound "re-resolving" leaf, which the search-vs-pursuit decision later removed). Treat as a session artifact, not the spec; this file is the spec.
