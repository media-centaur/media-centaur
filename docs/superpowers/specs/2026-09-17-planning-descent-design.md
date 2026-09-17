# Planning descent — search the scope that fits

**Status: draft for discussion, 2026-09-17.** Nothing here is decided until
the "Decisions" section says so.

Triggered by a real run: one missing episode of an owned seven-season
series was planned by searching the whole series, then the season, then
(never reached) the episode. The right-sized term is the cheapest and the
most complete, and it ran last.

## Glossary

Existing project terms, as the code uses them today:

- **Want** — the set of `{season, episode}` units a plan must land.
- **Unit** — one wanted episode. A plan unit before commit, a pursuit unit after.
- **Term** — one literal indexer query string (`Title S07`).
- **Rung** — one breadth of term: *series* (`Title`), *season* (`Title Season 7`,
  `Title S07`), *episode* (`Title S07E13`).
- **Scope** — what a release contains, parsed from its name: series, seasons,
  season, episode range, episode.
- **Pack** — a release whose scope is wider than one episode.
- **Span sizes** — per-season aired-episode counts, persisted on the plan.
  Only media-search plans carry them (`Plans.create_series_plan/3`).
- **Fit** — wanted-in-span ÷ aired-in-span for a pack's scope. A pack is
  assignable only when fit ≥ `pack_min_fit` (setting, default 75%). Unknown
  span size → not judged (monotonic opt-in).
- **Residual** — wanted units no assignment covers yet.
- **Descent** — walking the rungs against the residual, re-solving after
  each rung, halting when the residual is empty.
- **Assignment** — the release the solver chose for a unit; grabbed on commit.
- **Offer** — a fit-gated pack attached to an unfound unit; the user opts in.
- **Coverage guard** — a release published before an episode aired cannot
  contain it (`CoverageGuard`).
- **Corpus** — cached results per term, fresh for 30 minutes.
- **Seek loop** — the pursuit-side retry (`Jobs.PursueTarget`) after a plan
  commits or a grab fails. Searches the episode term only, snoozes with
  backoff, exhausts after 12 attempts.

Terms this design introduces (naming is open):

- **Fitting rung** — a rung at which a pack could clear the fit gate for
  some span of the want. The episode rung always fits.
- **Assign pass** — the fitting rungs, searched broadest first, halting when
  the residual empties. The only pass that can assign.
- **Offer pass** — the non-fitting rungs, searched narrowest first and only
  for units the assign pass left unfound. Its packs become offers, never
  assignments.

"Pass" follows `Planner`'s own vocabulary (consolidation pass, singles
pass). "Stage" is avoided: it already names pipeline stages and the
descent panel's rung states.

## Use cases

| # | Want | Origin | Today | Fit-first |
|---|---|---|---|---|
| U1 | 1 episode, finished season | gap row click | series, season×2, episode (halted at 3 today); pick taken from a 100-capped page | episode; then season + series as offers only if unfound |
| U2 | k scattered episodes of one season, k/N < fit | several gap rows | 1 + 2 + k | k episode terms; season offer |
| U3 | most of a season (≥ fit) | Download control, season scope | 1 + 2 (+ residual episodes) | season×2 first; residual episodes; series as offer |
| U4 | whole season | Download control | as U3 | as U3 |
| U5 | several seasons or the whole series | Download control, unowned show | series first, usually done | unchanged |
| U6 | weekly drop, 1 unit of an in-progress season | tracking | 1 + 2 + 1, and fit gating is **off** (no span sizes) | episode; packs gated (needs span sizes, see F4) |
| U7 | catch-up drop, several due units | tracking | as U6 | episodes; partial packs via the coverage guard |
| U8 | later cour of an anime season | any | cour-shaped terms | unchanged |
| U9 | sparse across seasons | gap rows | 1 + 2×seasons + k | episodes; per-season offers; series offer |
| U10 | movie | any | every phrasing, best of the union | unchanged |
| U11 | specials (season 0) | gap row | unexamined | out of scope, noted |

Costs are indexer requests when the corpus is cold. Corpus hits are free
but the *page* is still the 100-capped page (F2).

## Findings

Evidence is the acquisition log ring for 2026-09-17 14:52–15:40 UTC and
the code cited.

