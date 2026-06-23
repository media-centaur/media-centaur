---
status: planning
started: 2026-06-23
last_updated: 2026-06-23
---
# Artifact ↔ canon reconciliation engine

## Goal

Stop the system from **fabricating canonical structure to accommodate an
artifact's self-description.** A downloaded file labelled `S02E01` for a
show TMDB numbers as one 38-episode season currently mints a phantom
"Season 2" with blank episodes, while the canonical S01E29–38 slots show
empty — the *same content under two numbering schemes*, split into a real
view and an orphaned shell. The fix is to make the **mapping between
artifacts and the canonical episode spine a first-class, model-driven,
confidence-rated, human-arbitrable, revisable relation** — never a
side-effect of ingest, and never a reason to invent canon. Materialize
this engine for the **ingest** direction now; shape it so **acquisition**
(already shipped, hand-built) can converge onto it later.

## Status

Planning. Design settled through a long design conversation (2026-06-23,
session "downloading / matching cours"). No engine code yet. The
**acquisition direction already ships** as hand-built pieces in
[`cour-aware-acquisition.md`](cour-aware-acquisition.md) (v0.99.6) — those
are this engine in disguise and are the convergence target, not throwaway.

## Background — the worked example (Frieren, do not re-investigate)

*Frieren: Beyond Journey's End* (TMDB 209867). TMDB, with no episode
groups, lists it as **1 series, 1 season, 38 episodes** (absolute
numbering). The release world packages the third broadcast run (cour) as
its **own "Season 2"** (`S02E01–E09`, later E10).

Live data confirmed on the prod node + disk (2026-06-23):

- Library `TVSeries` "Frieren…" has **Season 1 (28 eps, full metadata)**
  and a phantom **Season 2 (9–10 eps, blank names)**.
- Disk (`/home/shawn/videos/media-library`) holds the third cour as loose
  files from **three different release groups** — `S02E01 - Shall We Go,
  Then`, `s02e02/03/04` (sensei, *no titles*), `S02E05 - Logistics…`,
  `S02E06` (UIndex), `S02E07 - The Divine Revolte`, `S02E08 - A
  Magnificent End`, `S02E09 - Himmel's Memoirs`.
- The detail view (TMDB-driven) correctly shows 38 episodes with E29–38
  missing — **that view is right, leave it.** The bug is the *separate*
  orphaned Season 2.
- Episode count: cour = 9 (now 10) → maps to absolute E29–38; the 38th is
  the most-recent episode. TMDB's 38 is the spine; the cour partial-fills
  the tail.

This is the **anime absolute-vs-seasonal numbering problem** the wider
ecosystem only solved with dedicated mapping databases (TheTVDB + XEM,
AniDB). We are TMDB-only, so we **cannot look up** the canonical mapping —
we can only infer it and have the user confirm. That constraint is *why*
human arbitration is a designed state here, not a failure path.

## The ideal design

### The core conflation (the original sin)

Ingest fuses three things that want to be separate layers: the **canonical
work** (TMDB's ordered episodes), the **artifacts** (files/releases named
in arbitrary schemes), and the **mapping** between them. Today the pipeline
collapses all three at ingest — parse, match by number, and *if numbering
disagrees, fabricate structure to force the artifact in.* That fabrication
is the root cause of every symptom (phantom seasons, blank episodes, the
wedged pursuit, cour-as-season).

### Three layers

1. **Spine** — the canonical episode list, from TMDB. The *only* source of
   structure. The library **never invents** a season/episode node.
   "Missing" = a spine node with nothing placed on it. (The detail view
   already lives here — that's why it's correct.)
2. **Artifact** — a file *or a release candidate*. Carries **claims**:
   `(season, episode)`, an `episode_title`, a range, an absolute number. A
   claim is **evidence, not truth** — `S02E01` is what the artifact *says
   about itself*, nothing more.
3. **Placement** — a reconciled link from an artifact to a spine node,
   carrying **provenance** (which model + what evidence), **confidence**,
   and **state**.

### The reconciliation engine

Pluggable **interpretation models**, each pure:
`propose(spine, current_placements, unplaced_artifacts) :: [candidate]`,
where a candidate is a proposed set of `artifact → spine_node` placements
with a confidence and a human-readable rationale. The engine collapses
agreeing candidates (corroboration → high confidence) and surfaces
disagreement (the conflict *is* the signal to the user).

**Initial models** (our discussed signals — none is the foundation; they
adjust confidence over the ordinal spine):

- **Gap-fill** — align the sorted unplaced artifacts onto the contiguous
  *missing* spine nodes, in order. The reliable floor; needs zero
  metadata. ("Fills the missing E29–38, in order.")
- **Title match** — map by `episode_title` where present (the Parser
  **already extracts `episode_title`** — no new parser work). Corroborates
  / catches off-by-one. Abstains when titles absent.
