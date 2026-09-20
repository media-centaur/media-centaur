---
status: accepted
date: 2026-09-04
---
# Outbound HTTP goes through one seam: upstream tagging, instrumentation, and an origin-freshness cache

## Context and Problem Statement

Outbound HTTP clients were built five ways, so no single place could count
requests, errors or latency per remote party, and nothing used the freshness
TMDB states on every response (`Cache-Control: max-age`, weak ETags). A
twelve-episode import fetched the same show twelve times.

## Decision Outcome

One seam, because a cache and a status panel are properties of the request
path, not of any one integration.

1. **Every outbound request is built through `MediaCentaur.HttpClient.new/2`**
   and names its upstream — `HttpClient.Upstream`, a closed enum: TMDB, TMDB
   images, Prowlarr, qBittorrent, SABnzbd, GitHub, Steam. MC0029 forbids
   `Req.new/1` and URL-first `Req.get/2` outside the seam. An *upstream* is a
   remote party; an *integration* (`IntegrationHealth`) is a user-configured,
   credential-bearing service with a verify probe.
2. **One telemetry event per request**, `[:media_centaur, :http, :request,
   :stop]`, carrying upstream, method, host, path, status or error, cache
   outcome and rate-limit wait. `HttpClient.Stats` feeds the Status page;
   `HttpClient.IncidentContext` assesses the upstreams no other subsystem
   grades.
3. **Freshness comes from the origin.** The cache plugin stores a 200 for
   its `max-age`, revalidates a stale entry with `If-None-Match`, and
   coalesces concurrent misses on one key. No policy table; a caller that
   must see fresh data passes `reload: true`. Only GETs, only on clients that
   attach the plugin (TMDB, Steam). TMDB rate limiting runs after the cache
   step so a hit never spends a slot.

   *Amendment 2026-09-20 (ADR-071):* a request the caller made conditional —
   carrying its own `If-None-Match` — passes the cache untouched, neither
   looked up nor stored, and reports `:conditional`. TMDB detail freshness
   is now a policy above this seam (`MediaCentaur.TMDB.Store`);
   `reload: true` remains for the credential probe and, until Phase 2 of
   `tmdb-fetch-policy`, the release-tracking refresher.
4. **Not started under test.** The coordinator and stats are absent in
   `:test`; cache tests start their own coordinator under a unique name.

### Consequences

* `ImageFiles` serves two CDNs, so its callers name the upstream.
* Four stats GenServers share a skeleton by copy; collapsing them is
  deferred work.
