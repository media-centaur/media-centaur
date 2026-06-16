---
status: in-progress
started: 2026-06-16
last_updated: 2026-06-16
---
# Pursuit unit season/episode ordering

## Goal

A composite pursuit's units carry `season_number`/`episode_number`
(ADR-055) but get their `position` from raw insertion order
(brace-expansion / pick order), so the residual-driven descent
(`RunPlan`) and every unit query walk them in whatever order they were
picked rather than in airing order. Make `position` *derive* from
`{season_number, episode_number}` so searches/grabs proceed in season
→ episode order, with a stable fallback that leaves S/E-less units
(movies, unparseable query batches) in their input order. There is no
download-client priority handle — Prowlarr's `grab/1` takes only
`{guid, indexerId}` — so "priority" here means the order MC itself
searches and submits, not torrent-client queue position.

## Status

All three phases landed 2026-06-16 (unpushed). `UnitOrder` primitive +
both creation paths (`Start` TMDB-door, `StartFromPick` query-door)
derive `position` from season/episode; schema comment updated. Acquisition
suite green (491 tests). Pending: full `mix precommit`, then release.

## Decisions made

* `2026-06-16` — Order by MC's own search/grab sequence, not download
  client priority: Prowlarr exposes no priority field, so the only
  lever is the order units are processed (governed by `position`,
  which unit queries already sort by).
* `2026-06-16` — Single shared primitive
  `Acquisition.Pursuits.UnitOrder.with_positions/2`: stable sort by
  `{season || sentinel, episode || sentinel}`, returns
  `[{item, position}]`. All-nil S/E → keys equal → stable sort
  preserves input order (no regression on movies / unparseable
  batches).
* `2026-06-16` — Split by S/E availability. `Start` (TMDB-door) already
  has structured S/E → pure rewire, no parsing, ships first.
  `StartFromPick` (query-door) only has titles (`SearchResult` carries
  no parsed S/E) → needs the parser, deferred to phase 2.
* `2026-06-16` — Dormant until multi-unit pursuits land (`Units.single!/1`
  still raises on >1 unit). This is "wire it correctly now"; no visible
  behavior change today.

## Next steps

1. ~~Phase 1 — `UnitOrder` + `Start`.~~ Done — `UnitOrder.with_positions/2`
   (`unit_order.ex` + 7 pure tests), `Start.insert_units/2` derives
   `position`, dropped the `Map.get(spec, :position, index)` path.
2. ~~Phase 2 — `StartFromPick` (query-door).~~ Done — parses
   `{season, episode}` from the pick's `term` (falls back to
   `result.title`) via `MediaCentaur.Parser`, feeds `UnitOrder`;
   unparseable → input order preserved.
3. ~~Phase 3 — docs.~~ Done — `Unit` schema `position` comment now says
   it governs search/grab order.
4. Run `mix precommit`; ship.

## Completion criteria

* `UnitOrder` pure module with red→green unit tests covering ordering,
  stable fallback, and cross-season.
* `Start` derives `position` from S/E; `StartFromPick` derives it from
  parsed titles.
* A multi-unit pursuit built out of airing order ends up with units
  ordered by `{season, episode}`.
* `mix precommit` green.

## Pointers

* `lib/media_centaur/acquisition/pursuits/unit.ex` — `position` field.
* `lib/media_centaur/acquisition/pursuits/commands/start.ex` — TMDB-door.
* `lib/media_centaur/acquisition/pursuits/commands/start_from_pick.ex` — query-door.
* `lib/media_centaur/acquisition/pursuits/units.ex` — queries sort by `position`.
* `lib/media_centaur/acquisition/jobs/run_plan.ex` — residual-driven descent consumer.
* [ADR-055](../decisions/architecture/2026-06-09-055-composite-pursuits.md) — composite pursuits / units.
