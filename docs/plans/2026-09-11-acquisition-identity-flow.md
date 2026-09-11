# Design: one identity, from TMDB to the shelf

Campaign: [`campaigns/indexer-id-search.md`](../../campaigns/indexer-id-search.md).
Written with the `unify_design` pass: enumerate every part of the flow first,
design the coherent version, verify it against the enumeration, then name the
cost. **Status: design, awaiting approval.**

Occasioned by a live defect: the same wrong film was downloaded five days
running (6.2 GB) because the automatic movie door built its plan without the
film's identity. The defect is the symptom; the enumeration below is the
diagnosis.

## Glossary

Terms defined before first use. One concept per sentence.

* **Title identity** — the answer to *which film or show is this*. Eight
  fields as TMDB spells them: `tmdb_type`, `tmdb_id`, `imdb_id`, `tvdb_id`,
  `title`, `original_title`, `year`, `origin_country`.
* **Scope** — which episode, season, or collection part *within* a title.
  Distinct from identity: an id names the title, never the scope.
* **Bounds** — the quality preference for a grab. Distinct from both. (Note
  the existing vocabulary collision: `plan.criteria` is bounds,
  `Search.Criteria` is identity + scope. Different ideas, similar names.)
* **Door** — a code path that creates a plan. Each door assembles identity
  from whatever it holds.
* **Hop** — a place identity is copied from one representation into another.
* **Wanted identity** — the identity the ledger says we are trying to get.
* **Declared identity** — the identity an indexer or download client asserts
  about a release (`imdbId`/`tmdbId`/`tvdbId` on a Prowlarr result).
* **Derived identity** — the identity we infer by parsing a release name or a
  file name. A heuristic.
* **Filed identity** — the identity the library records an imported file
  under. Written to `library_external_ids`.

The defect in one sentence, in these terms: *the wanted identity never
reached the door, and the filed identity is never compared to it.*

## Part 1 — The enumeration

Every part of the flow that touches identity. Organised by stage.

### A. Origination — where identity enters the system

| # | Where | Carries |
|---|---|---|
| A1 | `TMDB.Identifiers.from_payload/2` | `imdb_id`, `tvdb_id` — the one module that knows where TMDB puts them (top level for a movie, appended `external_ids` for a series) |
| A2 | `TMDB.Mapper.original_title/1` | `original_title` |
| A3 | TMDB payload directly | `title`/`name`, year (from `release_date`/`first_air_date`), `origin_country` |
| A4 | `Search.SearchResult` (`search_result.ex:96`) | **Declared** identity from Prowlarr, normalised to string spellings |
| A5 | `Parser.parse/1` | **Derived** identity from a release or file name |

### B. Persistence — where identity is stored

| # | Table | Identity columns | Gap |
|---|---|---|---|
| B1 | `acquisition_plans` | all 8 | — |
| B2 | `acquisition_pursuits` | all 8 | — |
| B3 | `release_tracking_items` | 7 | **no `year`** |
| B4 | `release_tracking_wants` | `part_tmdb_id`, `title`, `air_date` | no external ids (known, deliberate — collection parts) |
| B5 | `acquisition_corpus_candidates` | declared: `imdb_id`, `tmdb_id`, `tvdb_id` | — |
| B6 | `library_external_ids` | filed identity | — |
| B7 | `reconciliation_awaiting_files` | `tmdb_id`, `series_title` | — |

### C. Doors — every site that assembles plan identity

The campaign counted **four doors**. There are **seven**.

| # | Site | Door | Identity assembled |
|---|---|---|---|
| C1 | `plans.ex:64` | Media search, TV | tmdb, type, title, origin_country, imdb, tvdb, original_title ✅ |
| C2 | `plans.ex:93` | Media search, movie | tmdb, type, title, year, imdb, original_title ✅ |
| C3 | `plans.ex:167` | Discovery one-click, movie (fetches its own payload) | ✅ |
| C4 | `drop_planner.ex:114` | "Plan now", TV | ✅ |
| C5 | `drop_planner.ex:155` | "Plan now", movie | ✅ |
| C6 | `drop_planner.ex:256` | Automatic sweep, TV | ✅ |
| C7 | `drop_planner.ex:305` | **Automatic sweep, movie** | ❌ no `imdb_id`, no `original_title`; `year` read from `want.air_date` |

