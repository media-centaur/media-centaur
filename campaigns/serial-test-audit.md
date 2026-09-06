---
status: planning
started: 2026-09-06
last_updated: 2026-09-06
---
# Audit the tests that are serial by choice

## Goal

Cut suite wall time by moving tests out of the serial phase where nothing
forces them to be there. Measured at 6762 tests, the serial phase is **45% of
the tests and about 80% of the wall time**. Most of that is `DataCase`, which
is serial because SQLite is — not negotiable here. But 38 files are plain
`ExUnit.Case, async: false`: serial by a decision someone made, not by the
database. Those are the only population where the split can actually move, and
each one is either justified or a free win.

## Status

Planning, no code. The measurement below is the whole basis for the campaign;
re-measure before acting on it, because the numbers drift with machine load.

    total ~82s   =   ~15s async phase   +   ~67s serial phase

    async: true    275 files   3595 tests
    async: false   265 files   2925 tests   (182 DataCase, 44 ConnCase, 38 ExUnit.Case)

## Decisions made

* `2026-09-06` — Opened after the Nostr connection tests were split
  (commit `7d73c41`). Serialising that file would have removed its flakiness
  and cost ~0.9s of serial phase; raising its positive `assert_receive`
  budgets achieved the same for free. That trade generalises and is the model
  for this campaign: prefer the fix that costs no wall time.
* `2026-09-06` — `DataCase` files are out of scope. They are serial because of
  SQLite, and changing that is a database-concurrency question, not a test
  hygiene one.
* `2026-09-06` — `mix test --slowest` is **not** a valid input here. Under
  full-suite load it reported one favicon test at 4108ms that runs in 168ms
  alone: the figure was scheduler and sandbox contention, not cost. Any test
  it flags must be re-timed in isolation before anyone optimises it.

## Next steps

1. **Enumerate the 38.** For each, record *why* it is serial. Expect three
   buckets: writes global state (`:persistent_term`, application env, a named
   process, a stubbed client), depends on wall-clock or scheduler timing, or
   has no stated reason at all.
2. **Convert the third bucket first.** A file with no reason is either a free
   win or a latent isolation bug that async exposes. Either outcome is worth
   having; the second is worth more.
3. **For the global-state bucket, check `GlobalStateSandbox`.** It already
   restores every `:persistent_term` key the app owns before each sync test.
   A file serial only because it writes state the sandbox already handles may
   not need to be. A file that writes state the sandbox does *not* handle is a
   candidate for extending the sandbox rather than for staying serial.
4. **For the timing bucket, apply the Nostr lesson.** A wall-clock budget on
   asynchronous work is a test assumption, not a performance assertion.
   Raising a positive `assert_receive` ceiling is free; `refute_receive` waits
   its full budget on every run and must stay small. Converting one of these
   to async usually means fixing a constant, not adding a sleep.
5. **Re-measure after each batch**, back to back on the same machine. Do not
   compare a number taken now against one taken earlier in a session.

## Completion criteria

* Every one of the 38 plain `ExUnit.Case, async: false` files either runs
  async, or carries a one-line comment naming the specific state or timing
  reason it cannot.
* Suite wall time is measured before and after in one sitting, and the delta
  is recorded here.
* No test converted to async becomes flaky: each converted file survives the
  full suite five times consecutively.
* Any isolation bug the conversion exposes is fixed at its root, not by
  reverting the file to serial.

## Pointers

* `test/support/global_state_sandbox.ex` — what is already reset for sync
  tests, and the classification a new stateful child must be added to.
* `.claude/skills/automated-testing/SKILL.md` — the async-ownership rules and
  the "a test that writes global state must be `async: false`" constraint this
  campaign audits against.
* Commit `7d73c41` — the worked example: frame semantics moved to a synchronous
  seam and went fully deterministic; transport kept its socket and got one
  named budget constant.
