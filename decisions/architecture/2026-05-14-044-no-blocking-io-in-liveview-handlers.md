---
status: accepted
date: 2026-05-14
---
# No blocking external I/O in LiveView mount, handle_event, or handle_info

## Context and Problem Statement

A user reported that clicking a pursuit on `/download` took roughly
half a second to open the detail modal — well beyond the
"instantaneous" feel a LiveView app should offer for a click that
opens an already-fetched row. Investigation traced the latency to
`AcquisitionLive.load_pursuit_detail/1`: when the pursuit was in
`awaiting_decision` state, `build_decision/3` synchronously called
`Acquisition.list_alternatives_for(pursuit)`, which fired a
brace-expanded Prowlarr search across the user's configured indexers
before the LiveView could render. The DB portion of the load took
under 5 ms; the remaining ~495 ms was a network round-trip to
Prowlarr happening *on the WebSocket message handler*.

A LiveView process serialises its own messages — while it is
blocked on a synchronous external call, it can render nothing, react
to nothing, and respond to nothing. The Phoenix heartbeat is the
second-order victim: long-enough blocks (≥ 30 s, e.g. brace-expanded
fan-out across slow indexers) trip the client into long-poll
downgrade. The same module already contained the canonical fix for
this elsewhere — `handle_event("refresh_alternatives", ...)`
intentionally dispatches the Prowlarr call to a
`Task.Supervisor.start_child` and `send`s the result back as
`{:alternatives_refreshed, _, _}`. The modal-open path simply
inherited the synchronous shape from an earlier era of the code and
never caught up.

The user's correct intuition was: "the state is already in memory."
That's true for the *session* (the LiveView process has assigns that
persist across events) but false for two other tiers the click
crossed:

* **Domain state** — Pursuits / Targets / Events live in sqlite, not
  in a GenServer. Every modal open re-reads them. This is cheap
  (sub-ms on a local sqlite file) and is not the bottleneck.
* **External state** — Prowlarr is a separate HTTP service. No
  amount of "stateful process" architecture inside our application
  removes a round-trip to someone else's server.

The rule worth pinning is not about pursuits or about Prowlarr in
particular. It is about the boundary between work the LiveView can
afford to do synchronously and work it cannot.

## Decision Outcome

Chosen option: **forbid synchronous external I/O in LiveView
`mount/3`, `handle_event/3`, `handle_info/2`, `handle_params/3`, and
the helpers they call.** Use `assign_async/3`, `start_async/3`, or a
`Task.Supervisor.start_child` + `send` + `handle_info` round-trip
instead, with a loading placeholder rendered on the first pass.

The rule covers any call whose latency is not bounded by the local
process or a local file. Concretely:

* **Always async.** Prowlarr search, TMDB metadata fetch, qBittorrent
  RPC, any HTTPS call, any file read off a mounted media drive (the
  drive may be slow, remote, or unmounted), any operation that
  internally awaits one of the above.
* **Synchronous OK.** Repo queries on local sqlite, ETS reads,
  `:persistent_term.get/1`, pure functions, view-model assembly,
  PubSub broadcasts to local subscribers.
* **Synchronous OK only when proved.** GenServer `call`s to
  in-process singletons (`QueueMonitor`, `Capabilities`,
  `AutoGrabService`). These are local but can still bottleneck if
  the singleton itself blocks. Document the synchronous call and the
  invariant that justifies it, or use `cast` / a fire-and-forget
  pattern.

### Canonical fix shape

The pattern is already established in this codebase (see
`AcquisitionLive.handle_event("refresh_alternatives", ...)` and its
`handle_info({:alternatives_refreshed, _, _}, _)` partner). Repeat
it:

1. On the synchronous path, assign a placeholder view-model with a
   `loading?: true` flag (or its equivalent) so the template can
   render a spinner / skeleton immediately. Stash the work-in-flight
   identity (pursuit id, item id, query) on the socket.
2. Dispatch the slow work via `Task.Supervisor.start_child(...)`
   under `MediaCentarr.TaskSupervisor`. Inside the task, perform the
   external call and `send(parent, {:slow_work_finished, identity,
   result})`.
3. Add a `handle_info/2` clause that matches the message, checks
   that the identity is still relevant (the user may have closed the
   modal, navigated away, or kicked off a newer fetch), and merges
   the result into assigns. Stale results are dropped silently.

`assign_async/3` and `start_async/3` (Phoenix LiveView 0.20+) are
the higher-level form of the same pattern and are preferred when
the result maps cleanly onto a single assign. Reach for the manual
`Task.Supervisor` + `send` shape when the result needs to land on
multiple assigns atomically or when the message needs a stable
identity-aware drop path.

### Consequences

* Good, because user-perceived latency for modal opens, page mounts,
  and event clicks drops from "the external service's worst case"
  to "the local DB's best case" — single-digit ms on warm caches.
* Good, because the WebSocket heartbeat is never put at risk by
  cumulative blocking time, eliminating the silent long-poll
  downgrade that turns the rest of the page sluggish.
* Good, because the rule is enforceable in code review — "you added
  an HTTP call in `handle_event/3`" is a concrete violation, not a
  judgment call.
* Bad, because every async path requires a loading-state branch in
  the template and a `handle_info/2` partner — more wiring than a
  blocking call, and another place state can drift (stale-identity
  drops). The cost is paid once per call site and is small relative
  to the perceived-latency win.
* Bad, because contributors must remember that "Repo.* is fast on
  sqlite" only holds while we ship sqlite. A future migration to a
  networked DB would move every Repo call into the async-required
  bucket. The ADR will be revisited then; until then, local sqlite
  is the assumption.

### Audit trigger

When reviewing a LiveView change, scan the diff for any of the
following inside `mount`, `handle_event`, `handle_info`,
`handle_params`, or their helpers:

* `Acquisition.search`, `Prowlarr.*`, `Tmdb.*`, `Req.*`, `:hackney`,
  `:httpc`, `HTTPoison.*`, `Finch.*`
* `qBittorrent.*`, `Downloads.DownloadClient.*` writers
* `File.read`, `File.stat`, `File.ls`, `Path.wildcard` against a
  configured media path (the local-FS exception covers `_build/`
  and `tmp/`, not user-configured drives)
* Anything that internally calls one of the above

Any match → the path must be moved off the LiveView process. The
fix shape is the canonical Task.Supervisor + send loop above.
