---
status: accepted
date: 2026-08-11
---
# Cinematic modal frame for TMDB-grounded modals; artwork promotion ladder

## Context and Problem Statement

Three modals grounded in a TMDB identity each drew it differently, and the imagery policy was split: UIDR-014 §4 forbade TMDB hotlinks.

## Decision Outcome

1. **One frame.** Every TMDB-grounded modal renders `CinematicShell`, filling `:hero_mast` / `:orientation` / `:body`. Tenants: `DetailPanel`, the plan, title detail and pursuit modals.
2. **One artwork ladder**, by how durable the app's relationship with the title is:

   | Tier | Condition | Source | Lifetime |
   |---|---|---|---|
   | Browsing | no durable reference | TMDB CDN hotlink via `LiveHelpers.tmdb_cdn_url/2`, the only builder | none |
   | Referenced | tracked item or live pursuit | `MediaCentaur.TmdbArtwork` cache | swept 7 days after last use, once unheld |
   | Library | entity imported | entity-keyed store (`image_url/2`) | forever |

Supersedes UIDR-014 §4; the Incoming title modal became a tenant with no close-X.

### Consequences

* Tracked items carry no artwork path columns; the cache layout answers deterministically.
