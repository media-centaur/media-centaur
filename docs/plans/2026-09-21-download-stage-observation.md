# Design: the stage a download reached is observed, not inferred

Written with the `unify_design` pass: strip to the core idea, design the slice
greenfield, diff against the code, decide every incoherence, name the cost.
**Status: built 2026-09-21.**

Occasioned by a live defect: immediately after a grab, a pursuit reads
**"Downloaded — Finished downloading"**, then flips to "Downloading" once the
download client picks the release up. The flicker is the symptom; the
enumeration below is the diagnosis.

## Glossary

Terms defined before first use. One concept per sentence.

* **Target** — one grab attempt of one release. `TargetUnit`'s moduledoc is
  explicit: a target is *one release*, and one release may cover many units (a
  season pack). So one target is exactly one download at the client.
* **Hand-off** — Prowlarr accepting a grab, or the user picking a release. The
  moment `Target.status` becomes `acquired`.
* **Queue snapshot** — `QueueMonitor`'s cached list of `%QueueItem{}`, refreshed
  every 10 s while a LiveView watches, 30 s idle.
* **Pairing** — deciding which queue item is a given target's download.
  `QueueMatcher.find_item/4` is the declared single predicate.
* **Observation** — a recorded fact about a target's download read from a queue
  snapshot. Durable.
* **Telemetry** — the live figures on a queue item (progress, ETA, health).
  Ephemeral; meaningful only while the item is present.
* **Stage** — how far a target's download has got: handed off → at the client →
  left the client → in review → in the library. Ordered and monotonic.

The defect in one sentence, in these terms: *stage is inferred from telemetry
presence, and telemetry absence is not evidence.*

## Part 1 — The enumeration

### A. Where `acquired` is written

| # | Site | Meaning |
|---|---|---|
| A1 | `Jobs.PursueTarget.grab_found/5` → `Target.acquire_changeset/5` | Prowlarr returned `:ok` to the grab |
| A2 | `Commands.PickTarget` → `Target.acquired_changeset/2` | the user picked a release |

Neither means the download client has the item. Neither calls
`Acquisition.poll_queue_now/0`, so the UI additionally waits up to one
`QueueMonitor` cadence (10–30 s) after the client *does* have it.

### B. Where stage is decided for display

| # | Site | Inputs |
|---|---|---|
| B1 | `PursuitStatus.derive/4` | pursuit state, unit decision flag, target status, queue item |
| B2 | `PursuitStatus.derive/6` → `derive_held/6` | + `IntegrationAvailability.up?(:prowlarr)` |
| B3 | `PursuitStatus.derive/6` → `derive_located/5` | + `:in_review` from `Pursuits.download_location/2` |
| B4 | `Pursuits.build_row/7` | calls B1–B3 with `queue_item = nil`, **always** |
| B5 | `PursuitRow` component | hides the status line when a download is paired at render |

B4 is deliberate (the row must not depend on `QueueMonitor` cadence) and
correct as far as it goes; B5 covers it while a torrent is live. Neither
covers the window this defect lives in.

### C. The offending clause

`pursuit_status.ex:216` — `acquired` + no queue item:

> **"Downloaded"** — "Finished downloading — still importing, or already in
> your library."

Three distinct realities reach it:

1. **Hand-off just happened.** The client has not registered the item, or the
   cached snapshot has not caught it. ← the reported defect.
2. **The download never arrived.** Prowlarr said `:ok`, nothing appeared at the
   client, ever. No `Policy` rule covers this, so the pursuit displays
   "Finished downloading" **permanently**. `priv/guide/pursuits.md` even has a
   section for diagnosing this case — while the status line asserts the
   opposite.
3. **The download finished** and the client dropped it. The only case the copy
   is right about — and largely already handled elsewhere (`:in_review`,
   `LibraryReconciler` → satisfied).

### D. What records observation today

| # | Fact | Owner | Written by | Fit |
|---|---|---|---|---|
| D1 | `Target.torrent_hash` | target | grab time **and** first observation | ambiguous provenance — presence proves nothing about observation |
| D2 | `Target.content_path` | target | first observation only | nulled when the path is not visible to this host (`usable_content_path/1`), so nil ≠ unobserved |
| D3 | `Pursuit.last_queue_state` / `last_queue_health` | **pursuit** | `Observations.observe_pursuit!/4` | nil *does* mean unobserved — but on the wrong owner, and see E |

There is no sound per-target "has this download ever been seen at the client".

### E. Incoherences found while enumerating

