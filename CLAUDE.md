Read `AGENTS.md` for Elixir, Phoenix, LiveView, Ecto, and CSS/JS guidelines.

## Skills-First Development

**Always invoke the appropriate thinking skill BEFORE exploring code or writing implementation.** Skills contain paradigm-shifting insights that guide what patterns to look for and what anti-patterns to avoid.

| Area | Skill |
|------|-------|
| General Elixir implementation, refactoring, architecture | `elixir-thinking` |
| LiveView, Channels, PubSub, components, mount | `phoenix-thinking` |
| Ecto, schemas, changesets, contexts, migrations | `ecto-thinking` |
| GenServer, Supervisor, Task, ETS, concurrency | `otp-thinking` |
| Oban, background jobs, workflows, scheduling | `oban-thinking` |
| Ash resources, domains, actions, changes | `ash-framework` |
| Broadway pipeline, producers, processors, batchers | `broadway` |
| Phoenix web layer, controllers, views, routing | `phoenix-framework` |
| General coding standards, naming, structure | `coding-guidelines` |

Invoke the skill **first**, then explore the codebase, then write code.

# Media Centaur — Backend

A Phoenix/Elixir web application that manages the Media Centaur media library. It is the **write-side** of the system: it creates and edits entity records, scrapes metadata from external APIs, and downloads artwork images. The `frontend` app connects via WebSocket (Phoenix Channels) to receive library data, send playback commands, and get real-time updates.

## Version Control (Jujutsu)

See [specifications/CLAUDE.md](../specifications/CLAUDE.md) for Jujutsu workflow.

## Build & Run

```bash
mix setup              # install deps, create DB, run migrations, build assets
mix phx.server         # start dev server (http://localhost:4000)
mix test               # run tests (creates and migrates test DB automatically)
mix precommit          # compile --warning-as-errors, unlock unused deps, format, test
```

### Release

```bash
MIX_ENV=prod mix assets.deploy && MIX_ENV=prod mix release   # build release
_build/prod/rel/media_centaur/bin/media_centaur start         # run release
```

Migrations in a release: `bin/media_centaur eval "MediaCentaur.Release.migrate()"`. See `docs/getting-started.md#release` for full details including systemd setup.

> Note: When compiling, always use the environment variable `MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8` to parallelize and speed up compilation.

Run `mix precommit` before finishing any set of changes and fix all issues it reports.

**Zero warnings policy.** Application code and tests must compile and run with zero warnings. This includes unused variables, unused aliases, unused imports, and any log output during tests that indicates misconfiguration (e.g., HTTP requests hitting real endpoints instead of stubs). Treat every warning as a bug — fix it before moving on.

## Ash-Driven Migrations

**Never hand-write or manually edit Ecto migrations.** Always design Ash resources first (attributes, identities, relationships), then run `mix ash_sqlite.generate_migrations --name <short_name>` to auto-generate the migration. The resource definition is the source of truth — the migration is a derived artifact. If a migration needs custom SQL (data backfill, deduplication, table recreation for SQLite constraints), create a **separate** manual migration file — never edit or replace an Ash-generated migration. Never use `Ecto.Migration` directly to create, alter, or drop tables managed by Ash resources.

## Architecture Principles

