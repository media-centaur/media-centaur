---
status: in-progress
started: 2026-09-17
last_updated: 2026-09-18
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
- **Integration** — the server a request goes to: Prowlarr (and behind
  it the indexers), a download client, TMDB and its image CDN, GitHub,
  a Nostr relay.
- **Outage** — an integration that is reachable but cannot do the job
  (Prowlarr answering 500 on grabs), or not reachable at all.
- **Hand-off outage** — the specific outage where Prowlarr answers
  searches but cannot pass a release to the download client (HTTP 500,
  `DownloadClientUnavailableException`). Graded by
  `Prowlarr.grab_outage?/1`.
- **Back-off** — retry spacing that grows with consecutive failures, to
  a cap.
- **Availability** — the published answer per integration, `:up` or
  `{:down, since, reason}`; while an integration is down, requests that
  need it are held, not sent, and the first good probe or request marks
  it up again. Earlier drafts of this file called this "the circuit";
  the code name is `MediaCentaur.IntegrationAvailability` (owner, 2026-09-17).
- **Coalescing** — many callers with the same need against one
  integration make one request, not N.
- **Recovery wake** — resuming held work from a recovery signal instead
  of the next scheduled poll.
- **Watched cadence** — the queue monitor's faster poll (10 s) while at
  least one LiveView subscribes to it; **idle cadence** is 30 s.
- **Metered integration** — one that counts requests against a limit, or
  escalates a back-off when hit repeatedly: TMDB and its image CDN,
  Prowlarr's live searches and grabs (the indexers behind them), GitHub,
  Nostr relays.
- **Free integration** — one that does neither: the download clients on
  the LAN, answered in under a millisecond. Its only cost is log noise.
- **Probe** — a free request whose only purpose is to learn whether a
  integration can do the job, so that no metered request is spent to
  learn it.

## Status

**Implementing. Rollout steps 1–3 of 5 landed (2026-09-17, 2026-09-18);
step 4 (GitHub and relays — confirm only, no code expected) is next.**
Resume by reading, in this order: this file; the approved design
`docs/superpowers/specs/2026-09-17-availability-design.md` (glossary,
cost classes, the value, evidence and probes, held work, recovery, what
the user sees, diff against the code); the three executed plans
`docs/superpowers/plans/2026-09-17-availability-plan.md`,
`.../2026-09-18-availability-step-2-plan.md` and
`.../2026-09-18-availability-step-3-plan.md`; then
`git log --oneline 71314bb9..` for what landed.