Web entry points (`incoming_live.ex:1266`, `:1270`) route through C1/C2 and
assemble nothing themselves.

The blind spot is now legible: *release tracking* reads as one door, and is
four code paths. Three were wired; the fourth was missed, and nothing in the
codebase could have told us — there is no place where the set of doors is
enumerated.

### D. Hops — every projection of identity

| # | From → To | Site |
|---|---|---|
| D1 | TMDB payload → `Targeting.Selection` | `targeting.ex:126` |
| D2 | TMDB payload → movie plan attrs | `plans.ex:175` |
| D3 | `ReleaseTracking.Item` → plan attrs | `drop_planner.ex` ×4 |
| D4 | attrs → `Plan` row | `plan.ex:94` |
| D5 | `Plan` → `Search.Criteria` | `match_criteria.ex:23`, `:36` |
| D6 | `Plan` → `Pursuit` | `commit_plan.ex:111` |
| D7 | `Pursuit` → `Recipe` | `recipe.ex:64` |
| D8 | `Recipe` → `Search.Criteria` | `recipe.ex:123` |
| D9 | Prowlarr raw → `SearchResult` | `search_result.ex:96` |
| D10 | `SearchResult` ↔ corpus candidate | `corpus.ex:116`, `:300` |

**Eight fields, ten hops, every one hand-copied field by field.** Two
independent routes reach `Search.Criteria` — D5 at solve time, D6→D7→D8 at
execute time — and they must agree by hand.

### E. Comparisons — every place identity is checked

| # | Comparison | Site | Rule |
|---|---|---|---|
| E1 | `TitleMatcher.matches?/2` | `run_plan.ex:505`, `alternatives.ex:164`/`:315`, `pursue_target.ex:312` | declared id beats derived name; mismatch rejects |
| E2 | `TitleMatcher.coverage/2` | `run_plan.ex:277`, `alternatives.ex:321` | same, for packs |
| E3 | `Wants.present_movies/1` | `wants.ex:351` | want closes on exact `tmdb_id` in library |
| E4 | `Wants.present_episodes/1` | `wants.ex:347` | want closes on library container |
| E5 | Pipeline `Stages.Search` | `stages/search.ex` | filename → TMDB search → `TMDB.Confidence` gate |
| E6 | `QueueMatcher.find_item/4` | `queue_matcher.ex` | infohash-first pairing; not title identity |
| E7 | `DropPlanner.failed_guids_by_unit/2` | `drop_planner.ex:339` | excludes guids from **terminally-failed** units only |

### F. The return path — download → file → shelf

| # | Link | State |
|---|---|---|
| F1 | `Target.content_path` written on completion | **populated for 20 of 76 succeeded targets (26%)** |
| F2 | `Targets.find_content_path_for/1` | reverse lookup exists — but returns a *path*, not the target, so identity cannot be recovered through it |
| F3 | `Pipeline` stages (Parse → Search → FetchMetadata → Ingest) | **zero references to Acquisition anywhere in `lib/media_centaur/pipeline/`** |
| F4 | `Library.Inbound` → `ExternalIds.put` | writes the filed identity |
| F5 | `Review.PendingFile` | human confirms identity when confidence is low |

### G. Legitimately identity-free paths

Not defects; they must survive the redesign unchanged.

| # | Path | Why |
|---|---|---|
| G1 | `StartFromPick` → `prowlarr_query` recipe | the person picked the release themselves; `TitleMatcher` skips these by design |
| G2 | Manual-query pursuits generally | the typed query *is* the intent |

## Part 2 — What the enumeration reveals

Three findings. The third is the one that changes the design.

