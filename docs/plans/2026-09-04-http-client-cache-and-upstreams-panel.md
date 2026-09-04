# HTTP Client: Response Cache and Upstreams Panel

## Glossary

- **HttpClient seam** — `MediaCentaur.HttpClient.new/2`, the one place a
  `Req` client is built. Every outbound HTTP request passes through it.
- **Upstream** — a remote party this app makes HTTP requests to. One
  row on the Status panel per upstream. Closed enum in
  `MediaCentaur.HttpClient.Upstream`: TMDB, TMDB images, Prowlarr,
  qBittorrent, SABnzbd, GitHub, Steam, indexers. Distinct from an
  *integration* (`MediaCentaur.IntegrationHealth`), which is a
  user-configured, credential-bearing service with a verify probe.
- **Fresh** — a cached response whose origin `max-age` has not elapsed.
  Served without a network request.
- **Stale** — a cached response past its `max-age` but inside the hard
  retention cap. Served only after revalidation.
- **Revalidate** — a request for a stale entry carrying
  `If-None-Match`. A 304 renews freshness and keeps the stored body.
- **Reload** — a call that must reach the upstream regardless of cache
  state, and overwrites the entry with what comes back. Requested with
  `cache: :reload`.
- **Single-flight** — concurrent misses or revalidations on one key
  share one in-flight request.
- **Coordinator** — the GenServer owning the cache table that runs
  single-flight and the retention sweep.

## Problem Statement

The TMDB client re-fetches identical resources within seconds: a
twelve-episode import calls `get_tv` and `get_season` twelve times
each for one show, Review and Incoming re-run searches the pipeline
just ran, and image repair re-reads details already fetched. TMDB
states per-response freshness (`Cache-Control: public, max-age=N`,
roughly one hour for search and eight hours for details) and weak
ETags, and nothing in the app uses either.

Separately, outbound HTTP has no observability. Five construction
paths exist (`HttpClient.new`, a process-dict module seam in
`ImageFiles` and `SteamStore`, bare `Req.new` in self-update, bare
`Req.get` in info-hash resolution, `Req.new(plug:)` in showcase), so
no single place can count requests, errors, or latency per upstream.

## Core Idea

Every outbound request is built through one seam, and that seam is
where integration-agnostic HTTP concerns live: stub routing, response
caching, instrumentation. The cache and the panel are two steps
attached at the seam, not features beside the client.

## Design

### `MediaCentaur.HttpClient` context

- `new(module, opts)` — unchanged signature. Requires `upstream:` in
  `opts`. Tags the request, attaches instrumentation steps, attaches
  cache steps when `cache: true`, routes to a `Req.Test` stub in test.
- `Upstream` — the closed enum and display names.
- `Cache` — the Req plugin. Request step reads ETS directly and halts
  with a synthesized response on a fresh entry; otherwise hands off to
  the coordinator. Response step stores a 200 and renews on a 304.
  Entry: key, raw body binary, ETag, fresh-until, stored-at. Key is
  method, path, and sorted query with the api key stripped.
- `Cache.Coordinator` — owns the ETS table, single-flight, sweep past
  the seven-day hard cap, entry-count cap.
- `Stats` — telemetry handler on `[:media_centaur, :http, :request,
  :stop]`, cast into a GenServer, snapshot on read. Per upstream:
  session and fifteen-minute request and error counts, median latency,
  cache hit, miss, revalidated counts, last success and failure, plus
  a bounded recent-request feed.
- `IncidentContext` — the `:http` subsystem assessor. Mints a fault
  on a sustained per-upstream error rate over the window; vitals
  return the stats snapshot.

### Policy

- Freshness comes from origin `max-age`. No hand-written TTL table.
- `/configuration` (the credential probe) and the release-tracking
  refresher use `cache: :reload`.
- Artwork and file downloads never attach the cache.
- Rate limiting stays TMDB's. `TMDB.RateLimiter` gains a request step
  TMDB attaches after the cache step, so a hit never spends a slot.

### Status page

- `:http` joins the board subsystems, the console components, the
  activity-widget registry, and the diagnostics contributors.
- The widget renders one row per upstream with the recent-request
  feed behind a disclosure. The TMDB rate-limit budget moves here
  from the Metadata widget.

## Reconciliation (unify_design)

| Incoherence | Disposition |
|---|---|
| Five client-construction paths | Fix now: all converge on `HttpClient.new` with `Req.Test` stubs. |
| TMDB private request span duplicates the generic event | Fix now: retire it. |
| Rate-limiter budget on the Metadata widget | Fix now: move to the HTTP panel. |
| Stale moduledocs (`TMDB.Client`, `MediaCentaur.Cache`) | Fix now. |
| `HttpClient` boundary unchecked | Fix now: real deps and exports. |
| Fourth mirrored stats GenServer | Scheduled: collapse the four onto one base after the panel ships. |
| Empty retention panel for `:http` | No change: drill-in hides empty lists. |

## Steps

1. `HttpClient.new` with `upstream:`, instrumentation steps, `Upstream`.
2. `Cache` plugin and `Coordinator`: fresh hit, miss, reload, single-flight, revalidation, sweep, cap.
3. TMDB adoption: cache and rate-limit steps, keyword options on the client API, reload sites, retire the private span.
4. Converge `ImageFiles`, `SteamStore`, self-update, info-hash, showcase onto the seam; rewrite their tests on `Req.Test`.
5. Credo check: no `Req.new` or URL-form `Req.get` outside `HttpClient`.
6. `Stats`, `IncidentContext`, board subsystem, widget and story, smoke test.
7. Docs: moduledocs, `docs/tmdb.md`, `docs/architecture.md`, ADR, wiki.