What exists in code after step 1 (HEAD `49fc475f` at the time of
writing): `MediaCentaur.IntegrationAvailability` (value, store,
`available?/1` gate, change broadcast on
`Topics.integration_availability_updates/0`);
`Search.ProwlarrAvailability` (the one writer for `:prowlarr` and both
hand-offs, hooked into `Prowlarr.search/3`, `Prowlarr.grab/2`,
`IndexerHealth.check/1`); `Search.ProbeJob` (probes while down, 60 s
cadence, honours Prowlarr's `retry_at`, completes on up);
`Jobs.PursueTarget` holds before search and grab (unconfigured Prowlarr
snoozes an hour, a down one the cadence; a hand-off hold stamps the
target once per outage, a Prowlarr hold writes nothing);
`Prowlarr.grab_outage?/1` narrowed so a non-hand-off grab 5xx charges an
attempt; the Waiting copy in the modal and on the Downloads index;
`Pursuits.IncidentContext` reading the value; `test/support/prowlarr_stubs.ex`;
the `Library.Availability` → `MediaFileAvailability` rename; wiki
Troubleshooting's pursuit Waiting entry. Every task had a spec review
and a quality review, then one whole-step review; final precommit
7,451 Elixir + 811 JS tests green.

What step 2 added (2026-09-18): `IndexerHealth.current/1` — a fresh
roster read while Prowlarr is up, the probe's last observation while it
is down, so no renderer probes a server the probe job already owns;
`ViewModels.SearchOutage` — one sentence read from the availability
value, replacing the duplicate `blind_reason/1` that `GapVerdict` and
`IncomingLive.PlanLogic` each carried over `IndexerHealth`, and naming a
rejected API key for the first time (a 401 used to read "unreachable");
the Incoming page's health read, its `search_outage` assign and its
subscription to `Topics.integration_availability_updates/0` (the web
boundary now deps `IntegrationAvailability`, which also gained
`subscribe/0`); `Jobs.RunPlan` holds before a plan's searches
(unconfigured an hour, down the probe cadence, mirroring `PursueTarget`)
and `DropPlanner.run_tick/1` gates on `available?(:prowlarr)` instead of
configuration alone; `Acquisition.Reactor` runs a planner tick on
`{:integration_availability_changed, :prowlarr, :up}`
(`Handlers.prowlarr_available/0`); `Search.IncidentContext` decides from
the value, its 900 s staleness rule retired and `:search_provider_rejected`
added as its own condition. Six test files that configured Prowlarr's URL
and key without recording a passing connection test now call
`ProwlarrStubs.mark_ready!/0` — the new `RunPlan` gate reads
`prowlarr_ready?/0`, so a half-configured fixture snoozed instead of
planning. Full suite 7,465 green.

What step 3 added (2026-09-18): `MediaCentaur.TMDB.Availability` — the
one writer for `:tmdb`, folding the outcome of every request through the
single `TMDB.Client.get/3` funnel (a cache hit reports nothing; a 4xx
that is not 401/403 neither opens nor closes the value); `TMDB.ProbeJob`
— one `GET /configuration` every 5 minutes while down, completing on up
or on an unconfigured TMDB; `:rate_limited` joins the reason vocabulary
for 429; `ReleaseTracking.Refresher` holds at the tick and again per item
(so a TMDB that dies mid-cycle costs one failed request, not one per
tracked title), re-arms at the probe cadence instead of the 6-hour
interval, and runs the deferred cycle on the recovery broadcast;
`TmdbArtwork.ensure/2` serves what is on disk while TMDB is down.
`TmdbStubs` gained `mark_ready!/0` and `mark_unconfigured!/0`. Three test
files moved from async to sync — they drive TMDB failures through the
client, which now writes global state an async test may not (MC0036):
`tmdb/identifiers_test`, `reconciliation/spine_test`,
`pipeline/stages/fetch_metadata_test`. Full suite 7,480 green at three
seeds.

Process notes for the next step: implement with one editing agent at a
time in this checkout — the dev daily driver reloads `lib/` live, and on
2026-09-17 two concurrent editors crashed it and raced on git (see the
`f71bb8de` / `2845498e` history); reviews are read-only and may run in
parallel; `agent-mix` only, never bare `mix`.

Droppable follow-ups the step-1 reviews left: pin the two re-stamp
branches of the hand-off hold with tests; a recovered hand-off's
stamped copy lingers on the target until its next run (at most one
cadence); `ProwlarrStubs` moduledoc should mention `mark_unconfigured!/0`.

Simulated TMDB outage, measured on the dev node 2026-09-18 (the
verification step 3 owed): with `:tmdb` reported down, one full refresh
tick across 5 tracked items plus an artwork warm for an identity with
nothing on disk cost **0 requests** to `tmdb` and 0 to `tmdb_images`. The
same actions against the pre-change code, minutes earlier, cost **+7**
API requests and **+3** CDN downloads. Reporting `:tmdb` up again ran the
deferred cycle at once: +5 requests, one per tracked item. The campaign's
criterion — requests/hour during an outage below the healthy rate, not
above it — holds for TMDB.

Measurement basis (2026-09-17): the inventory below is verified against
the code and one day of observation — the dev node's log ring, the
day's systemd journal (seven boots, one real download-client outage
16:47–16:56 CEST, and the hand-off outage, fixed in the stack at 20:18
CEST), and the Connections tile.

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
**costs**, not by how often it runs. A poll against a free integration is
fine at any cadence, in outage too. A request against a metered one is
never spent to learn what a probe could tell.

| Integration | Class | Consequence for the audit |
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

