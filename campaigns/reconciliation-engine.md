---
status: phase-a-complete
started: 2026-06-23
last_updated: 2026-06-24
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

**Phase A (ingest reconciliation) complete end-to-end** (2026-06-24,
unpushed). A TV file whose parsed season isn't in TMDB's canonical season
list is diverted at ingest — **no phantom season** — into a durable
awaiting-queue, surfaced on `/reconcile` (sidebar "Mapping") where the
engine's recommended file→episode mapping is shown for confirm / override /
partial-accept; confirming materializes the real TMDB episode and links the
file. Committed per phase (9 commits `2e59419d`→`60be1491`), all
`mix precommit`-green; full suite green at `--seed 0`. **Owner to-dos:** (1) eyeball
`/reconcile` in a browser (visual pass was deferred — interaction wiring is
test-covered); (2) the existing Frieren phantom is **not** self-healed by
design — re-download to route it through the new flow; (3) wiki page for the
new surface is a follow-up (shape just settled). **Phase B** (acquisition
convergence) and **Phase C** (relink) remain.

### Earlier history

Phase A started 2026-06-23 (session "downloading / matching cours").
Design settled in a long design conversation. **Pure engine core landed**
(committed, unpushed): the `MediaCentaur.Reconciliation` boundary +
vocabulary (`SpineNode`, `Artifact` with claims, `Placement`,
`Interpretation`), the `Model` behaviour, the `Models.GapFill` reliable
floor (numbering-agnostic ordinal fill of the missing tail, confidence by
count-fit), and **`Models.TitleMatch`** (decision-independent title→spine
identity match; confidence 0.9 > gap-fill's ordinal 0.85; corrects
gap-fill's off-by-one; abstains when titles absent; case/punctuation-
insensitive; skips ambiguous titles), all unit-tested. The rest of Phase A
(engine merge/rank, persistence queue, spine assembly, confirm/link path,
`/reconcile` surface, pipeline trigger) then landed the same week after the
four design forks were settled — see "Built so far" and the Phase A
checklist below. (Absolute-number model deferred — gap-fill + title-match
cover the Frieren case; add it when a release surfaces an absolute number we
extract.) The **acquisition direction already ships** as hand-built pieces in
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
  began `deps: []` (pure); **now `deps: [Library, TMDB]`** for the spine read
  + confirm/link. The ingest **divert** lives in the `Pipeline` boundary
  (gained a `Reconciliation` dep), *not* in `Library.Inbound` — Library
  can't depend on Reconciliation (Reconciliation→Library would cycle).
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
  * `2026-06-24` (build refinement) — **The pin needs no separate table.**
    A confirmed mapping *is* a `WatchedFile` link → a `present?` spine
    node, which already blocks gap-fill from reusing that node — i.e. it
    re-proposes around it and never overturns it, for free. Partial-accept
    falls out: accepted files link + leave the queue, the rest stay
    awaiting. So persistence is just `Reconciliation.AwaitingFile`
    (the queue) + existing links. The `Engine.resolve` `pinned:` param
    stays for in-session partial-accept and Phase B, but there is no
    durable pin record.
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
- **Confidence bands are provisional guesses** (gap-fill 0.85 / 0.7 / 0.4;
  title-match 0.9). The `auto`-vs-`proposed` threshold is now **resolved**
  (conservative: ≥2 models corroborate + exact fit — see Decisions), so the
  bands feed display + ranking, not the auto gate. Revisit the magnitudes
  once we see field behaviour.
- **Trigger trusts show identity** (settled upstream by `search`'s
  confidence gate). A wrong identity reaching `fetch_metadata` would map onto
  the wrong spine — but preventing that is identity-review's job;
  reconciliation assumes the show is right.
- **Specials / season 0** — **resolved**: title-match maps them by identity,
  gap-fill refuses season 0 → unmatched specials land unplaced/manual.

## Acquisition convergence map (Phase B — shipped piece → engine concept)

