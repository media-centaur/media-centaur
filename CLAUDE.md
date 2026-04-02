Read `AGENTS.md` for Elixir, Phoenix, LiveView, Ecto, and CSS/JS guidelines.

## Skills-First Development

**Always invoke the appropriate thinking skill BEFORE exploring code or writing implementation.** Skills contain paradigm-shifting insights that guide what patterns to look for and what anti-patterns to avoid.

| Area | Skill |
|------|-------|
| General Elixir implementation, refactoring, architecture | `elixir-thinking` |
| LiveView, PubSub, components, mount | `phoenix-thinking` |
| Ecto, schemas, changesets, contexts, migrations | `ecto-thinking` |
| GenServer, Supervisor, Task, ETS, concurrency | `otp-thinking` |
| Oban, background jobs, workflows, scheduling | `oban-thinking` |
| Broadway pipeline, producers, processors, batchers | `broadway` |
| Phoenix web layer, controllers, views, routing | `phoenix-framework` |
| Keyboard/gamepad nav, focus context, nav graphs, page behaviors | `input-system` |
| Writing tests — Elixir, JavaScript, or Playwright E2E | `automated-testing` |
| General coding standards, naming, structure | `coding-guidelines` |
| Production debugging, service health, runtime logs | `troubleshoot` |
| mpv Lua scripts, overlays, key bindings, playback UI | `mpv-extensions` |

Invoke the skill **first**, then explore the codebase, then write code.

# Media Centaur — Backend

A Phoenix/Elixir web application that manages the Media Centaur media library. It is the **write-side** of the system: it creates and edits entity records, scrapes metadata from external APIs, and downloads artwork images. The LiveView web UI provides library browsing, review, playback control, and administration.

## Version Control (Jujutsu)

All repositories use **JJ (Jujutsu)** — never use raw `git` commands.

- After completing a feature: `jj describe -m "type: short description"`
- Use conventional commit style (e.g. `feat:`, `fix:`, `refactor:`). Concise and high-level.
- Amend the existing change for follow-up fixes (if not yet pushed).
- Start unrelated features with `jj new`.
- Adjust the description as scope becomes clearer.

## Build & Run

```bash
mix setup              # install deps, create DB, run migrations, build assets
mix phx.server         # start dev server (http://localhost:4001)
mix test               # run tests (creates and migrates test DB automatically)
mix precommit          # compile --warning-as-errors, unlock unused deps, format, test
mix seed.review        # populate review UI with all visual cases (idempotent)
```

### Dev service

```bash
scripts/install-dev    # install systemd user service for dev server
```

The dev server can run as a persistent systemd user service. `scripts/install-dev` installs a unit that runs `mix phx.server` via `mise exec`, with a named BEAM node for remote shell access.

```bash
systemctl --user start media-centaur-backend-dev     # start
systemctl --user stop media-centaur-backend-dev      # stop
journalctl --user -u media-centaur-backend-dev -f    # logs
iex --name repl@127.0.0.1 --remsh media_centaur_dev@127.0.0.1   # REPL
```

Disconnect the REPL with `Ctrl+\` (leaves the server running).

### Release

```bash
scripts/release              # build production release
scripts/install              # install to ~/.local/lib/media-centaur/ and set up systemd
```

Manual build (if needed):

```bash
MIX_ENV=prod mix assets.deploy && MIX_ENV=prod mix release   # build release
_build/prod/rel/media_centaur/bin/media_centaur start         # run release
```

Migrations in a release: `bin/media_centaur eval "MediaCentaur.Release.migrate()"`. See `docs/getting-started.md#release` for full details including systemd setup.

> Note: When compiling, always use the environment variable `MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8` to parallelize and speed up compilation.

Run `mix precommit` before finishing any set of changes and fix all issues it reports.

**Zero warnings policy.** Application code and tests must compile and run with zero warnings. This includes unused variables, unused aliases, unused imports, and any log output during tests that indicates misconfiguration (e.g., HTTP requests hitting real endpoints instead of stubs). Treat every warning as a bug — fix it before moving on.

