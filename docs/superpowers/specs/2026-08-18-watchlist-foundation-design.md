# Watchlist foundation (Discovery context) — design

Date: 2026-08-18
Status: approved (design); implementation not started

## Purpose

First iteration of a recommendation/discovery surface. The long-term destination
is social: friends and broadcast recommendation feeds over Nostr
(`campaigns/friends-recommendations.md`, parked). This iteration builds the
substrate that every future candidate source lands on: a local **watchlist** —
title-level "I want to watch this" intent with provenance — plus the triage
surface and the pursue hand-off.

## Decisions from the brainstorm

1. **Foundations in pursuit of social.** Solo discovery and social sharing are
   both wanted; we build the foundation now with the social layer as the
   architectural destination. Consequence: every candidate carries *provenance*
   from day one.
2. **Broadcast-first social model (campaign Q4 resolved).** The core future
   gesture is a published feed that followers browse, not a directed inbox.
   The data model stays **directed-capable**: a recommendation with an optional
   recipient is a small schema difference later, so no directed fields are
   built now.
3. **Iteration 1 = watchlist primitive alone.** No automated candidate sources
   yet. Manual adds from surfaces that already show titles, plus a Watchlist
   page with pursue/remove. Sources (TMDB discover, Letterboxd import, Nostr)
   become adapters onto this proven surface.
4. **Watchlist tracks titles, not acquisition status.** Items may reference
   titles already in the library ("you have this — watch it"). Library presence
   is a live, derived property of an item, never a membership criterion. This
   keeps received recommendations for owned titles meaningful later.
5. **New `Discovery` bounded context** (over extending ReleaseTracking or
   adding a Library state). ReleaseTracking means "watch for future releases to
   acquire" — an acquisition-side concern; watchlist is viewing intent and will
   grow social provenance. Library stays "what you have". Discovery is the
   landing zone for all future candidate sources.

## Architecture

`MediaCentaur.Discovery` — `use Boundary, deps: [Library, TmdbArtwork,
Settings]`. No TMDB dep: items arrive carrying their identity (a
`ReleaseTracking.TitleResult`-shaped snapshot) from the search UI; Discovery
never calls TMDB. Upstream of Acquisition; Acquisition is unaware of it in v1
because pursue routes through the existing plan flow.

### Schema — `Discovery.WatchlistItem`, table `watchlist_items`

| Field | Type | Notes |
|---|---|---|
| `tmdb_id` | integer | with `media_type`, the identity; unique index on the pair |
| `media_type` | `Ecto.Enum` `[:movie, :tv_series]` | atoms match `TitleResult` exactly |
| `name`, `year`, `poster_path`, `overview` | snapshot | cached at add time; renders without TMDB |
| `source` | `Ecto.Enum` `[:manual]` | provenance; grows (`:friend`, `:import`, …) later |
| `note` | string, nullable | free-text "why" |
| timestamps | | `inserted_at` is the added-at |

Deliberate absences:

- **No status field.** Removal is deletion. A dismissals ledger (so automated
  sources don't re-surface rejected candidates) is forward design, needed only
  when pushy sources exist.
- **No library back-link columns.** Presence is resolved at read time via
  `Library.ExternalIds` — one source of truth, cannot go stale.
- **No sender/recipient columns.** Directed-capability is preserved by the
  provenance design; those arrive as nullable additive columns with the Nostr
  layer.

### Context API

- `add_to_watchlist(attrs)` — idempotent; re-adding an existing
  `{tmdb_id, media_type}` returns the existing item.
- `remove_from_watchlist(tmdb_id, media_type)`
- `list_watchlist()` — items decorated with library presence (movies via
  `ExternalIds.find_present_movie/1`, series via `tmdb_ids_for_tv_series/1`).
  *[Amended 2026-08-18: shipped as a single bulk `ExternalIds.tmdb_owners/1`
  lookup, and "in library" means* presentable (file-linked) *— not merely that
  a container row exists — via the `PresentableQueries` presence fragments
  (commits fd63a52c, b0922a63), since `Presentable.resolve` requires files.]*
- `on_watchlist?(tmdb_id, media_type)`
- `watchlisted_refs()` — `MapSet` of `{tmdb_id, media_type}` for bulk
  decoration of search results.

`Discovery.Events` broadcasts a `WatchlistUpdated` struct on a new
`MediaCentaur.Topics` entry (ADR-060 pattern: `@enforce_keys` struct, one
`broadcast/1`).

### Artwork

`Discovery.TmdbArtworkHolds` — a `TmdbArtwork.HoldProvider` (copy the
18-line `ReleaseTracking.TmdbArtworkHolds` template), registered in config.
`TmdbArtwork.ensure/2` on add promotes posters from TMDB hotlink to the local
referenced tier; watchlist items persist, so their artwork must too.

## UI

**Media search results** (`components/acquisition/media_results.ex`): each row
gains a watchlist action with three states — add / on watchlist (activate again
to remove) / in library. This also closes an existing gap: search results
currently show no in-library state (it appears only inside the plan modal).
Both decorations are bulk lookups (`watchlisted_refs/0`, `ExternalIds` bulk
functions) when results load.

**Detail pages** (movie, TV series): an "on watchlist" toggle — where
owned-title viewing intent is expressed.

**`/watchlist` — `WatchlistLive`**: rows with poster, name, year, note,
provenance label, and one state-dependent primary action:

- not in library → **Plan**, navigating to
  `/incoming?plan=new&tmdb_id=…&tmdb_type=…` (existing plan modal, untouched —
  search discovers, plan approves, pursuit executes per ADR-055).
- in library → link to the detail page.

Pursuit-in-flight decoration is composed in the LiveView by asking
ReleaseTracking/Acquisition directly; Discovery stays pure.

Page plumbing: router entry in `live_session :default`, sidebar link
(`layouts.ex`), input-system registration (`assets/js/input/config.js` zones +
cursor priority, page behavior module, `data-page-behavior` +
`data-nav-zone`/`data-nav-item` attributes), storybook stories for new
components in the same commit (MC0009). Empty state per house voice, no
redundant CTA. All user-facing copy through the writing-copy skill; user-facing
term is "watchlist".

## Liveness

- `WatchlistLive` subscribes to `Topics.library_updates` (completed pursuit
  flips an item to in-library without reload — the ReleaseTracking refresher
  pattern) and the discovery topic.
- `IncomingLive` refreshes watchlist decorations on discovery events.

## Testing

Test-first (automated-testing skill). Context tests: add idempotency, removal,
library-presence decoration against Library factories. LiveView tests:
watchlist page states, add-from-search, add/remove from detail. Story
compile/render for new components. No network: snapshots passed in,
`TmdbArtwork.ensure/2` stubbed as in ReleaseTracking tests. One new table;
safe-migration-per-release applies (idempotent, CHANGELOG mention). Test
fixtures use generic placeholder titles only.

## Out of scope — the forward path

- **Candidate sources:** TMDB discover/trending seeded by watch history,
  list import (Letterboxd via CSV/scrape, generic TMDB-ref lists), follows on
  people/collections. Each is an adapter calling `add_to_watchlist` with its
  own `source` value.
- **Dismissals ledger** — arrives with the first automated source.
- **Nostr layer** — identity (keypair), transport (relay websockets),
  signed rec events with optional recipient; feeds the same funnel. See
  `campaigns/friends-recommendations.md`.

## Follow-ups on ship

- Wiki: new *Using Media Centaur* page section for the watchlist.
- Update `campaigns/friends-recommendations.md`: Q4 resolved (broadcast-first,
  directed-capable), foundation designed here.
