---
status: accepted
date: 2026-09-20
---
# TMDB knowledge is one record per title, asked only when due

## Context and Problem Statement

The app kept TMDB-derived facts in seven places and asked TMDB from
thirty call sites with no policy above the HTTP response cache: the
release-tracking refresher reloaded every tracked title every six
hours whether or not anything about it could still change, seven
surfaces fetched release facts on every open because nothing stored
them, and library metadata was frozen at import with no record of when
TMDB was last asked. The owner's rule: TMDB is consulted when the app
is *seeking new information* — whether a release date has been
announced — never on open for its own sake. Waste scales with the
library and the tracked set; a quiet day's request count is not a
ceiling.

## Decision Outcome

One record per identity, because every fetch site was a projection of
the same missing thing.

1. **`MediaCentaur.TMDB.Store` holds TMDB's last answer per
   `(media_type, tmdb_id)`** — the detail payload as received (the
   `images` block reduced to the selected logo), its ETag, when it was
   fetched and last changed — and, per stored season, the same. It is
   the only module that calls a `TMDB.Client` detail endpoint.
2. **Everything else is a projection.** Calendar rows, the render
   snapshot, the release window, the targeting universe, the library
   entity's TMDB fields, artwork paths: rebuilt from the record when it
   changes (`{:tmdb_title_changed, ref}` on `Topics.tmdb_titles/0`),
   never fetched on their own.
3. **A check is a conditional revalidation, made when due.** Due is the
   day after the title's next known event or seven days after the last
   fetch, whichever is first; a settled title — a movie past its home
   release or 180 days past its primary date with none typed, or
   canceled; a series ended or canceled with nothing ahead — is never
   due. `MediaCentaur.TMDB.Schedule` is the pure rule; the columns are
   derived on every write, so due-ness is a stored fact, not a timer.
4. **Checks are scheduled for titles the user owns, listed, tracks or is
   acquiring.** A title known only through a friend's activity or a
   one-off open is stored on first contact and never scheduled.
5. **The response cache stands aside for a caller-conditional
   request.** `HttpClient.Cache` neither looks up nor stores a request
   carrying its own `If-None-Match` (`:conditional`); it keeps
   ADR-064's role for search, probes and every other upstream.

Rolled out in five phases (campaign `tmdb-fetch-policy`). In Phase 1
the store fills through a transitional write-through from
`TMDB.Client.get_*`, and nothing schedules a check yet.

### Consequences

* Good, because a settled title costs zero requests and an unsettled one
  costs one small revalidation per due check, at any library size.
* Good, because "does the app know this title" is one query, and a
  title's facts have one fetch time.
* Bad, because the store duplicates description fields the library
  entity also holds; the entity's copy is declared a projection
  (Phase 4) rather than removed, since it is the library's own model.
* Bad, because the payload is stored whole: tens of kilobytes per
  title, measured in Phase 1 before Phase 2 widens the population.
* Collections are not identities here and stay on the old path until
  `collection-identity` decides what a collection is.

### Amendment 2026-09-20 — implemented

All five phases of `tmdb-fetch-policy` landed on main 2026-09-20. What
differs from the text above: the transitional write-through is gone —
`TMDB.Client` keeps `detail/2` for the store and `get_collection/2` for
the three collection callers, and Credo MC0038 (`TmdbDetailSeam`)
enforces both; the library's projection and the owned-titles reference
provider live in the `Pipeline` boundary (`Pipeline.TmdbProjection`,
`Pipeline.TmdbReferences`), because `Library` depends on nothing
TMDB-shaped (ADR-029); the import's credits come through
`Store.fetch_full/2` — the same request as first contact, the record
refreshed, the answer returned whole — rather than a separate request;
a stored title nothing references is swept seven days after its last
fetch (`TMDB.RetentionPolicies`, the artwork cache's twin); the three
Maintenance backfill buttons were removed; and the payload is stored
without its credits (the ten top-billed cast and the directing crew
kept for the preview) rather than "as received minus `images`".
