# Design: a sync test checks the machine out and checks it back in

Campaign: [`campaigns/test-suite-determinism.md`](../../campaigns/test-suite-determinism.md),
problem A. Written with the `unify_design` pass: core idea, greenfield shape,
diff against the code, each incoherence decided, cost named. **Not decided** —
the owner approves the trade before any implementation.

## Glossary

* **Global state** — everything a test can read that the SQL sandbox does not
  roll back: `:persistent_term`, the `:media_centaur` application env, named
  ETS tables, registered process names, live children of
  `MediaCentaur.TaskSupervisor`, and the state of singleton GenServers.
* **Baseline** — the snapshot of global state taken at the end of
  `test_helper.exs`. Every sync test starts from it and returns to it.
* **Checkout / check-in** — Ecto sandbox vocabulary, reused on purpose. A sync
  test *checks out* the machine at entry and *checks it in* at exit.
* **Restorable state** — global state the harness can put back to baseline by
  itself. Restored silently at check-in.
* **Verified state** — global state the harness cannot put back. Compared to
  baseline at check-in; a difference fails the test that made it, with the diff.
* **Disposition** — what a supervision-tree child's state is between tests:
  `:sandboxed`, `:unobservable`, `{:reset, fun}`, or `{:probe, fun}`. Executable,
  not prose.
* **Sync case** — a test module with `async: false`. The only kind of test that
  may write global state, because it is the only kind that owns the machine.

## Core idea

**A sync test checks the machine out and checks it back in. Everything global
is either returned by the harness or proven untouched at check-in — there is no
third category.** Async tests never check out, so they may not write global
state; that is a static property and is checked statically.

Everything below follows from this sentence. `:accepted` is the third category
the sentence forbids.

## Greenfield shape

One module owns the baseline and both edges: `MediaCentaur.GlobalStateSandbox`
(the name is right already).

```
capture_baseline!/0   at the end of test_helper — snapshot of restorable + verified state
checkout/1            entry of every sync test: verify (the async phase must have left
                      the baseline intact), then register check-in
checkin/0             exit of every sync test, in on_exit: restore restorable state,
                      verify verified state, raise with the diff on any difference
```

**Restorable** (put back at check-in, no test carries cleanup for it):

| Store | Rule |
|---|---|
| `:persistent_term` | keys namespaced `MediaCentaur*` — as today |
| application env | `Application.get_all_env(:media_centaur)` — same shape as above |
| singletons `{:reset, fun}` | `Console.Buffer`, `ErrorReports.Buckets`, `SearchSession`, and `TMDB.MetadataStats` once it has a `reset/0` |

**Verified** (compared at check-in, a difference fails the test):

| State | Rule |
|---|---|
| registered names | any `MediaCentaur*` name not in the baseline is a leaked process |
| named ETS tables | any table whose owner is a live app process, not in the baseline or with a changed size — a table the test process created dies with it and is not a leak |
| supervised tasks | `Task.Supervisor.children(MediaCentaur.TaskSupervisor)` is empty — **this is problem B's detector**, the same mechanism |
| singletons `{:probe, fun}` | `fun.()` equals its baseline value: `SelfUpdate.Updater.status/0`, `TMDB.RateLimiter.status/0` |

**Unobservable** singletons need no probe because they have no public read:
`BroadcastCoalescer` (`enqueue/1` only), `FileEventHandler`, `AbsenceSweeper`'s
schedule, `AutoApply` (pure functions only). The inventory test keeps forcing a
disposition for every child; `:accepted` is gone.

**The edge.** ExUnit has no global hook, so the edge is a case template every
sync test inherits. `DataCase` and `ConnCase` already funnel through one setup;
the plain sync files get `use MediaCentaur.SyncCase` (name to decide with the
owner — `MachineCase` says what it owns), whose only job is `checkout/1`. A Credo
check makes it the only way to write a sync test: a bare
`use ExUnit.Case, async: false` (or `use ExUnit.Case` with no `async`) in
`test/**` is a violation. The same check's other half: an `async: true` module
that calls `:persistent_term.put`, `Application.put_env`, `Config.update`,
`Config.put_*`, or `Req.Test.set_req_test_to_shared` is a violation — it is
writing state it does not own.