## Observability for Debugging

Every system — Elixir, JavaScript, or otherwise — must be designed so that Claude Code can get diagnostic feedback when something goes wrong at runtime. Tests passing while the app is broken means the observability gap is the first problem to solve.

- **Elixir/OTP:** The thinking log system (`MediaCentaur.Log`) already covers this. Use it.
- **JavaScript (browser):** The input system has built-in debug logging via `debug()` from `assets/js/input/core/debug.js`. Toggle at runtime: `window.__inputDebug = true`. All messages are prefixed `[input]` and silent by default. Use the Chrome DevTools MCP (`evaluate_script`) to enable/disable and `list_console_messages` to read output. Two call forms: `debug("msg", value)` for cheap args, `debug(() => ["msg", expensiveFn()])` for expensive args (stack traces, deep inspect). The lazy form is zero-cost when disabled. When adding debug logging to other JS systems, follow the same pattern — a toggle-gated function, never bare `console.log`.
- **New systems:** If it's not immediately obvious how to get runtime diagnostic output back to Claude Code, stop and consult with the user on how it should work before proceeding with the fix. Don't guess — the feedback loop is a prerequisite.

## Architecture Principles

- **This app owns all writes.** See [ADR-028](decisions/architecture/2026-03-07-028-backend-write-ownership.md). Only the backend writes to `images/` and mutates entities.
- **Schema.org is the data model.** All entity fields and types come from schema.org vocabulary. Read `DATA-FORMAT.md` before writing any code that encodes or decodes entity JSON.
- **UUIDs are stable forever.** An entity's `@id` is assigned once and never changed. It doubles as the image directory name. Never reassign or reuse a UUID.
- **Images: one copy per role.** Store one high-quality image per role (`poster`, `backdrop`, `logo`, `thumb`). Never store multiple resolutions. See `IMAGE-CACHING.md`.
- **All mutations broadcast to PubSub.** Any operation that creates, updates, or destroys entities must broadcast `{:entities_changed, entity_ids}` to `"library:updates"`. Collect entity IDs before deletion (they're gone afterward). PubSub subscribers (LiveViews) resolve IDs into updated/removed sets — the broadcaster doesn't need to distinguish. Cross-context interaction uses PubSub events, not direct function calls into another context's internals.
- **The pipeline is a mediator, not a side effect.** The pipeline actively orchestrates — it calls services, gathers data, and hands results to the library. Domain resources do not trigger pipeline behavior through state changes.

## Bounded Contexts

Five contexts own their tables and communicate only via PubSub events. No context aliases another context's modules. See [ADR-029](decisions/architecture/2026-03-26-029-data-decoupling.md).

| Context | Prefix | Owns | PubSub role |
|---------|--------|------|-------------|
| **Library** | `library_` | Entities, seasons, episodes, movies, extras, images, identifiers, watched files, watch progress | Subscribes to `pipeline:publish` and `library:commands`; broadcasts `library:updates` |
| **Pipeline** | `pipeline_` | Image queue | Discovery subscribes to `pipeline:input`; Import subscribes to `pipeline:matched`; broadcasts `pipeline:publish` |
| **Review** | `review_` | Pending files | Intake subscribes to `review:intake`; broadcasts `review:updates` and `pipeline:matched` |
| **Watcher** | `watcher_` | File presence | Broadcasts `pipeline:input` and `library:file_events` |
| **Settings** | `settings_` | Configuration entries | Broadcasts `settings:updates` |

**Acceptable reads:** Pipeline and Watcher may query `library_watched_files` directly (via Repo, not Library context) for dedup checks. Consumer modules (Dashboard, Admin, Playback, Serializer) read Library freely — they are not bounded contexts.

## Pipeline

See [`PIPELINE.md`](PIPELINE.md) for full pipeline architecture — PubSub-driven event flow, processing stages, idempotency guarantees, and extras handling.

## Specifications

Protocol specifications live in `specs/`. See [specs/README.md](specs/README.md) for the full document table, reading guide, and update workflow. Read the relevant spec (`DATA-FORMAT.md`, `IMAGE-CACHING.md`) before writing code that touches serialization, images, or entity fields.

## UI Design

See [`DESIGN.md`](DESIGN.md) for UI principles, page structure, color/theme standards, and component guidelines. Read it before any LiveView, layout, or styling work.

## Decision Records

Decision records live in `decisions/` using [MADR 4.0](https://adr.github.io/madr/). See `decisions/README.md` for the category index. **Filename convention:** `YYYY-MM-DD-NNN-short-title.md`, numbered per category.

- **Architecture** (`decisions/architecture/`): system design, data model, integration patterns, engineering standards
- **User Interface** (`decisions/user-interface/`): visual conventions, component behavior, layout patterns, interaction design

## Defaults

The `defaults/` directory contains git-tracked starter config files — seed values shipped with the repo, **never overwritten at runtime**. **Keep `defaults/backend.toml` complete.** Every configuration key recognised by `MediaCentaur.Config` must have an entry with a logical default value and a comment. The file must always be valid TOML.

## Testing Strategy

Load the `automated-testing` skill before writing any test — Elixir, JavaScript, or Playwright E2E. It covers test-first workflow, factory patterns, stub strategies, E2E parameterization, and all project testing policies.

**Test-first.** Write tests before implementation for all new features and bug fixes. Tests are the executable specification — if you can't write the test, the requirements aren't clear enough.

**Zero tolerance for flaky tests.** Every test must pass deterministically, every time. A flaky test is a bug — diagnose and fix the root cause before moving on. Never ignore, skip, or retry a flaky test.

### Pure Function Tests vs Resource Tests

- **Pure function modules** (Parser, Serializer, Mapper, Confidence, Resume, ProgressSummary) use `async: true` and build struct literals via factory — no database.
- **Resource tests** (Entity, WatchedFile, WatchProgress) use `DataCase` and exercise against the real database.
### Shared Test Factory

`test/support/factory.ex` provides `MediaCentaur.TestFactory`:

- `build_*` functions return plain structs with sensible defaults (no DB). Use for pure function tests.
- `create_*` functions persist records and return loaded records. Use for resource tests.

All tests that need test data use the factory.

### LiveView Logic Extraction (Mandatory)

All non-trivial logic in LiveViews and function components must be extracted into public pure functions and unit tested ([ADR-030](decisions/architecture/2026-04-02-030-liveview-logic-extraction.md)). LiveViews should be thin wiring — mount, event dispatch, and template rendering. Any `if`, `case`, `cond`, or `Enum` pipeline on domain data belongs in an extracted function. Extract into the same module (small helpers) or a dedicated helper module (larger clusters). Test with `async: true` and `build_*` factory helpers.

Examples: `file_absent?(file_info)`, `episode_status(episode, progress)`, `progress_label(progress)`, `icon_for_state(state)`, `group_episodes_by_season(episodes)`.

### What We Never Test

- **GenServer message protocols** — never use `:sys.get_state`, `:sys.replace_state`, or direct `GenServer.call/cast` in tests. Always test through the module's public API ([ADR-026](decisions/architecture/2026-03-07-026-genserver-api-encapsulation.md)). GenServers with testable public logic (Stats, RetryScheduler) should be tested. GenServers that are thin wrappers around external systems requiring real connections (MpvSession → mpv socket, Watcher → inotify) are not worth mocking.
- **Rendered HTML** — never assert on HTML output (`render_component`, `=~` on markup). LiveView integration tests (mount, patch, event handling) are acceptable — they test navigation and data flow, not DOM structure.
- **External API calls** in normal runs — tag `@tag :external` and exclude from default `mix test`.

### Pipeline Tests (Broadway)

**Test-first, mandatory.** Every change to the Broadway pipeline must have a corresponding test written *before* the implementation. The pipeline is the core of the application and bugs here are silent and cascading.

- **TMDB stubs via `Req.Test`.** All pipeline tests that touch TMDB use `test/support/tmdb_stubs.ex`, which installs a `Req.Test`-backed client into `:persistent_term`. Stub responses per-test with `stub_routes/1` or the individual `stub_*` helpers.
- **Image downloads use a no-op.** `config/test.exs` sets `:image_downloader` to `MediaCentaur.NoopImageDownloader`.
- **NEVER delete or weaken pipeline tests.** See [ADR-027](decisions/architecture/2026-03-07-027-regression-tests-append-only.md). Each test represents a real scenario — fix the pipeline, not the test.

### JavaScript Tests (Input System)

All input system JavaScript lives in `assets/js/input/`. Tests are in `assets/js/input/__tests__/` and run with **bun** (not vitest/npx):

```bash
bun test assets/js/input/                              # all input tests
bun test assets/js/input/__tests__/nav_graph.test.js   # single file
```

Tests use `bun:test` imports (`describe`, `expect`, `test`, `beforeEach`, `mock`).

**Test patterns:**

- **Pure modules** (`nav_graph.js`, `spatial.js`, `actions.js`, `input_method.js`) — test directly, no mocks needed.
- **State machine** (`focus_context.js`) — construct a `FocusContextMachine`, set nav graph via `setNavGraph(buildNavGraph(...))`, then assert on `transition()` / `gridWall()` return values and `machine.context`.
- **Orchestrator** (`index.js`) — full mock injection:
  - `createMockReader(overrides)` — returns controllable values for all reader methods. Override per-test with `getItemCount: (ctx) => ...`.
  - `createMockWriter()` — proxy that records all calls to `calls` array. Assert with `calls.filter(c => c.method === "focusByIndex")`.
  - `createMockGlobals()` — mock document/sessionStorage/rAF. Has `_dispatchKeyDown(key, opts)`, `_flushRAF()` helpers.
- **Page behaviors** — inject mock DOM interface, test return values.

**Mock writer returns:** The mock writer's proxy returns `undefined` from all calls. The real `DomWriter.focusFirst()` and `focusByIndex()` return `boolean` (defense-in-depth), but orchestrator tests don't depend on these return values.

### E2E Tests (Playwright)

The input system has E2E tests in `test/e2e/` that exercise real browser interactions. Every navigation test runs twice — once with keyboard, once with gamepad — via Playwright projects. Tests use a parameterized `inputAction` fixture that abstracts input method.

```bash
scripts/input-test                        # all tests, both input methods
scripts/input-test --project=keyboard     # keyboard only
scripts/input-test --project=gamepad      # gamepad only
scripts/input-test library                # library page, both methods
scripts/input-test --debug                # headed browser, step through
```

Requires the dev server running (`mix phx.server`). See the `automated-testing` skill for helpers, fixtures, and gamepad mock strategy.

### Import Boundaries

The input system enforces a strict dependency rule: `core/` never imports from the app layer. This is validated by dependency-cruiser via `mix boundaries` (included in `mix precommit`).

Config: `.dependency-cruiser.cjs`

## Parser

`lib/media_centaur/parser.ex` is a pure function module — no GenServer, no DB, no side effects. It transforms a file path into a `%Parser.Result{}` struct with title, year, type, season, and episode. See its `@moduledoc` for pattern examples and the decision tree.

- **Real paths only.** Every test case uses a real file path observed in the wild — never synthetic/invented paths.
- **One test per pattern.** Each distinct filename convention gets its own test case with a descriptive test name explaining what makes it unique.
- **NEVER delete or remove parser tests.** See [ADR-027](decisions/architecture/2026-03-07-027-regression-tests-append-only.md). Fix the parser, not the test.

## Thinking Logs

The app has a component-level logging system for development visibility. All thinking logs are **info level** and filtered by an Erlang primary filter based on a set of enabled component atoms stored in `:persistent_term`.

### Usage

```elixir
require MediaCentaur.Log, as: Log
Log.info(:pipeline, "claimed 3 files")
Log.info(:tmdb, fn -> "response: #{inspect(data, limit: 5)}" end)
```

### Components

| Component | Covers |
|-----------|--------|
| `:watcher` | File events, size checks, detection, scanning |
| `:pipeline` | Processing steps, producer claims, batch results |
| `:tmdb` | API calls, rate limiting, confidence scoring |
| `:playback` | Play/pause/stop, session lifecycle, progress |
| `:library` | Entity resolver, browser, admin, review |

### IEx Helpers

`Log.enable(:pipeline)`, `Log.disable(:pipeline)`, `Log.solo(:pipeline)`, `Log.mute(:pipeline)`, `Log.all()`, `Log.none()`, `Log.enabled()`, `Log.status()`

### LiveView

Visit `/operations` (Logging section) to toggle components and framework log suppression from the browser.

## CSS Animation Rules

- **Never use CSS `animation` (keyframes) on LiveView stream items.** LiveView morphdom re-inserts stream elements on re-render (`reset_stream`, `push_patch`), replaying all animations. This causes visible flashes across the entire grid. Use `phx-mounted` + `JS.transition()` instead — it only fires on DOM insertion and survives morphdom patches.
- **Minimize `reset_stream` calls.** In `handle_params`, compare grid-affecting params against current assigns and only reset when they changed. Selection-only changes (e.g. modal open/close) must skip the reset to avoid unnecessary DOM teardown.
- **`backdrop-filter: blur()` elements must stay in the DOM.** Never use `:if={}` to conditionally render elements with `backdrop-filter`. The browser pays a compositing setup cost on every insertion. Instead, keep the element always rendered and toggle with `data-state` + `visibility: hidden` / `pointer-events: none`.
- **Only animate `opacity` and `transform`.** These are the only compositor-only (GPU-cheap) properties. Animating `background`, `backdrop-filter`, `box-shadow`, or any layout property on a backdrop-filter element forces expensive per-frame recompositing.

## LiveView Callbacks

- **Annotate every callback group with `@impl true`.** Place `@impl true` before the first clause of each callback function name (`mount`, `render`, `handle_event`, `handle_info`, `handle_params`). This is the convention used across all LiveViews in this project.
- **Distinguish mount from selection change in `handle_params`.** On mount, `selected_entity_id` is `nil`. When a URL param like `selected=X` is present, `handle_params` sees `nil → X` as a "change." If you need to reset state only when the user *switches* entities (not on initial load), check that the previous value was non-nil: `selection_changed && socket.assigns.selected_entity_id != nil`. This ensures URL params like `view=info` survive page reload.

## Variable Naming

Write code for humans to read first, compilers second.

- **Never abbreviate** variables to save keystrokes. `file` not `wf`, `movie` not `e`,
  `season` not `s`, `result` not `res`.
- Name the variable what the value *is*, not what type it came from. If you created a
  `WatchedFile` that represents a video file the user dropped in, call it `file` or
  `video_file`, not `watched_file` or `wf`.
- This rule applies everywhere: tests, GenServers, LiveViews, changesets.

<!-- usage-rules-start -->
<!-- usage_rules-start -->
## usage_rules usage
_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

[usage_rules usage rules](deps/usage_rules/usage-rules.md)
<!-- usage_rules-end -->
<!-- usage_rules:elixir-start -->
## usage_rules:elixir usage
[usage_rules:elixir usage rules](deps/usage_rules/usage-rules/elixir.md)
<!-- usage_rules:elixir-end -->
<!-- usage_rules-start -->
## usage_rules usage
_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

[usage_rules usage rules](deps/usage_rules/usage-rules.md)
<!-- usage_rules-end -->
<!-- usage_rules:otp-start -->
## usage_rules:otp usage
[usage_rules:otp usage rules](deps/usage_rules/usage-rules/otp.md)
<!-- usage_rules:otp-end -->
<!-- usage-rules-end -->
