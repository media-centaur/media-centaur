---
name: automated-testing
description: "Use this skill at the START of ANY implementation task — new features, bug fixes, refactors, or any code change, not just when writing tests. This repo is strictly test-first: the test is written before the implementation, so this skill must load before you touch code, not after. Also use before writing standalone tests — Elixir, JavaScript, or Playwright E2E. Covers the test-first-for-bugfixes sequence (red → fix → green), factory patterns, stub strategies, E2E parameterization, and all project testing policies."
---

## Core Policies

**Test-first.** Write tests before implementation. The test is the executable specification — if you can't write the test, the requirements aren't clear enough. Stop and clarify.

**Test-first applies to bug fixes too — especially bug fixes.** The sequence is non-negotiable:

1. **Reproduce the bug in a failing test** against the unmodified buggy code. Run it and confirm it fails with the same error the user reported (same exception, same stack frame). If the failure mode differs from production, the test isn't reproducing the bug — fix the test before touching the code.
2. **Apply the fix.**
3. **Run the test and confirm it passes.** Green after red is how you *know* the fix works. Without the red step, you only know the code compiles and the test is consistent with the new code — you do not know the bug is fixed.

Never apply a fix first and write the test after. A test authored against already-fixed code can silently pass against the broken code too (wrong assertion, wrong setup, wrong path exercised) — you lose the proof that the test actually catches the regression. If you already applied a fix before remembering this rule, revert it, write the failing test, re-apply the fix, and verify red → green. The extra minute is the cost of the guarantee.

**Zero tolerance for flaky tests.** Every test must pass deterministically, every time. A flaky test is a bug. Diagnose the root cause. Never skip, retry, or mark as expected failure.

**Zero warnings.** Tests must compile and run with zero warnings — unused variables, unused aliases, log output indicating misconfiguration. `mix precommit` enforces `--warnings-as-errors`.

**Regression tests are append-only** ([ADR-027]). Parser and pipeline tests may only be added, never removed or weakened. Assertions must not be loosened (exact match → substring, tightening bounds). If a test fails after a code change, fix the code.

**Test through the public interface** ([ADR-026], [ADR-012]). Never promote `defp` to `def` for testability. Never use `:sys.get_state`, `GenServer.call/cast` from outside the owning module, or assert on `render_component` HTML output. Extract testable logic into pure function modules.

**Variable naming applies in tests.** Never abbreviate — `file` not `wf`, `movie` not `e`, `result` not `res`.

## LiveView Logic Extraction (Mandatory)

All non-trivial logic in LiveViews and function components must be extracted into public pure functions and unit tested ([ADR-030]). LiveViews are thin wiring — mount, event dispatch, template rendering. Any `if`, `case`, `cond`, or `Enum` pipeline on domain data belongs in an extracted function.

- **Extract into** the same module (1–3 small helpers) or a dedicated helper module (larger clusters).
- **Test with** `async: true` and `build_*` factory helpers — no database, no rendering.
- **Examples:** `file_absent?(file_info)`, `episode_status(episode, progress)`, `progress_label(progress)`, `icon_for_state(state)`, `group_episodes_by_season(episodes)`.

## What We Never Test

- **GenServer internals** — no `:sys.get_state`, no direct `call/cast`. Test public API only. Thin wrappers around external systems (MpvSession, Watcher) are not worth mocking.
- **Rendered HTML** — never assert on HTML output (`render_component`, `=~` on markup). LiveView integration tests (mount, patch, event handling) are fine — they test data flow, not DOM.
- **External API calls** in normal runs — tag `@tag :external`, excluded from default `mix test`.

## Page Smoke Tests (Mandatory for Every Route + Zone)

`test/media_centarr_web/page_smoke_test.exs` mounts every top-level
LiveView route and asserts it renders without crashing. This is the
cheapest possible safety net for the class of bug that pure-helper unit
tests can't catch — a render-path crash (`KeyError`, `BadBooleanError`,
`FunctionClauseError`) that only fires when the template actually
renders with realistic data.

**Rules:**

- **Every new route gets a smoke test entry** added in the same change
  that introduces the route. Same for every zone of a multi-zone
  LiveView (the library page has `?zone=watching`, `?zone=library`,
  `?zone=upcoming` — each needs its own smoke).
- **Seed enough fixture data to exercise the non-trivial render
  branches.** An empty-state-only smoke catches a different (smaller)
  class of bug than one that actually renders cards / rows / overlays.
  When you ship a new template branch (e.g. a theatrical-movie variant,
  a paused-download variant), extend the smoke fixture so the branch
  renders during the test.
