# Debugging the Test Suite — Slowness & Flakes

Read this when the suite is slow, hanging, or flaking. Not needed to write a test.

```bash
mix test --slowest 30                       # 30 slowest TESTS at the end
mix test <file> --trace                     # per-test wall time, serial (max_cases 1)
mix test --repeat-until-failure 20          # flake hunt — re-run until one fails
mix test --seed 0                           # deterministic order (reproduce a flake)
mix test --timeout 8000 --max-failures 15   # turn hangs into fast, reported failures
```

## Per-test ms excludes `setup`/`on_exit`

A test reporting `8ms` that leaves a ~1s gap before the next one is paying that
second in **teardown** — the supervised-task drain waiting on an un-awaited async
task — not in the test body. `--trace` shows the per-test number; the gap between
lines is the teardown. **Chase the gap, not the number.**

## Gotchas that will waste your time

- **`pkill -f 'mix test'` kills its own shell.** The command's own cmdline contains
  `mix test`, so it matches and dies before reaching the real process. Target a
  unique substring (`pkill -f 'mix test --slowest'`) or check
  `fuser priv/repo/media_centaur_test.db`.

- **`mix test … | tail` shows nothing until the run ends.** `tail` buffers to EOF,
  so you can't watch progress and a mid-run kill loses all output. Redirect to a
  file (`> /tmp/out 2>&1`) and read that.

- **`--trace` sets the per-test timeout to `:infinity`** — useless for hunting
  hangs. Use a low `--timeout` *without* `--trace` so a hung test fails fast with a
  stacktrace at the blocked line.

- **A full run at idle CPU / load < 1 is *blocked*, not slow.** It's waiting on
  timeouts, sleeps, or IO — not computing. Look for `:timer.sleep` in orphaned
  tasks (HTTP retry backoff is the classic), real network calls not stubbed for the
  calling process, or `refute_receive` with long timeouts.

- **Telemetry measurement must filter by the emitting process.** Ecto emits
  `[:media_centaur, :repo, :query]` synchronously in the process that ran the
  query, so an unfiltered handler counts queries from **every** process in the VM.
  Background workers (projection `Cache.Worker`s refreshing on the entity-creation
  PubSub, etc.) firing during the measured window inflate the count — passes in
  isolation, flakes in the full suite (`got 26 vs 15`). Gate the handler on
  `self() == parent`. Reference implementation: `count_queries/1` in
  `test/media_centaur/library_test.exs`. This is a no-op in isolation and
  deterministic under load; any telemetry measurement scoped to "what this code
  did" needs it.

## Slow teardown means unowned async

`DataCase` terminates orphaned supervised tasks after a short grace rather than
waiting on them. If teardown is slow, the cause is async work nobody owns — fix
the seam (see the async-ownership rules in `SKILL.md`), don't extend the wait.
`MC0018` (`no_db_in_on_exit`) catches the related footgun of DB access after the
sandbox has closed.
