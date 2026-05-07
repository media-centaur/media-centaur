---
status: accepted
date: 2026-05-07
---
# Acquisition pursuits — a goal-level aggregate over grab attempts

## Context and Problem Statement

The acquisition system as it stood ([ADR-035](2026-04-15-035-acquisition-prowlarr-integration.md), [ADR-037](2026-04-16-037-acquisition-integration-scope.md)) modelled each search-and-grab as a single atomic `Grab` row with a five-state lifecycle (`searching | snoozed | grabbed | abandoned | cancelled`). This was sufficient when "we tried once, it worked or it didn't" was the whole story.

Three product requirements pushed beyond that model:

1. **A torrent that stalls for days** should be detected, an event recorded, and the user offered alternative releases — instead of silently sitting in qBittorrent forever.
2. **Identity verification** must run on the file that actually lands. Today `TitleMatcher` filters releases at *search* time only; a poorly-named torrent that slips through becomes the wrong show in the library with no rollback path.
3. **A coherent timeline per acquisition goal**. Cancelling a grab and re-arming creates an unconnected new row. The user has no single thread that says "we tried release X, it stalled, we tried release Y, that one worked."

A single mutable `Grab.status` flag cannot express any of this. We need an aggregate that persists across multiple grab attempts, an append-only history, and a place to detect / decide / act intelligently between them.

## Decision Outcome

Chosen option: **Introduce a `Pursuit` aggregate inside `MediaCentarr.Acquisition`**, identified TMDB-keyed (matching `Grab`), with an append-only event log, a hybrid-autonomy policy, and a strict separation between the read-side facade, write-side commands, and orchestrating workers.

### Aggregate shape

A `Pursuit` is one acquisition goal — *"get S01E03 of show X at 1080p"* — that may span multiple `Grab` attempts. State machine:

```
active            ─┬→ satisfied          (final grab imported & verified)
                   ├→ needs_decision     (system needs user input)
                   ├→ exhausted          (no acceptable alternatives left)
                   └→ cancelled          (user)

needs_decision    ─┬→ active             (user picked an alternative)
                   ├→ exhausted
                   └→ cancelled
```

Identification: `(tmdb_id, tmdb_type, season_number, episode_number)` — the same key Grab uses, so pursuit creation is naturally idempotent on the same key. Library-entity FKs are deliberately **absent**: a pursuit can exist before any library entity does.

`Grab` rows gain a nullable `pursuit_id` FK and an `excluded_release_guids` array. The exclusion list is denormalised onto the grab so `SearchAndGrab` has zero pursuit-awareness — it just reads exclusions from its own row and filters Prowlarr candidates. Pursuit-awareness lives at the entry points (`Acquisition.enqueue/4`, `Acquisition.grab/2`) and at the fallback initiator (`Commands.RecordUserChoice`).

### Append-only event log

`acquisition_pursuit_events` records every meaningful step. The FK to pursuits is `nilify_all` and the pursuit title is denormalised — so events survive pursuit deletion (the pattern set by [`WatchHistory.Event`](../../lib/media_centarr/watch_history/event.ex)).

In-memory representation is a typed struct per kind (one module each under `Pursuits.Events.*`); the DB row stores `kind` + `payload` map. A small `Pursuits.Events.Define` macro generates the struct, the `EventBehaviour` callbacks (`kind/0`, `to_payload/1`, `from_payload/1`), and the type — each event module ends up ~3 lines. The mapping kind ↔ struct module is exhaustive and asserted by a unit test.

`Pursuits.Events.record/1` is the **single write path**: persist + broadcast (the typed struct, not a map) on `acquisition:updates`. Subscribers always receive structs; cold replays from the DB rebuild the struct via `from_payload/1` so on-disk shape never leaks into UI or downstream code.

### Hybrid autonomy via pure Policy + commands + workers

The architectural shape is `Snapshot → Policy → Action → Command`:

- **`Pursuits.Snapshot`** — value object. Frozen view of a pursuit's world (pursuit, latest grab, queue state, now).
- **`Pursuits.Snapshots.build/1`** — the only assembler. Reads sideways into `QueueMonitor` and the latest grab.
- **`Pursuits.Policy.evaluate/1 :: Snapshot.t() -> Action.t()`** — pure. No I/O, no DB, no PubSub. Fully unit-tested with constructed snapshots before any worker exists.
- **`Pursuits.Action`** — discriminated union (`:no_action | {:auto_cancel, _} | {:request_decision, _} | {:satisfy, _} | {:exhaust, _}`).
- **`Pursuits.Commands.<Verb>`** — one command module per verb. Each `execute/1` wraps work in `Repo.transaction/1`, calls `Events.record/1` for state changes, returns `{:ok, pursuit} | {:error, _}`.
- **`Pursuits.Watcher`** (Oban cron, every 15 min) — orchestrator only. Reads active pursuits, builds snapshots, asks `Policy`, dispatches to commands. Zero domain logic.