- **Per-page setup lives in `page_smoke_test.exs`**, not in per-page
  test files. The smoke is intentionally isolated from feature tests
  so the safety net stays uniform.
- **The smoke is not the primary test** — feature tests still cover
  behaviour. The smoke just guarantees "this route mounts and renders
  for a representative dataset" so render-path regressions surface
  immediately instead of in a user's browser.

If you change a template in a way that adds a new code path, ask
yourself: would the existing smoke fixture exercise this path? If not,
extend the fixture. The bar is "would a reasonable user see this state
in production?"

## Running Tests

```bash
# Elixir
mix test                                              # full suite (excludes :external)
mix test test/path/to/file_test.exs                   # single file
mix test test/path/to/file_test.exs:42                # single test by line
mix precommit                                         # compile + format + boundaries + test

# JavaScript (input system unit tests)
bun test assets/js/input/                             # all input tests
bun test assets/js/input/core/__tests__/              # core framework tests
bun test assets/js/input/__tests__/                   # app-layer behavior tests
bun test assets/js/input/__tests__/nav_graph.test.js  # single file

# E2E (Playwright — requires dev server running)
scripts/input-test                                    # all tests, both input methods
scripts/input-test --project=keyboard                 # keyboard only
scripts/input-test --project=gamepad                  # gamepad only
scripts/input-test library                            # library page, both methods
scripts/input-test --debug                            # headed browser, step through
scripts/input-test --trace on                         # capture trace for replay
scripts/input-test --ui                               # Playwright UI mode
```

---

## Elixir Tests

### Test Case Templates

| Template | When | Async? |
|----------|------|--------|
| `use ExUnit.Case, async: true` | Pure functions (Parser, Serializer, Mapper, Confidence) | Yes |
| `use MediaCentarr.DataCase` | Ecto schema tests, pipeline stages, anything touching DB | No (SQLite) |
| `use MediaCentarrWeb.ConnCase` | HTTP/LiveView connection tests | No |

### Factory — `MediaCentarr.TestFactory`

All tests use the shared factory. Never inline `Ecto.Changeset.cast` / `Repo.insert!` boilerplate.

- **`build_*`** — pure structs with sensible defaults, no DB. For async pure function tests.
  - `build_movie/1`, `build_tv_series/1`, `build_movie_series/1`, `build_video_object/1`, `build_season/1`, `build_episode/1`, `build_extra/1`, `build_image/1`, `build_identifier/1`, `build_progress/1`
- **`create_*`** — persisted via context modules, returns loaded records. For DataCase tests.
  - `create_movie/1`, `create_tv_series/1`, `create_movie_series/1`, `create_video_object/1`, `create_season/1`, `create_episode/1`, `create_extra/1`, `create_image/1`, `create_identifier/1`, `create_linked_file/1`, `create_pending_file/1`, `create_watch_progress/1`

### TMDB Stubbing — `TmdbStubs`

Pipeline tests stub TMDB via `Req.Test` — never use mocking libraries.

```elixir
setup do
  TmdbStubs.setup_tmdb_client(self())  # installs stub client, auto-cleanup
end

test "searches TMDB" do
  TmdbStubs.stub_search_movie(%{title: "Inception", year: 2010})
  # ... call pipeline stage ...
end
```

Helpers: `stub_search_movie/1`, `stub_search_tv/1`, `stub_search_both/2`, `stub_get_movie/2`, `stub_get_tv/2`, `stub_get_season/3`, `stub_get_collection/2`, `stub_tmdb_error/2`, `stub_routes/1` (multi-endpoint).

Fixtures: `movie_search_result/1`, `tv_search_result/1`, `movie_detail/1`, `tv_detail/1`, `season_detail/1`, `collection_detail/1`.

### Image Downloads

`config/test.exs` sets `:image_downloader` to `MediaCentarr.NoopImageDownloader`. No HTTP or file I/O in tests.

### Filesystem Isolation ([ADR-016])

- `config/test.exs` sets `:skip_user_config, true` — no real TOML config loaded
- `config/test.exs` sets `:watch_dirs, []` — no real watch directories
- Tests needing filesystem paths create temp dirs via `System.tmp_dir!()` and override `:persistent_term`

### Pipeline Tests (Broadway)

**Mandatory test-first.** Every pipeline change needs a test written before implementation.

- Call stage functions directly (`run/1`, `Pipeline.process_payload/1`) — no Broadway topology
- Stub TMDB with `TmdbStubs` helpers
- Images use `NoopImageDownloader`
- Test orchestration and state transitions, not leaf functions
- **Never delete or weaken pipeline tests** ([ADR-027])

