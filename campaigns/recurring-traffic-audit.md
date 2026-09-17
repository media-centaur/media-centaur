---
status: planning
started: 2026-09-17
last_updated: 2026-09-17
---
# Recurring outbound traffic audit

## Goal

Every recurring request the app makes on its own — polls, retries,
refreshes, scheduled ticks — should stop, slow, or coalesce when the
thing it talks to cannot answer usefully, and resume the moment it can.
Today most of them run at a fixed rate whatever the answer is. The case
that opened this: with Prowlarr unable to hand releases to SABnzbd, two
pursuits will each retry a doomed grab every 15 minutes and re-run
their indexer searches every 30 minutes, indefinitely, by design of the
fit-first campaign's decision 5 (an outage never exhausts). Correct, and
wasteful. The audit finds every source of recurring traffic, measures
what it does during an outage, and gives each one logic that fits.

## Glossary

- **Recurring traffic** — a request the app issues without a person
  asking at that moment: a poll, a retry, a refresh, a scheduled tick.
- **Dependency** — the server a request goes to: Prowlarr (and behind
  it the indexers), a download client, TMDB and its image CDN, GitHub,
  a Nostr relay.
- **Outage** — a dependency that is reachable but cannot do the job
  (Prowlarr answering 500 on grabs), or not reachable at all.
- **Back-off** — retry spacing that grows with consecutive failures, to
  a cap.
- **Circuit** — a per-dependency switch: while the dependency is known
  down, requests that need it are held, not sent; the first success (or
  a probe) closes it again.
- **Coalescing** — many callers with the same need against one
  dependency make one request, not N.
- **Recovery wake** — resuming held work from a recovery signal instead
  of the next scheduled poll.

## Status

Planning, 2026-09-17. Nothing measured yet beyond the evidence below.
Opened at the close of `fit-first-search-order` (its spec:
`docs/superpowers/specs/2026-09-17-planning-descent-design.md`).

## Evidence so far (2026-09-17)

- Pursuit retry after a hand-off outage: `Jobs.PursueTarget` snoozes 15
  minutes without charging an attempt (`@download_client_snooze_seconds`),
  and the corpus keeps a term fresh for 30 minutes
  (`Corpus` `@freshness_window_minutes`). Per pursuit: 4 grab attempts
  and 2 rounds of 2–3 live indexer searches an hour, for as long as the
  outage lasts. Two tracking-born movie pursuits (Tony, The End of Oak
  Street) will do exactly that from 21:39 CEST. N pursuits multiply it;
  nothing ties them to the one dependency that is down.