| # | Incoherence |
|---|---|
| E1 | **Observation lives on the pursuit.** Migration `20260612170000` moved it unit → pursuit to stop a 38-episode pack minting 38 identical `DownloadStarted` rows. It overshot: ADR-055 composites hold *several* torrents at once (`Pursuits.all_downloads/3` renders one bar each), and pursuit-level observation tracks exactly one of them — the latest release title. The correct owner is the **target**: one target = one release = one download, and a pack's 38 units already share one target. |
| E2 | **Two pairing predicates.** `QueueMatcher.find_item/4` is documented as "the single shared matcher"; `Observations.find_queue_item/2` is a second one — exact title equality, no infohash, no prefix tolerance. They disagree on exactly the releases the hash exists to rescue. |
| E3 | **Observation runs on the wrong clock.** The only writer is `Pursuits.Watcher`, cron `*/15 * * * *`. A download that starts and finishes inside 15 minutes is never observed at all. `content_path` capture — which `LibraryReconciler` depends on for its authoritative path match — inherits that 15-minute latency. |
| E4 | **`DownloadStarted.infohash` is always `nil`.** The event has the field; the pursuit-scoped emitter cannot fill it, because it does not know which torrent it observed. |
| E5 | **Two passes over one pairing.** `Observations.observe_pursuit!/4` and `DownloadIdentity.capture!/3` run back-to-back in the same Watcher tick, pair the same target against the same snapshot (by different predicates, per E2), and write different columns of the same row. |
| E6 | **No `poll_queue_now` after a grab or a pick.** The one moment we *know* the snapshot is stale is the one moment nothing asks for a fresh one. |

## Part 2 — The core idea

> **A target's download passes through an ordered sequence of stages, and the
> stage it has reached is a durable observed fact recorded on the target. Live
> telemetry decorates the current stage; it never defines it.**

The defect follows from violating the second sentence for exactly one hop:
"left the client" is inferred from telemetry absence.

## Part 3 — The greenfield design

### One owner

Every fact about a download belongs on its **target**. Not the unit (N units
share a pack's one target), not the pursuit (a composite has several downloads
in flight).

### One value type — the target's download observation

```
first_seen_in_queue_at :: utc_datetime | nil   # write-once. THE stage fact.
last_queue_state       :: string | nil         # last observed telemetry
last_queue_health      :: string | nil         # last observed telemetry
torrent_hash           :: string | nil         # pairing key (already present)
content_path           :: string | nil         # durable file link (already present)
```

`first_seen_in_queue_at` is the fact that does not exist today. Its absence
after hand-off means *not yet at the client*; its presence plus current absence
means *left the client*. Both are statements of fact, neither is a guess.

### One matcher, one pass, one clock

`QueueMatcher.find_item/4` pairs. One pass per target per queue snapshot does
all of it: pair → stamp `first_seen_in_queue_at` → capture hash/`content_path`
write-once → record `(state, health)` → emit `DownloadStarted` / `HealthChanged`.
`Observations.observe_pursuit!/4` and `DownloadIdentity.capture!/3` collapse
into it (E5).

The clock is the queue snapshot, not the 15-minute cron. `Downloads` cannot
depend on `Acquisition` (Boundary), so the trigger is a thin listener in
Acquisition on `Topics.acquisition_queue()` — the `InboundListener` shape,
seated next to it in the supervision tree.

### One stage function

```
Pursuits.Stage.of(target, queue_item, location, now) :: stage
```

| target.status | first_seen | live item | in review | stage |
|---|---|---|---|---|
| `seeking` | — | — | — | `:seeking` |
| `acquired` | nil | absent | — | `:handed_off` (within window) / `:missing` (beyond) |
| `acquired` | — | present | — | `:at_client` |
| `acquired` | set | absent | yes | `:in_review` |
| `acquired` | set | absent | no | `:left_client` |
| `succeeded` | — | — | — | `:done` |
| `failed` / `cancelled` | — | — | — | `:stopped` |

`PursuitStatus.derive` becomes: overriding conditions first (held, awaiting
decision, `download_client_unavailable`), then one stage → copy mapping. That
collapses the current `derive/4` + `derive/6` + `derive_located/5` +
`derive_held/6` clause soup, which otherwise gains a *fifth* input axis and
gets worse.

New copy, replacing the one lying clause:

* `:handed_off` → **"Sent to <client>"** — "Waiting for it to appear at the download client." (`:info`)
* `:missing` → **"Not at the download client"** — "Prowlarr accepted the grab but nothing arrived." (`:warning`, offers `change_target`)
* `:left_client` → today's "Downloaded — still importing" copy, now actually earned.

The hand-off window is a policy value in `Pursuits.Thresholds`, beside
`stall_window_hours` — not a magic number in a view model.

