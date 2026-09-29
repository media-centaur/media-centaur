---
status: planning
started: 2026-09-29
last_updated: 2026-09-29
---
# Durable work: every pending state has a job behind it

## Glossary

* **Pending state.** A stored value that says work is under way or
  owed: a status such as `:approved` shown as "Importing", a plan
  `"planning"`, an image queue entry `"pending"`.
* **Durable.** Survives a process crash and a restart: an Oban job, or a
  row a named pass is guaranteed to re-run.
* **Recovery pass.** A named function that re-derives lost work, such as
  startup recovery (`Watcher.Rescan.recover/0`) re-sending unlinked
  files.
* **Carrier.** How work travels today: PubSub message, Broadway pipeline,
  `Task.Supervisor.start_child`, `start_async`, Oban job, GenServer
  state.
* **Post-commit insert.** An Oban job inserted after the transaction
  that stored its pending state has committed. A crash between the two
  leaves the state with no job. Oban runs on the Lite engine through the
  app's `Repo`, so an insert inside `Repo.transaction` commits or rolls
  back with it.
* **Durable job.** An Oban job carrying work in ADR-076's first row,
  built by ADR-077's rules.
* **Command.** The context function that records a decision — and,
  under ADR-077, inserts its durable job in the same transaction.
* **Orphaned job.** A job left `executing` because the node stopped
  while it ran.

## Goal

Bring the codebase in line with
[ADR-076](../decisions/architecture/2026-09-29-076-durability-follows-the-cost-of-losing-the-work.md):
the mechanism carrying each piece of background work matches what
losing it costs, and no stored pending state lacks a stored job behind
it. Found in Review, where an approval shown as "Importing" rode a PubSub
message a crash could lose.

## Status

Planning. Inventory reconciled and every site classified (2026-09-29,
below). Fifteen findings, F1–F15. ADR-077 (how a durable job is built)
accepted. No code yet.

## Method

1. Load `elixir:oban-thinking` and `unify_design` before changing any
   site; `automated-testing` before any code (test-first).
2. For each pending state and each carrier site, record: what the work
   is, who triggers it (a person, the system), what losing it costs, the
   ADR-076 row it belongs in, and whether it already complies.
3. Where two callers do the same work, one durable and one
   re-derivable, design one path through the job (ADR-076, last rule) —
   run the `unify_design` pass for it and put the design in *Decisions*
   before code.
4. Move non-compliant sites one per commit, each with a test that kills
   the carrier mid-work (or restarts) and asserts the work completes or
   is reported.

## Findings (non-compliant)

Numbered by finding, not by order of work. File:line as of `38ec7959`.

