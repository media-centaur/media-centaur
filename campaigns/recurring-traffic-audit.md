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
- **Availability** — the published answer per dependency, `:up` or
  `{:down, since, reason}`; while a dependency is down, requests that
  need it are held, not sent, and the first good probe or request marks
  it up again. Earlier drafts of this file called this "the circuit";
  the code name is `MediaCentaur.Availability` (owner, 2026-09-17).
- **Coalescing** — many callers with the same need against one
  dependency make one request, not N.
- **Recovery wake** — resuming held work from a recovery signal instead
  of the next scheduled poll.
- **Watched cadence** — the queue monitor's faster poll (10 s) while at
  least one LiveView subscribes to it; **idle cadence** is 30 s.
- **Metered dependency** — one that counts requests against a limit, or
  escalates a back-off when hit repeatedly: TMDB and its image CDN,
  Prowlarr's live searches and grabs (the indexers behind them), GitHub,
  Nostr relays.
- **Free dependency** — one that does neither: the download clients on
  the LAN, answered in under a millisecond. Its only cost is log noise.
- **Probe** — a free request whose only purpose is to learn whether a
  dependency can do the job, so that no metered request is spent to
  learn it.

## Status

Measured, shape decided, defects 1 and 3 landed, design drafted —
2026-09-17 evening. The design spec is
`docs/superpowers/specs/2026-09-17-availability-design.md`; two owner
decisions in it are taken (`Availability`; the search incident persists
while down). Implementation in progress from the plan. The inventory
below is
verified against the code (constants cited) and against one day of
observation: the dev node's log ring, the day's systemd journal (seven
boots, one real download-client outage 16:47–16:56 CEST, and the
hand-off outage, fixed in the stack at 20:18 CEST), and the Connections
tile. Owner walk-through of the remaining items in progress — see
*Open items*. No code written.

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

## Cost classes

The principle (owner, 2026-09-17): treat each source by what a request
**costs**, not by how often it runs. A poll against a free dependency is
fine at any cadence, in outage too. A request against a metered one is
never spent to learn what a probe could tell.

| Dependency | Class | Consequence for the audit |
|---|---|---|
| Download clients on the LAN | free | Polling stays as it is, outage included. Only the noise is fixed: two warnings per poll, and SABnzbd's 403 graded "unreachable" instead of "check your key". |
| Prowlarr live searches | metered, × indexer count | Every live search in an outage burns indexer quota and deepens Prowlarr's persistent back-off. The corpus already makes repeats free for 30 min. |
| Prowlarr grabs | free on a failed hand-off, metered on success | Verified 2026-09-17 in Prowlarr's history: the stack's indexer runs in **Redirect** mode (`grabMethod=Redirect`), so Prowlarr hands SABnzbd a link and the indexer download happens only when SABnzbd fetches it. A grab that fails at the hand-off never reaches the indexer. Under Prowlarr's default Proxy mode the NZB is fetched first and a doomed grab is metered — the circuit covers both. |
| TMDB and image CDN | metered | The 6 h reload of every tracked title is the deferred caching campaign's question. Here it only needs to hold during a TMDB outage. |
| GitHub | metered, small | 60/h unauthenticated; a failed check retrying every 15 min is within budget. |
| Nostr relays | metered | Already backed off exponentially. Nothing to do. |

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
2. **A circuit per metered dependency, fed by free probes.** While a
   dependency is known down, work that needs it is held, not attempted.
   The probes are free requests: the queue monitor's poll for a client
   link, Prowlarr's own download-client test call for the hand-off
   (it reaches the client from inside Prowlarr's network without
   touching an indexer — the app's own client poll cannot answer this,
   since on 2026-09-17 the app reached SABnzbd while Prowlarr could
   not), the indexer roster read for Prowlarr itself. One switch, not
   N snoozes.
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
* `2026-09-17` (evening, owner) — **Cost, not cadence, decides the
  treatment.** Sources are classed metered or free (glossary, *Cost
  classes*). Free dependencies keep polling at today's cadence and get
  quieter logs; metered ones get the circuit.
* `2026-09-17` (evening, owner) — **Shape: a circuit per metered
  dependency, opened and closed by free probes, with held work resumed
  on the first good probe.** Per-source back-off is rejected as the
  primary mechanism (N pursuits would still probe N times, the
  plan-then-pursuit double grab would survive, recovery would wait for
  each countdown). The circuit is a value the graders publish, not a
  process.
* `2026-09-17` (evening, owner) — Both scope calls confirmed: local-only
  sources are out (kept in the table so they are not re-audited); the
  TMDB refresh policy stays with its own campaign. And: while designing
  and building the circuit, **flesh out the outbound-traffic slice in
  whatever way it needs to mature properly** — the outbound HTTP seam,
  the graders, the Connections tile — not the minimum patch.
