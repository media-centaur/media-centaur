---
status: accepted
date: 2026-05-07
---
# Acquisition pursuits — a goal-level aggregate over grab attempts

## Context and Problem Statement

Acquisition modelled each search-and-grab as one mutable `Grab` row with a status flag. That cannot express a torrent that stalls for days, verification of the file that actually lands, or a coherent timeline across attempts: cancelling and re-arming produced an unconnected row, so nothing said "release X stalled, release Y worked".

## Decision Outcome

`MediaCentaur.Acquisition.Pursuits` introduces a `Pursuit` aggregate: one acquisition goal that spans any number of attempts.

1. **Identity is TMDB-keyed, with no library foreign key.** A pursuit can exist before any library entity does; the entity is the outcome of a satisfied pursuit. [ADR-055](2026-06-09-055-composite-pursuits.md) later moved the per-attempt thread onto `Unit` rows so one pursuit covers many wanted things.
2. **An append-only, typed event log.** Each event kind is a struct module under `Pursuits.Events`, persisted as `kind` plus payload and rebuilt as the struct on replay. `Pursuits.Events.record/1` is the single write path: persist, then broadcast the struct. The log outlives the pursuit (the pursuit id nilifies; the title is denormalised onto the row).
3. **Snapshot → Policy → Action → Command.** `Pursuits.Snapshots.build/2` is the one impure assembler of a unit's world; `Pursuits.Policy.evaluate/1` is pure and returns an `Action`; each side-effecting transition is its own `Pursuits.Commands.<Verb>` module running in a transaction and recording events; `Pursuits.Watcher` (Oban cron, every 15 minutes) only orchestrates — it builds snapshots, asks the policy, dispatches commands, and holds no domain logic.
4. **Hybrid autonomy.** Safe cases (no seeders) produce an automatic action; taste cases (slow but progressing, several plausible alternatives) produce a decision request for the user. The watcher dispatches both the same way.
5. **Search stays pursuit-unaware.** Already-tried releases are recorded on the unit's attempt thread (`tried_release_guids`) and excluded from candidates there, so the search path never reasons about pursuits.

[ADR-063](2026-08-31-063-plan-diagnosis-model.md) owns the diagnosis vocabulary a plan's outcomes render in.

### Consequences

* Every state change is both a database row and a broadcast, so the timeline UI and live subscribers read one source of truth.
* Adding an autonomy rule is additive — fields on the snapshot, a clause in the policy, a dispatch in the watcher — but each rule needs its observations persisted first.