| # | Finding | Sites | Loss today | Disposition |
|---|---|---|---|---|
| F1 | Review approval rides PubSub to Import | `review.ex:607-624` → `pipeline/import/producer.ex:20` | `settle_with_library/0` at restart resets `:approved` to `:pending` — the approval is undone, not done | One import path through an Oban job inserted in the approve transaction; replaces the Import pipeline. Design first (*Next steps* 3) |
| F2 | Deletes run in `start_async` | `review_live.ex:206` (`execute_delete`), `title_detail_host/library_events.ex:292` (`run_delete`) | Page closed mid-delete: files gone, `PendingFile` rows or library records remain; `:all` stops between groups | Oban job per delete |
| F3 | Plan lifecycle outside jobs | `RunPlan` post-commit insert `plans.ex:325` (create) and `:496` (replan); `plan_title` in a task `plans.ex:155`; automatic-plan gate on `PlanEvents.Changed` → `Reactor` (`reactor.ex:43`, `handlers.ex:77`); `CommitPlan.execute` in the caller — `incoming_live.ex:1408` `start_async` or the Reactor | `"planning"` plan with no job, for good (a tracking draft then blocks re-planning its want); an automatic plan waits on the board forever; a half-committed plan stays `ready` and re-approval hits `ensure_no_overlap` | `RunPlan` inside the transaction; gate and commit as Oban jobs; the click inserts a job |
| F4 | `Target "seeking"` post-commit insert, failure swallowed | `targets.ex:127` (`restart_target`), `pursuits/commands/helpers.ex:31` via `change_target.ex:94`, `auto_cancel.ex:93`; compliant: `commit_plan.ex:244` | Target `seeking` with no job, for good — policy never acts on `seeking`, no pass re-enqueues | Insert in the command's transaction, failure rolls back; correct `ChangeTarget`'s moduledoc (its reason is backwards) |
| F5 | Removed title keeps its seeking targets | `release_tracking.ex:384` `item_removed` → `reactor.ex:42` | The app keeps searching for and grabbing a title the person removed | Cancel in the removal's transaction, or a job inserted there |
| F6 | Picking a release runs in a task, grab before record | `acquisition.ex:486` `pick_alternative_async`, grab at `:495` | Pick lost; a crash between grab and `PickTarget` leaves a download no pursuit records | Oban job (pursuit_id, guid); record before grab |
| F7 | Setting a rung runs in a task | `release_tracking.ex:476` `set_rung_async` (`put_rung` then `derive`) | Rung lost, or Follow+ stored with no tracked item, for good (`reconcile/2` only drops) | Write the rung synchronously; derive as an Oban job in the same transaction |
| F8 | Watch completion → history → share chain on PubSub | `progress_records.ex:127` → `watch_history/recorder.ex:35` (task); `watch_event_created` / `title_intent_changed` → `activities/publisher.ex:93` (task) | Watch event lost for good, and with it the watched share; a lost withdrawal leaves a false listing on friends' feeds | Watch event in `mark_completed`'s transaction; share/withdraw as an Oban job inserted with the event or the intent write |
| F9 | Rematch rides two PubSub hops | `review/rematch.ex:16` → `inbound.ex:82`; `inbound.ex:250` → `review/intake.ex:22` | First hop lost: nothing happens; second: restart re-discovers the files and may re-import the same wrong match | Oban job inserted by the request |
| F10 | Library → release-tracking listeners | `library/events.ex:88` `containers_deleted`, `:96` `movies_added` → `release_tracking/library_listener.ex:23-24` | Tracked item dangles on a deleted container and can keep grabbing (moduledoc: "would dangle forever"); an arrived movie stays listed | Jobs inserted with the library write, or a reconcile pass that reads the state |
| F11 | Person-run image and Maintenance work | `maintenance.ex:103` (`clear_database_async`, `refresh_image_cache_async`); `ImageRefreshWorker` completes on a PubSub hand-off (`image_refresh.ex:86` `enqueue_images`); `image_ready` row upsert (`pipeline/image.ex:109` → `inbound.ex:81`) | Partial database clear; library without artwork mid-refresh; a refresh that reports done and never ran; a downloaded image with no `Library.Image` row | Oban jobs; the refresh job writes the queue rows itself |
| F12 | Remount reset runs async | `library/absence_sweeper.ex:170` | The next TTL check can purge files ADR-045's remount rule protects | Run the `UPDATE` inline, before the TTL check (not a carrier move) |
| F13 | Uniqueness drops new work | `PursueTarget` `unique: [period: 300, keys: [:target_id]]` and `RunPlan` `unique: [period: 60, keys: [:plan_id]]`, both in Oban's default `:successful` states (includes `completed`); `targets.ex:127` re-arms under the same id; `Plans.replan/2` re-runs under the same plan id | A re-arm within 5 min, or a replan within 60 s (excluding a release on a just-solved board), inserts nothing: `"seeking"` / `"planning"` with no job. Found by the `:manual` switch — inline mode skips uniqueness | Unique among jobs not yet started (ADR-077 rule 6, amended) |
| F14 | Job failures are invisible | No `[:oban, :job, …]` handler in `lib/` | A raising job leaves its error in `oban_jobs.errors` only — no Console line, no incident | One telemetry handler (ADR-077 rule 7) |
| F15 | No orphan rescue | `Oban.Lifeline` is off unless configured (Oban 2.24 `Config.normalize_services/1`); not configured | A job running when the node dies stays `executing` for good | Enable Lifeline; workers declare `timeout/1` (ADR-077 rule 8) |

