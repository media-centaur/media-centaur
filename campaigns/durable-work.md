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
* **Grab.** Handing one chosen release to Prowlarr, which passes it to a
  download client (`Prowlarr.grab/1`).
* **Grabbing target.** A target in status `grabbing`: a release has been
  chosen for it and the grab is owed. It stores the release, and its
  `Jobs.GrabTarget` job performs the grab.

## Goal

Bring the codebase in line with
[ADR-076](../decisions/architecture/2026-09-29-076-durability-follows-the-cost-of-losing-the-work.md):
the mechanism carrying each piece of background work matches what
losing it costs, and no stored pending state lacks a stored job behind
it. Found in Review, where an approval shown as "Importing" rode a PubSub
message a crash could lose.

## Status

Done on branch `durable-work`, awaiting the owner's merge (worktree
`../media-centaur-app-durable-work`). Every area of the *Work list* has a
disposition: the shared layer (tests in `:manual`, failure logging, boot
rescue, MC0041), F1, F3, F4, F5, F7, F9, F10, F11, F12, G1 (F3c, F6, the
manual pick) and M6–M7 built; F2, F8's watch event and listing share, and
M1–M5 declined or deferred with the owner's calls and reasons recorded.
ADR-076 and ADR-077 carry the amendments.

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
5. Before moving a site, check that ADR-077's shape serves it. A job is
   one answer, not the answer: a write can move into the decision's
   transaction (F5, F8's watch event, F12), a reconcile pass can read the
   state (F10), and volume may argue against one job per item (F1). A
   misfit is reported to the owner as a finding, never bent to the rule.

## Work list

The areas, in the order they are taken. Each is analysed when it is
reached — what the case needs, whether ADR-077's shape serves it, the
shape chosen, the test — and the analysis goes under *Analyses* before
any code. Status: **open**, **analysed**, **done**, **declined**.

| # | Area | Status |
|---|---|---|
| S1 | Suite runs Oban in `:manual` (ADR-077 rule 10) | done `abf65eec` |
| F13 | Uniqueness drops new work | done `abf65eec` |
| F14 | Job failures are invisible | done `f323baa0` |
| F15 | No orphan rescue | done `36688ce5` |
| C1 | Credo: a worker's `unique` names its `states:` | done |
| C2 | Credo: a durable job is inserted in the decision's transaction | declined (analysis) |
| F4 | `"seeking"` writers insert after commit | done |
| F3a | Plan solve: `RunPlan` inserted after commit | done |
| F3b | Automatic plan gate rides PubSub | done |
| G1 | A chosen release is owed a grab (F3c, F6, manual pick, `PursueTarget`) | done — layers 1–4; layer 5 declined |
| F3d | Auto-select door runs in a task | done |
| F1 | Review approval rides PubSub to Import | done — row + re-send pass (owner) |
| F8 | Watch completion → history → share on PubSub | done — withdrawals reconciled; watch event and listing share declined (owner) |
| F6 | Picking a release runs in a task, grab before record | done (G1 layer 3) |
| F7 | Setting a rung runs in a task | done |
| F5 | Removed title keeps its seeking targets | done — tracking pursuits reconciled |
| F2 | Deletes run in `start_async` | declined (owner) |
| F9 | Rematch rides two PubSub hops | done |
| F10 | Library → release-tracking listeners | done — dangling containers reconciled; `movies_added` declined |
| F11 | Person-run image and Maintenance work | done — refresh and image rows fixed; Maintenance declined |
| F12 | Remount reset runs async | done |
| M1–M7 | The minor items below the findings table | done — M6, M7 fixed; M1–M5 declined or deferred, with reasons |

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
| F15 | No orphan rescue | `Oban.Lifeline` is off unless configured (Oban 2.24 `Config.normalize_services/1`); not configured | A job running when the node dies stays `executing` for good | Boot rescue, `MediaCentaur.Jobs.rescue_orphans/1` (ADR-077 rule 8, amended) |

**Minor (M1–M7), not ADR-076 violations but the same shape** — take
when touching the file:

* **M1** `settings_live.ex:547` manual update check: a killed check never
  sends `check_complete`; Status stays on `:checking` until the next
  scheduled check. Guarantee the broadcast or run it as `CheckerJob`.
* **M2** `home_live.ex:368`, `library_live.ex:190`, `settings_live.ex:826`
  Scan: runs `Rescan.scan/0` in `start_async`; a closed page skips the
  remaining watchers. Use `Rescan.scan_async/0` as `console_page_live`
  does.
* **M3** `integration_health.ex:237`: a crashed verifier leaves ETS
  `:pending` until retest; `async_nolink` + `:DOWN` would report it.
* **M4** `tmdb_title_changed` (`tmdb/store.ex:508`) and `entities_changed`
  (`library/events.ex:82`) carry projection updates with no named pass
  — stale until the next event for that title.
* **M5** Suspected, unverified: `RetryScheduler` resets `"pending"` image
  rows older than 30 s while they may still be queued in the producer —
  a long backlog could download twice. Needs a test.
* **M6** `Pursuits.Commands.Runner.run/3`: its `@spec` says it returns
  a `Pursuit`, but it returns the work function's value; `log_outcome/2`
  matches only a `Pursuit`, so `ChangeTarget`'s and `AutoCancel`'s
  success lines are never logged.
* **M7** `Jobs.RunPlan`: after the crash rescue writes the plan's error
  it returns `{:error, exception}`, so Oban retries a run that can only
  no-op, and the retry logs a failure warning. Return `:ok` (the crash is
  already reported) or `{:cancel, …}`.

## Analyses

One section per area, written when the area is reached.

### C1 — a worker's `unique` names its `states:` (analysed 2026-09-30)

**The case.** Oban's default unique states (`:successful`) include
`completed`, so a unique worker that names no states silently drops a new
job while a finished one is inside the period. That default caused F13
twice (`RunPlan`, `PursueTarget`) and no test saw it: inline mode skips
uniqueness. Three workers still rely on the default, each deliberately —
`IdentityVerifier` (60 s, one verification per file event),
`ImageRefreshWorker` (60 s, repeat refreshes of one entity),
`CheckerJob` (120 s, a boot check racing a cron tick).

**Does a check fit?** Yes. The mistake is invisible at the call site and
costs a stored state with no job; the rule is purely syntactic (`use
Oban.Worker` with `unique:` and no `states:`), so a static check holds it
exactly with no false positives. It prescribes no value — only that the
choice is written down.

**Shape.** MC0041 `ObanUniqueStatesDeclared`: flag `use Oban.Worker`
whose `unique:` keyword list lacks `states:`. Test: the check's own
`Credo.Test.Case` cases. Each of the three workers was judged on its own:
`IdentityVerifier` and `CheckerJob` keep `:successful`, now written down
with the reason. `ImageRefreshWorker` did not fit its own stated intent
("rapid double-clicks coalesce") — counting completed jobs also dropped a
deliberate second refresh a person asked for after the first finished —
so it moved to the not-yet-started states, with a regression test.

**Done** 2026-09-30.

### C2 — a durable job is inserted in the decision's transaction (analysed 2026-09-30)

**The case.** ADR-077 rule 1. A violation is an `Oban.insert` after the
`Repo.transaction` that wrote the pending state.

**Does a check fit?** No — declined. The transaction and the insert are
often in different functions (`Plans.create_plan/2` →
`insert_units/2`; command → `Helpers.enqueue_pursue/1`), and whether a
row is a *pending state* is semantic. A lexical check would be both
noisy and blind. The rule is held by Method step 4's test instead: every
moved site has a test that stops after the commit and asserts the job
row exists.

### F4 — `"seeking"` writers insert after commit (analysed 2026-09-30)

**The case.** A target in `"seeking"` is owed a search, and
`PursueTarget` is the only thing that searches: policy never acts on a
seeking target, and no pass re-enqueues one. Four writers put a target in
`"seeking"`:

* `ChangeTarget` and `AutoCancel` — `Helpers.insert_seeking_target/1`
  inside `Runner.run`'s transaction, then `Helpers.enqueue_pursue/1`
  after it commits, which logs and swallows an insert failure. The
  `ChangeTarget` moduledoc keeps the insert out "so a rollback cannot
  leave a partial enqueue" — the reverse of what happens: in the
  transaction, a rollback takes the job with it.
* `Targets.rearm_target/1` → `restart_target/2` — the update and the
  insert are two statements with no transaction; the insert's result is
  ignored.
* `CommitPlan.degrade_to_seeking` — compliant (insert in the
  transaction, matched `{:ok, _}`).

**Does ADR-077 fit?** Yes, directly: a stored pending state with an
existing worker. Nothing here argues for another shape.

**Shape.** One function owns "a target enters seeking":
`Targets.start_seeking/1` takes the target changeset, writes it and
inserts `PursueTarget` in one transaction (joining the caller's when
there is one), and returns `{:error, _}` if either fails. All four
writers call it; `Helpers.enqueue_pursue/1` goes, and with it the
swallowed failure; the `ChangeTarget` moduledoc is corrected.

**Test.** `JobRuns.capture_inserts/1` (new) records each Oban insert a
function makes and whether it ran inside a transaction
(`Repo.in_transaction?/0` from a telemetry handler on the insert). Each
writer: the `PursueTarget` insert happened inside the transaction. Red
on the current code for all three non-compliant writers. This is the
Method step 4 test for every later site.

**Done** 2026-09-30, as analysed. No insert-failure test: Oban's insert
cannot be made to fail from a test without a seam, and the rollback on
`{:error, _}` is `Repo.transaction/1`'s own contract.

**Also seen, not F4.** `Runner.run/3`'s `@spec` says it returns a
`Pursuit`; it returns the work function's value, so `log_outcome/2`
never logs for `ChangeTarget` or `AutoCancel` (they return a tuple) —
M6.

### F3 — plan lifecycle (analysed 2026-09-30)

A plan moves `planning` → `ready` → `committed` | `discarded`. Four
different pieces of work hang off it, and they do not all want the same
shape, so F3 is taken as four areas:

* **F3a — the solve.** `"planning"` is owed a `RunPlan`. `create_plan/2`
  inserts it after the plan's transaction commits (`plans.ex:325`);
  `replan/2` updates then inserts with no transaction (`:496`). Same case
  as F4: insert in the transaction, failure rolls back. Test:
  `capture_inserts` on create and replan.
* **F3b — the automatic gate.** A `"ready"` plan whose policy is
  `automatic` (or any tracking draft) is owed a gate decision — commit,
  park, discard or delete (`Reactor.Handlers.gate/1`). Today a
  `PlanEvents.Changed` PubSub message to the Reactor GenServer carries
  it; a lost message leaves an automatic plan waiting on the board and a
  tracking draft blocking its want forever. A stored state owed work:
  ADR-077 fits. Full analysis below.
* **F3c — approval.** `CommitPlan.execute/1` creates the pursuit, grabs
  each release group at Prowlarr (one HTTP call and one transaction per
  group), then stamps `committed`. It runs in its caller — a person's
  approve in `start_async`, or the gate. A crash midway leaves a pursuit
  and some grabs with the plan still `ready`, and a retry is rejected by
  its own overlap check. Not a carrier swap: the grabs must first become
  resumable (grab only groups whose units hold no target yet), and what
  the pursuit watcher does with a unit that has no target yet must be
  known before the pursuit can exist ahead of its grabs. A grab that
  reached Prowlarr before a crash cannot be known to have landed, so a
  retry may grab it again — at-least-once, like `PursueTarget`'s own grab
  (F6 shares this). Analysed in full when reached.
* **F3d — the doors.** The auto-select door, `plan_title/2`, runs the
  targeting fetch and the plan's creation in a fire-and-forget task: a
  person's click with nothing stored until the plan exists, lost with the
  task. It becomes a job the click inserts. The choose-releases door
  (`title_detail_host/acquisition.ex:111,157`) is **not** moved: the
  view waits for the plan id to open its board, nothing is stored until
  the plan exists, and closing the modal abandons it by design — that is
  a view-owned wait, `start_async`'s own row. Once the plan exists, F3a
  makes the rest durable.

#### F3c — approval, in full (2026-09-30): a misfit, with the owner

The outline's shape — commit the pursuit and the plan in one
transaction, then grab the release groups in a resumable job — does not
fit. Between the two, the pursuit's units have no target, and the UI
reads a unit with no target as a fault: *"Unknown — Pursuit has no
target — change target to begin"*, with *Change target* offered
(`PursuitStatus.stage_action(:no_target, …)`). With Prowlarr down the job
holds, so the fault would stand for the whole outage, and *Change
target* would race the job.

The case is wider than F3c. "A chosen release is owed a grab" happens in
four places, each as *grab at Prowlarr, then record*:

| Site | Chooser | Today |
|---|---|---|
| `CommitPlan.grab_assignments` | a plan (person or gate) | F3c |
| `Acquisition.pick_alternative_async` → `PickTarget` | a person, in a task | F6 |
| `Acquisition.pick_targets/2` → `StartFromPick` | a person, manual search | not in the audit |
| `PursueTarget` after its own search | the system | a job, but grabs before it records |

All four share the gap: a crash after the grab and before the record
leaves a download no pursuit knows about, and a retry grabs again.

**Options**

1. **A target that is owed a grab.** A target status (`"grabbing"`)
   carrying the chosen release, covering the units it lands for, written
   with a `GrabTarget` job in one transaction (`Targets.start_seeking/1`'s
   sibling). The job grabs and moves it to `acquired`, or on a failed
   grab degrades it to `seeking` per unit (today's fallback). All four
   sites write the target first and grab in the job; approval and a
   person's pick become synchronous writes. The UI gains one stage
   ("Sending to the download client"). Costs a status (`TargetStatus`,
   `Stage`, `PursuitStatus`, MC's target-status contract check) and
   touches the pursuit model; closes F3c, F6 and the manual-search pick in
   one shape, and `PursueTarget` records before it grabs. A crash after a
   grab still re-grabs on retry — at-least-once, stated, not solved.
2. **F3c alone.** A `GrabPlan` job over the committed pursuit, plus a UI
   rule that a unit with no target under a committing plan reads as
   "Starting". Smaller; leaves three sites with the same gap and a second
   representation of "grab owed" (units without targets).
3. **Move `CommitPlan` into a job as it is.** It outlives the page, but a
   crash midway still half-commits and blocks re-approval. Smallest;
   leaves the defect.

#### F3b — the automatic gate, in full (2026-09-30)

`RunPlan` is the only writer of `"ready"`, on two paths: the normal
finish (`run_plan.ex:127`) and the crash rescue (`failed_changeset`,
which lands in `ready` with an error). Both broadcast
`PlanEvents.Changed`; the Reactor GenServer receives it and runs
`Handlers.gate/1`, which acts only on gated plans — tracking drafts
(delete an empty one, discard when the title stopped grabbing, approve
when something was found and the policy is automatic) and automatic
manual plans (approve only a clean one). A review plan is not gated.

Shape:

* `Plans.Gate` (new module) takes the gate logic out of
  `Reactor.Handlers` unchanged, with `needed?/1` saying whether a plan is
  gated.
* `Jobs.GatePlan` (new worker, `:acquisition`, unique on `plan_id` among
  jobs not yet started) fetches the plan and runs the gate when it is
  still `ready`.
* Both of `RunPlan`'s transitions to `ready` insert `GatePlan` in the
  same transaction when `Gate.needed?/1`.
* The Reactor stops handling `PlanEvents.Changed` and drops its
  `acquisition_updates` subscription, which it held only for this. The
  broadcast stays: views still refresh on it (ADR-076 row 3).

Until F3c, an automatic approval inside `GatePlan` runs `CommitPlan`
there — in a job, so it outlives any page; F3c makes it resumable.

Test: `RunPlan` finishing a gated plan inserts `GatePlan` inside its
transaction, on both paths; a review plan inserts none. The gate's
existing cases (`reactor/handlers_test.exs`) move with it and run
through the job; `drop_planner_test`'s `tick_and_gate` stops calling the
Reactor's handler by hand.

**Done** 2026-09-30, as analysed. Two things surfaced: one drop-planner
test read a plan the gate would have deleted — it passed only because
tests never ran the gate — and now reads it at creation. And `RunPlan`
returns `{:error, exception}` after its crash rescue has already marked
the plan, so Oban retries a run that can only no-op (the plan left
`planning`) — M7.

### F1 — Review approval → Import (analysed 2026-09-30): with the owner

**The case.** An approval stores `PendingFile :approved` ("Importing")
and publishes `{:file_matched, …}` on `pipeline:matched`. The Import
Broadway pipeline fetches metadata and publishes `entity_published`;
`Library.Inbound` ingests and reports the link outcome, which closes the
item. Two PubSub hops; losing either leaves the item "Importing" until the
next boot, when `Review.settle_with_library/0` sets it back to `:pending`
— the approval is undone, not done. Automatic matches take the same two
hops, and boot's `rescan_unlinked` re-derives them (ADR-076 row 2).

**What constrains the shape.** `Pipeline` depends on `Review` (Discovery
consults dismissals; boot recovery settles the queue), so `Review`
cannot insert a Pipeline-owned job without a cycle. And the second hop
into `Library.Inbound` is a PubSub message a job would also have to cross.

**Options**

1. **The approval row is the durable record; a named pass carries it
   out.** `:approved` already stores the decision. Recovery stops undoing
   it: boot re-sends approved-but-unlinked files to Import instead of
   resetting them, and a periodic pass (Oban cron in `Pipeline`) re-sends
   any approved longer than a few minutes ago, so a lost hop costs minutes,
   not a restart. The PubSub nudge stays for latency. Covers both hops
   (an unlinked approval is re-sent whichever one was lost). No boundary
   change, no new job type, Broadway stays for volume. It is ADR-076's
   row 2 for a case the ADR puts in row 1 — the ADR is amended to say a
   stored decision re-sent by a scheduled pass meets the invariant.
2. **An import job for approvals through a port.** `Review` inserts a job
   whose worker `Pipeline` supplies by configuration (the way
   ErrorReports resolves its contributors); the job imports and calls
   ingest directly. Durable to the letter of ADR-077, but approvals and
   automatic matches then take two carriers for one piece of work, and
   ingest gains a second entrance.
3. **One import path through Oban for everything** (the ADR's last rule
   read literally). Replaces the Import Broadway pipeline with a queue,
   Discovery inserts a job per match, approvals need option 2's port, and
   ingest becomes a function the job calls. The largest change; the
   volume cost (thousands of jobs on a first scan, SQLite's one writer)
   is unmeasured, and it rebuilds the part of the pipeline that works.

**Chosen** (owner, 2026-09-30): option 1. **Done**: `settle_with_library/1`
re-sends instead of reopening; `Review.SettleJob` (cron, five minutes,
fifteen-minute in-flight cutoff); Discovery treats an approved file as
settled, so the boot rescan cannot import it twice; ADR-076 amended; the
wiki's Review Queue page on the unpushed `durable-work` branch of the wiki
repo.

### F8 — completion → watch history → share (analysed 2026-09-30): with the owner

**The case.** `ProgressRecords.mark_completed/1` (Library) flips
`WatchProgress.completed` and publishes `entity_watch_completed`;
`WatchHistory.Recorder` records a `WatchEvent` on a task and publishes
`watch_event_created`; `Activities.Publisher` shares a *watched* activity
on a task. Separately, a rung change (`Discovery`) publishes
`title_intent_changed`, and the Publisher shares a *listing* when a title
crosses onto List, or *withdraws* it when the title drops below.

**What constrains the shape.** `WatchHistory` depends on `Library`, so a
completion cannot insert a WatchHistory job; the durable row it leaves
is `completed: true`, with no completion time — `last_watched_at` moves
on every save, and a rewatch reuses the row. `Activities` depends on
`Discovery` and `Library`, so an Activities pass can read intents.

**Three parts, three answers.**

1. **Watch event and the watched share — decline.** Lost only when the
   Recorder or its task dies in the moment after a completion. A pass
   would need a completion time on `WatchProgress` (a migration) and a
   rule for telling a lost completion from a rewatch; the result is one
   history row and one share, rarely. Cost well above the loss.
2. **The listing share — decline.** The toggle is temporal: it governs
   what is said at the moment of listing. A pass that listed every title
   standing at List would publish, when the toggle is next on, titles
   listed while it was off — a change of meaning, not a repair.
3. **The withdrawal — a reconcile pass.** A lost withdrawal leaves a false
   statement on friends' feeds indefinitely, and the fix is state-based
   and safe: every own listing still standing whose title no longer
   stands at List is withdrawn. `Activities` runs it on a schedule (and at
   boot); the PubSub path stays for latency. Outward-facing: a wrong
   answer withdraws a true listing, so the test covers both sides.

### F7 — setting a rung (analysed and done 2026-09-30)

`ReleaseTracking.set_rung/3` wrote the rung (`Discovery.put_rung/3`) and
derived the tracking machinery — a TMDB calendar fetch at Follow and above
— and the title detail ran it on a fire-and-forget task when a calendar
was needed; a crash lost the choice or stored Follow with no tracked
title, for good. ADR-077 fits without a boundary problem: `ReleaseTracking`
owns both halves. `set_rung/3` now writes the rung and inserts
`ReleaseTracking.DeriveJob` in one transaction; the job reads the rung
when it runs (`derive_from_rung/3`), so the latest of quick changes wins.
Setting a rung asks TMDB nothing, which also takes the calendar fetch out
of `DiscoveryLive`'s handlers (its Undo could raise onto Follow).
`set_rung_async/3` is gone.

### F5 — a removed title's searches (analysed and done 2026-09-30)

Removing a tracked item (`ReleaseTracking.delete_item/1`) publishes
`item_removed`; the Reactor cancels in-flight targets on every pursuit of
that title. `Acquisition` depends on `ReleaseTracking`, so the removal
cannot cancel in its own transaction. Two effects, two answers:

* **Tracking pursuits and drafts** (started by release tracking): state
  says it all — a tracking pursuit whose item no longer exists is
  orphaned. `ModeReconciler`, the sweep's existing state-based pass, now
  treats a gone item as withdrawn and cancels with reason `item_removed`
  (a switched-off one keeps `auto_grab_disabled`). A lost message costs
  at most one sweep.
* **Manual pursuits of the same title**: the Reactor cancels these too,
  but only as the removal happens — afterwards "no tracked item" is also
  the normal state of a title never tracked, so no pass can tell a lost
  cancel from a manual download that should run. This effect stays
  best-effort on PubSub.

### F2 — deletes in `start_async` (analysed 2026-09-30): with the owner

**The case.** Review's delete (`ReviewLive.execute_delete/1`) and the
title detail's (`LibraryEvents.run_delete/1`) resolve the target, `rm`
files or `rm -rf` a folder, then clean up records — in the page's
`start_async`, so closing the page mid-delete stops partway. The logic
itself lives in the web layer (the delete-all payload is
`ManagePanel.build_delete_all_payload/2`), and the page shows the result
from memory: "Deleting…", then close the modal, reload the file list, or
flash the failure.

**What losing it costs.** Files already removed: their records heal —
the watcher reports the removal (`files_removed` → the file-event
handlers; `AbsenceSweeper` as the TTL backstop) and Review's rows for them
go the same way. Files not yet removed: still there, still listed, and
deleting again finishes the job. No stored state claims work that isn't
happening; the loss is visible and repeatable.

**Options**

1. **A delete job per surface, the logic moved into its context.**
   `Library` (and `Review`) gain a delete command that inserts a job; the
   job resolves, removes and cleans up, and broadcasts its outcome, which
   the page — if still open — turns into "close / reload / flash". Durable,
   and it moves domain logic out of the web layer, but it touches both
   surfaces' UI flow and `ManagePanel`.
2. **Decline.** The cost of loss is a partial delete a person sees and
   repeats, and the records heal on their own; ADR-076 row 1 by the
   letter, but no stored state lies, and the move is mostly UI plumbing.

**Chosen** (owner, 2026-09-30): option 2, decline. ADR-076 amended.

### F9 — rematch (analysed and done 2026-09-30)

A rematch rode two hops: `Review.Rematch` → `library:commands` →
`Library.Inbound` (teardown) → `review:intake` → `Review.Intake` (queue
rows). A lost first hop costs nothing lasting — the title is still there,
and the person can ask again. A lost second hop was the defect: the
entity gone, its files unlinked and in no queue, until a restart
re-discovered them and could re-import the very match being fixed.

`Review` depends on `Library`, so there is no boundary in the way.
Releasing removes cached artwork from disk (possibly under a media
directory), so it runs in a job rather than the handler: the click
inserts `Review.RematchJob`, which in one transaction releases the entity
(`Library.Rematch.release/1`, moved out of `Inbound`) and adds its files
to the queue. `library:commands` is gone — rematch was its only message —
and `Review.Intake` no longer takes `files_for_review`.

### F10 — library → release tracking (analysed and done 2026-09-30)

`ReleaseTracking` depends on `Library`, so a library write cannot call it;
both reactions ride `LibraryListener`'s PubSub subscriptions.

* **`containers_deleted`** → `detach_library_containers/1`. A lost message
  leaves an item pointing at a container that no longer exists — a fact
  in state, so a pass repairs it: `detach_dangling_containers/0` finds such
  items (`Library.Containers.existing_ids/2`) and runs the same detach and
  reconcile. `SweepJob` calls it every quarter hour.
* **`movies_added`** → the watchlist auto-remove. Declined: it reacts to
  the arrival, never to the state, by design — a person who lists a movie
  they already own keeps it listed — so a pass would change what it means.
  A lost message leaves the movie on the watchlist, which the person sees
  and can remove.

### F11 — image and Maintenance work (analysed and done 2026-09-30)

Four parts, judged separately:

* **`ImageRefreshWorker`** completed as soon as it published
  `{:enqueue_images}`; the producer turned that into queue rows. A lost
  message: the refresh reported done, nothing queued. Now the refresh
  writes the rows itself (`ImageQueue.enqueue/3`, the producer's handler
  for `Library.Inbound`'s message uses the same function) and nudges with
  `images_pending`; a stored pending row is what `RetryScheduler` re-sends.
* **`image_ready`** — the batcher marked entries complete and published the
  image for `Library.Inbound` to record; a lost message left the file on
  disk and no `Library.Image` row, which nothing repairs. `Pipeline` depends
  on `Library`, so the batcher now marks the entries complete and records
  each image (`Library.Images.ready/1`, moved from `Inbound`) in one
  transaction.
* **Clear database** and **Refresh image cache** (Maintenance, on a task):
  declined on F2's precedent — an interruption is visible (a half-cleared
  library, missing artwork) and the person repeats it; no stored state
  claims work that is not happening.

### M1–M7 — the minor items (analysed 2026-09-30)

* **M1, manual update check** — declined. The Settings page runs the check
  in its own task on purpose: its comment records that a
  worker-to-view PubSub gap once left the card stuck on "Checking…", and
  the check's `:manual` source must keep AutoApply from installing on a
  button press — the job path carries neither guarantee. A killed check
  leaves Status reading "Checking" for at most one scheduled tick.
* **M2, Scan buttons** — declined. A scan is re-derived (auto-scan, boot);
  a closed page skips the rest until then, and the page-owned task is what
  gives the button its "scanning" state.
* **M3, integration verifier** — declined. In-memory only (ETS), cleared by
  a retest or a restart; no stored state.
* **M4, TMDB projection messages** — declined for this campaign. No stored
  state claims work; a lost `tmdb_title_changed` leaves descriptive data
  stale until the title changes again. A repair needs a per-title
  "projected at" to compare against the store — its own piece of work if
  it is ever wanted.
* **M5, possible duplicate image downloads** — deferred to a performance
  audit: an efficiency question, not a durability one; a repeated download
  overwrites the same path and `Images.ready/1` upserts.
* **M6, `Runner` outcome logging** and **M7, `RunPlan` crash retries** —
  fixed (`e61bba83`).

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
  (Lite engine, same SQLite file). Orphans are rescued at boot, not by
  `Oban.Lifeline`: Lifeline rescues by age, and a `RunPlan` legitimately
  runs for tens of minutes (owner, after first choosing Lifeline).

## Design — G1: a chosen release is owed a grab (2026-09-30)

Chosen by the owner over F3c's narrower options (see F3c, in full).
Covers F3c, F6, the manual-search pick, and `PursueTarget`'s own grab.

**Lifecycle.** A new target status, `grabbing`:

    grabbing ─┬─► acquired   Prowlarr accepted the grab
              ├─► failed     Prowlarr refused the release; each unit it
              │              covered gets a new seeking target (today's
              │              plan fallback, `Targets.start_seeking/1`)
              └─► cancelled  the person or the system cancelled it

`TargetStatus`: `grabbing` is in flight (a job is alive) and cancellable,
not rearmable. An outage — Prowlarr unreachable, or the download client
refusing the hand-off — does not fail the target: the job holds (snoozes
at the probe cadence), as `RunPlan` and `PursueTarget` do.

**Storage.** The target stores the chosen release (`release`, a map of
the `SearchResult` fields `Prowlarr.grab/1` and `InfoHash.resolve/2`
read), so the grab never depends on the corpus's retention. It covers its
units through `TargetUnit` rows and is each unit's `current_target`, as
an acquired target is today.

**Write.** `Targets.start_grabbing/2` writes the target, its coverage
and the unit pointers, and inserts `Jobs.GrabTarget`, in one transaction
(joining the caller's). Each site keeps its own events and attempt
accounting at the write, where the decision is made.

**Job.** `Jobs.GrabTarget` (`:acquisition`, unique on `target_id` among
jobs not yet started): re-reads the target; acts only while it is
`grabbing`; holds on an outage; grabs; on success resolves the infohash
and moves the target to `acquired` in one transaction; on a refusal
fails it and starts seeking per covered unit. A crash after the grab and
before the record re-grabs on retry: at-least-once, stated, not solved.

**UI.** One stage, `:grabbing`, in `Pursuits.Stage` and
`PursuitStatus` — copy written with the `writing-copy` skill.

**Layers**, each leaving the product working:

1. The mechanism alone — status, column, `start_grabbing/2`,
   `GrabTarget`, the stage. No site uses it.
2. Plan approval (F3c): `CommitPlan` writes the pursuit, one grabbing
   target per release group and `committed` in one transaction; the
   person's approve and the gate call it synchronously.
3. A person's pick of an alternative (F6).
4. The manual-search pick (`pick_targets/2`).
5. `PursueTarget` records its chosen release before grabbing —
   **declined** (analysed 2026-09-30). `PursueTarget` keeps its attempt
   budget, backoff ladder and exhaustion on the target row; routing its
   grab through `GrabTarget` would send a refusal down the pick/plan
   fallback (a new seeking target per unit), resetting that budget on
   every refusal so the pursuit never exhausts. The gap it would close is
   two consecutive statements in a job that is already durable: a crash
   between them re-searches on retry and may grab the same release again,
   which qBittorrent refuses as a duplicate. Splitting the accounting to
   close that window costs more than the window.

## Next steps

Every row of the *Work list* has a disposition. What remains:

1. **Owner:** review and merge branch `durable-work` (worktree
   `../media-centaur-app-durable-work`) and the wiki's `durable-work`
   branch; neither is pushed.
2. Ship: the CHANGELOG entry is drafted at `/ship`. User-visible: a
   manual-search pick no longer reports a refused grab at once — the
   pursuit shows it and searches again; the **Grabbing** stage; an import
   interrupted by a restart resumes by itself; the Approve button has no
   "Approving…" state (approval is instant now).
3. Retire this file once shipped (ADR-042).

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
