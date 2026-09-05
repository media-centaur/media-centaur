# Cinematic modal frame for TMDB-grounded modals; artwork promotion ladder

- Status: Accepted
- Date: 2026-08-11

## Context and Problem Statement

Three modals were grounded in a TMDB identity but each drew it differently: the
library detail modal had the full cinematic treatment (fixed backdrop, pinned
orientation block, logo lockup), the plan modal had a compact poster-thumbnail
header over a scrolls-with-content backdrop, and the Incoming title modal had a
flat banner header. Their imagery policy was equally split: UIDR-014 §4 said "no
hot-linking TMDB images from the downloads page in v1", but shipped code
hotlinked at seven hand-built widths, while tracking artwork downloaded to a
bare-id local store that two different modules resolved from.

## Decision

**One frame.** Every modal grounded in a TMDB identity renders
`CinematicShell` — the extracted tenant-agnostic half of the detail-modal
technology (always-in-DOM `<.modal>`, panel-fixed backdrop + atmosphere, single
scrollport, sticky orientation block with its backing replica, body sheet with
per-view scroll memory). Tenants fill `:hero_actions` / `:orientation` /
`:body` slots; the frame renders **both** backdrop copies from one
`backdrop_url`, making the byte-identical-URL invariant structural. Tenants:
library `DetailPanel`, the plan modal, the Incoming title modal, and the
pursuit modal.

**One artwork policy — a promotion ladder** keyed to how durable the app's
relationship with the title is:

| Tier | Condition | Source | Lifetime |
|---|---|---|---|
| Browsing | No durable reference — search rows, plan modal, cast headshots | TMDB CDN hotlink via `LiveHelpers.tmdb_cdn_url/2` (the only builder) | Nothing downloaded |
| Referenced | A tracked item or non-terminal pursuit exists | `MediaCentaur.TmdbArtwork` local cache, resolved via `urls/2` | Swept 7 days after last use, once unheld |
| Library | Entity imported | Entity-keyed permanent store (`image_url/2`) | Forever |

This **supersedes UIDR-014 §4's imagery rules**: hotlinking is now sanctioned
for the browsing tier (it was already shipped practice; the honest fix was
tiering, not prohibition). It also amends UIDR-017: the title modal's "centered
modal through the house `<.modal>` seam" is now the cinematic frame, and its
close-X is gone — backdrop click and Escape close, like every other tenant.

## Consequences

- A just-picked search result, a tracked title, and a library title read as the
  same surface; only data source and artwork lifetime differ.
- Hand-built `image.tmdb.org` strings are a Credo-grep away from extinction:
  new hotlinks must go through `tmdb_cdn_url/2`.
- Tracked items no longer carry artwork path columns — the cache layout
  (`images/tmdb/{media_type}-{tmdb_id}/{role}.{ext}`) answers deterministically
  and disk is the download ledger.
- Rollout record: `campaigns/cinematic-modal-unification.md` (git history).
