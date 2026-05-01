> **Internal contributor guide.** This file describes architecture, conventions, and workflows for people working *on* the codebase (human or AI). End users: see [README.md](README.md).

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
| **ANY implementation** — features, bug fixes, refactors (test-first is mandatory) | `automated-testing` |
| General coding standards, naming, structure | `coding-guidelines` |
| Production debugging, service health, runtime logs | `troubleshoot` |
| UI work — components, CSS, styling, layout, modals, cards, themes | `user-interface` |
| mpv Lua scripts, overlays, key bindings, playback UI | `mpv-extensions` |

Invoke the skill **first**, then explore the codebase, then write code.

# Media Centarr — Backend

A Phoenix/Elixir web application that manages the Media Centarr media library. It is the **write-side** of the system: it creates and edits entity records, scrapes metadata from external APIs, and downloads artwork images. The LiveView web UI provides library browsing, review, playback control, and administration.

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
mix phx.server         # start dev server (http://localhost:1080)
mix test               # run tests (creates and migrates test DB automatically)
mix precommit          # compile --warning-as-errors (incl. boundary), format (Quokka), credo --strict, JS boundaries, deps.audit, sobelow, test
```

### Seeding

```bash
mix seed.review        # populate the review UI with all visual test cases
```

One-shot utility for the review UI's visual test cases. Run once after
initial setup. Idempotent — safe to re-run.

### Config overrides (isolated dev/demo instances)

`MEDIA_CENTARR_CONFIG_OVERRIDE` points at a TOML file that fully replaces
the default (`~/.config/media-centarr/media-centarr.toml`). The override
TOML carries its own `port`, `database_path`, and `watch_dirs`, so a
mis-configured command can't accidentally clobber the real DB. This is
the single mechanism for running dev + demo side-by-side with the
installed release.

Shipped overrides live in `defaults/`:

| TOML | Purpose | Binds |
|------|---------|-------|
| `defaults/media-centarr-showcase.toml` | Demo instance, public-domain media | :4003 |

The dev systemd unit at `defaults/media-centarr-dev.service` does not use a config override — it reads the default `media-centarr.toml` and binds :1080.

```bash
# Showcase demo — public-domain media for screenshots, fully contained
# in priv/showcase/ (git-ignored; rm -rf resets cleanly).
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix ecto.create
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix ecto.migrate
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix seed.showcase
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix phx.server

