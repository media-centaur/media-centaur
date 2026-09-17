# Availability: held work for metered integrations — design

Date: 2026-09-17. Campaign: `campaigns/recurring-traffic-audit.md`.
Status: approved by the owner 2026-09-17 (both decisions below taken as
recommended). Implementation plan: `docs/superpowers/plans/2026-09-17-availability-plan.md`.

## Problem

Every recurring request the app makes on its own runs at a fixed rate
whatever the answer is. Measured on 2026-09-17 during a real outage of
Prowlarr's link to SABnzbd: each pursuit retried a doomed grab every
15 minutes and re-ran a live indexer search every 30 minutes, N
pursuits with no shared memory of the answer; the release tracker
re-planned every young want through the dead link every 30 minutes;
the Incoming page and the corpus re-probed Prowlarr every 30 seconds
with no memory of the last answer. The owner's principle for the fix:
treat each source by what a request **costs**. Free integrations may
poll at any cadence. Metered ones must never be asked to learn what a
free probe could tell.

## Core idea

Every metered outbound request is preceded by a free question — is the
integration up right now? — answered from one published availability
value per integration that free probes keep current. Work whose
integration is down is held, not attempted, and resumes on the first
good probe.

## Glossary

- **Integration** — a server the app talks to on its own: Prowlarr (and
  the indexers behind it), a download client, TMDB and its image CDN,
  GitHub, a Nostr relay.
- **Hand-off** — Prowlarr's own link to a download client, which the
  app cannot see directly. It fails as HTTP 500
  `DownloadClientUnavailableException` on a grab. One per download-client
  slot: `{:handoff, :usenet}`, `{:handoff, :torrent}`.
- **Metered integration** — counts requests against a limit or escalates
  a back-off when hit repeatedly. **Free integration** — does neither;
  its only cost is log noise.
- **Probe** — a free request whose only purpose is to learn whether a
  integration can do the job.
- **Availability** — the published answer per integration: `:up`, or
  `{:down, since, reason}`. The code's name for what the campaign
  called the circuit.
- **Held work** — a job or tick that consulted availability, found its
  integration down, and waits without spending a request.
- **Watched / idle cadence** — the queue monitor's 10 s poll while a
  page subscribes, 30 s otherwise. Unchanged by this design.

## Cost classes

| Integration | Class | Treatment |
|---|---|---|
| Download clients (LAN) | free | Polling unchanged, outage included. Log noise reduced to transitions. |
| Prowlarr live searches | metered, × indexers | Held while Prowlarr is down or blind. |
| Prowlarr grabs | free on a failed hand-off (Redirect mode, verified), metered on success; metered under Proxy mode | Held while the hand-off for the release's protocol is down. |
| TMDB API and image CDN | metered | Tracking refresh and artwork warm hold while TMDB is down. Refresh cadence untouched (deferred campaign). |
| GitHub | metered, small | Unchanged; a failed check retries on the 15-minute cron, within budget. |
| Nostr relays | metered | Unchanged; already backed off exponentially. |

Only four integrations gate metered work: `:prowlarr`,
`{:handoff, :usenet}`, `{:handoff, :torrent}`, `:tmdb`.

## Greenfield design

### The availability value

```
%MediaCentaur.IntegrationAvailability.Status{
  integration: :prowlarr | {:handoff, :usenet | :torrent} | :tmdb,
  state: :up | {:down, since :: DateTime.t(), reason :: atom()},
  observed_at: DateTime.t()
}
```

- Runtime-only, in `:persistent_term`, one entry per integration, like
  `IndexerHealth` and `QueueState`. Nothing durable: a restart starts
  `:up` and the first request or probe corrects it.
- **One writer per integration**: the module that owns the client.
  `Search.Prowlarr` writes `:prowlarr` (from every request outcome and
  from `IndexerHealth` observations) and both hand-offs (from grab
  outcomes and the hand-off probe). `TMDB.Client` writes `:tmdb`.
  Nobody else calls `report/2`.
