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
- **Hand-off outage** — the specific outage where Prowlarr answers
  searches but cannot pass a release to the download client (HTTP 500,
  `DownloadClientUnavailableException`). Graded by
  `Prowlarr.grab_outage?/1`.
- **Back-off** — retry spacing that grows with consecutive failures, to
  a cap.
- **Circuit** — a per-dependency switch: while the dependency is known
  down, requests that need it are held, not sent; the first success (or
  a probe) closes it again.
- **Coalescing** — many callers with the same need against one
  dependency make one request, not N.
- **Recovery wake** — resuming held work from a recovery signal instead
  of the next scheduled poll.
- **Watched cadence** — the queue monitor's faster poll (10 s) while at
  least one LiveView subscribes to it; **idle cadence** is 30 s.

## Status

Measured, 2026-09-17 evening. The inventory below is verified against
the code (constants cited) and against one day of observation: the dev
node's log ring, the day's systemd journal (seven boots, one real
download-client outage 16:47–16:56 CEST, and the hand-off outage that
is still open), and the Connections tile. The shape of the fix is not
chosen yet — see *Decisions to make*. No code written.

Opened at the close of `fit-first-search-order` (its spec:
`docs/superpowers/specs/2026-09-17-planning-descent-design.md`).

## Evidence (measured 2026-09-17)

Healthy baseline, idle, two download clients configured, nobody on a
page (Connections tile, 15-minute window after the 19:47 CEST boot):

| Upstream | Requests / 15 min | Requests / hour | Source |
|---|---|---|---|
| sabnzbd | 70 | 280 | queue monitor, 2 calls per poll |
| qbittorrent | 35 | 140 | queue monitor, 1 call per poll |
| prowlarr | 3 | — | one pursuit retry and two manual picks, all grabs |
| tmdb, tmdb_images, github | 0 | 0 | gated / nothing due |

The watched cadence multiplies the client rows by three (1,260/h for the
pair) for as long as Incoming or Downloads is open.

What each source did in an outage, observed:

- **Queue monitor, clients down (16:47–16:49 CEST, idle).** Both slots
  refused connections; polls continued every 30 s, two warnings per
  poll. The failure cadence is the idle cadence — there is no growth.
- **Queue monitor, SABnzbd answering 403 (16:49–16:56 CEST, page
  open).** Polls every 10 s once the page was open — 28 polls, two
  warnings each, in six minutes. The
  `:auth_failed` row of `QueueMonitor.cadence_ms/3` never fired: SABnzbd
  reported the bad key as **HTTP 403 with a string body**, which
  `DownloadClient.Sabnzbd` returns as `{:http_error, 403, _}` and
  `QueueMonitor.classify_error/1` grades `:unreachable`. Only the
  HTTP-200 `{"status": false, "error": "API Key …"}` form grades
  `:auth_failed`. An `{:offline, _}` slot keeps the watched cadence on
  purpose (queue_monitor.ex:168-175).
- **Pursuit start during the hand-off outage** (17:39 and 19:39 CEST,
  three titles): per title, 1–2 live searches, then **two grabs of the
  same release** — `CommitPlan.grab_assignments/3` grabs, fails,
  "degrades to seeking"; `PursueTarget.handle_found/5` then grabs the
  identical result again before it snoozes. The second grab is spent on
  an outage the first one just proved.
- **Pursuit retry during the hand-off outage** (20:10:13 CEST, the
  15-min snooze, watched live): one live search and one grab, both
  doomed, then another 15-minute snooze. The search ran only because
  the term's last live search (19:39:57) had aged past the corpus's
  30-minute window; the 19:55 retry had served it from the corpus. So a
  one-term pursuit costs 4 grabs and 2 searches an hour for as long as
  the outage lasts, and N pursuits cost N times that with no shared
  memory of the answer.
- **Corpus zero-result probe.** `Corpus.blind?/0` calls
  `IndexerHealth.check/0` (two Prowlarr reads) after every live search
  that returns `[]` (corpus.ex:64,80). During the 16:52 Prowlarr 401
  window that was invisible from the search call site.
- **Incoming page health loop.** Two Prowlarr reads every 30 s per open
  page (`@storage_refresh_ms`, incoming_live.ex:165), no back-off; each
  failed read during the 401 window minted a diagnostic event
  (16:52:33, 16:53:03, 16:53:33).
- **Decision modal double fetch.** At 17:06:48 and 19:40:37 CEST every
  Prowlarr search in the alternatives set ran **twice within one
  second**: `load_pursuit_detail/1` runs from `handle_params` and again
  from the lifecycle-event reload (`maybe_reload_modal_for_event/2`),
  and each starts `start_async_alternatives_fetch/2` while the first is
  still in flight. User-initiated, not recurring — but it is the
  coalescing failure in miniature.
- **Release-tracking sweep** every 900 s (53 today, median exactly
  900 s): the drop planner's clock. `WantSchedule` already backs off by
  want age (30 min under 48 h, 4 h to 7 d, 24 h to 30 d, then 7 d) — by
  age, not by outage. `Capabilities.prowlarr_ready?/0` is a
  configuration gate, not a health gate, so every young want is
  re-planned through a dead Prowlarr every 30 min.