- **Absolute number** — when a name carries one.
- **Offset / cour** — release-season N starts after the prior
  release-season's episode count (or air-date run boundary). Fuzziest;
  lowest default confidence. The shipped `CourSegmentation` is one source
  of run boundaries for this model.

The release's own season/episode label is treated as **untrusted ordering
information only** — never as truth about which spine node an artifact is.

### Placement states (these *are* the UX)

- **auto** — one unambiguous interpretation → linked silently.
- **proposed** — ≥1 interpretation, awaiting choice → the review surface.
- **unplaced** — nothing proposed → fully manual assignment.
- **pinned** — user override; models may re-propose around it, never
  overturn it.

Placements are **derived and revisable** (project deriver model): a new
artifact re-runs reconciliation over the show; placements update — except
pinned ones. Nothing is baked at ingest; nothing fabricates canon.

### One engine, three call sites (the payoff / convergence target)

- **Ingest** — file-artifact claim → spine node. *(Build now.)*
- **Acquisition coverage** — a release candidate is an artifact whose claim
  is a *range*; "what does this pack actually contain?" vs. the spine is
  the **same operation**. The shipped `CoverageGuard`, `CourCoverage`,
  `CourSegmentation`, `Planner.Option.offer_only` are this engine,
  hand-built and scattered. *(Converge later.)*
- **Relink-on-move** — a moved file re-asserts a claim → re-placement.

Everything downstream reads only **spine + placements**, so it is
numbering-agnostic by construction:

- present/missing = placed vs. unplaced spine nodes,
- acquisition wants = aired spine nodes with no placement,
- **pursuit completion = wanted spine nodes now have placements** — the
  wedge bug dissolves, because completion stops depending on the release's
  numbering matching ours.

### Problem → how the design dissolves it

| Problem | Dissolved by |
|---|---|
| Phantom seasons | Canon never gains fabricated nodes; unplaceable artifacts stay `unplaced` |
| No single reliable signal | Plural models + confidence, not one matcher |
| Ambiguity needs a human | `proposed` is a designed state with shown provenance — confirmation is first-class |
| Extensibility | New model = new proposer; engine unchanged |
| Files arrive over time / piecemeal | Placements derived & revisable, recomputed as artifacts land |
| Cour acquisition (shipped) | Same engine, release-as-artifact-with-range claim |
| Wedged pursuits | Completion reads placements, not release numbering |

## Decisions made

* `2026-06-23` — **Reconciliation is a first-class relation**, not an ingest
  side-effect. Three layers (spine / artifact-with-claims / placement). The
  canonical spine is never fabricated to fit an artifact. (design conversation)
* `2026-06-23` — **Plural interpretation models + confidence**, no single
  matcher. Release season/episode labels are untrusted ordering hints;
  titles/absolute-numbers/gap-fill/offset are confidence-adjusting signals.
  Gap-fill is the reliable floor; title-match runs on the Parser's existing
  `episode_title`. (design conversation)
* `2026-06-23` — **Surfaced confirmation as standing UI philosophy** — prefer
  showing inferences for the user to confirm/redirect over silent automation;
  legibility + a redirect point. ([[feedback-prefer-surfaced-confirmations]])
* `2026-06-23` — **Review unit = the show (container); grouping = a model
  output the user chooses; partial-accept is the escape hatch.** No persisted
  "cluster" entity — grouping is emergent from the chosen interpretation, so we
  never ask the user to pre-declare the thing they're there to decide.
* `2026-06-23` — **Episode-mapping review is a second, distinct review
  dimension** from today's identity review (`Review.PendingFile` answers "which
  show?", per-file; this answers "which episode, given the show?", show-scoped).
  Don't shoehorn into `PendingFile`.
* `2026-06-23` — **Ingest trigger = case (a) only:** the parsed season is *not
  present in TMDB's season list* → divert the file (no phantom) to the mapping
  review. **Leave case (b)** — season valid but episode beyond TMDB's known
  count — on its current ingest-and-backfill path (often a legitimate
  aired-before-TMDB episode). Identity confidence is already settled upstream,
  so the mapping review can trust "the show is right."
* `2026-06-23` — **Build the engine for ingest now; leave acquisition on its
  shipped code; name everything (artifact, claim, spine node, placement, model,
  confidence) so converging the two later is a refactor, not a rewrite.** No
  universal engine up front (architecture-astronaut trap).
* `2026-06-23` — **No self-heal of the existing Frieren phantom** — owner
  re-downloads; the forward fix routes the new ingest through the mapping
  review. (owner)

## Next steps

Test-first throughout (`automated-testing`). Synthetic air dates / generic
placeholder titles in tests — no real titles (house rule). The Frieren data
above is prod runtime, exempt, reference only.

### Phase A — ingest reconciliation (build now)

1. **Vocabulary + spine read.** Define artifact / claim / spine-node /
   placement in code (likely under a new `MediaCentaur.Reconciliation`
   context — confirm boundary deps; it needs Library + TMDB-spine, and is
   read by the pipeline + a new Review surface). The spine for a show =
   TMDB's ordered episodes; "present" = library placements.