| Source | Integration | Cadence (code) | On failure today | Gate today |
|---|---|---|---|---|
| Pursuit retry, hand-off outage — `Jobs.PursueTarget` | Prowlarr → client | 15 min, no attempt charged (`@download_client_snooze_seconds`) | fixed, never exhausts | none — each target snoozes alone |
| Pursuit retry, Prowlarr error — `Jobs.PursueTarget` | Prowlarr | 1 h, no attempt charged (`@prowlarr_error_snooze_seconds`) | fixed, never exhausts | none |
| Pursuit retry, nothing acceptable — `Jobs.PursueTarget` | Prowlarr / indexers | 4 h × 2^n, cap 24 h, 12 attempts (Settings) | back-off by attempt | attempt budget |
| Plan solve — `Jobs.RunPlan` | Prowlarr | one corpus search per search-order step, per plan; enqueued by every drop-planner tick | error marks the plan, no retry of its own | **step 2:** held while `:prowlarr` is down (snooze at the probe cadence, an hour when unconfigured); corpus freshness (30 min) |
| Corpus re-search — `Acquisition.Corpus` | Prowlarr / indexers | any term older than 30 min on any consult (`@freshness_window_minutes`) | errors never recorded → next consult re-hits | freshness window; **+2 reads on every `[]` via `blind?/0`** |
| Drop planner tick — `DropPlanner` via `Reactor` on `{:tracking_sweep_completed}` and on `:prowlarr` recovery | Prowlarr (through plans) | every sweep, 15 min; per want `WantSchedule` 30 min / 4 h / 24 h / 7 d by age | stateless re-derive | **step 2:** `available?(:prowlarr)`; `Discovery.grabs?`; claims |
| Queue monitor poll — `Downloads.QueueMonitor` | download clients | 10 s watched, 30 s idle (`@poll_watched_ms`, `@poll_idle_ms`) | 30 s flat on `:auth_failed` only; offline keeps watched cadence | `Capabilities.client_ready?/1` (config) |
| Indexer health probe — `Search.IndexerHealth` | Prowlarr (2 reads) | **step 2:** 30 s while Incoming is open **and Prowlarr is up** (`current/1`); on every zero-result live search | while down the probe job's 60 s read is the only one | `prowlarr_ready?` (config) |
| Tracking refresh — `ReleaseTracking.Refresher` | TMDB | 6 h (Settings), `reload: true` per item, 1–2 seasons per TV item, concurrency 4 | **step 3:** held at the tick and per item; re-armed at the probe cadence; the held cycle runs on recovery | **step 3:** `available?(:tmdb)` |
| Tracking image backfill — `Refresher.bulk_download_images/1` | TMDB image CDN | rides the 6 h cycle | failure logged; re-tried every cycle forever (gate is file-on-disk) | **step 3:** rides the refresh gate — it only ever sees successfully fetched items |
| Update check — `SelfUpdate.CheckerJob` | GitHub | cron every 15 min, contacts GitHub per the user's interval (default 6 h); boot check at +30 s | failed check leaves next tick due → 15-min retry, no back-off | `SelfUpdate.enabled?`, unique 120 s |
| Nostr relay — `Nostr.Connection` | relays | ping 30 s; reconnect 1 s → 60 s cap | exponential back-off | back-off is the gate — **mature** |
| Image retry — `Pipeline.Image.RetryScheduler` | TMDB image CDN (via pending rows) | tick 2 min; per entry 30 s → 5 min cap, 5 tries | `:permanent` after 5 | budget is the circuit — **mature** |
| Artwork warm on mount — `TmdbArtwork.ensure/2` | TMDB + image CDN | per fresh mount per identity | logged, no negative cache → re-fetched on every mount for identities TMDB has no art for | **step 3:** `up?(:tmdb)` — while down it answers from disk; files-on-disk check; Discovery de-dupes per session |
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
2. **A circuit per metered integration, fed by free probes.** While a
   integration is known down, work that needs it is held, not attempted.
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
4. **Coalesce by integration.** Two pursuits against one dead client
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
  classes*). Free integrations keep polling at today's cadence and get
  quieter logs; metered ones get the circuit.