**Finding 1 — one idea, eleven representations.** Eight fields copied by hand
across ten hops (D), assembled independently at seven doors (C), persisted in
seven shapes (B). C7 drops three fields; nothing structural prevented it and
nothing detects it. Adding a ninth identity field today means finding
seventeen sites by memory. That is how C7 happened, and it is how the *next*
one happens.

**Finding 2 — the tracked title cannot answer a question it should own.**
`ReleaseTracking.Item` carries every identity field except `year` (B3). So
even with C7 wired, the automatic movie door has no year to give, and
`year_matches?(_parsed, nil)` tolerates everything (`title_matcher.ex:248`).
The door compensates by reading `want.air_date` — scope answering an identity
question, the wrong owner. Both halves are load-bearing: of the two releases
that got through, the id gate would have rejected one and the year gate the
other.

**Finding 3 — the two ends of the flow never meet.** We search with a wanted
identity and we file under a derived one, and **nothing compares them** (F3).
The pipeline re-derives identity from the filename with no knowledge that a
pursuit asked for something specific. In the live defect: wanted
`tmdb:663875`/`tt11887594`, filed `tmdb:1417935`/`tt29512008`, no signal. The
want then stays open — correctly, by its own rule (E3) — and the sweep plans
it again tomorrow. E7 does not catch it either, because its comment assumes
*"satisfied units' wants are closed"*, which is precisely what a wrong-film
grab violates.

This is the defect's actual engine. Fixing C7 and B3 stops *this* loop by
making the wrong release unpickable. It does not make a wrong filing
**detectable** — and a silent wrong filing is what turns a single bad grab
into an unbounded daily loop.

## Part 3 — The coherent design

**Core idea.** Every acquisition decision is one comparison between the
identity we want and an identity something declares. So identity is a single
value, resolved once at origination and carried unchanged to every
comparison — *including the comparison that files the download.*

### 3.1 One value type

`TitleIdentity` (name to be agreed — see *Open naming decision*) holding
exactly the eight fields, with constructors, one per real source:

```
from_tmdb_payload/2   (A1+A2+A3, subsumes Targeting.Identifiers)
from_tracked_title/1  (B3)
from_plan/1           (B1)
from_pursuit/1        (B2)
from_search_result/1  (A4 — declared)
from_parsed/1         (A5 — derived)
```

This collapses duplication that exists **now**, at eleven sites. It is not
speculative flexibility.

### 3.2 One comparison

`compare/2 :: :match | :mismatch | :unknown` — promoted out of
`TitleMatcher.compare_external_ids/2`, unchanged in rule, so that the
*importer* can apply the same rule the matcher already applies. The rule is
already correct and already documented; only its reach is wrong.

### 3.3 Identity, scope and bounds separated

Identity, scope and bounds stop travelling as one undifferentiated bag of
fields. This is what `TitleMatcher`'s moduledoc already asserts — *"An id
names the title, not the scope"* — and what the code does not reflect. Doors
pass an identity struct; they cannot drop a field, because there is no field
to drop.

`Search.Criteria` itself keeps its flat shape and gains a single projection
into it — see *Boundary consequence* under Decisions, which rules out
embedding the struct there and explains why the result is better.

### 3.4 The door count stops being something anyone has to remember

The prose above is worth nothing on its own. "There are seven doors" in a
design doc rots exactly the way "four doors" rotted in the campaign — both
are a number held outside the code. Two layers, so the next contributor
cannot repeat this by omission:

**Layer 1 — omission becomes impossible.** `create_plan/2` takes a
`%TitleIdentity{}`, not a loose attrs map, and the struct carries
`@enforce_keys` for what TMDB always supplies. A door cannot drop
`imdb_id` because there is no per-field assembly to drop it from — it
passes one value or it does not compile. The seven doors stop mattering,
because being wrong requires being wrong in `from_tracked_title/1`, which
is one place.

This is the real answer to "how did C7 happen". Not *we forgot a door* —
*the shape permitted a door to be half-built.*