- Queue monitor: polls each download client every 10 s. During the
  morning's stack rework the log ring held a warning every 10 s for six
  minutes ("sabnzbd request failed — 403 API Key Incorrect"), then
  `econnrefused` every 10 s until the stack came back. The polls feed
  `Downloads.IncidentContext` (three minutes' grace) — the cadence is
  right for a live client and pointless against a dead one.
- Prowlarr search errors already back off (`handle_prowlarr_error`,
  one hour, no bump) and the corpus refuses to record an outage as fresh
  negative knowledge. That is the mature end of today's spectrum.
- Prowlarr escalates an indexer's own back-off from 60 s to 15 min under
  repeated failure and it persists — so app-side retries against a
  backed-off indexer make the back-off worse (memory:
  `reference-prowlarr-search-api-facts`).

## Inventory to audit

Fixed-rate today unless noted. Measure each during (a) a healthy day and
(b) a simulated outage of its dependency; record requests/hour on the
Status **Connections** tile, which already counts them per server.

| Source | Dependency | Cadence today | Where |
|---|---|---|---|
| Pursuit retry after outage | Prowlarr → client | 15 min, no cap | `Jobs.PursueTarget` |
| Pursuit retry, no acceptable release | Prowlarr/indexers | 4h → 24h, 12 attempts (Settings) | `Jobs.PursueTarget` |
| Corpus re-search | Prowlarr/indexers | every term older than 30 min on any consult | `Acquisition.Corpus` |
| Queue monitor poll | download clients | 10 s per client | `Downloads.QueueMonitor` |
| Tracking refresh | TMDB | per `RefreshSchedule` | `ReleaseTracking.Refresher` |
| Drop planner tick | Prowlarr (via plans) | per tracking sweep; `WantSchedule` gates each want | `Acquisition.DropPlanner` |
| Pursuits watcher | local + clients | every 15 min (Oban cron) | `Pursuits.Watcher` |
| Indexer health check | Prowlarr | on Incoming mount / async | `Search.IndexerHealth` |
| Subsystem evaluator | local | every 5 min (Oban cron) | `ErrorReports.EvaluatorJob` |
| Update check | GitHub | 15-min tick, gated by the user's interval | `SelfUpdate.CheckerJob` |
| Nostr relay | relays | reconnect with back-off (already) | `Nostr.Connection` |
| Artwork / image fetch | TMDB image CDN | on demand + pipeline | `TmdbArtwork`, image pipeline |
| Cache workers | local | interval refresh | `Cache.Worker` |

## What "mature" means here

1. **Back-off on failure, capped.** A retry loop whose last answer was
   an outage waits longer each time, to a cap, and never charges the
   patience budget for it.
2. **A circuit per dependency.** While a dependency is known down —
   the queue monitor already grades the client links; the hand-off
   probe (`Pursuits.IncidentContext`) now knows Prowlarr's — work that
   needs it is held, not attempted. One switch, not N snoozes.
3. **Recovery wakes the work.** The first successful poll or grab
   re-schedules whatever the circuit held, so recovery is not paid for
   with a 15-minute wait.
4. **Coalesce by dependency.** Two pursuits against one dead client
   should cost one probe, not two retry loops.
5. **Visible budgets.** Requests/hour per server stay on the Connections
   tile; an audit target is a number, not a feeling.

## Decisions made

* `2026-09-17` — Opened, with the outage-retry cadence from the
  fit-first campaign (decision 5, 15-minute snooze) as the first case.

## Next steps

1. Measure: one healthy day and one simulated outage per dependency
   (stop the client, break Prowlarr's client entry, block TMDB), read
   the Connections tile and the log ring, fill the table's cadence
   column with observed numbers.
2. Decide the shape: per-source back-off vs a dependency circuit the
   sources consult. Recommendation to test first: a circuit keyed by
   dependency, fed by the existing graders (`Downloads.Connectivity`,
   `Pursuits.IncidentContext`, `Search.IndexerHealth`), with recovery
   wakes — because it fixes N sources with one mechanism.
3. Apply to the pursuit retry first (the live case), then the queue
   monitor against a dead client, then whatever the measurements rank
   next.
4. Wiki: Troubleshooting's outage entries say what the app does while a
   dependency is down and when it resumes.

## Completion criteria

* Every row in the inventory has a measured cadence, healthy and in
  outage, and a stated policy.
* No source retries a request a known-down dependency cannot serve
  more than once per back-off step; the pursuit retry during a
  hand-off outage costs at most a probe per interval, not a search plus
  a grab per pursuit.
* Recovery of a dependency resumes held work within one poll interval.
* Requests/hour per server during a simulated outage are below the
  healthy-day rate, not above it.

## Pointers

* `lib/media_centaur/acquisition/jobs/pursue_target.ex`,
  `acquisition/corpus.ex`, `downloads/queue_monitor.ex`,
  `downloads/connectivity.ex`, `acquisition/pursuits/incident_context.ex`,
  `search/indexer_health.ex`, `config/config.exs` (Oban crontab).
* ADR-054 (subsystem incidents), UIDR-016 (Needs attention),
  `campaigns/fit-first-search-order` (closed 2026-09-17; decision 5 is
  the first case here).
* Memory: `reference-prowlarr-search-api-facts` (indexer back-off
  escalation), `project-prowlarr-stack-sabnzbd-handoff-defects` (the
  outage that exposed this).