* `2026-09-17` (evening, owner) — **Shape: a circuit per metered
  integration, opened and closed by free probes, with held work resumed
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
  the same commit series: Troubleshooting gets one entry per integration
  saying what the app does while it is down and when it resumes; the
  Using Media Centaur page changes only if the circuit surfaces in the
  UI (the pursuit's Waiting state, the Downloads tile). Language terse
  and informative — nothing is being sold.
* `2026-09-17` (late evening, owner) — Spec approved
  (`docs/superpowers/specs/2026-09-17-availability-design.md`). Name:
  `MediaCentaur.IntegrationAvailability` (first `Availability`; renamed
  the same evening when review surfaced `Library.Availability`, which
  the owner renamed `MediaFileAvailability` — one word, two meanings,
  split); "circuit" and "dependency" retired for "availability" and
  "integration". The search-provider
  incident persists while the probe says down, replacing the 900 s
  staleness rule — this closes the indexer-blindness gap the owner had
  reserved to design together.
* `2026-09-18` — Step 3 took two calls the spec left implicit. **A
  rejected TMDB key opens `:tmdb`** (`:rejected`), on the spec's own
  reasoning that misconfigured is as useless as dead for held work —
  without it a rejected key is re-hammered by every refresh cycle and
  every artwork warm. **The image CDN does not write `:tmdb`**:
  `image.tmdb.org` and `api.themoviedb.org` are different hosts, a CDN
  failure is no evidence about the API, and holding metadata refreshes on
  it would be the wrong blame (the hand-off probe's "inconclusive moves
  nothing" rule). Artwork is held anyway, because the detail fetch it
  follows is. Also: 429 gets its own reason, `:rate_limited` — the server
  is answering and refusing to do more work, which "unreachable" would
  misreport to the person reading it.
* `2026-09-18` — **Open, for step 5 or its own decision:** TMDB has no
  `:subsystem` incident. `TMDB.IncidentContext` implements `vitals/0`
  only, so a sustained TMDB outage raises no condition on the Status
  board the way a Prowlarr one now does — the spec puts TMDB's
  user-visible surface on the Connections tile in step 5. Worth asking
  whether it should also have a condition, now that a probe keeps a
  continuous signal.
* `2026-09-18` — Step 2 implemented spec decision 2: the search
  incident's 900 s staleness rule is gone, so the condition lasts exactly
  as long as the probe says Prowlarr is down. And a Prowlarr that answers
  401/403 is its own condition (`:search_provider_rejected`, headline
  *Search provider rejected the API key*) rather than being reported as
  unreachable — the same outage for held work, a different thing to fix.
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

1. ~~SABnzbd's HTTP-403 bad-key answer is graded `:unreachable`~~ —
   landed `4b201b63` 2026-09-17: one predicate decides "rejected key"
   for both response shapes.
2. ~~`CommitPlan` grabs, fails on the hand-off outage, and the pursuit
   it starts grabs the same release again~~ — closed by construction in
   step 1: the pursuit's grab step is gated on the hand-off the plan's
   failed grab just opened.
3. ~~The decision modal starts two alternatives fetches for one open~~ —
   landed `f9630784` 2026-09-17: one in-flight fetch per pursuit.
4. ~~`Corpus.blind?/0` and Incoming's 30-second loop both probe Prowlarr
   with no memory of the last answer~~ — closed in step 2 by
   `IndexerHealth.current/1`: while `:prowlarr` is down the page reads
   the probe's last observation, and only the probe job probes.
   `Corpus.blind?/0` keeps its per-empty-result roster read by design —
   it is free, it is what keeps an empty result honest, and it writes the
   availability value.

## Next steps

1. ~~Write and execute the step-2 plan~~ — landed 2026-09-18:
   `docs/superpowers/plans/2026-09-18-availability-step-2-plan.md`. Ten
   tasks: `IndexerHealth.current/1` (the page stops probing what the
   probe job owns, closing defect 4); one `ViewModels.SearchOutage`
   sentence read from the value, replacing the duplicate `blind_reason/1`
   in `GapVerdict` and `PlanLogic` and naming a rejected key for the
   first time; the Incoming page's health read, outage assign and
   availability subscription; `RunPlan` and `DropPlanner` holds;
   `Reactor`'s recovery tick; `Search.IncidentContext` on the value with
   the 900 s staleness rule retired and `:search_provider_rejected`
   added; wiki and campaign.
2. ~~Step 3: `:tmdb`~~ — landed 2026-09-18
   (`docs/superpowers/plans/2026-09-18-availability-step-3-plan.md`),
   outage measured; see Status above.
3. **Step 4:** confirm GitHub and relays within budget; no code expected.
4. Step 5: queue-monitor logging at grade transitions only; Connections
   tile shows *down since* for Prowlarr and TMDB.
5. Close: bucket every remaining item (ship / verify / defer-to-X),
   glossary to `docs/GLOSSARY.md`, retire this file.

## Completion criteria

* Every row in the inventory has a measured cadence, healthy and in
  outage, and a stated policy.
* No source retries a request a known-down integration cannot serve
  more than once per back-off step; the pursuit retry during a
  hand-off outage costs at most a probe per interval, not a search plus
  a grab per pursuit.
* Recovery of an integration resumes held work within one poll interval.
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