- `report(integration, :up | {:down, reason}) :: :unchanged | {:changed, state}`
  writes only on transition, and on transition broadcasts
  `{:integration_availability_changed, integration, state}` on
  `Topics.integration_availability_updates/0`.
- `status(integration)` reads the value. `available?(integration)` is the
  gate: configured **and** up — `Capabilities` stays the configuration
  half (durable, settings-backed, "Test connection" passed);
  availability is the runtime half. One function answers "can I use
  it now", so gate sites never combine the two themselves.

A grab answered with a 5xx that is not the hand-off exception is about
the release, not an outage (review, 2026-09-17): Prowlarr answered, so
`:prowlarr` stays up and the pursuit charges an attempt, paced by the
attempt ladder rather than the probe cadence.

Reasons: `:unreachable` (transport error, 5xx, timeout), `:rejected`
(401/403 — misconfigured is as useless as dead for held work),
`:blind` (Prowlarr answers but every enabled indexer is backed off;
carries Prowlarr's `retry_at`), `:client_unavailable` (hand-off).

### Evidence and probes

| Integration | Opens on | Probe while down | Cadence | Closes on |
|---|---|---|---|---|
| `:prowlarr` | any Prowlarr request failing at transport, 5xx, 401/403; an `IndexerHealth` observation of `:unreachable` or `:blind` | the indexer roster read (`IndexerHealth.check/0`), free | 60 s; for `:blind`, at Prowlarr's own `retry_at` when it is later | any successful Prowlarr request; a roster read that is `:ok` or `:degraded` |
| `{:handoff, slot}` | a grab answered with `DownloadClientUnavailableException` for a release of that protocol | `GET /api/v1/downloadclient` + `POST /api/v1/downloadclient/testall`, free (12 ms, verified) — the slot is down when Prowlarr's enabled client of that protocol is invalid; a slot Prowlarr has **no** enabled client for reads up (no link to be broken; a grab then fails with Prowlarr's real answer). The probe never decides `:prowlarr` — a test-all timeout is about the client. | 60 s | a valid probe result for the slot; any successful grab of that protocol |
| `:tmdb` | transport error, 5xx, 429 | the cheapest TMDB call (`GET /configuration`), metered but one request | 5 min | any successful TMDB request, including a user-initiated one |

The probe is an Oban job per owning context — `Search.ProbeJob` for
`:prowlarr` and the hand-offs, `TMDB.ProbeJob` for `:tmdb` — on the
`:maintenance` queue, `unique` per integration. The owner module
enqueues it when `report/2` answers `{:changed, {:down, _}}`. The job
probes, reports, and `{:snooze, cadence}` while still down; it
completes when the integration is up. While up there is no probing: the
real requests are the evidence. Oban is the timer because it already
is one; no new process (Iron Law).

### Held work

| Site | Today | With availability |
|---|---|---|
| `Jobs.PursueTarget`, search step | searches, then snoozes 1 h on a Prowlarr error without charging | if `not available?(:prowlarr)`: `{:snooze, 60}`, no request, no attempt charged, no stamp |
| `Jobs.PursueTarget`, grab step | grabs, then snoozes 15 min on a hand-off failure without charging | if `not available?({:handoff, protocol})`: `{:snooze, 60}`, no request. The first pursuit to hit the outage still grabs once — that grab is the evidence that opens the hand-off |
| `Plans.CommitPlan` grab, then the pursuit's grab | two grabs of the same release in one second | the plan's failed grab opens the hand-off; the pursuit's grab step finds it down and holds. Defect 2 closes by construction |
| `Jobs.RunPlan` | searches; an error marks the plan and leaves it `ready` | `{:snooze, 60}` at entry while `:prowlarr` is unavailable; the plan stays in its searching state and the board's gap verdict reads the availability reason (the `:blind` verdict already exists) |
| `DropPlanner` tick | gated on `Capabilities.prowlarr_ready?/0` (configuration only) | gated on `available?(:prowlarr)`; a held tick creates no plans; wants stay open |
| `Corpus.blind?/0` | a roster read after every zero-result search | unchanged (free, and the moment-of-truth check for negative knowledge), but its observation is reported, so it also opens `:prowlarr` |
| `IncomingLive` 30 s loop | roster read every 30 s per open page, no memory | while `:prowlarr` is down the page reads `status/1` instead of probing — the probe job owns probing while down. While up the free read stays |
| `Refresher` tick | 6 h, fixed; per-item errors skipped | at tick, if `not available?(:tmdb)` reschedule in 5 min; mid-cycle, each item checks before fetching so one transport failure ends the cycle's TMDB traffic. Image backfill rides the same gate |
| `TmdbArtwork.ensure/2` on mount | fetches | returns the on-disk answer only while `:tmdb` is down |
| Queue monitor | polls; two warnings per failed poll | polls unchanged; one warning when a slot's grade leaves `:live`, one info when it returns; per-poll failures at debug |