**F1 — Rung order ignores the want.** `RunPlan.rungs/1` is a fixed
series → seasons → episodes list. For U1 the series and season packs are
gated by fit (1/22, 1/138) and can only ever become offers, yet they run
first. The precise term runs last or not at all.

**F2 — Broad terms return a sample, not a candidate set.** `Title` → 100
results (the indexer cap). `Title S07` → 100. `Title S07E13` → 2. For a
long-running show the broad page is an arbitrary slice of hundreds of
releases; it can miss the pack it exists to find and it can miss the
episode.

**F3 — Halting on an empty residual makes narrow picks luck-dependent.**
Because `Title S07` matches `S07E13` singles, a lone episode is assigned
from whatever singles the capped season page happened to contain, and the
descent halts before the precise term. Whether a better release existed is
unknown. Fit-first ordering removes this: a narrow want starts at its
complete candidate set. For wide wants, halting at the pack rung is the
deliberate "packs win" policy (campaign plan-solver-consolidation,
2026-06-10) and stays.

**F4 — Tracking-born plans have no span sizes, so fit gating is off for
every weekly drop.** `create_series_plan/3` persists
`Targeting.aired_counts/1`; `create_tracking_plan/2` persists nothing. In
`Planner`, an unjudged pack survives gating, and a single wanted unit
skips the consolidation pass into `assign_singles`, which ranks by
quality. A 2160p season pack published after the drop outranks a 1080p
single and is auto-grabbed for one episode. The coverage guard only
protects against packs published *before* the episode aired.

Confirmed on the dev node, 2026-09-17: `Planner.solve([{7, 13}], [pack,
single], prefs)` with a 2160p `{:season, 7}` option, a 1080p
`{:episode, 7, 13}` option and the app's real quality settings assigns
the **pack** under tracking-shaped prefs (no span sizes, `pack_min_fit:
nil`) and the **single** under media-search prefs (`%{"7" => 22}`,
0.75). `RunPlan.prefs/1` documents the gap in its own comment: "Movies
and tracking drops have none → nil → the planner stays broad-first."

**F5 — The seek loop cannot see packs.** `QueryBuilder.build_tv/1` for an
episode criteria emits the episode term only. An episode that exists only
inside a season pack (older shows, once singles are pruned) is invisible
to the pursuit; it retries for about a week and exhausts with no offer.
The plan and the pursuit search differently for the same unit.

**F6 — A grab failure is blamed on the release.** `PursueTarget.handle_found/3`
routes every `Prowlarr.grab/1` error to `handle_no_results(…, "grab_failed")`:
attempt count bumps, snooze 4h → 8h → … → 24h, twelve attempts to
exhaustion. Search errors already get the infrastructure treatment
(`handle_prowlarr_error/2`: one hour, no bump). Today's grab error was
Prowlarr HTTP 500 `DownloadClientUnavailableException` (SABnzbd unreachable):
the right release was found in two seconds and the pursuit slept four
hours. The modal then asked "Pick an alternative release", which cannot
help, and the owner cancelled twice. The release guid is *not* added to
`tried_release_guids` on this path, so nothing is blacklisted. The same
misclassification exists in `CommitPlan.grab_assignments/3`, which degrades
to seeking and discards the assignment.

**F7 — The pursuit modal's queries came from the pursuit row.** Plan-born
pursuits carry scope on their units; four readers in `Pursuits` read the
row and fell to the whole-series query. Being fixed separately
(`fix(acquisition): read a pursuit's scope from its units, not the row`).
It also fed the decision card's query list.

**F8 — The plan board's alternatives picker walks the same fixed ladder**
(`LadderTerms.for_unit/2` → series, season, episode terms for one unit).
Falls out of F1 once term ordering is fit-aware.

**F9 — The season rung costs two terms** (`Title Season 7` → 3 results,
`Title S07` → 100). The long form catches `Season 7 Complete` pack names.
Keep; droppable later if measured useless.

## The rule

> Search the rungs whose pack could be assigned, broadest first. Then,
> only for units still unfound, search the remaining rungs narrowest
> first, and let their packs be offers.

For want `W`, span sizes `S`, threshold `t`:

