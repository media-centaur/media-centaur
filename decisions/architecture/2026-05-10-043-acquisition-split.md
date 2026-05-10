---
status: accepted
date: 2026-05-10
---
# Acquisition split — extract Downloads and Search as sibling contexts

## Context and Problem Statement

`MediaCentarr.Acquisition` has grown to **76 files** across three
distinct responsibilities that share a single boundary:

1. **Search** (~12 files) — Prowlarr API client, query builder /
   expander, title matcher, search results, quality classifier,
   search session. *Stateless / read-only with respect to the
   download lifecycle.*
2. **Grab + Pursuits** (~46 files) — the `Grab` schema and its
   `searching → snoozed → grabbed | abandoned | cancelled` lifecycle,
   the `SearchAndGrab` Oban worker, auto-grab policy / service /
   settings, plus the entire `Pursuits` subsystem
   ([ADR-039](2026-05-07-039-acquisition-pursuits.md)) — pursuit
   aggregate, watcher, observations, timeline events, identity
   verifier, commands. *Owns the durable acquisition lifecycle.*
3. **Downloads** (~10 files) — qBittorrent driver + dispatcher,
   `QueueMonitor`, `QueueItem`, `QueueState`, `QueueStatus`,
   `Health`, `HealthHistory`. *Talks to the running download client,
   exposes queue snapshots, is consumed by Pursuits + Web.*

Three forces push for a split:

* **Boundary mismatch** — the three clusters do not share
  vocabulary or state. A change to `Health.classify/3` should not
  require rereading anything about `Pursuit.State`. A new download
  client driver should not need awareness of the grab lifecycle.
* **Vestigial dependency** — the boundary declares
  `deps: [MediaCentarr.Library, ...]`, but zero code in Acquisition
  references the `Library` module. The dep was inherited and never
  cleaned up. It's a small symptom of a bigger missing-line-item:
  the boundary stopped describing the actual coupling some time ago.
* **Cognitive load on contributors** — a fresh contributor (or a
  fresh agent context) scanning a 76-file module spends most of its
  budget figuring out which files matter for the task at hand. The
  pursuits subsystem is well-documented internally but its location
  *inside* a context named "Acquisition" obscures that the
  acquisition facade is a thin Prowlarr-facing layer over a much
  deeper aggregate.

The desktop-rearchitecture campaign Workstream B captured this as
"Pillar 1 partition + Pillar 3 re-routing — separate the grab /
download path from Library writes." Investigation showed there are
no Acquisition-to-Library writes to separate; the real opportunity
is the sub-context split itself.

## Decision Outcome

Chosen option: **extract `MediaCentarr.Downloads` and
`MediaCentarr.Search` as sibling contexts to `MediaCentarr.Acquisition`,
in two phased rollouts. Pursuits stays inside Acquisition for now.**
Each phase ships independently and leaves the boundary tree in a
correct state.

### Target boundary tree

```
MediaCentarr.Search           (new)  — stateless Prowlarr-facing layer
MediaCentarr.Acquisition      (slim) — grab lifecycle + pursuits aggregate
MediaCentarr.Downloads        (new)  — download-client integration
```

Boundary deps:

```
Search        → Capabilities, Settings
Downloads     → Capabilities
Acquisition   → Search, Downloads, Capabilities, ReleaseTracking, Settings
```

### File movements

**Search:** `prowlarr.ex`, `search_provider.ex`, `search_result.ex`,
`search_session.ex`, `query_builder.ex`, `query_expander.ex`,
`title_matcher.ex`, `quality.ex`, `quality_window.ex`. *No DB
schema; all values are runtime structs.*

**Downloads:** `download_client.ex`, `download_client/dispatcher.ex`,
`download_client/qbittorrent.ex`, `download_client/qbittorrent/sync.ex`,
`queue_item.ex`, `queue_monitor.ex`, `queue_state.ex`,
`queue_status.ex`, `health.ex`, `health_history.ex`. *No DB schema
— `QueueItem` is a struct, monitoring state lives in `QueueMonitor`'s
GenServer + `:persistent_term`.*

**Acquisition (remaining):** `grab.ex`, `grab_status.ex`,
`auto_grab_policy.ex`, `auto_grab_service.ex`,
`auto_grab_settings.ex`, `cancel_reasons.ex`, `config.ex`,
`jobs/search_and_grab.ex`, `reactor.ex`, plus the entire `pursuits/`
subtree (29 files). View-models stay co-located with their consumer
context.

### Rollout phases

Each phase ends with `mix precommit` green and is independently
shippable.

**Phase 1 — Extract `Downloads`.** Smallest, cleanest cluster.
QueueMonitor is the only stateful piece; it moves with its
supervisor child registration. External callers
(`MediaCentarrWeb.AcquisitionLive`, `Pursuits.Snapshot`,
`Pursuits.Observations`, etc.) update their aliases. Validates the
split pattern before bigger moves.

