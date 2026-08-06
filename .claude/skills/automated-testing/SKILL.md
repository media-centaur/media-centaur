---
name: automated-testing
description: "Use at the START of any implementation task — new feature, bug fix, or refactor — before touching code, because this repo is strictly test-first. Also use before writing any Elixir, JavaScript, or Playwright test."
---

## Core Policies

**Test-first — bug fixes included.** The test is the executable specification. If
you can't write it, the requirements aren't clear enough: stop and clarify.

For a bug fix the sequence is non-negotiable:

1. **Red** — reproduce the bug in a failing test against unmodified code. It must
   fail with the *same* error the user reported (same exception, same stack frame).
   A different failure mode means the test isn't reproducing the bug.
2. **Fix.**
3. **Green** — confirm the test now passes.

A test authored against already-fixed code can silently pass against the broken
code too, so without the red step you have no proof it catches the regression. If
you fixed it before remembering this, revert, write the failing test, re-apply.

**Zero tolerance for flaky tests.** A flaky test is a bug — diagnose the root
cause. Never skip, retry, or mark as expected failure.

**Zero warnings.** `mix precommit` runs `--warnings-as-errors`.

**Regression tests are append-only** ([ADR-027]). Parser and pipeline tests may
only be added — never removed, never weakened (no exact-match → substring, no
loosened bounds). If a test fails after a code change, fix the code.

**Test through the public interface** ([ADR-026]). Never promote `defp` to `def`
for testability; never use `:sys.get_state` or `GenServer.call/cast` from outside
the owning module (MC0004). Extract testable logic into pure function modules.

**No abbreviations, tests included** — `file` not `wf`, `movie` not `e` (MC0002).

## What We Never Test

- **GenServer internals** — public API only. Thin wrappers around external systems
  (MpvSession, Watcher) aren't worth mocking.
- **Rendered HTML** — never assert on markup (`render_component`, `=~` on HTML).
  LiveView integration tests (mount, patch, events) are fine; they test data flow.
- **External APIs** in normal runs — tag `@tag :external`, excluded by default.

**`render_click` is not a browser click.** It reads `phx-value-*` off the rendered
DOM and never runs LiveView's client JS — e.g. it misses the native `value` merge
on `<button>` that clobbers `phx-value-value` to `""` (the interface-scale picker:
green test, dead control, now MC0021). A passing LiveView test only proves the
handler is right *given the params it was handed*. When correctness depends on what
the browser actually sends, the regression layer is a Playwright E2E or a manual
`chromium-probe` click — and "verified" means you ran one.

## LiveView Logic Extraction (Mandatory)

LiveViews are thin wiring — mount, event dispatch, rendering. Any
`if`/`case`/`cond`/`Enum` pipeline on domain data must be extracted into a public
pure function and unit tested ([ADR-030]): same module for 1–3 small helpers, a
dedicated helper module for larger clusters. Test with `async: true` and `build_*`
factories — no database, no rendering. Examples: `file_absent?/1`,
`episode_status/2`, `group_episodes_by_season/1`.

## Async Ownership ([ADR-049])

Flakiness in this codebase lives almost entirely in the LiveView layer (async +
render timing). Pure and synchronous DataCase tests are deterministic. **When a
test flakes, suspect an un-awaited async assign first.**

- **Async work is owned, never orphaned.** In the web layer never
  `Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, …)` — it leaks past
  navigation and orphans under the global supervisor in tests. Use `start_async/3`
  / `assign_async/3` for view loads (cancelled with the LiveView, awaitable in
  tests), or an Oban job for work that must outlive it. Enforced by MC0019.
- **Tests drive async to completion.** Await before asserting —
  `render_async(view)`, `assert_receive`, or a poll-with-deadline on a
  deterministic predicate. Never lean on teardown to settle in-flight work, and
  never `Process.sleep` to "let it settle".
- **Teardown is O(1).** `DataCase` terminates orphaned tasks after a short grace.
  Slow teardown means unowned async — fix the seam, don't extend the wait.

## Page Smoke Tests (Mandatory per Route + Zone)