### Parser Tests

- Real paths only — every test case uses a file path observed in the wild
- One test per filename convention
- Append-only — never delete parser tests ([ADR-027])

### Ecto Schema Tests

- Use `DataCase` with `create_*` factory helpers
- Test through context-module public APIs against the real database — never
  stub the data layer, never call `Repo` directly from tests
- For bulk operations, wrap in `Ecto.Multi` and assert on the transaction result

---

## JavaScript Unit Tests (Bun)

Tests use `bun:test` imports (`describe`, `expect`, `test`, `beforeEach`, `mock`).

### Test Patterns by Module Type

**Pure modules** (`nav_graph.js`, `spatial.js`, `actions.js`, `input_method.js`):
- Test directly, no mocks needed
- Assert on return values

**State machine** (`focus_context.js`):
- Construct `FocusContextMachine` with config
- Set nav graph via `setNavGraph(buildNavGraph(...))`
- Assert on `transition(action)` return value and `machine.context`

**Orchestrator** (`core/__tests__/orchestrator.test.js`):
- Full mock injection via three factories:
  - `createMockReader(overrides)` — controllable reader values. Override per-test: `getItemCount: (ctx) => 8`
  - `createMockWriter()` — proxy recording all calls to `calls` array. Assert: `calls.filter(c => c.method === "focusByIndex")`
  - `createMockGlobals()` — mock document/sessionStorage/rAF. Helpers: `_dispatchKeyDown(key, opts)`, `_dispatchMouseMove(x, y)`, `_flushRAF()`

**Page behaviors** (`__tests__/*_behavior.test.js`):
- Mock DOM interface with only needed methods
- Test behavior method return values
- Example: `mockDom({ filterValue: "" })` with `getFilter()` stub

### Import Boundaries

`core/` never imports from the app layer. Validated by dependency-cruiser via `mix boundaries` (in `mix precommit`). Config: `.dependency-cruiser.cjs`. Tests in `__tests__/` are exempt.

### Mock Writer Returns

The mock writer proxy returns `undefined` from all calls. The real `DomWriter.focusFirst()` and `focusByIndex()` return `boolean`, but orchestrator tests don't depend on return values.

---

## E2E Tests (Playwright)

### Architecture

Every navigation test runs twice — once with keyboard, once with gamepad — via Playwright projects. Tests are input-method-agnostic through the `inputAction` fixture.

**Location:** `test/e2e/`

**Requires:** Dev server running (`mix phx.server` at `http://127.0.0.1:1080`)

### Parameterized Input Method

```javascript
// Import from fixture (NOT from @playwright/test)
import { test, expect } from "./fixtures/input-method.js"

test("arrow down moves focus", async ({ page, inputAction, navigateTo }) => {
  await navigateTo("/dashboard")           // auto-setups gamepad mock if needed
  await inputAction("NAVIGATE_DOWN")       // keyboard: ArrowDown, gamepad: D-pad down
  await expectContext(page, "sections")
})
```

**Fixtures provided by `fixtures/input-method.js`:**
- `inputMethod` — `"keyboard"` or `"gamepad"` (from project config)
- `inputAction(action)` — dispatches semantic action via correct input method
- `navigateTo(path)` — navigates with full LiveView + gamepad setup

**Semantic actions:** `NAVIGATE_UP`, `NAVIGATE_DOWN`, `NAVIGATE_LEFT`, `NAVIGATE_RIGHT`, `SELECT`, `BACK`, `PLAY`, `CLEAR`, `ZONE_NEXT`, `ZONE_PREV`

### Gamepad Mock Strategy

The gamepad mock overrides `navigator.getGamepads()` before the LiveView hook mounts. GamepadSource's rAF polling loop reads mock state naturally — no patching of internal code.

```javascript
import { injectGamepadMock, connectGamepad, pressButton, Button } from "./helpers/gamepad.js"

// Button constants
Button.A      // 0 — Select/Cross
Button.B      // 1 — Back/Circle
Button.Y      // 3 — Clear/Triangle
Button.LB     // 4 — Zone prev
Button.RB     // 5 — Zone next
Button.START  // 9 — Play/Menu
Button.UP     // 12 — D-pad up
Button.DOWN   // 13 — D-pad down
Button.LEFT   // 14 — D-pad left
Button.RIGHT  // 15 — D-pad right

// In page.addInitScript or page.evaluate:
await injectGamepadMock(page, { id: "Xbox Wireless Controller" })
await connectGamepad(page)                // dispatches gamepadconnected
await pressButton(page, Button.DOWN)      // full press-release cycle
await holdButton(page, Button.DOWN)       // press without release (for repeat tests)
await releaseButton(page, Button.DOWN)
await moveAxis(page, 1, 0.8)             // analog stick (axis 1 = left Y)
await centerAxis(page, 1)                // return to zero
await disconnectGamepad(page)
```

