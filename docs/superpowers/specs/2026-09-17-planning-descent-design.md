# Planning search order — search the scope that fits

**Status: decided 2026-09-17; rollout tracked in
[`campaigns/fit-first-search-order.md`](../../../campaigns/fit-first-search-order.md).**

Triggered by a real run: one missing episode of an owned seven-season
series was planned by searching the whole series, then the season, then
(never reached) the episode. The right-sized term is the cheapest and the
most complete, and it ran last.

## Glossary

Project terms as the code uses them today:

- **Want** — the set of `{season, episode}` units a plan must land.
- **Unit** — one wanted episode. A plan unit before commit, a pursuit unit after.
- **Term** — one literal indexer query string (`Title S07`).
- **Scope** — how much of a series something covers: series, a season, an
  episode range, one episode. A release has a scope (parsed from its
  name); a term has a scope (what it is shaped to find). Today's code
  calls a term's scope a "rung" and the three of them a "ladder"; this
  design retires both words.
- **Pack** — a release whose scope is wider than one episode.
- **Span sizes** — per-season aired-episode counts, persisted on the plan.
  Only media-search plans carry them (`Plans.create_series_plan/3`).
- **Fit** — wanted-in-span ÷ aired-in-span for a pack's scope. A pack is
  assignable only when fit ≥ `pack_min_fit` (Settings → Acquisition →
  "Season packs", default 75%). Unknown span size → not judged.
- **Residual** — wanted units no assignment covers yet.
- **Search order** — the sequence of scopes a plan searches, each against
  the residual, re-solving after each, halting when the residual is
  empty. Today's code calls this the "descent".
- **Assignment** — the release the solver chose for a unit; grabbed on commit.
- **Offer** — a fit-gated pack attached to an unfound unit; the user opts in.
- **Coverage guard** — a release published before an episode aired cannot
  contain it (`CoverageGuard`).
- **Corpus** — cached results per term, fresh for 30 minutes.
- **Retry loop** — the pursuit-side retry (`Jobs.PursueTarget`) after a
  plan commits or a grab fails. Searches the episode term only, snoozes
  with backoff, exhausts after 12 attempts.

Terms this design adds. Plain words; nothing coined.

- **A scope fits** — a pack at that scope could clear the fit gate for
  some span of the want. The episode scope always fits.
- **Primary search** — the scopes that fit, searched widest first,
  halting when the residual empties. The only search that assigns.
- **Fallback search** — the scopes that did not fit, searched narrowest
  first, only for units the primary search left unfound. Its packs
  become offers, never assignments.

## Use cases

| # | Want | Origin | Today | Fit-first |
|---|---|---|---|---|
| U1 | 1 episode, finished season | gap row click | series, season×2, episode (halted at 3 today); pick taken from a 100-capped page | episode; then season + series as offers only if unfound |
| U2 | k scattered episodes of one season, k/N < fit | several gap rows | 1 + 2 + k | k episode terms; season offer |
| U3 | most of a season (≥ fit) | Download control, season scope | 1 + 2 (+ residual episodes) | season×2 first; residual episodes; series as offer |
| U4 | whole season | Download control | as U3 | as U3 |
| U5 | several seasons or the whole series | Download control, unowned show | series first, usually done | unchanged |
| U6 | weekly drop, 1 unit of an in-progress season | tracking | 1 + 2 + 1, and fit gating is **off** (no span sizes) | episode; packs gated once tracking plans carry span sizes (F4) |
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

**F1 — Search order ignores the want.** `RunPlan.rungs/1` is a fixed
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
search halts before the precise term. Whether a better release existed is
unknown. Fit-first ordering removes this: a narrow want starts at its
complete candidate set. For wide wants, halting at the pack scope is the
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

**F5 — The retry loop cannot see packs.** `QueryBuilder.build_tv/1` for an
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
`tried_release_guids` on this path, so nothing is blacklisted.
`CommitPlan.grab_assignments/3` degrades a failed grab to seeking, which
immediately runs the retry loop — so classifying the error there covers
the plan path too.

**F7 — The pursuit modal's queries came from the pursuit row.** Plan-born
pursuits carry scope on their units; four readers in `Pursuits` read the
row and fell to the whole-series query. Fixed in `1764bea9`
(`fix(acquisition): read a pursuit's scope from its units, not the row`),
shipped in v1.32.1. It also fed the decision card's query list.

**F8 — The plan board's alternatives picker walks the same fixed order**
(`LadderTerms.for_unit/2` → series, season, episode terms for one unit).
Falls out of F1 once term ordering is fit-aware.

**F10 — The pursuit modal's "Pick a release" list is not the episode's.**
Found 2026-09-17 while scoping step 4. `Acquisition.list_alternatives_for/2`
searches a TMDB pursuit through `do_search_for_recipe/2`, which calls
`search_expanded(recipe.title, type:, year:)`: the bare show title, with
two options Prowlarr silently drops. No `QueryBuilder`, no
`TitleMatcher`, no scope check; the first eight non-tried results are
shown whatever they are. For an episode unit that is eight arbitrary
releases of the show. `find_alternative/2`, which resolves a picked guid,
runs the same search with no unit at all. The evidence run shows it:
"prowlarr search — 30 Rock" twice at 15:06:48, the moment the modal
opened its decision card. `acquisition_test.exs` "excludes guids in
tried_release_guids and caps the list at 8" pins the shape with titles
like `Sample.Show.Release.7`. This is F8's twin on the pursuit side, and
the reason the earlier display fix (F7) changed the modal's *listed*
queries but not what it searched.

**F9 — The season scope costs two terms** (`Title Season 7` → 3 results,
`Title S07` → 100). The long form catches `Season 7 Complete` pack names.
Keep; droppable later if measured useless.