**Layer 2 — ingress is declared, and the declaration is enforced.** The
structural fix protects identity specifically; it does not warn the next
person that this surface has many entrances at all. So `Plans` names its
doors in one registry, and a custom Credo check (house convention:
prefer a check over prose) fails on any `create_plan` call site absent
from it. Adding an eighth door forces you to declare it — the compiler
takes care of it being *correct*; the check takes care of you *knowing
it exists*.

A registry that drifts is worse than none, which is why it is the check,
not a comment, that holds it.

### 3.5 The return path closes

The structural change, and the reason this is not just a wiring fix:

1. A grab stamps the identity it wanted where the importer reads it. Not a
   reverse lookup from the file — see the measurement below.
2. The pipeline compares the landing file's **derived** identity against that
   **wanted** identity using 3.2.
3. `:match` or `:unknown` → file it, as today.
4. `:mismatch` → **review**, not a silent filing. The machinery already
   exists (F5); this is a new reason to reach it.

A wrong grab becomes one reviewable event instead of an unbounded loop.

## Part 4 — Verifying the design against the enumeration

Every enumerated item, and what the design does to it.

| Item | Disposition under the design |
|---|---|
| A1–A3 | Fold into `from_tmdb_payload/2`. `Targeting.Identifiers` becomes its internals. |
| A4 | `from_search_result/1`. Declared identity gains a name. |
| A5 | `from_parsed/1`. Derived identity gains a name — and becomes comparable to wanted identity, which is what F3 needs. |
| B1, B2 | One identity constructed/destructured at the schema boundary. Columns unchanged (see cost). |
| B3 | **Add `year`.** Nullable, refresher self-heals — the route `origin_country` and `imdb_id` already travelled. |
| B4 | Unchanged. The collection-part gap stays open and stays documented; closing it is its own decision. |
| B5–B7 | Unchanged. Already single-purpose. |
| C1–C6 | Pass an identity instead of six-to-eight keyword pairs. Behaviour identical. |
| C7 | **Fixed by construction** (§3.4 layer 1). Cannot omit what it never enumerates. |
| C1–C7 as a *set* | **Declared in a registry, enforced by a Credo check** (§3.4 layer 2). An eighth door must announce itself. |
| D1–D8 | Collapse to constructor calls. The two routes to `Criteria` become one projection. |
| D9, D10 | Unchanged — they cross the indexer boundary, where field-by-field normalisation is the job. |
| E1, E2 | Unchanged rule; now reading identity from a struct. |
| E3, E4 | Unchanged. Want closure on exact id is correct and stays. |
| E5 | Gains the wanted identity as an input when the file came from a target (F3). |
| E6 | Unchanged. Infohash pairing is not identity. |
| E7 | **Widened**: exclude guids already grabbed against a still-open want, not only terminally-failed ones. Backstop, defence in depth. |
| F1 | **Not relied upon.** Measured protocol-asymmetric (below); the grab stamps identity forward instead. |
| F2 | Left alone. Still serves `DeleteTargets`; not load-bearing for identity. |
| F3 | **Closed.** The design's centre. |
| F4, F5 | Unchanged; F5 gains a new reason to fire. |
| G1, G2 | Unchanged. `prowlarr_query` recipes carry no identity and must not be made to. |

### The question the enumeration surfaced, and its answer

**F1 is 26% populated — and the gap is protocol-shaped.** Measured
2026-09-11 across 76 succeeded targets:

| Grab kind | Succeeded | With `content_path` |
|---|---|---|
| Torrent (40-char infohash) | 29 | 19 |
| Usenet (client id) | 25 | **1** |
| No hash recorded (pre-capture) | 22 | 0 |

`content_path` is effectively a qBittorrent field. `Downloads.QueueItem` reads
it from qBittorrent's own `content_path`, and the SABnzbd shape that should
supply the equivalent from `storage` is not reaching the target. The live
defect is the illustration: four of the five wrong grabs were usenet, and all
four recorded no path.

