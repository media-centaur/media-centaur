---
status: accepted
date: 2026-06-17
---
# Canonical episode identity — one TMDB-anchored vocabulary, ambiguity only at the edges

## Context and Problem Statement

A tracked show (Frieren, TMDB 209867) sat with ten aired-but-missing
episodes that auto-grab kept "succeeding" on without ever delivering them.
TMDB models the show as **one continuous 38-episode Season 1** (no
Season 2; the 2026 cour is episodes 29–38). The library declared 38 but
held 28. Auto-grab, wanting `S01E29–E38`, searched *"Frieren Season 1"*,
found a `Season 01 [2023-2024] COMPLETE` pack (the first cour, episodes
1–28, already owned), grabbed it, and marked the target **succeeded** —
delivering none of the wanted episodes. Wants stayed open → the same
wrong pack was re-grabbed every tick → `/upcoming` showed ten perpetual
"TODAY" cards.

Two failures, both about **numbering**:

1. **Search by TMDB season cannot find split-cour releases.** Release
   groups name the 2026 cour `S2` or absolute `29`, never `S01E29`.
2. **Coverage was credited from a release's *title*, not its *contents*.**
   A "Season 01 COMPLETE" release was assumed to cover episodes 29–38
   because they nominally live in season 1.

Underneath both: episode identity is an **implicit, scattered
convention** — the tuple `(tmdb_series_id, season_number, episode_number)`
is reconstructed in ~13 places (parser captures, `Want.unit_key`
strings, `find_episode_by_season_episode`, the library reconciler, UI
formatters), with **no representation of an absolute ordinal**. Every
edge improvises its own numbering, so anime split-cours (TMDB merges
broadcast seasons; the world splits them) break silently.

## Decision

**`EpisodeIdentity` — `(tmdb_series_id, season_number, episode_number)`
plus a derived absolute ordinal — is the single internal vocabulary for
"which episode," represented coherently in every slice. All numbering
ambiguity is confined to three named edge adapters.**

- **TMDB is the source of truth.** The canonical key is the tuple the
  schema already enforces (`Episode` unique on `[season_id,
  episode_number]`); this ADR promotes the implicit convention to a
  first-class concept rather than inventing one.
- **Absolute ordinal is derived, not stored** — `Σ episode_count(seasons
  < s) + e`, season 0/Specials excluded — recomputable from TMDB season
  data per [ADR-057](2026-06-14-057-derived-data-is-recomputable.md). For
  a single-season show it equals `episode_number`.
- **Three edge adapters own all ambiguity:** *parse-in* (filename →
  identity), *query-out* (identity → indexer search terms), *match-in*
  (release → the identity **set** it actually delivers). Nothing internal
  reasons about loose season/episode integers or `"s1e29"` strings.
- **Resolution is absolute-ordinal-first, air-date tiebreak.** A fansub
  `Frieren - 29` maps to `S01E29` because TMDB's continuous numbering
  *is* absolute. Broadcast-season names (`S2E01`) on a TMDB-*merged* show
  are **best-effort** — not derivable from TMDB alone — and surface as
  "couldn't place this release," never silently mis-bound.
- **Coverage is proven by contents.** A release's covered-identity set is
  what it actually delivers (filename / air-window), never assumed from
  its title. A unit satisfies **iff its canonical identity is present in
  the library**; a release that delivers nothing new is recorded as
  tried so the planner never re-grabs it.

## Consequences

- **Positive.** The wrong-pack re-grab loop becomes structurally
  impossible (coverage-by-contents). Split-cour anime is findable and
  bindable (absolute-first adapters). One concept replaces ~13 scattered
  reconstructions; release-tracking, acquisition, library, and display
  speak the same identity. Composes with composite pursuits
  ([ADR-055](2026-06-09-055-composite-pursuits.md)) and wants
  ([ADR-056](2026-06-10-056-release-tracking-wants.md)).
- **Limits (accepted).** Broadcast-season-named releases for TMDB-merged
  shows are best-effort; we do **not** build or maintain an external
  scene/offset mapping database (Sonarr/XEM-style) and do **not** adopt a
  second metadata source (AniDB/TVDB). TMDB stays the only source of
  truth.

Rollout: `campaigns/canonical-episode-identity.md` (reconciliation-first,
four phases).