## The rule

> Search the scopes whose pack could be assigned, widest first. Then,
> only for units still unfound, search the remaining scopes narrowest
> first, and let their packs be offers.

For want `W`, span sizes `S`, threshold `t`:

- series scope fits ⇔ `|W| / Σ S ≥ t`
- season `n` fits ⇔ `|W ∩ season n| / S[n] ≥ t`
- episode scope always fits

**Primary search**: `[series if it fits] → [fitting seasons of the
residual] → [episodes of the residual]`. Re-solve after each scope; halt
when the residual is empty. Identical to today's search restricted to
fitting scopes, so the solver, the coverage guard, and the "packs win"
policy are untouched.

**Fallback search** (only if the residual is non-empty after the primary
search): `[non-fitting seasons of the residual] → [series if it did not
fit]`. Gather, solve once, gated packs become offers as today. Nothing is
assigned from this search by construction: every pack here failed fit.

Checked against the table: U1 runs one term when the episode exists; U3
and U4 start at the season pack; U5 is unchanged; U9 spends its requests
on episodes and offers per season.

Fit is judged against the plan's whole want (`prefs.all_wanted`), as the
solver already does, so a scope's fitness does not drift as units get
covered.

### Where it lives

A pure module, `Acquisition.Plans.SearchOrder`, takes want, span sizes
and threshold and returns the ordered scopes, each as
`{scope, :primary | :fallback, terms_for_residual}`. `RunPlan` iterates
it; `Alternatives.for_unit` and the retry loop reuse it. `LadderTerms`
keeps building terms and is renamed `SearchTerms`; `SearchOrder` decides
order. `PlanEvents.DescentStatus` becomes `PlanEvents.SearchProgress` and
carries `:primary | :fallback` on each scope so the board's expectation
panel can say "looking for a pack to offer" rather than "searching".
`GapVerdict.active_headline/2` and the board headline ("broadest releases
first, drilling down only for what's still missing") follow.

## Decisions

All 2026-09-17, with the owner.

1. **Adopt the rule** (F1, F2, F3, F8). Owner: yes.
2. **Fallback search runs automatically.** Owner had no preference; my
   call. It costs at most `seasons-in-residual + 1` terms, once, only when
   something was not found, and an unfound old episode whose only copy
   is a season pack should show the offer without a second click.
3. **Tracking plans get span sizes from the tracking item** (F4); the
   planner's "unknown → not judged" contract stays. Owner: yes.

   *Corrected 2026-09-17, same day.* The first wording said "from the
   tracking calendar". The calendar cannot supply them: it holds only
   the episodes after the library's last one
   (`Helpers.fetch_tv_releases/4` → `Extractor.extract_episodes_since/3`),
   so a count from it would make a one-episode want look like the whole
   season. The refresher already fetches the show details (per-season
   `episode_count`) and the full detail of every season it walks (each
   episode with its air date) on every pass. Season sizes — aired count
   where the season detail was fetched, `episode_count` otherwise — are
   recorded on the tracking item (`season_sizes`, same shape as
   `Plan.span_sizes`) at refresh, and the drop planner passes them into
   the plan. Zero extra TMDB requests; no TMDB call in the plan-creating
   path. Until an item's first refresh after the upgrade its sizes are
   empty and its drop plans keep today's behavior.
4. **The pursuit side searches like the plan side** (F5, F10). Owner had
   no preference; my call, widened 2026-09-17 after F10. Two halves:
   - The decision card's alternatives for a TMDB unit come from the
     unit's terms in search order (episode term, then the season and
     series terms as fallback), identity-verified through
     `TitleMatcher.coverage/2`, and only releases whose scope covers the
     unit are listed. A pack is shown as one, with its scope and episode
     count, and picking it is the same act as "grab the pack" on the plan
     board. Resolving a picked guid searches the same way.
   - Before exhausting, the retry loop runs the fallback terms once; if a
     pack covers the unit it raises the decision "Only a season pack has
     this episode — grab it?" instead of exhausting silently.
   Last in the rollout order.
5. **Grab-failure classification** (F6). `Prowlarr.grab/1` transport
   errors and HTTP 5xx become an infrastructure outcome
   (`download_client_unavailable`): no attempt bump, short snooze, status
   copy that names the client. 4xx stays release-blamed. The next attempt
   re-picks from the corpus, so the pick is kept without storing it.
   Owner: yes.
6. **Naming.** Plain programmer words only. "Rung", "ladder" and
   "descent" leave the acquisition code as the modules that carry them
   are touched; "scope", "search order", "primary" and "fallback" replace
   them. Owner's principle: no terms coined to be unique across bounded
   contexts. (`TitleIntent.rung/0`, the tracking level, is a different
   word in a different context and is not in scope.)

## Out of scope

- Specials (U11). The search has no season-0 shape.
- Query term shapes (year, alternate titles for TV). Unchanged.
- Movie planning (U10). Not ordered by scope.
- Dropping the pursuit row's `season_number` / `episode_number` columns,
  which no reader uses after F7. A separate change with a migration.
- A Status "Needs attention" item while a download client is unreachable.
  Worth having; tracked in the campaign as a follow-up once what exists
  today is checked.

## Verification

- `SearchOrder` unit tests: one per use-case row, asserting the
  scope/kind/term sequence for that want.
- `RunPlan` integration: U1 with a stubbed corpus makes exactly one
  indexer request when the episode exists; U4 starts at the season term.
- `Planner` regression for F4: a lone wanted unit with no span sizes and a
  pack option is *not* assigned the pack (fails today).
- `PursueTarget`: a 500 from grab leaves attempt count unchanged and the
  target snoozed under the infrastructure outcome (fails today).
- Board: the progress panel renders the fallback search distinctly (story
  + LiveView test).