- **Ash is the only data interface.** Never write raw SQL queries, use `Ecto.Query`, call `Repo` directly, or use `execute()` with SQL strings in application code or migrations. All database reads and writes go through Ash actions — no exceptions. If Ash doesn't have the necessary action or capability for an operation, plan and implement the missing Ash action first — never bypass Ash with manual queries. This includes data migrations: use Ash actions in a `Mix.Task` or seed script, not raw SQL.
- **Use bulk APIs for bulk operations.** When operating on multiple records (destroy, update, create), always use `Ash.bulk_destroy/3`, `Ash.bulk_update/4`, or `Ash.bulk_create/4` — never loop `Ash.destroy!/1` or `Ash.update!/2` over individual records. If a resource lacks the necessary action for a bulk operation, add it first. Bulk APIs let the data layer execute a single query instead of N+1.
- **This app owns all writes.** Only the manager writes `images/`. The `frontend` never writes these files.
- **Schema.org is the data model.** All entity fields and types come from schema.org vocabulary. Read `DATA-FORMAT.md` before writing any code that encodes or decodes entity JSON.
- **UUIDs are stable forever.** An entity's `@id` is assigned once and never changed. It doubles as the image directory name. Never reassign or reuse a UUID.
- **Phoenix Channels is the integration point with the UI.** The UI connects via WebSocket (`/socket`) and joins `library` and `playback` channels. The backend sends the full library on join and pushes all data and state changes in real time.
- **Images: one copy per role.** Store one high-quality image per role (`poster`, `backdrop`, `logo`, `thumb`). Never store multiple resolutions. See `IMAGE-CACHING.md`.
- **Batch all channel entity pushes.** Any code path that pushes entity lists or entity-removal IDs to a channel must chunk the payload using the channel's `@batch_size`. Never push an unbounded list of entities in a single message — bulk operations can touch every entity in the library.
- **All mutations broadcast to PubSub.** Any operation that creates, updates, or destroys entities must broadcast `{:entities_changed, entity_ids}` to `"library:updates"`. Collect entity IDs before deletion (they're gone afterward). The channel handler resolves IDs into updated/removed sets — the broadcaster doesn't need to distinguish. Cross-context interaction uses PubSub events, not direct function calls into another context's internals.
- **Bulk operations must never silently discard errors.** Always pass `return_errors?: true` to `Ash.bulk_update/4`, `Ash.bulk_create/4`, and `Ash.bulk_destroy/3`. Check `result.error_count` and log or propagate errors — never assume `result.records || []` is safe without checking for failures first. Silent bulk failures are invisible and can stall entire subsystems.
- **Bulk operations on non-atomic actions need `strategy: :stream`.** AshSqlite cannot express `attribute_in`/`attribute_equals` validations as atomic SQL. Actions with these validations must set `require_atomic? false`, and any `bulk_update`/`bulk_create` call on such actions must pass `strategy: :stream` — otherwise the default `[:atomic]` strategy fails with `NoMatchingBulkStrategy`.
- **Ash changes are for intrinsic data operations only.** Ash changes must NOT orchestrate external integrations, call APIs, download files, or cross context boundaries. They are appropriate for validation and transformation intrinsic to a resource.
- **The pipeline is a mediator, not a side effect.** The pipeline actively orchestrates — it calls services, gathers data, and hands results to the library. Domain resources do not trigger pipeline behavior through state changes.

## Pipeline

See [`PIPELINE.md`](PIPELINE.md) for full pipeline architecture — PubSub-driven event flow, processing stages, idempotency guarantees, and extras handling.

## Specifications

Cross-component specifications live in `../specifications`. See [specifications/CLAUDE.md](../specifications/CLAUDE.md) for the full document table, reading guide, and update workflow. **Every contract between the backend and the frontend must be documented in a specification file.** Read the relevant spec (`DATA-FORMAT.md`, `IMAGE-CACHING.md`) before writing code that touches serialization, images, or entity fields.

## UI Design

See [`DESIGN.md`](DESIGN.md) for UI principles, page structure, color/theme standards, and component guidelines. Read it before any LiveView, layout, or styling work.

## Architecture Decision Records

ADRs live in `adrs/` using [MADR 4.0](https://adr.github.io/madr/). See `adrs/template.md` for the blank template. **Filename convention:** `YYYY-MM-DD-NNN-short-title.md`.

## Defaults

The `defaults/` directory contains git-tracked starter config files — seed values shipped with the repo, **never overwritten at runtime**. **Keep `defaults/backend.toml` complete.** Every configuration key recognised by `MediaCentaur.Config` must have an entry with a logical default value and a comment. The file must always be valid TOML.

## Testing Strategy

**Test-first.** Write tests before implementation for all new features and bug fixes. Tests are the executable specification — if you can't write the test, the requirements aren't clear enough.

**Zero tolerance for flaky tests.** Every test must pass deterministically, every time. A flaky test is a bug — diagnose and fix the root cause before moving on. Never ignore, skip, or retry a flaky test.

### Pure Function Tests vs Resource Tests

- **Pure function modules** (Parser, Serializer, Mapper, Confidence, Resume, ProgressSummary) use `async: true` and build struct literals via factory — no database.
- **Ash resource tests** (Entity, WatchedFile, WatchProgress) use `DataCase` and exercise Ash actions against the real database.
- **Channel tests** use `ChannelCase` and verify wire format contracts.

### Shared Test Factory

`test/support/factory.ex` provides `MediaCentaur.TestFactory`:

- `build_*` functions return plain structs with sensible defaults (no DB). Use for pure function tests.
- `create_*` functions persist via Ash actions and return loaded records. Use for resource and channel tests.

All tests that need test data use the factory. Never inline `Ash.Changeset.for_create` boilerplate in tests.

### What We Never Test

- **GenServer internals** (Watcher, Config, MpvSession, PlaybackManager) — implementation details, not contracts.
- **LiveView DOM** — LiveViews are thin presentation layers. Test the data contracts they consume, not the DOM they render.
- **External API calls** in normal runs — tag `@tag :external` and exclude from default `mix test`.

### Pipeline Tests (Broadway)

**Test-first, mandatory.** Every change to the Broadway pipeline must have a corresponding test written *before* the implementation. The pipeline is the core of the application and bugs here are silent and cascading.

- **TMDB stubs via `Req.Test`.** All pipeline tests that touch TMDB use `test/support/tmdb_stubs.ex`, which installs a `Req.Test`-backed client into `:persistent_term`. Stub responses per-test with `stub_routes/1` or the individual `stub_*` helpers.
- **Image downloads use a no-op.** `config/test.exs` sets `:image_downloader` to `MediaCentaur.NoopImageDownloader`.
- **NEVER delete or weaken pipeline tests.** Each test represents a real scenario that has caused or could cause silent data corruption. If a pipeline change causes a test to fail, fix the pipeline — do not delete or relax the assertion.

## Parser

`lib/media_centaur/parser.ex` is a pure function module — no GenServer, no DB, no side effects. It transforms a file path into a `%Parser.Result{}` struct with title, year, type, season, and episode. See its `@moduledoc` for pattern examples and the decision tree.

- **Real paths only.** Every test case uses a real file path observed in the wild — never synthetic/invented paths.
- **One test per pattern.** Each distinct filename convention gets its own test case with a descriptive test name explaining what makes it unique.
- **NEVER delete or remove parser tests.** Every existing test case represents a real filename pattern observed in the wild. If a parser change causes an existing test to fail, fix the parser — do not delete or weaken the test. Tests may only be added, never removed.

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
| `:channel` | Library sync, entity pushes, playback commands |
| `:library` | Entity resolver, browser, admin, review |

### IEx Helpers

`Log.enable(:pipeline)`, `Log.disable(:pipeline)`, `Log.solo(:pipeline)`, `Log.mute(:pipeline)`, `Log.all()`, `Log.none()`, `Log.enabled()`, `Log.status()`

### LiveView

Visit `/operations` (Logging section) to toggle components and framework log suppression from the browser.

## LiveView Callbacks

- **Annotate every callback group with `@impl true`.** Place `@impl true` before the first clause of each callback function name (`mount`, `render`, `handle_event`, `handle_info`, `handle_params`). This is the convention used across all LiveViews in this project.

## Variable Naming

Write code for humans to read first, compilers second.

- **Never abbreviate** variables to save keystrokes. `file` not `wf`, `movie` not `e`,
  `season` not `s`, `result` not `res`.
- Name the variable what the value *is*, not what type it came from. If you created a
  `WatchedFile` that represents a video file the user dropped in, call it `file` or
  `video_file`, not `watched_file` or `wf`.
- This rule applies everywhere: tests, GenServers, LiveViews, Ash changes.

<!-- usage-rules-start -->
<!-- ash-start -->
## ash usage
_A declarative, extensible framework for building Elixir applications._

[ash usage rules](deps/ash/usage-rules.md)
<!-- ash-end -->
<!-- ash_ai-start -->
## ash_ai usage
_Integrated LLM features for your Ash application._

[ash_ai usage rules](deps/ash_ai/usage-rules.md)
<!-- ash_ai-end -->
<!-- ash_phoenix-start -->
## ash_phoenix usage
_Utilities for integrating Ash and Phoenix_

[ash_phoenix usage rules](deps/ash_phoenix/usage-rules.md)
<!-- ash_phoenix-end -->
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