# Capture marketing screenshots against the showcase (manual only —
# screenshots are NOT regenerated on every deploy):
scripts/screenshot-tour
```

`mix seed.showcase` refuses to run without `MEDIA_CENTARR_CONFIG_OVERRIDE`
set — that guarantee is why the earlier profile mechanism was collapsed
into this single lever.

### Dev service

```bash
scripts/install-dev    # install systemd user service for dev server
```

The dev server can run as a persistent systemd user service. `scripts/install-dev` installs a unit that runs `mix phx.server` via `mise exec`, with a named BEAM node for remote shell access.

```bash
systemctl --user start media-centarr-dev     # start
systemctl --user stop media-centarr-dev      # stop
journalctl --user -u media-centarr-dev -f    # logs
iex --name repl@127.0.0.1 --remsh media_centarr_dev@127.0.0.1   # REPL
```

Disconnect the REPL with `Ctrl+\` (leaves the server running).

### Release + deployment

Shipping a release is tagging the repo — nothing is installed locally by hand any more. The flow:

1. `scripts/preflight` — **pre-flight only.** Builds a production release locally at `_build/prod/rel/media_centarr/` so you can verify the build is clean and the bundled installer is present before tagging. Does NOT install anything.
2. `/ship <level>` (where `<level>` is `major`, `minor`, or `patch`) — runs upgrade-safety checks, drafts a user-facing CHANGELOG entry, bumps `mix.exs`, commits, tags `v<version>`, pushes. The tag is the deployment trigger: `.github/workflows/release.yml` picks it up and publishes the tarball to GitHub Releases.
3. **Local production catches up via the in-app updater.** Settings > Overview → *Update now* downloads and verifies the new tarball through `MediaCentarr.SelfUpdate`, same as any end user. This is the dogfood loop; there is no `scripts/install`.

First-time install on a new machine goes through the public installer (`curl … install.sh | sh`), which drops the bundled `bin/media-centarr-install` into place. Every subsequent update uses the in-app button.

Manual build (if needed):

```bash
MIX_ENV=prod mix assets.deploy && MIX_ENV=prod mix release   # build release
_build/prod/rel/media_centarr/bin/media_centarr start         # run release directly (no install)
```

Migrations in a release: `bin/media_centarr eval "MediaCentarr.Release.migrate()"`.

> Note: When compiling, always use the environment variable `MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8` to parallelize and speed up compilation.

Run `mix precommit` before finishing any set of changes and fix all issues it reports.

**Zero warnings policy.** Application code and tests must compile and run with zero warnings. This includes unused variables, unused aliases, unused imports, and any log output during tests that indicates misconfiguration (e.g., HTTP requests hitting real endpoints instead of stubs). Treat every warning as a bug — fix it before moving on.

## Static Analysis

`mix precommit` runs four analysis tools in addition to format and test. Run them ad-hoc with their own commands:

- **`mix format`** — formatter with the **Quokka** plugin enabled. Quokka reads `.credo.exs` and auto-rewrites many Credo violations during `mix format` (pipe normalization, deprecation rewrites, single-pipe fixes, `with` cleanups, etc.). It is intentionally configured to **skip `:module_directives`** (alias/import reordering) because that rewriter has shadowed stdlib modules in this codebase — see the comment in `.formatter.exs`.
- **`mix credo --strict`** — Credo lints `lib/` and `test/` against `.credo.exs`. Five **custom checks** live in `lib/media_centarr/credo/checks/` and encode house rules:
  - `PredicateNaming` — boolean functions end in `?`, `is_` is reserved for `defmacro`/`defguard` (AGENTS.md).
  - `NoAbbreviatedNames` — bans denylisted parameter names (`wf`, `e`, `ep`, `s`, `res`, `wp`, `ent`).
  - `ContextSubscribeFacade` — LiveViews must subscribe via `Library.subscribe()`/etc., not direct `Phoenix.PubSub.subscribe/2` (see "Context facade subscribe pattern" below).
  - `NoSysIntrospection` — bans `:sys.get_state` and friends in `test/` (ADR-026).
  - `LogMacroPreferred` — code under `lib/media_centarr/` (excluding `console/` and `log.ex`) must use `MediaCentarr.Log` macros, not direct `Logger` calls (see "Thinking Logs" below).

  Plugin checks: `credo_naming` (module/filename consistency, denylisted module-name terms), `credo_envvar` (compile-time env reads), `credo_check_error_handling_ecto_oban` (the `Repo.transaction` 4-tuple-inside-Oban-worker bug). Each tuned/disabled check in `.credo.exs` carries a comment explaining why.
- **`mix sobelow`** — Phoenix-aware security scan (XSS, CSRF, traversal, RCE, hardcoded secrets). Configured via `.sobelow-conf` to ignore `Config.HTTPS` and `Config.CSP` because this app is a self-hosted LAN-only media center; revisit if a public deployment mode is added.
- **`mix deps.audit`** — `mix_audit` checks dependencies against the GitHub Advisory Database for known CVEs.
- **Boundary** — runs as a Mix compiler (no separate command). Each context module declares `use Boundary, deps: [...], exports: [...]` and `mix compile --warnings-as-errors` fails on any cross-boundary call without a declared `dep:`. This is the canonical source of truth for inter-context dependencies — read the `use Boundary` line in each context facade, not prose in this file. See [ADR-029](decisions/architecture/2026-03-26-029-data-decoupling.md) for the rationale.

When you add a new house rule that fits a static check, prefer adding it as a custom Credo check over prose in this file — code-as-spec keeps it enforced.

## Observability for Debugging

Every system — Elixir, JavaScript, or otherwise — must be designed so that Claude Code can get diagnostic feedback when something goes wrong at runtime. Tests passing while the app is broken means the observability gap is the first problem to solve.

- **Elixir/OTP:** The thinking log system (`MediaCentarr.Log`) already covers this. Use it.
- **JavaScript (browser):** The input system has built-in debug logging via `debug()` from `assets/js/input/core/debug.js`. Toggle at runtime: `window.__inputDebug = true`. All messages are prefixed `[input]` and silent by default. Use the Chrome DevTools MCP (`evaluate_script`) to enable/disable and `list_console_messages` to read output. Two call forms: `debug("msg", value)` for cheap args, `debug(() => ["msg", expensiveFn()])` for expensive args (stack traces, deep inspect). The lazy form is zero-cost when disabled. When adding debug logging to other JS systems, follow the same pattern — a toggle-gated function, never bare `console.log`.
- **New systems:** If it's not immediately obvious how to get runtime diagnostic output back to Claude Code, stop and consult with the user on how it should work before proceeding with the fix. Don't guess — the feedback loop is a prerequisite.

## Architecture Principles

- **This app owns all writes.** See [ADR-028](decisions/architecture/2026-03-07-028-backend-write-ownership.md). Only this app writes to `images/` and mutates entities. *Why:* concurrent writers would race on entity records and image files; concentrating writes here lets the pipeline sequence them without cross-process locks.
- **Ecto schemas are the data model.** Field names, types, and associations are defined in the schema modules under `lib/media_centarr/library/`. `specs/DATA-FORMAT.md` describes how those schemas combine into the entry shape the LiveView UI consumes; the schemas themselves are the canonical reference for fields. *Why:* schema-as-spec keeps the data definition next to the code that uses it, so renames and field additions can't drift from a separate document.
- **UUIDs are stable forever.** An entity's UUID is assigned once and never changed. It doubles as the image directory name. Never reassign or reuse a UUID. *Why:* reassigning a UUID would orphan its `data/images/{uuid}/` directory and invalidate every external reference that had resolved it — caches, LiveView state, log entries, existing PubSub IDs in flight.
- **Images: one copy per role.** Store one high-quality image per role (`poster`, `backdrop`, `logo`, `thumb`). Never store multiple resolutions. See `IMAGE-CACHING.md`. *Why:* resizing is cheap at render time, disk is expensive, and storing multiple resolutions multiplies every invalidation path.
- **Shared image service.** `MediaCentarr.Images` is the single download+resize module. Any context that needs to fetch an image from a URL calls `Images.download/3` (with optional resize via libvips) or `Images.download_raw/2` (raw bytes, no processing). The Pipeline's `ImageProcessor` and ReleaseTracking's `ImageStore` both delegate to it. Never write inline HTTP+File.write for images — use `Images`.
- **Every `library_images` row is paired with a `pipeline_image_queue` row that carries its `source_url`.** The queue row is the authoritative pointer back to the original asset. `Library.ImageHealth` detects rows whose files are absent from disk; `Pipeline.ImageRepair.repair_all/0` re-enqueues each via the existing Producer/ImageProcessor chain — reusing the stored `source_url` when present, or re-querying TMDB to reconstruct one (movies via `tmdb_id`; TV/MovieSeries/VideoObject via `library_external_ids`; episodes via parent series + season). Operator entry point: Settings → Library maintenance → "Repair missing images". *Why:* image files can be lost (disk failure, accidental rm, half-completed seed) without the rest of the DB being wrong — the repair path heals just the gap instead of forcing a full re-ingest. Any new code that writes a `library_images` row must also write a queue row, otherwise repair has no source URL to recover from.
- **All mutations broadcast to PubSub.** Any operation that creates, updates, or destroys entities must broadcast `{:entities_changed, entity_ids}` to `"library:updates"`. Collect entity IDs before deletion (they're gone afterward). PubSub subscribers (LiveViews) resolve IDs into updated/removed sets — the broadcaster doesn't need to distinguish. Cross-context interaction uses PubSub events, not direct function calls into another context's internals. *Why:* PubSub is the only reload signal the UI ever gets; a missed broadcast leaves LiveViews stale until the next navigation, and a direct cross-context call silently couples the two contexts against ADR-029.
- **The pipeline is a mediator, not a side effect.** The pipeline actively orchestrates — it calls services, gathers data, and hands results to the library. Domain resources do not trigger pipeline behavior through state changes. *Why:* implicit triggers fan out through hidden paths that are impossible to reason about; explicit orchestration keeps the call graph discoverable and the sequencing deterministic.

## Data Model (Entity Decomposition)

The library uses **type-specific tables** instead of a single polymorphic Entity table. Each media type is a first-class Ecto schema with its own table, associations, and UUID identity.

| Type | Table | Schema | Children |
|------|-------|--------|----------|
| Standalone Movie | `library_movies` (`movie_series_id` NULL) | `Library.Movie` | Extras |
| TV Series | `library_tv_series` | `Library.TVSeries` | Seasons → Episodes, Extras |
| Movie Series | `library_movie_series` | `Library.MovieSeries` | Movies (children), Extras |
| Video Object | `library_video_objects` | `Library.VideoObject` | — |

**Key patterns:**
- Movie serves both standalone movies and MovieSeries children — distinguished by nullable `movie_series_id`
- Images, identifiers, extras, and watched files use type-specific FKs (`movie_id`, `tv_series_id`, `movie_series_id`, `video_object_id`)
- WatchProgress tracks playable items directly via `movie_id`, `episode_id`, or `video_object_id`
- Image directories use the type record's UUID: `data/images/{movie.id}/`, `data/images/{tv_series.id}/`

**Decomposition is complete.** The old `library_entities` table was dropped on 2026-04-03 (`priv/repo/migrations/20260403000002_drop_entity_table.exs`); type-specific tables are the only data path. `library_entity_id` columns survive in unrelated tables (release_tracking, etc.) as references to type-specific UUIDs that were preserved across the data migration — those columns are correct, just legacy-named.

## Bounded Contexts

Ten bounded contexts plus the `MediaCentarr.TMDB` adapter. Each owns its data and broadcasts via PubSub. Cross-context references are enforced at compile time by the Boundary library — see each context's `use Boundary, deps: [...]` declaration for the canonical inter-context dependencies. See [ADR-029](decisions/architecture/2026-03-26-029-data-decoupling.md) for the rationale and sanctioned-deps list.

| Context | Table prefix |
|---------|--------------|
| **Library** | `library_` |
| **Pipeline** | `pipeline_` |
| **Review** | `review_` |
| **Watcher** | `watcher_` (none — in-memory file presence) |
| **Settings** | `settings_` |
| **ReleaseTracking** | `release_tracking_` |
| **Playback** | _(none — in-memory sessions)_ |
| **Console** | _(none — in-memory ring buffer; filter persisted via `Settings.Entry`)_ |
| **Acquisition** | `acquisition_` |
| **WatchHistory** | `watch_history_` |

PubSub topic strings live in `MediaCentarr.Topics` — that's the source of truth for what each context broadcasts and subscribes to. Read that module instead of duplicating topic info here.

**Settings as shared infrastructure:** `Settings` is treated as shared key/value infrastructure in addition to being a bounded context. Any context that needs per-user or per-installation persistence without justifying its own table (Console's filter and buffer cap, for example) may write to `Settings.Entry` directly via a declared `Settings` dep in its `use Boundary`. The coupling is one-directional — Settings carries no domain logic of its own.

**Context facade subscribe pattern:** Each bounded context exposes a `subscribe/0` function that wraps `Phoenix.PubSub.subscribe/2` with the context's topic from `MediaCentarr.Topics`. LiveViews call these instead of constructing PubSub subscriptions directly — topic knowledge stays in the context that owns it:

```elixir
# In mount/3
if connected?(socket) do
  Library.subscribe()
  Playback.subscribe()
  Settings.subscribe()
