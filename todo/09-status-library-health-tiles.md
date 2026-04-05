# Library health tiles on the Status page

**Source:** design-audit 2026-04-06, DS22
**Severity:** Moderate (planned feature)
**Scope:** `lib/media_centaur/library.ex`, `lib/media_centaur/status.ex`, `lib/media_centaur_web/live/status_live.ex`, `DESIGN.md`

## Context

`DESIGN.md` promises, under the Status-page planned additions:

> **Health indicators**: entities missing images, entities without TMDB IDs, library "completeness"

None of these exist today. The Status page shows operational health (pipeline state, watchers, errors) but no library health.

This is a user-visible gap between stated design and implementation.

## What to do

1. **Add count queries to `Library`**, one per health metric. They belong in the Library bounded context, not in `MediaCentaur.Status` (which is a consumer, not an owner of library data — per `CLAUDE.md` bounded contexts). Candidate signatures:

   ```elixir
   @spec count_entities_missing_images() :: %{movies: integer(), tv_series: integer(), movie_series: integer()}
   @spec count_entities_missing_tmdb_id() :: %{movies: integer(), tv_series: integer(), movie_series: integer()}
   @spec count_episodes_missing_thumbs() :: integer()
   ```

   Use `Ecto.Query` with left joins against `library_images` and `library_identifiers`. Keep them efficient — no N+1.

2. **Expose via the Status facade.** Add `Status.fetch_library_health/0` that calls the Library queries and returns a shape like:

   ```elixir
   %{
     missing_images: %{movies: 2, tv_series: 0, movie_series: 1, total: 3},
     missing_tmdb_id: %{movies: 0, tv_series: 1, movie_series: 0, total: 1},
     missing_thumbs: 12
   }
   ```

3. **Add a Health card to `StatusLive`.** Place it near the library stats tile row — either as a new row below the six catalog tiles, or as a dedicated card in the same `grid grid-cols-1 lg:grid-cols-2` row as Recent Changes / Recently Watched. Each row of the health card is a `flex items-baseline` (UIDR-008) with the count on the left and a label + breakdown on the right. Use `text-warning` / `text-error` when counts are non-zero.

4. **Clicking a health row drills into the Library with a filter.** If the library filter can accept a "missing images" filter term (it currently filters by name), either add a filter-by-health capability or accept that the click only navigates back to `/` without a pre-applied filter. If the filter work is too much, make the health rows non-interactive for now.

5. **Tests.** Each Library count query gets a test in `test/media_centaur/library_test.exs` (or a new `library_health_test.exs`) that creates a few factory records with and without images/identifiers and asserts the counts. `Status.fetch_library_health/0` gets a test covering the shape of the returned map.

6. **Update DESIGN.md.** Move "Health indicators" from the Planned additions section to the Status sections list as a shipped feature.

## Acceptance criteria

- Three library health metrics visible on `/status`.
- Counts are correct on a fresh DB (`mix seed.review` plus a handful of entities).
- Library queries are indexed / efficient — no full table scan.
- `mix precommit` clean.
- DESIGN.md updated to reflect the feature is shipped.
