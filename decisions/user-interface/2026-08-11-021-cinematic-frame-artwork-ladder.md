---
status: accepted
date: 2026-08-11
amended: 2026-11-01
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
   | Referenced | tracked item, live pursuit, or a New Releases shelf member (amendment 2026-11-01) | `MediaCentaur.TmdbArtwork` cache | swept 7 days after last use, once unheld |
   | Library | entity imported | entity-keyed store (`image_url/2`) | forever |

Supersedes UIDR-014 §4; the Incoming title modal became a tenant with no close-X.

### Consequences

* Tracked items carry no artwork path columns; the cache layout answers deterministically.

**Amendment 2026-11-01 (campaign `discovery.md`, M9).** A member of the
New Releases shelf (`MediaCentaur.NewReleases`) is a referenced title:
the shelf refresh ensures its record and artwork through
`TmdbArtwork.ensure/2`, its provider keeps it alive and scheduled, and
the daily sweep removes it once it has left the shelf and nothing else
holds it. The Referenced row of the ladder table names it.