Held Oban jobs snooze at the probe cadence: a snooze is a database
write, free, and it bounds recovery to one cadence. No wake machinery
for jobs. Oban 2.24 does not charge `max_attempts` for a snooze.

### Recovery

`{:integration_availability_changed, integration, :up}` on `Topics.integration_availability_updates/0`:

- `Acquisition.Reactor` — `:prowlarr` up runs a drop-planner tick at
  once, so wants held through the outage are planned within seconds,
  not at the next 15-minute sweep.
- `ReleaseTracking.Refresher` — `:tmdb` up runs a deferred cycle now.
- `IncomingLive`, `StatusLive` — re-render.

Hand-off recovery needs no subscriber: held pursuits are snoozing and
run within 60 s.

### What the user sees

- **A held pursuit** reads *Waiting — Prowlarr is unreachable* or
  *Waiting — Prowlarr could not reach your download client*, with no
  "next attempt" time (it resumes on recovery, not on a clock). The
  copy source moves from the target's last-outcome stamp to the
  availability value, passed into the pure view-model
  (`ViewModels.PursuitStatus`). The stamp stays as history.
- **A held plan** shows the existing blind verdict with the
  availability reason.
- **Status, Downloads tile**: the existing warning *Prowlarr could not
  hand releases to the download client* now comes from
  `{:handoff, slot}` being down past the grace window, not from a
  30-minute window over grab stamps; it clears the moment a probe
  succeeds.
- **Status, Connections tile**: rows for Prowlarr and TMDB show *down
  since HH:MM* while unavailable.
- **Status, Needs attention**: the search-provider incident persists as
  long as the probe says down (see decision 2).

## Diff against the code

**Seams reused as they are.** `HttpClient.Upstream` ids for the
upstream integrations; `Search.Prowlarr` as the single Prowlarr call
site (search, grab, roster, download clients) and
`Prowlarr.grab_outage?/1` as the hand-off classifier; `SearchResult.protocol`
to pick the slot; `IndexerHealth` as the Prowlarr observer with its
states and `retry_at`; `Corpus.search/2` as the one search entry for
both jobs; `Capabilities.*_ready?` as the configuration half;
`Acquisition.Reactor` for PubSub-driven ticks; `GapVerdict` `:blind`
for the plan board; `PursuitStatus` waiting copy; ADR-054 incident
tracks; Oban snooze; the Connections tile.

**State unified.** Three inferences of "is it down" become one value
with one writer each: `IndexerHealth` cache plus `Search.IncidentContext`'s
900 s staleness rule (Prowlarr); grab stamps plus a 30-minute window in
`Pursuits.IncidentContext` (hand-off); nothing at all for TMDB. The
incident contexts become thin readers of `status/1` plus their grace
window. `Downloads.Connectivity` stays as it is: a free integration
with a richer grade the Downloads UI needs.

**Incoherences, decided.**