**Async phase.** Async modules run before any sync module, so a leak from the
async phase is exactly what `checkout/1`'s entry verification sees on the first
sync test. It fails that test with a message naming the cause ("the async
phase left global state dirty; an async test wrote it — see MC00xx"). The
attribution is to the phase, not the test; the static check is what makes
this near-impossible, the runtime check is what makes it loud.

## Diff against reality

| Greenfield | Today | Gap |
|---|---|---|
| check-in restores | `restore!/1` at DataCase/ConnCase **entry** only | (c) the wrong edge; plain sync files uncovered — the seed-310401 failure |
| app env restorable | 17 files save/restore by hand | (b) scattered → one rule, same shape as `:persistent_term` |
| ETS verified | outside the inventory; three inert `on_exit` `:ets.delete` sites | (b) |
| registered names verified | nothing | (c) |
| live tasks verified | `DataCase` drain: 100 ms grace then `Process.exit(:kill)`, silently | (c) the detector for problem B is the thing the drain hides |
| `{:probe, fun}` | `:accepted` with a sentence — six children | (c) problem 2 |
| `MetadataStats` `{:reset, _}` | `:accepted` because a test "asserts on its own rows instead" | (c) the exact rot pattern problem 2 describes |
| one sync template | 37 plain `ExUnit.Case, async: false` files, 2 templates | (a) the seam exists (`setup_sandbox/1`); the plain files need one line each |
| static check | none | new custom Credo check |
| hand-rolled restores | ~12 files restore `{Config, :config}` in `on_exit`; `VerifierTest` nulls keys in setup | (b) all deletable once check-in restores; keeping them is two mechanisms |
| `TaskAwaits.await_supervised_tasks/0` | opt-in remedy | keep — it is how a test *owns* its async; check-in is the detector that says when it was forgotten |

## Incoherences, each decided

1. **Verify or restore `:persistent_term`?** Restore. Writing it is what
   `async: false` is for; verifying it would recreate problem 5 (every test
   undoing its own legitimate writes). Verify only what cannot be restored.
   *Fix now.*
2. **Live task at check-in: grace window or zero tolerance?** Zero tolerance.
   A grace window is a threshold, and a threshold under load is a problem-C
   flake. ADR-049 already says a test drives its async to completion; a live
   task at exit is a test that did not. The kill stays (so the task cannot hit
   the next test) but it follows a failure, not replaces one. *Fix now; the
   day-one failure count is unknown (see Cost).*
3. **ETS: restore or verify?** Verify. Restoring means the harness writing
   projection tables, a coupling to how each projection uses ETS. In `:test`
   no long-lived process owns one today, so verify costs nothing until the
   day it fires, and then the fix is at the seam. *Fix now.*
4. **Entry-dirty fails the first sync test.** Wrong test, right message,
   deterministic at a seed. The alternative — restore silently at entry — is
   problem 5 inside the harness. *Fix now, message names the async phase.*
5. **`MetadataStats`** gets `reset/0` and becomes `{:reset, _}`; the
   `status_live_test` workaround that "asserts on its own rows" is reviewed
   and, if it exists only to dodge the singleton, simplified. *Fix now.*
6. **`serial-test-audit`** converts sync files to async. The static check
   ("async tests do not write global state") is precisely the criterion that
   audit needs to convert safely. The two campaigns stay separate; this one
   hands the other a tool. *Scheduled: the audit runs after this lands.*
7. **Documentation** — `automated-testing` skill ("Global state is reset for
   you") and the `GlobalStateSandbox` moduledoc describe the entry-only model.
   Rewritten to checkout/check-in in the same change. *Fix now.*
8. **The probe formatter** stays as an instrument. Check-in reports the leak;
   the probe is still how you watch the whole run. *Keep.*

## Cost, honestly

* `GlobalStateSandbox`: the baseline grows from one store to five, plus
  `checkout/1` / `checkin/0` and the disposition vocabulary change. Roughly
  +150 lines and a rewritten test.
* `MediaCentaur.SyncCase` (or whatever it is named): ~20 lines. 37 files
  change one `use` line.
* Deletions: ~17 app-env restores, ~12 Config restores, 3 ETS deletes,
  `VerifierTest`'s setup nulling. Net negative in test code.
* Custom Credo check + its test: ~80 lines.
* `MetadataStats.reset/0`, `Updater`/`RateLimiter` probes: small.
* **Unknown:** how many tests fail on day one under zero tolerance for live
  tasks and under ETS/registered-name verification. Measured before the
  change by running the drain in report-only mode once. The orphan crash
  appears once per run, so the expected number is small, not zero.
* The `DataCase` change (drain → verify) touches every sync test's teardown.
  One precommit run tells the truth; no partial landing.

The cheap path — add a restore call to the 37 plain files and move on — would
fix seed 310401 and leave `:accepted`, the drain, and two uncovered stores
exactly as they are. That is the bolt-on this document exists to refuse.

## Open for the owner

* Name of the sync template: `MediaCentaur.SyncCase` or `MediaCentaur.MachineCase`.
* Zero tolerance for live tasks at check-in (incoherence 2) — confirm.
* Entry-dirty fails the first sync test (incoherence 4) — confirm.