end
```

## Pipeline

See [`docs/pipeline.md`](docs/pipeline.md) for full pipeline architecture — PubSub-driven event flow, processing stages, idempotency guarantees, and extras handling.

## Specifications

Protocol specifications live in `specs/`. See [specs/README.md](specs/README.md) for the full document table, reading guide, and update workflow. Read the relevant spec (`DATA-FORMAT.md`, `IMAGE-CACHING.md`) before writing code that touches serialization, images, or entity fields.

## UI Design

Load the `user-interface` skill before any UI work. It consolidates design principles, component recipes, CSS conventions, page structure, and all UIDR decisions into one reference.

## Public-facing documentation

End-user documentation lives in **three surfaces**, each with a distinct audience:

| Surface | Location | Audience |
|---|---|---|
| **README** | `README.md` in this repo | GitHub visitors — quick scan, logo, install, links out |
| **GitHub Pages** | `docs-site/index.html` in this repo (auto-deployed via `.github/workflows/pages.yml`) | Marketing / landing page at [media-centarr.github.io/media-centarr](https://media-centarr.github.io/media-centarr/) |
| **GitHub Wiki** | Separate repo cloned to `../media-centarr.wiki/` (jj-colocated) | Fleshed-out user docs — journey-based sidebar nav |

**Internal contributor docs** (`docs/architecture.md`, `docs/pipeline.md`, `docs/input-system.md`, `docs/library.md`, `docs/watcher.md`, `docs/tmdb.md`, `docs/playback.md`, `docs/mpv.md`) stay in this repo, reviewed in PRs, not surfaced on the Pages site or wiki. User-facing pages under `docs/` are pointer stubs to the wiki.

### Keep the wiki in sync with user-visible changes

Whenever a change affects end-user behavior or setup, update the wiki alongside the code **in the same unit of work**:

- New or renamed setting visible in the Settings page → update `Settings-Reference.md`.
- New config file key → update `Configuration-File.md` (and `Adding-Your-Library.md` if it's a watch-dir concern).
- Changes to keyboard / gamepad bindings → update `Keyboard-and-Gamepad.md` and `Keyboard-Shortcuts.md`.
- New or changed UI flow (browsing, playback, review queue, release tracking) → update the corresponding *Using Media Centarr* page.
- New download-client driver or Prowlarr capability → update `Prowlarr-Integration.md` / `Download-Clients.md`.
- New failure mode with a user-actionable fix → add to `Troubleshooting.md`.
- New non-obvious decision about what Media Centarr does or doesn't do → add to `FAQ.md`.

Workflow:

```sh
cd ~/src/media-centarr/media-centarr.wiki
# edit the relevant page(s)
jj describe -m "wiki: <short summary>"
jj bookmark set master -r @
jj git push
```

The wiki repo is a sibling of the main code repo (`~/src/media-centarr/media-centarr.wiki/`), jj-colocated with git. It has its own `master` branch pushed to `git@github.com:media-centarr/media-centarr.wiki.git`.

If a feature is still WIP and the user-visible shape hasn't settled, note the wiki work as a follow-up — but don't mark the feature done without the wiki update.

### Pages site updates

`docs-site/index.html` auto-deploys on any push to `main` that touches `docs-site/**`. Edit, commit, push — the workflow handles deploy. Screenshots live at `docs-site/assets/screenshots/*.png`; keep the paths stable so the placeholder-to-real swap is a drop-in.

## Decision Records

Decision records live in `decisions/` using [MADR 4.0](https://adr.github.io/madr/). See `decisions/README.md` for the category index. **Filename convention:** `YYYY-MM-DD-NNN-short-title.md`, numbered per category.

- **Architecture** (`decisions/architecture/`): system design, data model, integration patterns, engineering standards
- **User Interface** (`decisions/user-interface/`): visual conventions, component behavior, layout patterns, interaction design

**Prefer moduledocs for technical concepts.** Document module-internal contracts (syntax rules, parsing behavior, struct shape, format details) in the relevant `@moduledoc`, not in a decision record. Reserve ADRs for decisions that apply repository-wide or that supersede an existing ADR. The test: would a contributor want to read this while looking at the module, or while browsing `decisions/`? Former → moduledoc. Latter → ADR.

## Defaults

The `defaults/` directory contains git-tracked starter config files — seed values shipped with the repo, **never overwritten at runtime**. **Keep `defaults/media-centarr.toml` complete.** Every configuration key recognised by `MediaCentarr.Config` must have an entry with a logical default value and a comment. The file must always be valid TOML.

## Testing Strategy

Load the `automated-testing` skill before writing any test — Elixir, JavaScript, or Playwright E2E. It covers test-first workflow, factory patterns, stub strategies, E2E parameterization, and all project testing policies.

**Test-first.** Write tests before implementation for all new features and bug fixes. Tests are the executable specification — if you can't write the test, the requirements aren't clear enough.

**Zero tolerance for flaky tests.** Every test must pass deterministically, every time. A flaky test is a bug — diagnose and fix the root cause before moving on. Never ignore, skip, or retry a flaky test.

### Pure Function Tests vs Resource Tests

- **Pure function modules** (no DB, no side effects) use `async: true` and build struct literals via factory.
- **Resource tests** (anything that touches the database) use `DataCase` and exercise against the real database.
### Shared Test Factory

`test/support/factory.ex` provides `MediaCentarr.TestFactory`:

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
- **Image downloads use a no-op.** `config/test.exs` sets `:image_downloader` to `MediaCentarr.NoopImageDownloader`.
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

### Test and Example Content (No Real Show Titles)

Anything we write into the codebase — test queries, fixture titles, `@doc`/`@moduledoc` examples, comment examples, seed data — must use **generic placeholders** (`Sample Show`, `Movie A`, `Sample.Show.S01E01.1080p.WEB-DL.mkv`) or titles already vetted as PD/CC. Don't bake real copyrighted show or film titles into source we author.

This is the same legal-safety story as the showcase PD/CC rule, extended beyond the showcase. Real titles in code drift into screenshots, demos, copy-pasted issues, and grep results.

**Exempt:**

- `test/media_centarr/parser_test.exs` and any other parser regression fixtures — these are real filenames the parser has been observed to handle and are append-only per [ADR-027].
- Production runtime data (logs, real DB rows, the user's own dev media library on disk) — that's user content, not source we author.

When you discover an existing real title in code, replace it. This is not that kind of software — copyrighted titles do not belong in our source, even in tests or fixtures.

## Parser

`lib/media_centarr/parser.ex` is a pure function module — no GenServer, no DB, no side effects. It transforms a file path into a `%Parser.Result{}` struct with title, year, type, season, and episode. See its `@moduledoc` for pattern examples and the decision tree.

- **Real paths only.** Every test case uses a real file path observed in the wild — never synthetic/invented paths.
- **One test per pattern.** Each distinct filename convention gets its own test case with a descriptive test name explaining what makes it unique.
- **NEVER delete or remove parser tests.** See [ADR-027](decisions/architecture/2026-03-07-027-regression-tests-append-only.md). Fix the parser, not the test.

## Thinking Logs

The app has a component-tagged logging system for development visibility. All log entries flow through an Erlang `:logger` handler into an in-memory ring buffer (`MediaCentarr.Console.Buffer`, default 2,000 entries) and are viewable in the browser via the Guake-style **Console** drawer (press `` ` `` backtick). Filter visibility is UI-driven — there is no source-level suppression.

### Usage

```elixir
require MediaCentarr.Log, as: Log
Log.info(:pipeline, "claimed 3 files")
Log.info(:tmdb, fn -> "response: #{inspect(data, limit: 5)}" end)
Log.warning(:watcher, "backlog: #{count} events")
Log.error(:library, "failed to persist entity: #{inspect(reason)}")
```

The `MediaCentarr.Log` module contains only the `info/2`, `warning/2`, and `error/2` macros — call sites never change.

### Components

The handler classifies every entry into one component:

| Component | Source |
|-----------|--------|
| `:watcher` | Explicit via `Log.info(:watcher, ...)` — file events, detection, scanning |
| `:pipeline` | Explicit — processing steps, producer claims, batch results |
| `:tmdb` | Explicit — API calls, rate limiting, confidence scoring |
| `:playback` | Explicit — play/pause/stop, session lifecycle, progress |
| `:library` | Explicit — entity resolver, browser, admin, review |
| `:system` | Fallback — any log without a component tag and no framework prefix |
| `:phoenix` | Automatic — logs from `Phoenix.*` modules |
| `:ecto` | Automatic — logs from `Ecto.*`, `Postgrex.*`, `DBConnection.*` |
| `:live_view` | Automatic — logs from `Phoenix.LiveView.*` modules |

Framework components (`:phoenix`, `:ecto`, `:live_view`) default to HIDDEN in the console filter. Flip their chips to see Ecto queries or Phoenix request logs.

### Accessing the buffer

- **Browser:** press `` ` `` from any page to open the sticky drawer, or navigate to `/console` for the full-page view. Filter chips, level segment, and text search are all live.
- **IEx/Remote shell:** `MediaCentarr.Diagnostics.log_recent(20)` prints the 20 most recent entries. `MediaCentarr.Console.recent_entries/1` returns them as `%Entry{}` structs.
- **Settings page** no longer has a Logging section — all controls moved to the Console.

### Architectural notes

- The bounded context `MediaCentarr.Console` owns the buffer, handler, filter, and view helpers. LiveViews interact only through the `MediaCentarr.Console` public facade (ADR-026).
- `ConsoleLive` (sticky drawer) and `ConsolePageLive` (full-page `/console`) share all mount setup, PubSub handlers, and event handlers via `ConsoleLive.Shared` (`__using__` macro). Each LiveView is thin wiring — mount options, render template, and any view-specific events (e.g. `toggle_console` for the drawer). Pure logic lives in `ConsoleLive.Logic` (ADR-030).
- The buffer survives page navigation and reload (sticky LiveView + server-side state). It is lost on BEAM restart.
- Filter state and buffer size are persisted per-user to `Settings.Entry` with a 2-second debounce.
- See `decisions/architecture/2026-04-05-031-console-log-buffer-and-ui-filtering.md` for the design rationale.

## CSS Animation Rules

- **Never use CSS `animation` (keyframes) on LiveView stream items.** LiveView morphdom re-inserts stream elements on re-render (`reset_stream`, `push_patch`), replaying all animations. This causes visible flashes across the entire grid. Use `phx-mounted` + `JS.transition()` instead — it only fires on DOM insertion and survives morphdom patches.
- **Minimize `reset_stream` calls.** In `handle_params`, compare grid-affecting params against current assigns and only reset when they changed. Selection-only changes (e.g. modal open/close) must skip the reset to avoid unnecessary DOM teardown.
- **`backdrop-filter: blur()` elements must stay in the DOM.** Never use `:if={}` to conditionally render elements with `backdrop-filter`. The browser pays a compositing setup cost on every insertion. Instead, keep the element always rendered and toggle with `data-state` + `visibility: hidden` / `pointer-events: none`.
- **Only animate `opacity` and `transform`.** These are the only compositor-only (GPU-cheap) properties. Animating `background`, `backdrop-filter`, `box-shadow`, or any layout property on a backdrop-filter element forces expensive per-frame recompositing.

## LiveView Callbacks

- **Annotate every callback group with `@impl true`.** Place `@impl true` before the first clause of each callback function name (`mount`, `render`, `handle_event`, `handle_info`, `handle_params`). This is the convention used across all LiveViews in this project.
- **Distinguish mount from selection change in `handle_params`.** On mount, `selected_entity_id` is `nil`. When a URL param like `selected=X` is present, `handle_params` sees `nil → X` as a "change." If you need to reset state only when the user *switches* entities (not on initial load), check that the previous value was non-nil: `selection_changed && socket.assigns.selected_entity_id != nil`. This ensures URL params like `view=info` survive page reload.
- **Iron Law: no DB queries in `mount/3`.** `mount/3` runs twice — once for the static HTTP render and once after the WebSocket connects. The real risk is firing the same query on both paths. The canonical pattern is: subscriptions only in mount, data loading in `handle_params/3` (or a small `ensure_loaded/1` helper called from it) gated by `connected?(socket) and not socket.assigns.loaded?`. `home_live.ex:198-212` is the reference implementation; `acquisition_live.ex:67-79`, `review_live.ex`, `settings_live.ex`, `upcoming_live.ex:80-92`, and `watch_history_live.ex:43-58` follow the same shape. *Why:* doubled queries scale linearly with traffic and degrade as data grows; the Iron Law is a Phoenix-wide invariant, not a project preference. Cheap state setup (struct defaults, MapSet.new(), assigning `nil`) belongs in mount; anything that touches the DB, an ETS table, or a GenServer in another supervision tree belongs in handle_params. **Note:** `library_live.ex:84-90` uses an older variant (content-empty gate) that achieves the same one-load-per-process outcome by different mechanics; pending migration to the canonical pattern.

## LiveView Real-Time Updates

All LiveViews stay current via PubSub — no manual page refreshes. The pattern:

1. **Subscribe in `mount/3`** (inside `if connected?(socket)`) using context facade helpers: `Library.subscribe()`, `Playback.subscribe()`, etc.
2. **Handle PubSub messages in `handle_info/2`** with pattern-matched clauses for each message type. Every LiveView has a catch-all `def handle_info(_msg, socket)` at the end.
3. **Debounce rapid changes** with `debounce(socket, timer_assign, message, delay_ms)` from `LiveHelpers`. Callers that accumulate data (e.g. LibraryLive's pending entity IDs) do so before calling debounce — the utility only manages the timer lifecycle.
4. **Update streams surgically** where possible — `touch_stream_entries` for in-place changes, full `reset_stream` only when sort position may change (new entries).

**Shared utilities in `LiveHelpers`:**
- `debounce/4` — cancel-old-timer + schedule-new-timer, used by LibraryLive, ReviewLive, StatusLive
- `apply_playback_change/5` — pure function for `Map.put`/`Map.delete` on a playback sessions map, used by LibraryLive and StatusLive

## Variable Naming

Write code for humans to read first, compilers second.

- **Never abbreviate** variables to save keystrokes. `file` not `wf`, `movie` not `e`,
  `season` not `s`, `result` not `res`.
- Name the variable what the value *is*, not what type it came from. If you created a
  `WatchedFile` that represents a video file the user dropped in, call it `file` or
  `video_file`, not `watched_file` or `wf`.
- This rule applies everywhere: tests, GenServers, LiveViews, changesets.

Short names that are universally understood Elixir/OTP idioms are fine: `id`, `ok`,
`msg`, `pid`, `ref`, `fn`, `acc` (in reducers). Forbidden are domain abbreviations
that require mental expansion: `wf` (watched_file), `e` (entity), `res` (result),
`s` (season), `ep` (episode). Rule of thumb: if you can't say the name aloud and
have it be clear without context, it's too short.

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
<!-- ex_code_view-start -->
## ex_code_view usage
_⚠️ ALPHA — expect rough edges. Interactive code visualizations for Elixir projects — 3D software city and Ecto ERD, rendered as self-contained HTML._

[ex_code_view usage rules](deps/ex_code_view/usage-rules.md)
<!-- ex_code_view-end -->
<!-- ex_code_view:schema-extractors-start -->
## ex_code_view:schema-extractors usage
[ex_code_view:schema-extractors usage rules](deps/ex_code_view/usage-rules/schema-extractors.md)
<!-- ex_code_view:schema-extractors-end -->
<!-- ex_code_view:viewer-js-start -->
## ex_code_view:viewer-js usage
[ex_code_view:viewer-js usage rules](deps/ex_code_view/usage-rules/viewer-js.md)
<!-- ex_code_view:viewer-js-end -->
<!-- ex_code_view:views-start -->
## ex_code_view:views usage
[ex_code_view:views usage rules](deps/ex_code_view/usage-rules/views.md)
<!-- ex_code_view:views-end -->
<!-- usage-rules-end -->