- **Image retry scheduler** ticks every 120 s (407 DB reads today),
  per-entry back-off 30 s → 5 min cap, five tries then `:permanent`.
  The mature end of the spectrum, alongside the Nostr reconnect
  (1 s → 60 s cap, 30 s ping).
- **Prowlarr search errors** in `PursueTarget` already snooze one hour
  without charging an attempt (`handle_prowlarr_error/2`), and the
  corpus never records an error as fresh negative knowledge.
- Prowlarr escalates an indexer's own back-off from 60 s to 15 min under
  repeated failure and it persists — app-side retries against a
  backed-off indexer make the back-off worse (memory:
  `reference-prowlarr-search-api-facts`).

## Inventory

Verified against the code 2026-09-17. "Local only" rows were checked
and carry no outbound traffic; they stay listed so nobody re-audits
them. Policies are assigned once the shape is decided.

| Source | Dependency | Cadence (code) | On failure today | Gate today |
|---|---|---|---|---|
| Pursuit retry, hand-off outage — `Jobs.PursueTarget` | Prowlarr → client | 15 min, no attempt charged (`@download_client_snooze_seconds`) | fixed, never exhausts | none — each target snoozes alone |
| Pursuit retry, Prowlarr error — `Jobs.PursueTarget` | Prowlarr | 1 h, no attempt charged (`@prowlarr_error_snooze_seconds`) | fixed, never exhausts | none |
| Pursuit retry, nothing acceptable — `Jobs.PursueTarget` | Prowlarr / indexers | 4 h × 2^n, cap 24 h, 12 attempts (Settings) | back-off by attempt | attempt budget |
| Plan solve — `Jobs.RunPlan` | Prowlarr | one corpus search per search-order step, per plan; enqueued by every drop-planner tick | error marks the plan, no retry of its own | corpus freshness (30 min) |
| Corpus re-search — `Acquisition.Corpus` | Prowlarr / indexers | any term older than 30 min on any consult (`@freshness_window_minutes`) | errors never recorded → next consult re-hits | freshness window; **+2 reads on every `[]` via `blind?/0`** |
| Drop planner tick — `DropPlanner` via `Reactor` on `{:tracking_sweep_completed}` | Prowlarr (through plans) | every sweep, 15 min; per want `WantSchedule` 30 min / 4 h / 24 h / 7 d by age | stateless re-derive | `Capabilities.prowlarr_ready?` (config, not health); `Discovery.grabs?`; claims |
| Queue monitor poll — `Downloads.QueueMonitor` | download clients | 10 s watched, 30 s idle (`@poll_watched_ms`, `@poll_idle_ms`) | 30 s flat on `:auth_failed` only; offline keeps watched cadence | `Capabilities.client_ready?/1` (config) |
| Indexer health probe — `Search.IndexerHealth` | Prowlarr (2 reads) | 30 s while Incoming is open; on every zero-result live search | cached `unreachable`, no back-off | `prowlarr_ready?` (config) |
| Tracking refresh — `ReleaseTracking.Refresher` | TMDB | 6 h (Settings), `reload: true` per item, 1–2 seasons per TV item, concurrency 4 | per-item error skipped, cadence fixed | none — no TMDB-down circuit |
| Tracking image backfill — `Refresher.bulk_download_images/1` | TMDB image CDN | rides the 6 h cycle | failure logged; re-tried every cycle forever (gate is file-on-disk) | none |
| Update check — `SelfUpdate.CheckerJob` | GitHub | cron every 15 min, contacts GitHub per the user's interval (default 6 h); boot check at +30 s | failed check leaves next tick due → 15-min retry, no back-off | `SelfUpdate.enabled?`, unique 120 s |
| Nostr relay — `Nostr.Connection` | relays | ping 30 s; reconnect 1 s → 60 s cap | exponential back-off | back-off is the gate — **mature** |
| Image retry — `Pipeline.Image.RetryScheduler` | TMDB image CDN (via pending rows) | tick 2 min; per entry 30 s → 5 min cap, 5 tries | `:permanent` after 5 | budget is the circuit — **mature** |
| Artwork warm on mount — `TmdbArtwork.ensure/2` | TMDB + image CDN | per fresh mount per identity | logged, no negative cache → re-fetched on every mount for identities TMDB has no art for | files-on-disk check; Discovery de-dupes per session |
| Pursuits watcher — `Pursuits.Watcher` (cron 15 min) | local only | — | — | — |
| Subsystem evaluator — `ErrorReports.EvaluatorJob` (cron 5 min) and every `assess/0` | local only | — | — | — |
| Cache workers, Status vitals, HTTP cache sweep, retention sweeps | local only | — | — | — |