**Minor, not ADR-076 violations but the same shape** — take when
touching the file:

* `settings_live.ex:547` manual update check: a killed check never
  sends `check_complete`; Status stays on `:checking` until the next
  scheduled check. Guarantee the broadcast or run it as `CheckerJob`.
* `home_live.ex:368`, `library_live.ex:190`, `settings_live.ex:826`
  Scan: runs `Rescan.scan/0` in `start_async`; a closed page skips the
  remaining watchers. Use `Rescan.scan_async/0` as `console_page_live`
  does.
* `integration_health.ex:237`: a crashed verifier leaves ETS
  `:pending` until retest; `async_nolink` + `:DOWN` would report it.
* `tmdb_title_changed` (`tmdb/store.ex:508`) and `entities_changed`
  (`library/events.ex:82`) carry projection updates with no named pass
  — stale until the next event for that title.
* Suspected, unverified: `RetryScheduler` resets `"pending"` image
  rows older than 30 s while they may still be queued in the producer —
  a long backlog could download twice. Needs a test.

## Classification (compliant)

**Pending states**

| State | Work & carrier | ADR-076 row |
|---|---|---|
| `PendingFile :approved` | F1 | — |
| `Plan "planning"`, `"ready"`+automatic; `PlanUnit "pending"` | F3 | — |
| `Target "seeking"` | F4 | — |
| `Pursuit`/`Unit "active"`, `Target "acquired"` | `Pursuits.Watcher` cron `*/15` + `LibraryReconciler` | cron / named pass |
| `ImageQueueEntry "pending"`/`"failed"` | Image pipeline; `RetryScheduler` 2-min tick re-sends | named pass |
| `Want :open` | `DropPlanner.run_tick` on each `SweepJob` (cron) | named pass |
| `AwaitingFile :pending` | Waits on a person; row deleted only after its link | not pending work |
| `Incident :open` | `EvaluatorJob` cron `*/5` | cron |
| `TMDB.Store` `next_check_at` (added) | `TMDB.CheckJob` cron + `@reboot` | cron |
| `FilePresence.last_seen_at` (added) | `AbsenceSweeper` TTL pass | named pass |
| Activity row a relay lacks (added) | Own-events diff in `RelaySync` | named pass |
| In-memory `deleting` (UI) | F2 | — |

No other stored pending state found (schemas searched for status,
state, pending, queued, needs, next-due fields).

**`Task.Supervisor.start_child`** — 28 calls in 19 files. Non-compliant:
F3 (`plans.ex:155`), F6, F7, F8 (Recorder, Publisher), F11
(Maintenance), F12. Compliant:

* Page view: `acquisition.ex:292` interactive search, `:672`
  download-client discovery.
* Re-derived by a named pass or the next event: artwork warms
  (`activities.ex:536`, `discovery.ex:206`, `apps.ex:101/155/175`,
  `release_tracking/helpers.ex:21`); boot heals (`boot_heal.ex:77`);
  removed-file cleanup (`library/file_event_handler.ex:36`, TTL 30 d);
  startup recovery itself (`pipeline/discovery/producer.ex:98`); scans
  and rescans (`watcher.ex:188/318`, `watcher/rescan.ex:43/123/201`).
* Notify: `playback/mpv_session.ex:461/469`.
* Next tick re-derives: progress saves `mpv_session.ex:916/948`.

**`start_async`** — 15 files; `alternatives.ex`, `doors.ex`,
`self_update.ex`, `status.ex` mention it only in docs. Non-compliant:
F2, F3 (`incoming_live.ex:1408`). Borderline: the `title_detail_host/
acquisition.ex:111/157` plan creation — the view waiting for the plan
id is fine once F3 fixes the insert. Every other call is a view-owned
load, search, preview or artwork warm (`incoming_live.ex` 10 others,
`review_live.ex:114/252`, `episode_mapping_live.ex:84`,
`title_detail_host.ex:368/544/968`, `library_half.ex:202`,
`discovery_live.ex:512`).

