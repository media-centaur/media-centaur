Read `AGENTS.md` for Elixir, Phoenix, LiveView, Ecto, and CSS/JS guidelines.

# Freedia Center — Media Manager

A Phoenix/Elixir web application that manages the Freedia Center media library. It is the **write-side** of the system: it creates and edits entity records, scrapes metadata from external APIs, and downloads artwork images. The `user-interface` app connects via WebSocket (Phoenix Channels) to receive library data, send playback commands, and get real-time updates.

## Build & Run

```bash
mix setup              # install deps, create DB, run migrations, build assets
mix phx.server         # start dev server (http://localhost:4000)
mix test               # run tests (creates and migrates test DB automatically)
mix precommit          # compile --warning-as-errors, unlock unused deps, format, test
```

> Note: When compiling, always use the environment variable `MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8` to parallelize and speed up compilation.

Run `mix precommit` before finishing any set of changes and fix all issues it reports.

## Repository Layout

| Path | Purpose |
|------|---------|
| `lib/media_manager/library/` | Ash domain and resources: Entity, WatchedFile, WatchProgress, Image, Identifier, Season, Episode |
| `lib/media_manager/library/types/` | Ash enum types: EntityType, MediaType, WatchedFileState |
| `lib/media_manager/library/entity_resolver.ex` | Entity find-or-create orchestration with race-loss recovery |
| `lib/media_manager/library/watched_file/changes/` | Ash change modules for each pipeline step |
| `lib/media_manager/playback/` | Playback engine: resume algorithm, MPV session, playback manager |
| `lib/media_manager/pipeline/` | Broadway pipeline, producer, and image downloader |
| `lib/media_manager/tmdb/` | TMDB API client, confidence scorer, and response mapper |
| `lib/media_manager/serializer.ex` | Schema.org JSON-LD serializer (Entity → channel push format) |
| `lib/media_manager/config.ex` | TOML config loader (GenServer) |
| `lib/media_manager/watcher.ex` | File system watcher (inotify) |
| `lib/media_manager/parser.ex` | Video filename parser — pure function, path → `%Parser.Result{}` (see Parser section below) |
| `lib/media_manager_web/channels/` | Phoenix Channels: UserSocket, LibraryChannel, PlaybackChannel (WebSocket API for the UI) |
| `lib/media_manager_web/` | Phoenix web layer: router, LiveViews, components |
| `priv/repo/migrations/` | Ecto migrations (auto-generated from Ash resources) |
| `test/media_manager_web/channels/` | Channel tests: library and playback wire format verification (use `ChannelCase`) |
| `test/` | ExUnit tests |
| `assets/` | JS and CSS source (esbuild + Tailwind v4) |
| `defaults/` | Shipped starter config files (git-tracked seed values; never overwritten at runtime) |
| `AGENTS.md` | Elixir/Phoenix/LiveView/Ecto/CSS/JS coding rules |
| `PIPELINE.md` | Broadway pipeline architecture (detection → search → metadata fetch → image download → serialize) |

## Ash-Driven Migrations

**Never hand-write Ecto migrations.** Always design Ash resources first (attributes, identities, relationships), then run `mix ash_sqlite.generate_migrations --name <short_name>` to auto-generate the migration. The resource definition is the source of truth — the migration is a derived artifact.

## Architecture Principles

- **Ash is the only data interface.** Never write raw SQL queries or use `Ecto.Query` / `Repo` directly. All database reads and writes go through Ash actions. If Ash doesn't have the necessary action or capability for an operation, plan and implement the missing Ash action first — never bypass Ash with manual queries.
- **This app owns all writes.** Only the manager writes `images/`. The `user-interface` never writes these files.
- **Schema.org is the data model.** All entity fields and types come from schema.org vocabulary. Read `DATA-FORMAT.md` before writing any code that encodes or decodes entity JSON.
- **UUIDs are stable forever.** An entity's `@id` is assigned once and never changed. It doubles as the image directory name. Never reassign or reuse a UUID.
- **Phoenix Channels is the integration point with the UI.** The UI connects via WebSocket (`/socket`) and joins `library` and `playback` channels. The backend sends the full library on join and pushes all data and state changes in real time.
- **Images: one copy per role.** Store one high-quality image per role (`poster`, `backdrop`, `logo`, `thumb`). Never store multiple resolutions. See `IMAGE-CACHING.md`.
- **External API clients use `Req`.** Never use `:httpoison`, `:tesla`, or `:httpc`. `Req` is included and is the preferred HTTP client.

