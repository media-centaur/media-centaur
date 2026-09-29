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

## Goal

Bring the codebase in line with
[ADR-076](../decisions/architecture/2026-09-29-076-durability-follows-the-cost-of-losing-the-work.md):
the mechanism carrying each piece of background work matches what
losing it costs, and no stored pending state lacks a stored job behind
it. Found in Review, where an approval shown as "Importing" rode a PubSub
message a crash could lose.

## Status

Planning. Inventory reconciled and every site classified (2026-09-29,
below). Twelve findings, F1–F12. Two owner decisions open (*Next
steps*). No code yet.

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

## Next steps

1. **Owner decision:** do the four idempotent Maintenance repairs
   (`refresh_movie_subtitles`, `repair_missing_images`,
   `refetch_backdrops`, `rederive_extra_names`) fall under ADR-076 row 1?
   Nothing stores them as pending and losing one costs a re-click.
2. **Owner decision:** the order of work. Proposed: F4 and the
   `RunPlan` inserts of F3 first (post-commit inserts; small, mechanical,
   and they leave states nothing recovers), then F1 (design), the rest
   of F3, F8, F6, F7, F5, F2, F9, F10, F11, F12.
3. Design the single import path (F1) — `unify_design` pass; the job's
   last step needs a design for the `Pipeline` → `Library.Inbound`
   boundary (call ingest, or await the link outcome). Record it here.
4. Decide whether a Credo check can hold "no `Oban.insert` after a
   `Repo.transaction` that writes a pending state" — likely not
   statically; consider a single `enqueue-in-transaction` helper the
   check can require instead.
5. Move sites one per commit (Method step 4).

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