| Shipped (cour-aware-acquisition, v0.99.6) | Reconciliation concept |
|---|---|
| Release candidate (`SearchResult`) | `Artifact` whose claim is a *range* |
| `CourCoverage.classify/3` (title → episode range) | a title/ordinal interpretation **model** |
| `CourSegmentation` runs | run-boundary input to the **offset model** |
| `CoverageGuard.coverable_units` (publish vs air date) | a confidence/validity rule on a placement |
| `Planner.Option.offer_only` | a placement that can only reach `proposed`, never `auto` |
| Pursuit "covered?" by release numbering | **wanted spine nodes have placements** |

## Built so far (current code shape)

Phase A whole; `mix test test/media_centaur/reconciliation/` green (42
tests) plus the web (`reconcile_{view,live}_test`) and pipeline/library
divert tests; compiles warnings-clean; boundary-clean; full suite green at
`--seed 0`. Commits `2e59419d`→`60be1491` (see `git log`): core+gap-fill,
title-match, engine+season-0, awaiting-queue, spine+resolve_show,
confirm/link, `/reconcile` surface, pipeline trigger, docs.

- `lib/media_centaur/reconciliation.ex` — `Boundary, deps: [Library, TMDB]`
  (the pure engine/models still do no I/O — purity is by construction +
  async unit tests, not boundary-enforced on those modules; `Repo` is
  boundary-exempt). Exports the vocabulary + `Model` + `Engine` +
  `Resolution` + `Spine` + `ShowReview` + `Models.*` + `AwaitingFile`.
  **Context root**: queue API (`divert/1` idempotent on `file_path`,
  `list_awaiting/0`, `awaiting_for_tmdb/1`, `resolve_awaiting/1`,
  `dismiss_awaiting/1`), `subscribe/0`, `resolve_show/2`, `confirm/2`,
  `confirm_recommended/1`.
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
- `Engine.resolve(spine, artifacts, opts)` → `Resolution{recommended,
  alternatives, pinned, unplaced, auto?}`. Ranks interpretations by
  confidence; builds `recommended` (a synthesized `model: :recommended`
  interpretation) by letting the highest-confidence model that placed each
  artifact win; keeps raw per-model interpretations as ranked
  `alternatives`. `auto?` true only under the conservative rule (≥2 models
  corroborate every placement + exact 1:1 gap fill + nothing unplaced).
  `opts[:pinned]` (list of `Placement`) marks nodes taken + withholds those
  artifacts so models re-propose around them.
- `AwaitingFile` schema + migration (`reconciliation_awaiting_files`):
  the durable divert queue. Fields: `file_path` (unique), `media_dir`,
  `tmdb_id`, `series_title`, `claimed_season/episode/title`, `status`
  (`:pending|:resolved|:dismissed`). **No pin/placement table** — a
  confirmed mapping is a `WatchedFile` link (a `present?` node), which is
  the pin (see Decisions).
- `Spine.assemble(tmdb_id, present_keys)` — the impure spine read: TMDB
  `get_tv` → season numbers → `get_season` per season → `[SpineNode]` with
  `present?` from the caller's present-set. Degrades to `[]` on show-fetch
  error; skips a failing season (mirrors `Acquisition.Cours`).
- `Library.present_episode_keys/1` — bulk present-set: `MapSet` of
  `{season, episode}` pairs with a linked `WatchedFile` for a series.
- `Reconciliation.resolve_show(tmdb_id, opts)` → `ShowReview{tmdb_id,
  series_title, tv_series_id, awaiting_files, spine, resolution}`. The
  read model the review surface renders: loads awaiting files → builds
  artifacts → resolves library series for the present-set → assembles
  spine → `Engine.resolve`. `opts[:pinned]` threads into the engine.
- **Boundary widened**: `Reconciliation` now `deps: [Library, TMDB]` (the
  pure engine/models still do no I/O — purity is by construction + async
  unit tests, not boundary-enforced on those modules).