### LiveView Wait Helpers

```javascript
import { waitForLiveView, waitForInputSystem, waitForGridItems, navigateAndWait } from "./helpers/liveview.js"

await waitForLiveView(page)              // wait for phx-connected class
await waitForInputSystem(page)           // wait for data-nav-context on <html>
await waitForGridItems(page, { min: 1 }) // wait for grid items in DOM
await waitForSections(page, { min: 1 })  // wait for section items
await waitForSettle(page, 100)           // brief pause for LiveView settle
await navigateAndWait(page, "/settings") // goto + waitForLiveView + waitForInputSystem
```

### Focus & Context Assertions

```javascript
import { expectContext, expectFocused, expectInputMethod, expectControllerType,
         expectFocusInZone, getFocusedNavItem, getZoneItemCount } from "./helpers/input.js"

await expectContext(page, "grid")                        // data-nav-context
await expectFocused(page, "[data-nav-item='entity-id']") // specific element focused
await expectInputMethod(page, "keyboard")                // data-input
await expectControllerType(page, "xbox")                 // data-gamepad-type
await expectFocusInZone(page, "sections")                // focus within zone

const item = await getFocusedNavItem(page)               // data-nav-item of activeElement
const count = await getZoneItemCount(page, "grid")       // items in zone
```

### Writing New E2E Tests

**Pattern for parameterized tests (run in both keyboard + gamepad):**
1. Import from `./fixtures/input-method.js`, not `@playwright/test`
2. Use `navigateTo` fixture for page setup (handles gamepad mock injection)
3. Use `inputAction` for all navigation — never call `page.keyboard.press` directly
4. Use `await getZoneItemCount()` and `test.skip()` when content may be absent
5. Assert on data attributes (`data-nav-context`, `data-input`), not DOM structure

**Pattern for gamepad-only tests:**
1. Import from `@playwright/test` directly
2. Skip with `test.skip(testInfo.project.use.inputMethod !== "gamepad")`
3. Use gamepad helpers directly (`pressButton`, `moveAxis`, etc.)
4. Install mock via `page.addInitScript()` before navigation

**Pattern for keyboard-only tests:**
1. Import from `./fixtures/input-method.js`
2. Skip with `test.skip(inputMethod === "gamepad", "keyboard-only test")`

### Test Suites

| Spec | Page | Key Behaviors |
|------|------|---------------|
| `sidebar.spec.js` | Cross-page | Page transitions, URL persistence, theme toggle, escape chains, input method persistence |
| `dashboard.spec.js` | Dashboard | Sequential section nav, sidebar transitions |
| `settings.spec.js` | Settings | Activate-on-focus, sections ↔ grid, escape chains |
| `review.spec.js` | Review | Master-detail, focus memory, list ↔ detail |
| `library.spec.js` | Library | Grid spatial nav, toolbar, zone tabs, drawer/modal, filter, empty grid |
| `gamepad-specific.spec.js` | Dashboard | Analog stick, deadzone, edge detection, priming, controller type, repeat timing |

### Debug Helpers

```javascript
await enableInputDebug(page)             // window.__inputDebug = true
await disableInputDebug(page)            // window.__inputDebug = false
const msgs = filterDebugMessages(logs)   // filter for [input] prefix
```

---

## Decision Record References

| ADR | Policy |
|-----|--------|
| [ADR-012] | Test-first, spec-first, zero warnings, test through public interface |
| [ADR-016] | Test environment never reads user config or real filesystem paths |
| [ADR-025] | Bulk operations: `return_errors?: true`, check `error_count`, `strategy: :stream` |
| [ADR-026] | GenServer API encapsulation — test public functions, not message protocol |
| [ADR-027] | Regression tests are append-only — never delete or weaken |

[ADR-003]: decisions/architecture/2026-02-20-003-ash-as-exclusive-data-interface.md
[ADR-012]: decisions/architecture/2026-02-27-012-engineering-standards.md
[ADR-016]: decisions/architecture/2026-03-01-016-test-env-filesystem-isolation.md
[ADR-025]: decisions/architecture/2026-03-07-025-ash-bulk-operation-safety.md
[ADR-026]: decisions/architecture/2026-03-07-026-genserver-api-encapsulation.md
[ADR-027]: decisions/architecture/2026-03-07-027-regression-tests-append-only.md