Oban runs `acquisition: 3` — with ~6 indexers behind Prowlarr that is
up to 18 simultaneous outbound requests when three jobs search at once
(config.exs:64-68).

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
* `2026-09-17` (evening) — Sources that never leave the machine
  (evaluator and its assessors, pursuits watcher, cache workers, Status
  vitals, HTTP cache sweep, retention sweeps) are out of scope; verified
  local-only and kept in the table so they are not re-audited.
* `2026-09-17` (evening) — The tracking refresher's `reload: true`
  policy (re-read every item every 6 h whether or not anything could
  have changed) is the deferred TMDB-caching campaign's question
  (memory `project-tmdb-caching-refresh-policy`, owner 2026-09-14).
  This audit gives that cycle outage behaviour only — hold while TMDB
  is down, resume on recovery — not a new refresh policy.

## Decisions to make

**Shape.** Two candidates; the measurements favour the second.

1. *Per-source back-off.* Each loop grows its own snooze
   (15 → 30 → 60 min, cap) on consecutive outage answers. Cheap, local,
   but N pursuits still probe N times per step, the plan-then-pursuit
   double grab stays, and recovery costs the current step's wait.
2. *A dependency circuit fed by the graders that exist.* One switch per
   dependency — `Downloads.Connectivity` for each client link,
   `Pursuits.IncidentContext` for the hand-off, `IndexerHealth` for
   Prowlarr — that outbound callers consult before sending. Held work is
   re-enqueued by the first success on that dependency (the queue
   monitor's next good poll, the first good grab). The queue monitor
   itself becomes the probe for client links, backing off to a cap while
   open and returning to cadence on the first success. Fixes every
   Prowlarr-side row with one mechanism and makes the double grab
   impossible (the second call finds the circuit open).

Open with the owner: whether the circuit is a value the graders publish
(a read on `persistent_term`, no process) or a process — the Iron Law
says a value, since the graders already own the state.

## Concrete defects found (fix regardless of shape)

1. SABnzbd's HTTP-403 bad-key answer is graded `:unreachable`, so the
   `:auth_failed` cadence never fires for it. Map `{:http_error, 403, _}`
   with an "API Key" body to `:auth_failed` in `DownloadClient.Sabnzbd`.
2. `CommitPlan` grabs, fails on the hand-off outage, and the pursuit it
   starts grabs the same release again in the same second.
3. The decision modal starts two alternatives fetches for one open when
   a lifecycle event lands during the first (`load_pursuit_detail/1`
   from `handle_params` and from `maybe_reload_modal_for_event/2`).
4. `Corpus.blind?/0` and Incoming's 30-second loop both probe Prowlarr
   with no memory of the last answer; a known-unreachable Prowlarr is
   re-probed every 30 s per open page.

## Next steps

1. ~~Measure~~ — done 2026-09-17; the numbers above. What is still
   unmeasured: a TMDB outage (block the API and CDN, watch the
   refresher and artwork warm) and a Nostr relay outage (expected fine).
2. Decide the shape with the owner (*Decisions to make*). Then write the
   design as a spec under `docs/superpowers/specs/`, with the glossary
   here promoted to it.
3. Apply to the pursuit retry first (the live case), then the queue
   monitor against a dead client, then the drop planner and Incoming's
   probe loop, then the rest by measured rate.
4. Fix the four concrete defects; 1 and 3 are independent of the shape
   and can land first.
5. Wiki: Troubleshooting's outage entries say what the app does while a
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
  `acquisition/jobs/run_plan.ex`, `acquisition/plans/commit_plan.ex`,
  `acquisition/corpus.ex`, `acquisition/want_schedule.ex`,
  `downloads/queue_monitor.ex`, `downloads/connectivity.ex`,
  `downloads/download_client/sabnzbd.ex`,
  `acquisition/pursuits/incident_context.ex`, `search/indexer_health.ex`,
  `release_tracking/refresher.ex`, `pipeline/image/retry_scheduler.ex`,
  `lib/media_centaur_web/live/incoming_live.ex` (`:refresh_storage`,
  `load_pursuit_detail/1`), `config/config.exs` (Oban crontab, queues),
  `http_client/stats.ex` (the Connections tile counter; cache hits are
  not requests).
* Measurement recipe: `~/scripts/agents/mc-eval
  'MediaCentaur.HttpClient.Stats.snapshot().upstreams'` for the
  15-minute window and since-boot totals per upstream; `journalctl
  --user -u media-centaur-dev -o short-iso` for cadence over a day
  (normalise digits, group by message, take the median gap).
* ADR-054 (subsystem incidents), UIDR-016 (Needs attention),
  `campaigns/fit-first-search-order` (closed 2026-09-17; decision 5 is
  the first case here).
* Memory: `reference-prowlarr-search-api-facts` (indexer back-off
  escalation), `project-prowlarr-stack-sabnzbd-handoff-defects` (the
  outage that exposed this), `project-tmdb-caching-refresh-policy`
  (the refresh-policy question this audit does not answer),
  `project-status-indexer-blindness-gap` (Search's 900 s staleness rule
  — a circuit for Prowlarr would give it the continuous signal it lacks).