- `Reconciliation.confirm_recommended/1` + `confirm/2` — the apply path.
  Links chosen files to canonical episodes and `resolve_awaiting`s them.
  `confirm/2` takes `%{awaiting_id => {season, episode}}` (per-file
  override + partial-accept; omit a file to leave it pending). Each file
  links independently (one failure doesn't roll back the rest). A confirm
  **materializes the real TMDB episode** — `find_or_create_season` +
  `find_episode_by_season_episode || create_episode` with the spine title —
  then links via `Library.link_file`; **never a phantom**. Returns
  `{:ok, %{linked, failed}}` or `{:error, :series_not_in_library}`.

## Next steps

Test-first throughout (`automated-testing`). Synthetic air dates / generic
placeholder titles in tests — no real titles (house rule). The Frieren data
above is prod runtime, exempt, reference only.

### Phase A — ingest reconciliation (✅ complete 2026-06-24)

1. ✅ **Vocabulary** — `SpineNode/Artifact/Placement/Interpretation` (commit
   `2e59419d`). Started `deps: []`; widened to `[Library, TMDB]` once the
   spine read + confirm landed (step 4).
2. ✅ **Interpretation models + engine** — `Models.GapFill`,
   `Models.TitleMatch`, `Engine.resolve` with conservative auto + pin
   support; specials rule (gap-fill skips season 0). `Resolution` is the
   merged/ranked output. (commits `13fd3265`, `17bed00a`)
   ✅ **Persistence** — `AwaitingFile` queue + context CRUD.
3. ✅ **Pipeline trigger.** `FetchMetadata.build_tv` now detects case (a)
   (`divert?/2`: parsed season not in TMDB's `data["seasons"]`, guarded on a
   non-empty list so trimmed data falls back to normal) → returns
   `season: nil` + a `divert:` claims payload instead of
   `build_minimal_season`. `Pipeline.Stages.Ingest.maybe_divert/1` parks the
   file via `Reconciliation.divert` (Pipeline boundary gained
   `Reconciliation` dep; divert lives Pipeline-side, NOT in Library.Inbound,
   to avoid the Library→Reconciliation cycle). `season: nil` makes Inbound
   create the series with **no phantom season and no file link** — verified
   by an Inbound test (`list_seasons_for_tv_series == []`).
4. ✅ **Spine assembly** — `Spine.assemble`, `Library.present_episode_keys`,
   `Reconciliation.resolve_show` → `ShowReview`. Boundary widened to
   `[Library, TMDB]`.
   ✅ **Show-scoped mapping review surface** — `ReconcileLive` at
   `/reconcile` (sidebar "Mapping"). Master list of shows with awaiting
   files + detail: per-file episode-picker table (recommended pre-filled),
   "Other interpretations" chips with "Use these", Confirm / Dismiss all.
   Pure view logic in `ReconcileView` (unit-tested); 5 live tests cover
   mount/select/confirm/override(form change)/dismiss; smoke entry added.
   `data-page-behavior="reconcile"` + minimal JS behavior registered.
   **Browser visual check deferred to owner** (running instances + prod-DB
   constraints; interaction wiring is test-covered, no phx-value-value
   footgun). **(done)**
5. ✅ `mix precommit` green; committed per phase (9 commits, unpushed).

### Phase A — deliberate deferrals (not loose ends)

* **Auto-apply hook unused (by design).** `Engine.resolve` computes
  `auto?` and `Resolution` carries it, but nothing auto-confirms yet —
  every batch goes through manual confirm on `/reconcile`. This is the
  conservative rollout (surfaced-confirmation first); enabling auto is a
  one-liner later: when `resolve_show` returns `auto?`, call
  `confirm_recommended`. Capability is tested and ready; the trigger is
  intentionally withheld until the confidence is trusted in the field.
* **Confirm creates a thin episode row** (name from spine title only; no
  description/duration/images). A later metadata refresh / deriver pass can
  enrich it. Name is the identifying field for v1.
* **Override select offers present episodes too** — overriding onto an
  already-present node could double-link; the user is in control. Add a
  guard if it bites.
* **resolve_show runs TMDB synchronously** in the LiveView — fine for a
  small admin queue; move to `assign_async` if it grows.
* **Absolute-number model not built** — gap-fill + title-match cover the
  Frieren case; add when a release surfaces an extracted absolute number.
* **Browser visual pass + wiki page** — owner to-dos (see Status).

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

**All Phase-A questions resolved.** The four design-pass forks were
resolved 2026-06-24 (see Decisions: auto threshold = conservative; conflict
density = expanded best + collapsed alt chips; persistence = links + queue,
no pin table; specials = title-match yes / gap-fill skips season 0).

* **Context/boundary — RESOLVED.** Everything lives in the
  `MediaCentaur.Reconciliation` context, now `deps: [Library, TMDB]`. The
  pure engine + models do no I/O (purity by construction + async unit tests,
  not boundary-enforced on those specific modules). The pipeline-side
  **divert** (`Ingest.maybe_divert`) lives in the `Pipeline` boundary, which
  gained a `Reconciliation` dep — divert can't live in `Library.Inbound`
  because Library can't depend on Reconciliation (Reconciliation→Library
  cycle).