The hybrid autonomy split — *auto for safe, user for taste* — is encoded in `Policy`'s output: safe cases (zero seeders) emit `{:auto_cancel, reason}`; taste cases (slow but progressing, multiple plausible alternatives) emit `{:request_decision, prompt}`. The Watcher dispatches identically for both — only the command differs.

### v1 scope and explicit deferrals

`Policy` v1 implements only the **exhaustion** rule (`attempt_count ≥ 4 AND pursuit older than 6 days → {:exhaust, :max_attempts}`), since exhaustion is well-defined from the pursuit row alone. Stall and zero-seeder rules require sliding-window observations the system does not yet persist; they are deliberately deferred. The architectural shape is in place — adding the rules later is purely additive (add fields to `Snapshot`, add cases to `Policy.evaluate/1`, add dispatch clauses to `Watcher`).

Manual fallback handling — user opens a pursuit detail page, picks an alternative, `Commands.RecordUserChoice` resumes the pursuit — is the v1 user surface for the trouble cases not yet auto-detected.

Identity verification (post-download `TitleMatcher` recheck on the actual filename, routing mismatches to Review) is also deferred to a follow-up — it requires hooking `Library.Inbound`, which itself is mid-refactor.

Threshold values (`max_attempts`, `min_age_days`) are hardcoded module attributes in `Pursuits.Policy`. Making them configurable via `Settings` is left as a follow-up — `Snapshot` is the obvious place for them so `Policy` stays pure.

### Architectural rules (non-negotiable)

These rules are enforced by the codebase shape and by `mix precommit`:

1. **One module, one responsibility.** Every moduledoc states a single responsibility with no "and" in the sentence.
2. **Cross-module communication via value objects.** Pure modules accept typed structs; they never reach sideways into other contexts.
3. **One write path per fact.** All pursuit lifecycle events go through `Pursuits.Events.record/1`.
4. **Commands over conditional helpers.** Each side-effectful transition is its own `Pursuits.Commands.<Verb>` module.
5. **Workers orchestrate; commands execute.** Workers contain zero domain logic.
6. **Policy is pure.** No I/O, no DB reads, no PubSub. Unit-tested with constructed snapshots.
7. **Component attrs are typed.** UI components consume `attr :vm, ViewModel.t()` — never bare maps.

### Rejected alternatives

- **Per-grab event log** (no aggregate). Rejected because the user has no thread connecting "we tried X, it failed, we tried Y, that one worked" — the explicit product requirement.
- **Persisting candidates from the first search** so fallback pops the next-best. Rejected: candidates go stale (a release with 0 seeders today might have many tomorrow), and we'd cache results we never use. Re-search on each fallback (excluding the tried list) keeps the data model simple.
- **Library entity FK on Pursuit**. Rejected because a pursuit exists *before* any library entity does — entity creation is the *outcome* of a satisfied pursuit, not a prerequisite for one.
- **Free-form `payload` map for events** (no typed structs per kind). Rejected because it forced subscribers to know the on-disk shape and made compile-time field-name checks impossible. The `Define` macro keeps each kind ~3 lines so the cost of adding kinds stays low.
- **Stall detection at the Watcher**. Rejected because it would put domain logic in a worker. Stall detection (when added) goes in `Snapshots.build/1` (impure assembler) so `Policy` can see a `stall_observed?: true` flag and stay pure.

## Consequences

* Good, because the user gets a coherent per-goal timeline that survives multiple grab attempts and re-arms.
* Good, because `SearchAndGrab` doesn't need to learn about pursuits — exclusions are denormalised onto its grab row.
* Good, because the Snapshot/Policy/Action/Command shape is testable end-to-end with constructed values, no mocks needed.
* Good, because every typed-event broadcast is also a persisted DB row — the timeline UI and the live PubSub subscription read the same source of truth.
* Bad, because the v1 scope is honest about what isn't implemented yet (stall, zero-seeders, identity verification) — the user-visible value lands in increments rather than as one complete story.
* Bad, because `acquisition_grabs` now has a nullable `pursuit_id` until legacy rows are backfilled (no backfill is planned; legacy grabs render as single-attempt rows).
