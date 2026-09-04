---
status: in-progress
started: 2026-09-04
last_updated: 2026-09-04
---
# HTTP client unification: response cache and upstreams panel

## Goal

Route every outbound HTTP request through `MediaCentaur.HttpClient.new/2`
and use that seam for two things the app lacks: an origin-freshness
response cache (TMDB and Steam) and a Status-page panel that reports
per-upstream traffic, errors, latency, and cache effectiveness.

## Status

Paused 2026-09-04 after step 3. Steps 1–3 are committed (`1d0b7b77`,
`e543385e`): the seam with upstream tagging and instrumentation, the
cache plugin and coordinator with revalidation and single-flight, and
TMDB adoption with keyword options and reload sites. Step 4 (client-path
convergence) was fully read but nothing of it is written yet.

Step 4 findings to carry forward:

* `ImageFiles` serves two upstreams (TMDB CDN, Steam CDN), so its
  `download/3` and `download_raw/3` take a required `upstream:` option
  from the four callers (showcase, tmdb_artwork, image_processor,
  apps/artwork).
* `NoopImageDownloader` and the `:image_http_client` /
  `:steam_store_http_client` config keys go away; `ImageFiles`,
  `SteamStore`, `UpdateChecker`, `Downloader`, and `InfoHash` join the
  `req_test_stubs` map (`:images`, `:steam`, `:github`, `:github`,
  `:indexers`). An un-stubbed image download in a test raises inside
  Req and is rescued by `ImageFiles.fetch/2` into a transient error;
  confirm the full suite accepts that in place of the noop's empty 200.
* Tests to rewrite on `Req.Test`: image_files_test, image_processor_test,
  apps_test, steam_store_test, steam_art_controller_test,
  checker_job_test (replace the persistent-term client with a `:github`
  stub).
* Boundaries to widen with `MediaCentaur.HttpClient`: Apps, SelfUpdate,
  Acquisition.
* Showcase's `Req.new(plug:)` clients in Prowlarr and qBittorrent become
  `HttpClient.new(__MODULE__, upstream: …, plug: …)`; Prowlarr, qBittorrent,
  SABnzbd add their `upstream:`.

## Decisions made

* `2026-09-04` — Cache freshness comes from origin `Cache-Control:
  max-age`, verified live against TMDB; no hand-written TTL table.
* `2026-09-04` — ETag revalidation and Steam adoption are in scope, not
  deferred.
* `2026-09-04` — Hand-rolled ETS plus coordinator rather than Cachex:
  revalidation needs stale entries kept and callers coalesced on stale
  keys, which Cachex's absent-key fetch model does not cover.
* `2026-09-04` — The HTTP-layer row unit is named **upstream**, distinct
  from **integration** (`IntegrationHealth`).
* `2026-09-04` — All five client-construction paths converge now; the
  owner accepted the coherence cost.
* `2026-09-04` — Collapsing the four mirrored stats GenServers onto one
  base is scheduled as the follow-up after the panel ships.

## Next steps

1. `HttpClient.new` with `upstream:` and instrumentation steps.
2. `Cache` plugin and `Coordinator`.
3. TMDB adoption.
4. Client-path convergence and test rewrites.
5. Credo check.
6. Stats, incident context, board, widget, story, smoke test.
7. Docs, ADR, wiki.
8. Follow-up: stats base collapse.

## Completion criteria

* No `Req.new` or URL-form `Req.get` outside `HttpClient`, enforced by Credo.
* A fresh cached TMDB response is served without a rate-limit slot or network request; a stale one revalidates with `If-None-Match`.
* The Status page shows an `:http` tile whose widget lists every upstream with live counts.
* Wiki Troubleshooting page documents the panel.

## Pointers

* Plan: `docs/plans/2026-09-04-http-client-cache-and-upstreams-panel.md`