`test/media_centaur_web/page_smoke_test.exs` mounts every top-level route and
asserts it renders — the cheapest net for render-path crashes (`KeyError`,
`FunctionClauseError`) that pure-helper tests can't catch.

- Every new route — and every zone of a multi-zone LiveView (`?zone=watching`,
  `?zone=library`, `?zone=upcoming`) — gets an entry in the same change.
- Seed enough fixture data to exercise non-trivial render branches. A new template
  branch (theatrical-movie variant, paused-download variant) means extending the
  fixture so it renders. Bar: "would a reasonable user see this in production?"
- Per-page setup lives in `page_smoke_test.exs`, not feature test files, so the net
  stays uniform. The smoke isn't the primary test — behaviour still needs one.

## Elixir Tests

| Template | When | Async? |
|---|---|---|
| `use ExUnit.Case, async: true` | Pure functions (Parser, Serializer, Mapper, Confidence) | Yes |
| `use MediaCentaur.DataCase` | Ecto schemas, pipeline stages, anything touching DB | No (SQLite) |
| `use MediaCentaurWeb.ConnCase` | HTTP/LiveView connection tests | No |

**Factory — `MediaCentaur.TestFactory`** (`test/support/factory.ex`). Always use
it; never inline `Ecto.Changeset.cast` / `Repo.insert!`. `build_*` returns pure
structs for async tests; `create_*` persists via context modules for DataCase
tests. Grep the module for the current helpers rather than guessing a name.

**TMDB — `MediaCentaur.TmdbStubs`** (`test/support/tmdb_stubs.ex`), stubbed via
`Req.Test`; never use a mocking library. Download clients:
`test/support/download_client_stubs.ex`.

```elixir
setup do
  TmdbStubs.setup_tmdb_client(self())   # installs stub client, auto-cleanup
end

test "searches TMDB" do
  TmdbStubs.stub_search_movie(%{title: "Sample Movie", year: 2010})
end
```

**Isolation** ([ADR-016]) — `config/test.exs` sets `:image_downloader` to
`NoopImageDownloader` (no HTTP or file I/O), `:skip_user_config` (no real TOML),
and `:media_dirs, []`. Tests needing real paths create temp dirs via
`System.tmp_dir!()` and override `:persistent_term`.

**Pipeline (Broadway)** — test-first, mandatory. Call stage functions directly
(`run/1`, `Pipeline.process_payload/1`), never the Broadway topology. Test
orchestration and state transitions, not leaf functions. Append-only ([ADR-027]).

**Parser** — real observed paths only, one test per filename convention.
Append-only ([ADR-027]).

**Ecto schemas** — `DataCase` + `create_*`, exercised through context-module public
APIs against the real database. Never stub the data layer, never call `Repo`
directly from a test. Wrap bulk operations in `Ecto.Multi` and assert on the
transaction result.

## Running Tests

```bash
mix test                                # full suite (excludes :external)
mix test test/path/to/file_test.exs:42  # single test by line
mix precommit                           # compile + format + credo + boundaries + audit + test
```

Front-end: `bun test assets/js/input/`, `scripts/input-test` — see
[references/frontend-tests.md](references/frontend-tests.md).

## Further Reference

Read [references/debugging-the-suite.md](references/debugging-the-suite.md) when
the suite is slow, hanging, or flaking.

| ADR | Policy |
|---|---|
| [ADR-016] | Test env never reads user config or real filesystem paths |
| [ADR-026] | GenServer API encapsulation — test public functions, not messages |
| [ADR-027] | Regression tests are append-only — never delete or weaken |
| [ADR-030] | LiveView logic extraction |
| [ADR-049] | Owned async, tests drive async, O(1) teardown |

[ADR-016]: decisions/architecture/2026-03-01-016-test-env-filesystem-isolation.md
[ADR-026]: decisions/architecture/2026-03-07-026-genserver-api-encapsulation.md
[ADR-027]: decisions/architecture/2026-03-07-027-regression-tests-append-only.md
[ADR-030]: decisions/architecture/2026-04-02-030-liveview-logic-extraction.md
[ADR-049]: decisions/architecture/2026-05-22-049-testing-principles.md