Open for **Phase B** (not Phase A): whether the acquisition models reuse the
same `Reconciliation.Model` behaviour directly or wrap it, and where pursuit
completion reads placements from (see Phase B steps).

## Completion criteria (Phase A — all met 2026-06-24)

* ✅ A downloaded file whose parsed season isn't in TMDB's season list is
  **never** ingested as a phantom season; it lands in a show-scoped mapping
  review with candidate interpretations. *(FetchMetadata `divert?/2` →
  `season: nil`; Inbound test asserts `list_seasons_for_tv_series == []`.)*
* ✅ The user can confirm/redirect a proposed mapping (with visible
  rationale) and partially accept; confirming links files to the correct
  canonical episodes without fabricating structure. *(`/reconcile` +
  `confirm/2`; per-file override + skip = partial-accept.)*
* ✅ Interpretation models are pluggable, pure, and unit-tested; adding one
  is additive. *(`Reconciliation.Model` behaviour; GapFill + TitleMatch.)*
* ✅ Vocabulary (artifact / claim / spine node / placement / model /
  confidence) is shared-shaped so acquisition can converge without a
  rewrite (Phase B).
* ✅ `mix precommit` green; no regression to normal single-season ingest or
  to the shipped acquisition path. *(Full suite green at `--seed 0`;
  existing FetchMetadata/Inbound tests unchanged + passing.)*

## Pointers

### Phase A implementation (what shipped — start here when resuming)

* **Context root + queue + orchestration + confirm:**
  `lib/media_centaur/reconciliation.ex` (`divert/1`, `list_awaiting/0`,
  `awaiting_for_tmdb/1`, `resolve_show/2`, `confirm/2`,
  `confirm_recommended/1`, `subscribe/0`).
* **Pure engine + models:** `reconciliation/engine.ex`,
  `reconciliation/models/{gap_fill,title_match}.ex`, `model.ex` (behaviour);
  vocabulary `spine_node.ex`, `artifact.ex`, `placement.ex`,
  `interpretation.ex`, `resolution.ex`.
* **Impure reads:** `reconciliation/spine.ex` (TMDB),
  `reconciliation/show_review.ex` (read model), `reconciliation/awaiting_file.ex`
  (schema) + migration `priv/repo/migrations/20260624120000_*`.
  `Library.present_episode_keys/1` (present-set).
* **Surface:** `lib/media_centaur_web/live/reconcile_live.ex` +
  `reconcile_view.ex` (pure view logic). Route `/reconcile` in `router.ex`;
  sidebar entry in `components/layouts.ex`; JS `assets/js/input/reconcile_behavior.js`
  (registered in `page_behavior.js`); topic `Topics.reconciliation_updates/0`.
* **Trigger:** `pipeline/stages/fetch_metadata.ex` (`divert?/2`,
  `build_divert_metadata/5`) + `pipeline/stages/ingest.ex` (`maybe_divert/1`).
* **Tests:** `test/media_centaur/reconciliation/*`,
  `test/media_centaur_web/live/reconcile_{view,live}_test.exs`,
  `test/media_centaur/library/present_episode_keys_test.exs`, plus divert
  cases in `fetch_metadata_test.exs` / `ingest_test.exs` / `inbound_test.exs`.

### Reference

* Phantom origin (pre-fix, now bypassed by the trigger):
  `fetch_metadata.ex` `build_minimal_season/1` — still used for the
  *case (b)* path (season in TMDB but episode beyond its count).
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