## Part 4 — Diff against reality, and dispositions

| # | Incoherence | Disposition |
|---|---|---|
| E1 | observation on the pursuit | **fix now** — move `last_queue_state`/`last_queue_health` to the target; expand+backfill migration now, contract next release (the precedent set by `20260612170000` → `20260906190000`, because the running app writes the old columns until it restarts) |
| E2 | two pairing predicates | **fix now** — delete `Observations.find_queue_item/2`, use `QueueMatcher.find_item/4` |
| E3 | 15-minute observation clock | **fix now** — `Pursuits.QueueListener` on `Topics.acquisition_queue()`; also cuts `content_path` latency 15 min → 10–30 s, which `LibraryReconciler` wants |
| E4 | `DownloadStarted.infohash` always nil | **fix now** — free once the emitter is target-scoped |
| E5 | two passes over one pairing | **fix now** — fold `DownloadIdentity` into `Observations`; delete the module (no compatibility shim, per CLAUDE.md) |
| E6 | no poll after grab/pick | **fix now** — one line each in `grab_found/5` and `PickTarget` |
| E7 | nothing ever resolves a `:missing` target | **scheduled convergence** — a `Policy` rule (`handed off, never observed, window elapsed → {:request_decision, …}`) needs its own threshold decision and tests. Convergence point: next acquisition change. Until then the state is *displayed honestly* and the user can `change_target`, which is the same recovery the rule would offer. |
| E8 | the stall/zero-seeder windows were unit columns | **fixed now** (found during the build) — same incoherence as E1 one level down. They are readings of one download, so an N-unit pursuit wrote N identical rows per tick and could disagree with itself mid-pass. Moved to the target; `Snapshots.build/4` already held it, so `Policy` reads them unchanged. |

No orphans: every column, module, and clause the greenfield design replaces is
deleted in the same change.

## What was built

| Piece | Where |
|---|---|
| The stage fact and the windows | `Target.first_seen_in_queue_at`, `last_queue_state`, `last_queue_health`, `stall_first_seen_at`, `zero_seeders_first_seen_at`; `Target.observation_changeset/2` + `window_changeset/2`, both no-ops when nothing moved |
| One stage function | `Pursuits.Stage.of/4` — ten stages, evidence before inference |
| One page-level read | `Pursuits.StatusContext` — clock, hand-off window, hold, queue and its grade, review membership, read once |
| Absence-is-not-evidence | `QueueState.answering?/1`, the one place a connectivity grade becomes a yes/no |
| One observation pass | `Pursuits.Observations.observe!/4` — `DownloadIdentity` folded in and deleted |
| On the client's clock | `Pursuits.QueueListener` on `Topics.acquisition_queue/0`; the Watcher decides and no longer observes |
| Copy from stages | `PursuitStatus.derive/6` — one arity, overriding conditions then a stage→copy map |
| A fresh snapshot when we know it's stale | `QueueMonitor.poll_now/0` after a grab and after a manual pick |

## Part 5 — The cost, honestly

One migration (3 columns added to `acquisition_targets`, 2 dropped from
`acquisition_pursuits`, backfilled), one new GenServer + supervision entry, two
modules merged and one deleted, `PursuitStatus.derive` restructured around
`Stage`, two one-line call sites, `Thresholds` gains a value. Plus tests
(`Observations`, `Stage`, `PursuitStatus`, listener wiring, `Watcher`
removal), Storybook variations for the two new states (MC0009 enforces this),
and `priv/guide/pursuits.md` + wiki copy. Estimate: one focused session,
possibly spilling into a second.

The migration is a single expand+backfill+drop rather than the expand/contract
pair used at `20260612170000`. That precedent existed because the migration was
hand-applied to a shared DB while the old code still ran; releases apply
migrations at boot on the new code, so there is no window, and CLAUDE.md's
no-compatibility-layers rule applies. The dev service is restarted as part of
the change.

**Always-on cost ledger** (the new listener):

| Path | Trigger | Cost |
|---|---|---|
| Queue snapshot, active targets present | 10 s watched / 30 s idle | one indexed query (typically 0–20 rows) + in-memory pairing |
| First observation of a target | once per target, ever | one `UPDATE` + one `DownloadStarted` event row |
| Telemetry transition | a handful of times per download's life | one `UPDATE` + one `HealthChanged` event row |
| No active targets | 10–30 s | one `exists?` returning false; pass skipped |

Steady-state downloading with unchanged health writes nothing. Writes land on
the main DB, bounded by transitions rather than by ticks — the constraint
recorded in the SQLite-busy note is respected.