**Phase 2 — Extract `Search`.** Larger module count but no
stateful pieces and no DB schema. `Prowlarr` and friends move
together. `Acquisition.SearchAndGrab` and `Acquisition.grab/2`
become callers of `Search.*` instead of internal users.

**Phase 3 — Clean up Acquisition boundary.** Drop the now-unused
`Library` dep. Re-export only what `Pursuits.*` consumers actually
need. The 30-file pursuits subtree stays; the cognitive-load case
for a fourth context is weaker once the other two are out.

**Phase 4 — (optional, not in scope of this ADR)** Promote Pursuits
to a top-level context if the case becomes compelling after the
first three phases land. Postponed because:

* Pursuits' identity is "the goal aggregate over grab attempts" —
  it is intrinsically about acquisition, not a sibling concern.
* Pursuits depends heavily on `Acquisition.Grab` and `GrabStatus`;
  promoting it would force an additional context-cross every time
  the grab lifecycle is read.
* The Pursuits subtree is internally well-organised
  (commands / events / pursuit / state / observations) and its
  scale is justified by [ADR-039](2026-05-07-039-acquisition-pursuits.md)
  — it isn't sprawl needing a split, it's depth.

### PubSub topic implications

No source-topic changes in Phases 1-3. `acquisition:updates`,
`acquisition:queue`, `acquisition:search` stay where they are
emitted. Open question deferred to a follow-up: rename
`acquisition:queue` → `downloads:queue` and `acquisition:search` →
`search:results` once consumers settle. Renaming is a separate PR
class (cross-cutting, no behavioural change) and would benefit from
a stable destination first.

`Topics.acquisition_*` getters become slightly misnamed for the new
boundaries (`Downloads` owns `Topics.acquisition_queue/0`). The
moduledoc gains a note pointing at the rename follow-up. Cosmetic;
acceptable.

### Consequences

* Good, because each new boundary describes one job: Search has no
  durable state, Downloads has no Prowlarr knowledge, Acquisition
  becomes a coherent grab + pursuit context.
* Good, because the vestigial `Library` dep on Acquisition gets
  dropped as part of Phase 3 — the boundary will accurately describe
  coupling for the first time in a while.
* Good, because new contributors (and fresh agent contexts) can
  load only the cluster they need: ~12 files instead of ~76 for a
  Prowlarr-driver change, ~10 files instead of ~76 for a queue
  driver tweak.
* Good, because the phased rollout means each PR is reviewable in
  one sitting — Phase 1 moves 10 files, Phase 2 moves ~12, Phase 3
  is dep + export hygiene.
* Bad, because cross-context aliases multiply: code that today
  writes `Acquisition.QueueItem` will write `Downloads.QueueItem`.
  Every consumer-side LiveView / component / test gains a new
  alias line. Estimated ~30 files touched per phase (mostly
  one-line alias swaps).
* Bad, because the `Topics.acquisition_*` getter names become
  slightly misleading after Phase 1 (Downloads owns
  `acquisition_queue/0`). Mitigated by a moduledoc note;
  fixed properly in a follow-up rename PR.
* Bad, because module names with the `Acquisition.` prefix are
  embedded in journaled / persisted state in a few places —
  Oban job worker module references (`SearchAndGrab` is in `jobs/`
  and stays in Acquisition, so this is contained) and the
  `acquisition_grabs` / `acquisition_pursuits` table names (which
  do **not** rename — DB names are independent of module
  hierarchy).
* Neutral, because boundary enforcement (Mix compiler via
  `Boundary`) will catch any forgotten alias path. Compilation
  failures in CI are the safety net.

### Out of scope

* **Renaming `acquisition_*` PubSub topics.** Deferred to a
  follow-up. Stable destination first.
* **Splitting Pursuits into its own context.** Phase 4 is parked
  pending real evidence it's needed.
* **Renaming DB tables.** `acquisition_grabs` and
  `acquisition_pursuits` keep their names regardless of module
  reshape; table names are durable contracts and renaming them
  requires a data migration with no offsetting benefit.
* **View-model relocation.** View-models stay co-located with
  their consumer (web) context — they were originally placed in
  Acquisition to be exported across the boundary, but moving them
  to `MediaCentarrWeb.*` is a separate concern that doesn't gate
  the boundary split.

## Notes

* Filed under desktop-rearchitecture campaign Workstream B.
* Supersedes the workstream's underspecified "Pillar 1 partition +
  Pillar 3 re-routing" framing — investigation showed the real
  opportunity is the context split, not a storage partition (the
  schemas are already separately namespaced) and not a PubSub
  reshape (the topics can be renamed later as a cosmetic
  follow-up).