2. **Interpretation-model behaviour** + the initial models (gap-fill,
   title-match, absolute-number; offset/cour optional first cut). Pure,
   unit-tested with synthetic data. Engine that runs models, merges
   agreement, ranks/surfaces conflict, assigns confidence → placement
   states.
3. **Pipeline trigger.** In `Pipeline.Stages.FetchMetadata.build_tv`,
   detect case (a) — `parsed.season` not in the show's TMDB season list —
   and divert the file to the mapping review instead of
   `build_minimal_season`. Verify no phantom season is created. Decide the
   payload/route (new `{:needs_episode_mapping, …}` vs. extending the
   existing review-intake path).
4. **Show-scoped mapping review surface.** New review dimension: a show +
   its unplaced artifacts + candidate interpretations (pre-selected best,
   alternatives one click away — *pending decision, see open questions*),
   per-file override, partial-accept. Confirming writes placements
   (links files to the right TMDB episodes); does NOT fabricate seasons.
5. `mix precommit` green; commit per phase.

### Phase B — converge acquisition (follow-up, fresh session OK)

6. Re-express the shipped cour-acquisition pieces (`CoverageGuard`,
   `CourCoverage`, `CourSegmentation`, `offer_only`) as reconciliation
   models + confidence rules over the same spine/artifact/placement
   vocabulary. Release candidate = artifact with a range claim.
7. Make **pursuit completion read placements** (wanted spine nodes placed),
   not release-numbering coverage — retiring the class of wedge bug at the
   source.

### Phase C — relink-on-move convergence (later)

8. A moved file = an artifact re-asserting a claim → re-placement through
   the same engine. Fold [`relink-on-move`] thinking in if still open.

## Open questions (resume here in a fresh session)

* **Conflict presentation** — pre-select the best candidate with
  alternatives one click away (lean), vs. always show the ranked set? (UI
  philosophy says make alternatives visible; the question is default
  density.)
* **Confidence thresholds** — when does a placement go `auto` vs.
  `proposed`? Proposal: `auto` only when models agree *and* counts fit;
  everything else `proposed`. Needs concrete rule.
* **Context/boundary** — where does the engine live (`Reconciliation`
  context?) and what are its `Boundary` deps? It must stay pure where
  possible (models take an assembled context; the season fetch / library
  read is the impure caller, mirroring `Acquisition.Cours`).
* **Persistence** — placements that are `pinned` (user overrides) must
  persist; `auto`/derived placements may be recomputable. What's the
  durable record vs. the derived view? (Deriver model: persist the human
  decisions + the file links; re-derive proposals.)
* **Specials / season 0** — how do OVAs/specials (a distinct cluster under
  the same show) flow through? They're the canonical "permutation 2".

## Completion criteria

* A downloaded file whose parsed season isn't in TMDB's season list is
  **never** ingested as a phantom season; it lands in a show-scoped mapping
  review with candidate interpretations.
* The user can confirm/redirect a proposed mapping (with visible rationale)
  and partially accept; confirming links files to the correct canonical
  episodes without fabricating structure.
* Interpretation models are pluggable, pure, and unit-tested; adding one is
  additive.
* Vocabulary (artifact / claim / spine node / placement / model /
  confidence) is shared-shaped so acquisition can converge without a
  rewrite (Phase B).
* `mix precommit` green; no regression to normal single-season ingest or to
  the shipped acquisition path.

## Pointers

* Trigger site: `lib/media_centaur/pipeline/stages/fetch_metadata.ex`
  (`build_tv/3`, `build_minimal_season/1` — the phantom origin).
* Identity review (the *other* dimension): `lib/media_centaur/review.ex`,
  `review/pending_file.ex` (per-file, identity), `review/intake.ex`.
* Parser claims: `lib/media_centaur/parser.ex` (`Result` struct already
  carries `episode_title`).
* Library spine: `lib/media_centaur/library.ex`
  (`get_tv_series_with_associations!/1`, `list_seasons_for_tv_series/1`,
  `find_present_episode/3`); `library/episode.ex` has **no `air_date`**
  (air dates come from TMDB / release-tracking `Want`).
* Shipped acquisition engine-in-disguise: `acquisition/coverage_guard.ex`,
  `acquisition/cours.ex`, `search/cour_queries.ex`, `search/cour_coverage.ex`,
  `acquisition/cour_segmentation.ex`, `Planner.Option.offer_only`.
* Season fetch + run derivation pattern to mirror for the impure caller:
  `acquisition/cours.ex` (`runs_for_season/2`, `TMDB.Client.get_season/3`).
* Related campaigns: [`cour-aware-acquisition.md`](cour-aware-acquisition.md)
  (shipped acquisition direction), [`duplicate-episode-copies.md`],
  [`unit-season-episode-ordering.md`] (adjacent episode-structure work —
  check for overlap before building).
* [ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md)
  (campaign convention).