**PubSub** — 87 publish sites; ~47 notify a view only. Of those that
carry work, non-compliant: F1, F3 (gate), F5, F8, F9, F10, F11
(`enqueue_images`, `image_ready`). Compliant (a named pass re-derives):
link outcomes → Review (`settle_with_library`), `file_detected` and
`needs_review` (`Rescan.recover`, `rescan_unlinked`), `files_removed`
(`AbsenceSweeper`), `images_pending` (`RetryScheduler`), Reactor ticks
(`tracking_sweep_completed`, `prowlarr :up`, `queue_state`), config and
social listeners (boot reconciles). `entity_published` is compliant for
automatic matches and becomes F1's path for approvals.

**Broadway**

| Pipeline | Fed by | Recovery | Complies |
|---|---|---|---|
| `Pipeline.Discovery` | `pipeline:input` PubSub | `Discovery.Producer` `{:recover}` | Yes |
| `Pipeline.Import` | `pipeline:matched` PubSub from Discovery and Review | automatic: `rescan_unlinked`; approvals: none | No — F1 |
| `Pipeline.Image` | `pipeline:images` PubSub over `ImageQueueEntry` rows | `RetryScheduler` | Yes, once the row exists (F11) |

**Oban workers** — 13. Cron: `Pursuits.Watcher`, `TMDB.CheckJob`,
`ReleaseTracking.SweepJob`, `Retention.SweepJob`,
`ErrorReports.SupersededSweepJob`, `ErrorReports.EvaluatorJob`,
`SelfUpdate.CheckerJob`. Self-scheduled while an integration is down:
`Search.ProbeJob`, `TMDB.ProbeJob`. `IdentityVerifier` is enqueued from
a listener with `LibraryReconciler` as its pass. Enqueued behind a
pending state: `PursueTarget` (F4), `RunPlan` (F3). `ImageRefreshWorker`
(F11).

## Decisions made

* `2026-09-29` — ADR-076 accepted: durability follows the cost of losing
  the work. (commit `f21552c1`)
* `2026-09-29` — The four idempotent Maintenance repairs stay as they
  are: no stored pending state, and losing one costs a re-click. (owner)
* `2026-09-29` — Before any site moves, one standard for building a
  durable job: ADR-077, from a `unify_design` pass. Oban is kept — it
  is the only option that commits the job in the decision's transaction
  (Lite engine, same SQLite file). Orphan rescue by `Oban.Lifeline`
  over a hand-built boot rescue (owner).

## Next steps

1. The shared layer, test-first, one commit each: the test suite to
   `testing: :manual` (107 tests in 13 files to fix, measured
   2026-09-29); `MediaCentaur.Jobs` with the failure handler (F14);
   Lifeline and worker timeouts (F15); `states: :incomplete` (F13).
2. Credo checks for what is static in ADR-077: a worker's `unique`
   declares `states:`; a worker defines `timeout/1`. Rule 1 (insert in
   the transaction) is probably not statically checkable — decide.
3. Move sites, highest cost first: F4, F3, F1 (design first — the
   `Pipeline` → `Library.Inbound` boundary and one job per file vs.
   batching, measured), F8, F6, F7, F5, F2, F9, F10, F11, F12. One
   commit per site (Method step 4).

## Completion criteria

* Every pending state and every carrier site is classified in this file
  against ADR-076, with its disposition.
* No stored pending state lacks a stored job behind it.
* Every move carries a test that loses the carrier and asserts the work
  completes or is reported.
* A decision on whether a Credo check can hold part of the rule (a house
  rule that fits a static check becomes one, per `CLAUDE.md`), and the
  check if so.
* `docs/architecture.md` and `docs/pipeline.md` describe the carriers as
  shipped.

## Pointers

* ADR-076, ADR-049 (owned async), ADR-044 (no blocking I/O in handlers),
  ADR-039 (pursuits), ADR-040 (data migrations enqueue Oban jobs),
  ADR-045 (remount fairness).
* `campaigns/review-coherence.md` — where the gap was found.
* `lib/media_centaur/pipeline/import.ex`, `import/producer.ex`,
  `library/inbound.ex`, `review.ex`.