* `2026-09-17` (evening, owner) — Of the four defects: **1 (SABnzbd 403
  → `:auth_failed`) and 3 (the doubled alternatives fetch) land now**,
  test-first, independent of the circuit. **2 (the plan-then-pursuit
  double grab) and 4 (Prowlarr re-probed every 30 s) fold into the
  circuit work** — 2 because the circuit removes it structurally and a
  standalone patch would be a symptom cover; 4 because those reads go
  to Prowlarr itself, not to an indexer, so they are free, and they
  become the circuit's probe.
* `2026-09-17` (evening, owner) — **Rollout order, by metered waste:**
  (1) pursuit retries during a hand-off outage — the hand-off circuit,
  probed by Prowlarr's download-client test call; (2) release-tracking
  re-planning through a dead Prowlarr — the Prowlarr circuit, probed by
  the indexer roster read, absorbing defect 4; (3) TMDB — refresher and
  artwork warm hold during an outage; (4) GitHub and relays — confirm
  only; (5) download-client log noise — one line at onset and one at
  recovery, last because it costs nothing.
* `2026-09-17` (evening, owner) — **No further outage simulations
  before the design.** TMDB is measured after the hold lands, as
  verification; the relay case is dropped (already mature). The two
  Prowlarr facts under *Open items* are verified before the spec.
* `2026-09-17` (evening, owner) — **Wiki rides each rollout step**, in
  the same commit series: Troubleshooting gets one entry per dependency
  saying what the app does while it is down and when it resumes; the
  Using Media Centaur page changes only if the circuit surfaces in the
  UI (the pursuit's Waiting state, the Downloads tile). Language terse
  and informative — nothing is being sold.
* `2026-09-17` (late evening, owner) — Spec approved
  (`docs/superpowers/specs/2026-09-17-availability-design.md`). Name:
  `MediaCentaur.Availability`; "circuit" retired. The search-provider
  incident persists while the probe says down, replacing the 900 s
  staleness rule — this closes the indexer-blindness gap the owner had
  reserved to design together.
* `2026-09-17` (evening) — The tracking refresher's `reload: true`
  policy (re-read every item every 6 h whether or not anything could
  have changed) is the deferred TMDB-caching campaign's question
  (memory `project-tmdb-caching-refresh-policy`, owner 2026-09-14).
  This audit gives that cycle outage behaviour only — hold while TMDB
  is down, resume on recovery — not a new refresh policy.

## Open items (owner walk-through, 2026-09-17)

1. ~~Shape~~ — decided, above.
2. ~~Scope calls~~ — confirmed, above.
3. ~~The four concrete defects~~ — decided, above: 1 and 3 now, 2 and 4
   with the circuit.
4. ~~Rollout order~~ — decided, above.
5. ~~Remaining measurements~~ — decided, above: none before the design.
6. ~~Wiki~~ — decided, above: rides each step.

Facts verified 2026-09-17 21:00 CEST, against the redeployed stack:
(a) a grab that fails at the hand-off spends **no** indexer download
under the stack's Redirect mode (history: `grabMethod=Redirect`; the
NZBgeek stats count queries and successful grabs only). So the metered
cost of a pursuit retry during a hand-off outage is its live search,
one per term per 30 minutes; the grab itself is free until the client
fetches. (b) `POST /api/v1/downloadclient/testall` through the app's
Prowlarr client answers in 12 ms with `[{id, isValid,
validationFailures}]` per client, reaches SABnzbd from inside Prowlarr's
network, and touches no indexer — it is the hand-off probe. The stack
fix itself is confirmed: the 30 Rock pursuit's 20:23 CEST retry grabbed
successfully.

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

1. ~~Measure~~ — done 2026-09-17; the numbers above. A TMDB outage is
   measured after the TMDB hold lands, as its verification.
2. ~~Decide the shape~~ — decided; facts verified; spec drafted
   2026-09-17 (`2026-09-17-availability-design.md`). Next: the two owner
   decisions in the spec, then a plan from it.
3. Apply in the decided order: hand-off circuit (pursuit retries),
   Prowlarr circuit (release-tracking re-planning, corpus probe,
   Incoming loop), TMDB hold, GitHub and relays confirmed, client log
   noise last.
4. ~~Fix defects 1 and 3~~ — landed 2026-09-17 (SABnzbd 403 →
   `:auth_failed`; one alternatives fetch per pursuit). 2 and 4 ride the
   circuit.
5. Wiki, per step: Troubleshooting's outage entry for that dependency
   says what the app does while it is down and when it resumes. Terse.

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
