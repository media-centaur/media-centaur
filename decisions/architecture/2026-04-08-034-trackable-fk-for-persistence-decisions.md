---
status: accepted
date: 2026-04-08
---
# Use trackable FKs, not display metadata, for persistence decisions

## Context and Problem Statement

MpvSession used `episode_number` (a display-context field) as a guard for whether to persist watch progress and broadcast updates. Standalone movies and video objects don't have episode numbers — they're not episodes — so their progress was silently discarded. The same pattern appeared in session recovery, which didn't resolve direct FKs for recovered sessions.

The root cause: a series-specific display concept (`episode_number`) was conflated with a universal question ("does this session have a trackable playable item?").

## Decision Outcome

Chosen option: "Guard on trackable FKs (`movie_id`, `episode_id`, `video_object_id`)", because these are the actual keys used to persist progress records, and they directly answer whether there's something to save.

**Rule:** Persistence, broadcast, and finalization decisions must be based on whether a direct FK (`movie_id`, `episode_id`, `video_object_id`) is present — never on display metadata like `episode_number`, `season_number`, or `episode_name`. Display fields describe *what to show the user*; FKs describe *what to track*.

### Consequences

* Good, because standalone movies and video objects now persist progress like any other playable item
* Good, because the guard is self-documenting — "no FK means nothing to save" is immediately clear
* Good, because session recovery now resolves direct FKs, so recovered sessions for any entity type can persist progress
* Bad, because nothing — the prior guard was simply wrong