1. `IntegrationHealth`'s moduledoc says nothing is probed on a schedule.
   After this, free probes run on a schedule while an integration is
   down, and only then. Amend the moduledoc in the same change.
2. `Capabilities` and availability both answer "can I use X" from
   different evidence. Kept as two inputs behind one `available?/1`,
   because one is durable configuration and the other runtime
   observation; folding them would put observations in Settings.
3. `Corpus.blind?/0` remains a per-empty-result roster read while up.
   It is free and it is what keeps an empty result honest; it now also
   reports. Not a duplicate of the probe, which only runs while down.
4. `PursueTarget`'s 1 h Prowlarr-error snooze and 15 min hand-off snooze
   remain for the request that discovers an outage (the evidence
   request). They no longer govern the loop: the next run is held by
   availability. Shorten both to the probe cadence so the discovering
   pursuit is not the slow one.

## Owner decisions (taken 2026-09-17)

1. **Name: `MediaCentaur.IntegrationAvailability`.** First chosen as
   `Availability`; renamed when the review surfaced that
   `MediaCentaur.Library.Availability` already meant "is this entity's
   media file reachable". The owner split the word: that module became
   `Library.MediaFileAvailability`, this one `IntegrationAvailability` —
   "integration" being the codebase's existing word for the external
   servers (`Capabilities.save_integration/2`, `IntegrationHealth`).
   The campaign's "dependency" and "circuit" are retired in favour of
   "integration" and "availability".
2. **Search incident persistence: persist while down.** Today a blind-indexer incident
   auto-resolves after 15 minutes without a fresh observation
   (`@staleness_seconds`), which is why a three-day outage read as
   "nothing wrong" (memory `project-status-indexer-blindness-gap`, an
   item you asked to design together). With the probe keeping the
   observation fresh while down, the staleness rule goes: the incident
   persists exactly as long as the probe says down, and clears within
   one probe of recovery. Confirmed by the owner as the resolution of
   that open item.

## Scope and cost

New: `IntegrationAvailability` (value, store, report, gate, topic) with unit
tests; `Search.ProbeJob` and `TMDB.ProbeJob`; the hand-off probe call
in `Search.Prowlarr`. Changed: gates at five sites, two incident
contexts, `PursuitStatus` copy source, `GapVerdict` reason, `Reactor`
and `Refresher` subscribers, queue-monitor logging, Connections tile,
`IntegrationHealth` moduledoc. Each step test-first; wiki entry per
step. Estimate: five sessions in the campaign's rollout order:

1. `IntegrationAvailability` + `:prowlarr` and hand-off writers + `Search.ProbeJob`
   + `PursueTarget` gates + `PursuitStatus` copy. Wiki: the pursuit
   Waiting entry.
2. `RunPlan`, `DropPlanner`, `Corpus` report, `IncomingLive` loop,
   `GapVerdict`, `Reactor` wake, both incident contexts. Wiki: Prowlarr
   unreachable / no indexers entries.
3. `:tmdb` writer, `TMDB.ProbeJob`, `Refresher` and `TmdbArtwork` gates.
   Wiki: TMDB down entry. Measure a simulated TMDB outage here.
4. GitHub and relays: confirm within budget; no code expected.
5. Queue-monitor log transitions, Connections tile *down since*.

The cheap path — each loop growing its own snooze — was rejected by the
owner on 2026-09-17: it leaves N pursuits probing N times, keeps the
double grab, and pays for recovery with the current step's wait.

## Out of scope, deferred by name

- How often the tracking refresher re-reads TMDB when TMDB is healthy,
  and a negative cache for identities TMDB has no artwork for:
  `project-tmdb-caching-refresh-policy` (owner, 2026-09-14).
- Cancelling an in-flight alternatives search when the user pivots
  pursuits: the request is already out; cancelling saves nothing
  metered.
- Local-only tickers (evaluator, pursuits watcher, cache workers,
  Status vitals, sweeps): verified to make no outbound requests.