## Pipeline

Video files flow through an automated pipeline driven by the **file watcher** (`MediaManager.Watcher`) and a **Broadway pipeline** (`MediaManager.Pipeline`):

1. **Watcher** detects new video files in `watch_dirs`, waits for size stability, creates a `WatchedFile` via `:detect` → state `:detected`
2. **Producer** polls DB every 10s, claims detected files → state `:queued`
3. **Processor** runs `:search` — searches TMDB, scores confidence → `:approved` or `:pending_review`
4. **Processor** (if approved) runs `:fetch_metadata` — checks for existing Entity by TMDB ID; if found, reuses it (→ `:complete`); if new, creates `Entity` + `Image` + `Identifier` records, and for TV series only the Season/Episode matching this file (→ `:fetching_images`)
5. **Processor** runs `:download_images` (new entities only) — downloads artwork to `{media_images_dir}/{uuid}/`, updates `Image.content_url` → `:complete` (best-effort; failure logs warning)
6. **Batcher** (concurrency 1) collects completed messages and broadcasts entity changes via PubSub (pushing to connected UIs over Phoenix Channels)

Steps 1–6 are fully automated, **idempotent**, and **concurrency-safe** — DB unique constraints and upsert patterns prevent duplicate records regardless of how many processors run in parallel. Scanning the same directories multiple times produces exactly one Entity per TMDB ID. Low-confidence matches stop at `:pending_review` and await manual approval in the admin UI. See [`PIPELINE.md`](PIPELINE.md) for full architecture details.

Key source files: `lib/media_manager/pipeline.ex`, `lib/media_manager/pipeline/producer.ex`, `lib/media_manager/pipeline/image_downloader.ex`, `lib/media_manager/watcher.ex`, `lib/media_manager/watcher/supervisor.ex`, `lib/media_manager/parser.ex`, `lib/media_manager/tmdb/` (client, confidence, mapper), `lib/media_manager/library/entity_resolver.ex`, `lib/media_manager/library/watched_file/changes/`, `lib/media_manager/serializer.ex`.

## Specifications