- series rung fits ⇔ `|W| / Σ S ≥ t`
- season `n` fits ⇔ `|W ∩ season n| / S[n] ≥ t`
- episode rung always fits

**Assign pass**: `[series if fits] → [fitting seasons of the residual] →
[episodes of the residual]`. Re-solve after each rung; halt when the
residual is empty. Identical to today's descent restricted to fitting
rungs, so the solver, the coverage guard, and the "packs win" policy are
untouched.

**Offer pass** (only if the residual is non-empty after the assign pass):
`[non-fitting seasons of the residual] → [series if it did not fit]`.
Gather, solve once, gated packs become offers as today. Nothing is
assigned from this pass by construction: every pack here failed fit.

Checked against the table: U1 runs one term when the episode exists; U3
and U4 start at the season pack; U5 is unchanged; U9 spends its requests
on episodes and offers per season.

Fit is judged against the plan's whole want (`prefs.all_wanted`), as the
solver already does, so a rung's fitness does not drift as units get
covered.

### Where it lives

A pure module — working name `Acquisition.Plans.Descent` — takes want,
span sizes and threshold and returns the ordered passes, each rung as
`{pass, rung_id, terms_for_residual}`. `RunPlan` iterates it;
`Alternatives.for_unit` and the seek loop reuse it. `LadderTerms` keeps
building terms; `Descent` decides order. `PlanEvents.DescentStatus` gains
the pass on each rung so the board's expectation panel can say "looking
for a pack to offer" rather than "searching". `GapVerdict.active_headline/2`
follows.

## Decisions

Open unless dated.

1. **Adopt the rule** (F1, F2, F3, F8). Recommendation: yes.
2. **Offer pass: automatic or on demand?** Automatic costs at most
   `seasons-in-residual + 1` extra terms, once, and only when something
   was not found. On demand ("look for packs" on the unfound row) costs
   nothing until asked. Recommendation: automatic. An unfound old episode
   whose only copy is a season pack should show the offer without a
   second click.
3. **Span sizes for tracking plans** (F4). Options: (a) derive them from
   the tracking item's own calendar (aired releases per season; no TMDB
   fetch); (b) treat unknown span sizes as "pack does not fit" (packs
   become offers only), reversing the planner's monotonic opt-in;
   (c) leave. Recommendation: (a). The data is already local and it keeps
   the planner's contract.
4. **Seek loop and packs** (F5). Options: (a) the seek loop keeps the
   episode term for its attempts, and *before exhausting* runs the offer
   pass once; if a pack contains the unit it raises a decision ("only a
   season pack has it — grab it?") instead of exhausting silently; (b)
   every attempt runs both passes; (c) leave. Recommendation: (a).
5. **Grab-failure classification** (F6). `Prowlarr.grab/1` transport
   errors and HTTP 5xx become an infrastructure outcome
   (`download_client_unavailable`): no attempt bump, keep the pick, short
   snooze (the queue monitor already knows when the client is back — it
   could wake the target), status copy that names the client, and a
   Needs-attention item while it persists. 4xx stays release-blamed.
   `CommitPlan` keeps the assignment as the unit's first target instead
   of degrading to a fresh search. Recommendation: do it; it is what bit
   today and it is independent of the rule.
6. **Naming**: fitting rung, assign pass, offer pass. Open.

## Out of scope

- Specials (U11). The ladder has no season-0 shape.
- Query term shapes (year, alternate titles for TV). Unchanged.
- Movie planning (U10). Not a ladder.
- Dropping the pursuit row's `season_number` / `episode_number` columns,
  which no reader will use after F7. A separate change with a migration.

## Verification

- `Descent` unit tests: one per use-case row, asserting the pass/rung/term
  sequence for that want.
- `RunPlan` integration: U1 with a stubbed corpus makes exactly one
  indexer request when the episode exists; U4 starts at the season term.
- `Planner` regression for F4: a lone wanted unit with no span sizes and a
  pack option is *not* assigned the pack (fails today).
- `PursueTarget`: a 500 from grab leaves attempt count unchanged and the
  target snoozed under the infrastructure outcome (fails today).
- Board: DescentStatus renders the offer pass distinctly (story + LiveView
  test).
