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

Phase A in progress (2026-06-23, session "downloading / matching cours").
Design settled in a long design conversation. **Pure engine core landed**
(committed, unpushed): the `MediaCentaur.Reconciliation` boundary +
vocabulary (`SpineNode`, `Artifact` with claims, `Placement`,
`Interpretation`), the `Model` behaviour, the `Models.GapFill` reliable
floor (numbering-agnostic ordinal fill of the missing tail, confidence by
count-fit), and **`Models.TitleMatch`** (decision-independent title→spine
identity match; confidence 0.9 > gap-fill's ordinal 0.85; corrects
gap-fill's off-by-one; abstains when titles absent; case/punctuation-
insensitive; skips ambiguous titles), all unit-tested. **Next (after a
design pass — open questions below):** the engine that merges/ranks
interpretations and assigns placement states, then the impure
spine-assembly + pipeline trigger + show-scoped review surface.
(Absolute-number model deferred — gap-fill + title-match cover the Frieren
case; add it when a release surfaces an absolute number we extract.) The
**acquisition direction
already ships** as hand-built pieces in
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

## Investigated facts (code grounding — verified 2026-06-23; don't re-derive)

- **Pipeline order:** discovery → `parse` → `search` → `fetch_metadata` →
  `ingest`. `ingest` writes via `Library.Inbound` (+ `link_file/2`).
  **Identity** is decided at the `search` stage behind a confidence gate;
  low-confidence / no-match returns `{:needs_review, …}` → a
  `Review.PendingFile`. So at `fetch_metadata` the show is already trusted.
- **The phantom's exact origin:** `FetchMetadata.build_tv/3` calls
  `Client.get_season(tmdb_id, parsed.season)`. Two unresolved cases:
  - **(a)** season absent on TMDB → `{:error}` → `build_minimal_season/1`
    mints `season_number: parsed.season`, name `"Season N"`,
    `number_of_episodes: 0`, episode `name: nil`. **This is the phantom.**
  - **(b)** season present but `Enum.find(episodes, episode_number ==
    parsed.episode)` misses → episode `name: nil` (blank episode inside a
    *real* season — often legitimately ahead of TMDB).
- **Review today is identity-only.** `Review.PendingFile` is **per-file**
  and answers "which TMDB *entity* is this?" (fields: tmdb_id, candidates,
  match_title, status pending/approved/dismissed). It does **no episode
  mapping**. `Review.Intake` is a GenServer on the `review:intake` topic
  (`create_pending_file` / `complete_review` / `files_for_review`). Our new
  flow is a **second review dimension**, not a `PendingFile` extension.
