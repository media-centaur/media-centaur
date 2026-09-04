---
status: accepted
date: 2026-09-04
---
# Outbound HTTP goes through one seam: upstream tagging, instrumentation, and an origin-freshness cache

## Context and Problem Statement

Outbound HTTP clients were built five ways: `HttpClient.new/2` (TMDB,
Prowlarr, the download clients), a process-dictionary module seam in
`ImageFiles` and `SteamStore`, bare `Req.new` with a persistent-term
client in self-update, a bare URL-form `Req.get` in info-hash
resolution, and `Req.new(plug:)` for showcase stubs. No single place
could count requests, errors, or latency per remote party, and nothing
used the freshness TMDB states on every response (`Cache-Control:
max-age`, roughly one hour for search and eight for details, plus weak
ETags). A twelve-episode import fetched the same show twelve times.

## Decision Outcome

Chosen option: "one seam, two steps", because a cache and a status panel
are both properties of the request path, not of any one integration.

1. **Every outbound request is built through
   `MediaCentaur.HttpClient.new/2`.** The call names its **upstream**
   (`MediaCentaur.HttpClient.Upstream`, a closed enum: TMDB, TMDB images,
   Prowlarr, qBittorrent, SABnzbd, GitHub, Steam, indexers). Steam is
   counted but has no panel row: fetched at most hourly for banner art,
   with nothing for the reader to do about a bad answer. Credo
   MC0029 forbids `Req.new/1` and URL-first `Req.get/2` outside the seam.
   An *upstream* is a remote party; it is deliberately distinct from an
   *integration* (`MediaCentaur.IntegrationHealth`), which is a
   user-configured, credential-bearing service with a verify probe.
2. **One telemetry event per request.** `[:media_centaur, :http,
   :request, :stop]` carries upstream, method, host, path, status or
   error, cache outcome, and rate-limit wait. `HttpClient.Stats` folds
   it into the Status page's Connections tile; `HttpClient.IncidentContext`
   assesses the upstreams no other subsystem grades.
3. **Freshness comes from the origin.** The cache plugin stores a 200
   for its `max-age`, revalidates a stale entry with `If-None-Match`,
   and coalesces concurrent misses on one key. There is no policy table;
   a caller that must see fresh data passes `reload: true`. Only GETs
   take part, and only clients that attach the plugin (TMDB, Steam).
   Rate limiting stays TMDB's own step, attached after the cache step so
   a hit never spends a slot.
4. **Not started under test.** The coordinator and stats are absent in
   `:test`, so `Req.Test` stubs never share state across tests; cache
   tests start their own coordinator under a unique name.

### Consequences

- Every remote party the app talks to is visible on one panel with the
  same figures.
- `ImageFiles` serves two CDNs, so its callers name the upstream.
- The four mirrored stats GenServers (`MetadataStats`, `Image.Stats`,
  `ScanStats`, `HttpClient.Stats`) share a skeleton by copy; collapsing
  them is the campaign's scheduled follow-up.