Cross-component specifications live in the **[freedia-center/specifications](https://github.com/freedia-center/specifications)** repository, stored locally at `../specifications` relative to this repo. **Every contract between the backend and the user-interface must be documented in its own specification file.** If a feature introduces a new integration surface — a new channel topic, a new message format, a new file convention, a new IPC mechanism — it must have a corresponding spec in `../specifications/` before the implementation ships.

| Document | Contents |
|----------|---------|
| [`COMPONENTS.md`](../specifications/COMPONENTS.md) | System architecture — how the manager and user-interface relate; responsibilities, integration contract |
| [`API.md`](../specifications/API.md) | Phoenix Channels WebSocket API — connection, channel topics, message schemas, error handling |
| [`PLAYBACK.md`](../specifications/PLAYBACK.md) | MPV integration, watch progress data model, resume algorithm, progress reporting |
| [`DATA-FORMAT.md`](../specifications/DATA-FORMAT.md) | JSON schema for entity data — entity types, field names, sub-types, examples, and `config.json` |
| [`IMAGE-CACHING.md`](../specifications/IMAGE-CACHING.md) | Image roles, directory layout, remote URL patterns, manager/UI responsibilities |
| [`TESTING.md`](../specifications/TESTING.md) | Automated and manual testing guide for both components |

### Reading the Specs

- **Before writing any code that touches the WebSocket API** (channels, messages, join replies), read `API.md` in full.
- **Before writing any playback, resume, or watch progress code**, read `PLAYBACK.md` in full.
- **Before writing any code that serializes entities** (for channel pushes), read `DATA-FORMAT.md` in full.
- **Before writing any image download or storage code**, read `IMAGE-CACHING.md` in full.
- **When adding a new entity field or type**, check [schema.org](https://schema.org) first. Use the canonical schema.org property name if one fits. Only introduce a non-schema.org field if there is no reasonable match, and document the reason in `DATA-FORMAT.md`.
- Field names (`name`, `datePublished`, `contentUrl`, `containsSeason`, etc.) and type names (`Movie`, `TVSeries`, `VideoGame`, `ImageObject`, `PropertyValue`) are schema.org identifiers — do not rename them.

### Working with the Specs

- **Specs are the authoritative contract.** The user-interface team (and future agents) learn what this app produces by reading the specs. When in doubt about a field name, message format, or behavior, the spec wins over the implementation.
- `API.md` specifies every channel topic, every client message, every server push, and every reply schema. The Rust UI implements its WebSocket client from this document — any deviation breaks the UI.
- `PLAYBACK.md` specifies the MPV launch flags, IPC protocol, progress persistence intervals, and resume algorithm. Both the backend implementation and the UI's playback state display derive from this spec.
- `DATA-FORMAT.md` specifies the JSON written by this app. Follow field names and structure exactly.
- `IMAGE-CACHING.md` specifies the exact `contentUrl` path format (`images/{uuid}/{role}.{ext}`), image roles, and remote URL patterns for each source (TMDB, Steam). Follow these precisely — the user-interface uses them verbatim.
- `COMPONENTS.md` describes the overall system architecture and which component owns what. Refer to it when designing new features that affect the integration boundary.

### Keeping the Specs Updated

When a contract changes — a new channel message, a new field, a new entity type, a changed image role, a new API endpoint — **update the spec first**, then update the implementation:

1. Edit the relevant file in `../specifications` (e.g. `API.md`).
2. If no existing spec covers the change, **create a new spec file** in `../specifications/` and add it to the table above and to `COMPONENTS.md`.
3. Update this app's implementation to match.
4. Note in `COMPONENTS.md` or the relevant spec if the change affects the user-interface, so its `CLAUDE.md` can be updated too.

Never let the implementation drift ahead of the spec. Never add a backend-to-UI contract (WebSocket message, file format, IPC protocol) without a spec documenting it.

### Keep Documentation Updated

Any .md documentation created for this project should be kept up to date.

## Defaults

The `defaults/` directory contains git-tracked starter config files. These are seed values shipped with the repo — they represent every configurable option with a logical default. They are **never overwritten at runtime**; the running app reads user config from XDG paths and falls back to these.

| File | Purpose |
|------|---------|
| `defaults/media-manager.toml` | All TOML configuration keys with their default values |

> **Keep `defaults/media-manager.toml` complete.** Every configuration key recognised by `MediaManager.Config` must have an entry in `defaults/media-manager.toml` with a logical default value and a comment explaining what it controls. Add the entry whenever a new config key is introduced. The file must always be valid TOML and parse without errors.

## Plans

Implementation plans live in `plans/` and are prefixed with a unique incrementing
number (e.g. `001-animate-menu-bar.md`, `002-add-search.md`). The number ensures
ordering and prevents naming collisions. Each plan must be **self-contained** —
it must include all context required to execute fully in a new session, without
relying on the conversation history from the session where the planning was done.

Always write the plan and save it before asking to execute. DO NOT AUTO EXECUTE AN IMPLEMENTATION PLAN AFTER SAVING THE PLAN. STOP AND REQUEST PERMISSION BEFORE EXECUTION.

Every implementation plan must include a **Smoke Tests** section identifying which stable contracts are affected and what tests to add (per the Testing Strategy). If the plan introduces no testable contracts, state that explicitly. Plans without a testing section are incomplete.

## Testing Strategy

**Test-first.** Write tests before implementation for all new features and bug fixes. Tests are the executable specification — if you can't write the test, the requirements aren't clear enough.

### Test Organization

Tests mirror `lib/` by domain. Each module gets its own test file.

| Test path | Tests for | `async` | Case |
|-----------|-----------|---------|------|
| `test/media_manager/parser_test.exs` | `Parser` | yes | `ExUnit.Case` |
| `test/media_manager/serializer_test.exs` | `Serializer` | yes | `ExUnit.Case` |
| `test/media_manager/tmdb/mapper_test.exs` | `TMDB.Mapper` | yes | `ExUnit.Case` |
| `test/media_manager/tmdb/confidence_test.exs` | `TMDB.Confidence` | yes | `ExUnit.Case` |
| `test/media_manager/playback/resume_test.exs` | `Playback.Resume` | yes | `ExUnit.Case` |
| `test/media_manager/playback/progress_summary_test.exs` | `Playback.ProgressSummary` | yes | `ExUnit.Case` |
| `test/media_manager/library/entity_test.exs` | Entity Ash actions | no | `DataCase` |
| `test/media_manager/library/watched_file_test.exs` | WatchedFile actions | no | `DataCase` |
| `test/media_manager/library/watch_progress_test.exs` | WatchProgress actions | no | `DataCase` |
| `test/media_manager_web/channels/library_channel_test.exs` | Library channel contract | no | `ChannelCase` |
| `test/media_manager_web/channels/playback_channel_test.exs` | Playback channel contract | no | `ChannelCase` |

### Pure Function Tests vs Resource Tests

- **Pure function modules** (Parser, Serializer, Mapper, Confidence, Resume, ProgressSummary) use `async: true` and build struct literals via factory — no database.
- **Ash resource tests** (Entity, WatchedFile, WatchProgress) use `DataCase` and exercise Ash actions against the real database.
- **Channel tests** use `ChannelCase` and verify wire format contracts.

### Shared Test Factory

`test/support/factory.ex` provides `MediaManager.TestFactory`:

- `build_*` functions return plain structs with sensible defaults (no DB). Use for pure function tests.
- `create_*` functions persist via Ash actions and return loaded records. Use for resource and channel tests.

All tests that need test data use the factory. Never inline `Ash.Changeset.for_create` boilerplate in tests.

### What We Never Test

- **GenServer internals** (Watcher, Config, MpvSession, PlaybackManager) — implementation details, not contracts.
- **LiveView DOM** — LiveViews are thin presentation layers. Test the data contracts they consume, not the DOM they render.
- **External API calls** in normal runs — tag `@tag :external` and exclude from default `mix test`.

## Parser

`lib/media_manager/parser.ex` is a pure function module — no GenServer, no DB, no side effects. It transforms a file path into a `%Parser.Result{}` struct with title, year, type, season, and episode.

### Test-First Workflow

- **Test-first, always.** Every parser bug or new pattern starts with a failing test. Write the test with the real file path, assert the expected result, watch it fail, then fix the parser.
- **Real paths only.** Every test case uses a real file path observed in the wild — never synthetic/invented paths. Include the full path as it appeared on disk.
- **One test per pattern.** Each distinct filename convention gets its own test case with a descriptive test name explaining what makes it unique.
- **No silent regressions.** Run the full parser test suite after every change. A green suite is the only definition of "done."
- **Document the pattern.** When adding a test for a new filename pattern, the test name should describe what's distinctive about it (e.g., "bare episode file inside abbreviated season directory").
- **NEVER delete or remove parser tests.** Every existing test case represents a real filename pattern observed in the wild. Removing a test risks silently reintroducing a regression for that pattern. If a parser change causes an existing test to fail, fix the parser — do not delete or weaken the test. Tests may only be added, never removed.

### Architecture

**Decision tree:** `candidate_name/1` selects the best text source → pattern matching (TV → season pack → movie → unknown) → title cleaning.

**`candidate_name/1` fallback chain:**
1. Parent is a season directory (`Season 1`, `S01`) → use grandparent (show name) + filename base
2. Filename is a bare episode marker (`S01E03`) → use parent directory + filename base
3. Filename is generic or very short lowercase → use parent directory
4. Otherwise → use filename base

**Quality token stripping:** bracket patterns first, then quality keywords, then release groups.

**TV title extraction:** strips year tokens, cleans title, strips trailing season markers (`S01`), falls back to directory names when the result is empty.

**Key constraint:** TV pattern `(.+?)SxxExx` requires at least one character before the S marker — bare episode filenames like `S01E03.mkv` won't match TV on their own, which is why `candidate_name/1` must prepend the show name from ancestor directories.

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

Use usage_rules to read documentation for any elixir packages (instead of reaching out to the web).

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
