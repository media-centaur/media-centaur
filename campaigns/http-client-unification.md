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

Steps 1–7 done and verified 2026-09-04: `mix precommit` green (6582
tests), the dev server restarted onto the new supervision tree, a live
`get_movie` pair showed miss (128 ms) then hit (0 ms), and the
Connections drill-in renders real figures. Commits `1d0b7b77`,
`e543385e`, `7850f104`, `309823c6`; wiki commit `8ebeb67` (local, push
when the tile ships). Unpushed.

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

1. Push the wiki edit when the app version carrying the tile ships.
2. Follow-up: collapse `MetadataStats`, `Image.Stats`, `ScanStats`, and
   `HttpClient.Stats` onto one attach/cast/snapshot base.

## Completion criteria

* No `Req.new` or URL-form `Req.get` outside `HttpClient`, enforced by Credo.
* A fresh cached TMDB response is served without a rate-limit slot or network request; a stale one revalidates with `If-None-Match`.
* The Status page shows an `:http` tile whose widget lists every upstream with live counts.
* Wiki Troubleshooting page documents the panel.

## Pointers

* Plan: `docs/plans/2026-09-04-http-client-cache-and-upstreams-panel.md`