- **Parser already gives us titles.** `Parser.Result`:
  `file_path, title (show), year, type (:movie|:tv|:extra|:unknown),
  season, episode, episode_title, parent_title, parent_year`. The TV
  regexes capture an optional `episode_title`. **No absolute-episode-number
  field** (absolute, when present, isn't separately extracted).
- **Library `Episode` has no air_date.** Fields: `episode_number, name (NOT
  title), description, duration_seconds, content_url, season_id`. Air dates
  come from TMDB and `ReleaseTracking.Want.air_date` (and `PlanUnit.air_date`,
  added in cour Phase 1) — never from the library episode row.
- **Boundaries** (`use Boundary`): `Search` deps = `[Capabilities,
  Settings]` → Search **cannot** depend on Acquisition (this is why
  `CourQueries`/`CourCoverage` live in Search and take a plain-map run, and
  why a query/title-classification model belongs Search-side).
  `Acquisition` deps include `Search, Library, TMDB, ReleaseTracking,
  Downloads, Review, Retention, Settings, Capabilities`. `Reconciliation`
  is currently `deps: []` (pure); reading the spine will need `Library` +
  `TMDB` — or be fed by an impure caller in the pipeline boundary.
- **Spine fetch pattern:** `TMDB.Client.get_season(tmdb_id, season,
  client \\ default_client())`; `default_client` reads
  `:persistent_term {TMDB.Client, :client}`; tests stub via
  `TmdbStubs.setup_tmdb_client/1` + `stub_get_season/3`.
  `Acquisition.Cours.runs_for_season/2` is the fetch+segment shape to mirror
  for the impure caller (degrade to empty on TMDB error, don't crash).
- **Frieren live (prod, 2026-06-23):** `TVSeries` → Season 1 (28 eps, real
  names) + phantom Season 2 (9 eps, blank names). Media dir
  `/home/shawn/videos/media-library`; third cour = loose files from sensei
  (no titles), UIndex, and standalone (titles present), beside the
  `Season 01 … COMPLETE … [SEV]` BDRip pack (E1–28 + Extras).
- **Test-infra gotchas:** SQLite has **no `ilike`** (use `like` or filter in
  Elixir); the full suite has a **pre-existing "Database busy" setup flake**
  in `acquisition_live_test` (clean in isolation) — not a regression, see
  [[project-suite-residual-concurrency-flakes]].

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
`propose(spine, artifacts) :: [Interpretation]` (the built signature —
`present?` on each `SpineNode` carries "already placed", so the gap is
read from the spine rather than passed separately). An `Interpretation`
is a proposed set of `artifact → spine_node` placements with a confidence
and a human-readable rationale. The engine collapses agreeing
interpretations (corroboration → high confidence) and surfaces
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
* `2026-06-24` — **Auto threshold = conservative.** A placement links
  silently (`auto`) only when ≥2 models corroborate the *same*
  `artifact→node` for **every** artifact in the batch AND counts fit
  exactly (no overflow/partial); everything else is `proposed`. Honors
  surfaced-confirmation — human arbitration is the designed state.
  (resolves the auto/proposed open question) (owner)
* `2026-06-24` — **Conflict presentation = expanded recommended + collapsed
  alternative chips.** The recommended interpretation renders as a
  per-episode mapping table (the decision content is always visible);
  other interpretations are collapsed summary chips (model · confidence ·
  one-line rationale) that expand on click; per-file override is the escape
  hatch. (resolves the conflict-density open question) (owner)
* `2026-06-24` — **Persistence = reuse links + pin + awaiting-mapping
  record.** Durable state is only (1) the existing library file↔episode
  links, (2) a user **pin** (chosen placement; models re-propose around it,
  never overturn), and (3) a lightweight **awaiting-mapping** record that
  parks diverted-but-unplaced files (the second review dimension — NOT
  `PendingFile`). All proposals/confidence are **re-derived** each run
  (deriver model, ADR-057). The awaiting-mapping record is the divert
  target the pipeline trigger needs. (resolves the persistence open
  question) (owner)
* `2026-06-24` — **Specials / season 0: title-match applies, gap-fill
  skips.** Title-match (identity) maps season-0 artifacts safely;
  ordinal gap-fill **refuses** season 0 (TMDB special ordering is
  unreliable) → unmatched specials land `unplaced`/manual. Small safe rule
  built now, not deferred. (resolves the specials open question) (owner)

## Design rationale & alternatives rejected (so we don't relitigate)

- **Title match as the *foundation* — rejected.** First proposed; corrected
  because titles are absent in many releases (2 of Frieren's 9 files had
  none). Titles are a **corroborator/anchor**, never the spine.
- **Air-date segmentation as the mapping signal — demoted to last-resort.**
  Not deterministic: a releaser's season-grouping needn't match air-date
  gaps. `CourSegmentation` survives only as *one source of run boundaries*
  for the offset model, not as the placement signal.
- **"Decode the release's numbering" — rejected framing.** The release
  `SxxEyy` label is the *least* trustworthy input. What we know reliably is
  **our** side: TMDB's episode list + what's present = the **gap**. Map the
  batch onto the gap; use the release numbering only to *order* the batch.
- **Cluster as a fixed structural atom — rejected (circular).** Clustering
  depends on the offset/mapping, which is the very thing under review. So
  grouping is an **output of each interpretation**; the **show** is the unit;
  the user picks the interpretation (which carries its grouping). No
  persisted "cluster" entity.
- **Review unit = per-file — rejected** (too granular; loses the batch
  coherence gap-fill needs). **Per-download/pack — rejected** (a cluster ≠ a
  download: Frieren's third cour arrived as *three* downloads from three
  groups but is *one* mapping problem). Landed on **show = container,
  interpretation = decision, partial-accept = escape hatch.**
- **Permutations that drove the unit decision:** (1) one contiguous run —
  common, one decision; (2) heterogeneous (cour + specials/OVAs + a misnamed
  file) — multiple clusters under one show container; (3) arrivals over time
  — the show review re-proposes as new files land.
- **Trigger case (a) vs (b) — (b) deliberately excluded.** Routing
  episode-beyond-TMDB-count into review would flood it with normal
  just-aired episodes that backfill on their own. Only (a),
  season-not-in-TMDB, is the numbering-mismatch signal.
- **Universal engine up front — rejected** (architecture-astronaut). Build
  ingest; shape the vocabulary for convergence; leave acquisition on its
  shipped code until Phase B.

## Out of scope / non-goals

- **The TMDB-driven detail view is correct** (shows 38 episodes, tail
  missing) — do **not** change it. The bug is the *separate* orphaned season.
- **No self-heal** of the existing phantom — forward fix only.
- **Do not re-segment or renumber library seasons** into a cour model. The
  library mirrors TMDB's canonical numbering; reconciliation maps artifacts
  *onto* the spine, it never restructures canon.
- **Leave case (b)** (episode beyond TMDB count) on ingest-and-backfill.
- **No external mapping DB** (TheTVDB / XEM / AniDB). TMDB-only — we infer +
  confirm; that's *why* human arbitration is a designed state.
- **Acquisition convergence (Phase B) and relink (Phase C) are follow-ups**,
  not part of the first ingest build.

## Risks & mitigations

- **Gap-fill assumes the incoming season is the show's *missing tail*.** If
  it's actually a re-release of a middle cour already present, ordinal fill
  misplaces. *Mitigation:* mandatory confirmation with shown rationale; a
  count overflow/mismatch lowers confidence so it never goes `auto`.
- **Confidence bands are provisional guesses** (gap-fill 0.85 / 0.7 / 0.4)
  and the `auto`-vs-`proposed` threshold is unresolved (open question).
- **Trigger trusts show identity** (settled upstream by `search`'s
  confidence gate). A wrong identity reaching `fetch_metadata` would map onto
  the wrong spine — but preventing that is identity-review's job;
  reconciliation assumes the show is right.
- **Specials / season 0 handling is unspecified** (open question) — may
  surface oddly until designed.

## Acquisition convergence map (Phase B — shipped piece → engine concept)

| Shipped (cour-aware-acquisition, v0.99.6) | Reconciliation concept |
|---|---|
| Release candidate (`SearchResult`) | `Artifact` whose claim is a *range* |
| `CourCoverage.classify/3` (title → episode range) | a title/ordinal interpretation **model** |
| `CourSegmentation` runs | run-boundary input to the **offset model** |
| `CoverageGuard.coverable_units` (publish vs air date) | a confidence/validity rule on a placement |
| `Planner.Option.offer_only` | a placement that can only reach `proposed`, never `auto` |
| Pursuit "covered?" by release numbering | **wanted spine nodes have placements** |

## Built so far (current code shape — commit `2e59419d` + title-match)

`mix test test/media_centaur/reconciliation/` green (15 tests); compiles
warnings-clean; boundary-clean.

- `lib/media_centaur/reconciliation.ex` — `Boundary, deps: []`, exports the
  vocabulary + `Model` + `Models.GapFill`.
- `SpineNode{season, episode, title, present?}` ·
  `Artifact{id, claimed_season, claimed_episode, claimed_title}` ·
  `Placement{artifact_id, season, episode}` ·
  `Interpretation{model, placements, confidence, rationale}`.
- `Model` behaviour: `propose([SpineNode], [Artifact]) :: [Interpretation]`.
  **Divergence from the prose above:** the built signature folds
  "already-placed" into `SpineNode.present?` rather than a separate
  `current_placements` arg — simpler; treat the built shape as canonical.
- `Models.GapFill` — sorts missing nodes + artifacts, zips, confidence by
  count-fit (exact `0.85` / partial `0.7` / overflow `0.4`), rationale
  `"Fills the missing E29–E37, in order (9 of 10)."`; abstains on empty gap
  or empty batch.
- `Models.TitleMatch` — indexes the spine by normalized title (case/
  punctuation-insensitive), maps each artifact's `claimed_title` to its
  uniquely-titled node, single flat confidence `0.9` (identity > ordinal),
  rationale `"Matched N title(s) to canonical E4, E5."`; matches the whole
  spine (decision-independent), abstains when no artifact/spine title is
  present, skips unmatched and ambiguous titles. One interpretation per
  call covering the artifacts it could place.

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

## Open questions

All four design-pass forks were **resolved 2026-06-24** — see Decisions
above (auto threshold = conservative; conflict density = expanded best +
collapsed alt chips; persistence = links + pin + awaiting-mapping record;
specials = title-match yes / gap-fill skips season 0).

Still to settle as we build:

* **Context/boundary** — the pure engine + models stay in
  `Reconciliation` (`deps: []`). The impure caller (assemble spine from a
  TMDB season fetch + library present-set, mirroring `Acquisition.Cours`)
  and the awaiting-mapping persistence need `Library` + `TMDB` — decide
  whether those live in a `Reconciliation` sub-namespace with widened
  boundary deps or in a pipeline-side caller that feeds the pure engine.

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
  (shipped acquisition direction — the convergence target). **Overlap check
  done 2026-06-23, no conflict:** `duplicate-episode-copies.md` is about two
  copies of the *same* unit (quality dedup), not numbering;
  `unit-season-episode-ordering.md` is **complete** (shipped v0.98.3,
  pursuit-unit ordering). Neither touches artifact↔spine mapping.
* `relink-on-move` (Phase C convergence): a moved file = an artifact
  re-asserting a claim. Check for an active campaign before building Phase C.
* [ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md)
  (campaign convention).