**Decided: §3.4 carries the wanted identity forward from the grab; it does
not reverse-look-up from the file.** A reverse link that works for one
protocol is exactly the kind of "works for now" seam this pass exists to
refuse. Making the grab stamp what it wanted is both more robust and
protocol-blind. (The SABnzbd `content_path` gap is a real defect on its own
terms — `DeleteTargets` uses that link for deletion boundaries — but it is a
Downloads concern, filed separately rather than folded in here.)

## Part 5 — The cost, honestly

* One new value type, ~8 call-site families converted (C1–C7, D1–D8).
* One custom Credo check + door registry (§3.4 layer 2).
* One migration: `year` on `release_tracking_items` + refresher write.
* `Search.Criteria` reshaped — touches `QueryBuilder` and `TitleMatcher`
  signatures, which have substantial test suites.
* §3.4 is the largest piece and the one with a prerequisite measurement (F1).
* Test churn is the bulk of the work, not the production code.

Sequenced so each step leaves a working product:

1. **Stop the class.** `TitleIdentity` + constructors; `create_plan/2` takes
   the struct. Convert C1–C7 and D1–D8. C7's defect disappears as a
   consequence, not as a patch.
1b. **Declare the ingress.** Door registry + Credo check, so the next door
   announces itself instead of being counted from memory.
2. **Give the tracked title its year.** B3 migration + refresher.
3. **Widen the loop-breaker.** E7.
4. **Measure F1**, then close F3.

Steps 1–3 end the live defect. Step 4 makes the *next* wrong grab visible
rather than silent.

## Decisions (2026-09-11, owner)

**The type is `MediaCentaur.TMDB.TitleIdentity`.** Named for the concept
*which film or show this is*, distinct from *which episode or part* (scope)
and *how good a copy* (bounds). `Title` already means a work in this codebase
(`TMDB.Title`, `TitleMatcher`, `TitleForm`), so the name inherits established
vocabulary rather than coining any. Homed in TMDB because identity
originates there and `TMDB.Identifiers` already owns where the ids come
from.

### Boundary consequence, and a refinement it forces

Verified against the `use Boundary` declarations:

| Context | deps on TMDB | New edge needed |
|---|---|---|
| `Acquisition` | yes | no |
| `ReleaseTracking` | yes | no |
| `Pipeline` | yes | no |
| `Library` | **no** (`[Retention, Subtitles]`) | **no** — the import-seam comparison lives in `Pipeline`, before `Library.Inbound` |
| `Search` | **no** (`[ErrorReports, HttpClient, Settings]`) | **must not** — see below |

Choosing TMDB costs **zero new Boundary edges**, provided §3.5's comparison
sits in `Pipeline` rather than inside `Library`. That is where it belongs
anyway: the pipeline is what knows a file just landed.

But it rules out the shape §3.3 first proposed. `Search.Criteria` cannot
embed a `TMDB.TitleIdentity` — that would add `Search → TMDB`, reversing an
inversion the `Search` moduledoc calls out as deliberate: *"Keeping this
struct in Search inverts the dependency cleanly — Search does not need to
know what a Pursuit / Recipe is."* Search must stay ignorant of its callers'
domain.

**So `Search.Criteria` keeps its flat shape, and gains one projection into
it.** `Acquisition.Plans.MatchCriteria` — which already deps both TMDB and
Search, and already exists to be exactly this — generalises from *plan →
criteria* to *identity + scope → criteria*, and serves **both** routes. That
directly retires the D5/D8 problem: the two independent paths to
`Search.Criteria` that must agree by hand become one function.

The inversion is preserved, the projection is single, and identity is owned
where it originates. Better than the shape it replaced.

## Deferred, with reasons

* **B4 — ids on wants.** Collection parts plan by a part's TMDB id and we
  hold no IMDb id for a part. Already documented as a deliberate gap in the
  campaign; worth closing only if parts mismatch in practice.
* **Want retirement.** `Wants.sync_item/1` opens and satisfies wants but
  never retires one the calendar no longer justifies — which is why a 2020
  theatrical-only want survived a rules change that would never have opened
  it. Real, but a ledger-lifecycle concern, not an identity one. Own design
  pass.
