Read `AGENTS.md` for Elixir, Phoenix, LiveView, Ecto, and CSS/JS guidelines.

# Freedia Center — Media Manager

A Phoenix/Elixir web application that manages the Freedia Center media library. It is the **write-side** of the system: it creates and edits entity records, scrapes metadata from external APIs, and downloads artwork images. The `user-interface` app consumes its output as a read-only consumer.

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
| `lib/media_manager/` | Business logic: file watcher, parser, TMDB client, JSON writer, Ash resources (`library/`) |
| `lib/media_manager_web/` | Phoenix web layer: router, LiveViews, controllers, components |
| `lib/media_manager_web/components/` | Shared HEEx components and layouts |
| `priv/repo/migrations/` | Ecto migrations |
| `priv/repo/seeds.exs` | Database seed data |
| `test/` | ExUnit tests |
| `assets/` | JS and CSS source (esbuild + Tailwind v4) |
| `defaults/` | Shipped starter config files (git-tracked seed values; never overwritten at runtime) |
| `AGENTS.md` | Elixir/Phoenix/LiveView/Ecto/CSS/JS coding rules |
| `PIPELINE.md` | Broadway pipeline architecture (detection → search → metadata fetch) |

## Architecture Principles

- **This app owns all writes.** Only the manager writes `media.json` and `images/`. The `user-interface` never writes these files.
- **Schema.org is the data model.** All entity fields and types come from schema.org vocabulary. Read `DATA-FORMAT.md` before writing any code that encodes or decodes entity JSON.
- **UUIDs are stable forever.** An entity's `@id` is assigned once and never changed. It doubles as the image directory name. Never reassign or reuse a UUID.
- **File system is the integration point.** There is no IPC with the user-interface. Write files to the data directory; the UI picks them up via hot-reload.
- **Images: one copy per role.** Store one high-quality image per role (`poster`, `backdrop`, `logo`, `thumb`). Never store multiple resolutions. See `IMAGE-CACHING.md`.
- **External API clients use `Req`.** Never use `:httpoison`, `:tesla`, or `:httpc`. `Req` is included and is the preferred HTTP client.

## Pipeline

Video files flow through an automated pipeline driven by the **file watcher** (`MediaManager.Watcher`) and a **Broadway pipeline** (`MediaManager.Pipeline`):

1. **Watcher** detects new video files in `media_dir`, waits for size stability, creates a `WatchedFile` via `:detect` → state `:detected`
2. **Producer** polls DB every 10s, claims detected files → state `:queued`
3. **Processor** runs `:search` — searches TMDB, scores confidence → `:approved` or `:pending_review`
4. **Processor** (if approved) runs `:fetch_metadata` — fetches full TMDB details, creates `Entity` + `Image` + `Identifier` records → `:fetching_images`
5. **Image download** → `:complete` *(not yet implemented)*

Steps 1–4 are fully automated. Low-confidence matches stop at `:pending_review` and await manual approval in the admin UI. See [`PIPELINE.md`](PIPELINE.md) for full architecture details.

Key source files: `lib/media_manager/pipeline.ex`, `lib/media_manager/pipeline/producer.ex`, `lib/media_manager/watcher.ex`, `lib/media_manager/parser.ex`, `lib/media_manager/tmdb/`, `lib/media_manager/library/watched_file/changes/`, `lib/media_manager/library/serializer.ex`, `lib/media_manager/json_writer.ex`.

## Specifications

Cross-component specifications live in the **[freedia-center/specifications](https://github.com/freedia-center/specifications)** repository, stored locally at `../specifications` relative to this repo.

| Document | Contents |
|----------|---------|
| [`DATA-FORMAT.md`](../specifications/DATA-FORMAT.md) | JSON schema for `media.json` — entity types, field names, sub-types, examples |
| [`IMAGE-CACHING.md`](../specifications/IMAGE-CACHING.md) | Image roles, directory layout, remote URL patterns, manager/UI responsibilities |
| [`COMPONENTS.md`](../specifications/COMPONENTS.md) | How the manager and user-interface relate; the integration contract |

### Reading the Specs

- **Before writing any code that reads or writes `media.json`**, read `DATA-FORMAT.md` in full.
- **Before writing any image download or storage code**, read `IMAGE-CACHING.md` in full.
- **When adding a new entity field or type**, check [schema.org](https://schema.org) first. Use the canonical schema.org property name if one fits. Only introduce a non-schema.org field if there is no reasonable match, and document the reason in `DATA-FORMAT.md`.
- Field names (`name`, `datePublished`, `contentUrl`, `containsSeason`, etc.) and type names (`Movie`, `TVSeries`, `VideoGame`, `ImageObject`, `PropertyValue`) are schema.org identifiers — do not rename them.

### Working with the Specs

- Treat `DATA-FORMAT.md` as the authoritative contract for the JSON written by this app and read by the user-interface. When in doubt about a field name, type, or structure, the spec wins.
- `IMAGE-CACHING.md` specifies the exact `contentUrl` path format (`images/{uuid}/{role}.{ext}`), image roles, and remote URL patterns for each source (TMDB, Steam). Follow these precisely — the user-interface uses them verbatim.
- `COMPONENTS.md` describes the integration contract between manager and user-interface. Refer to it when designing new features that affect the shared data directory.

### Keeping the Specs Updated

When a format decision changes — a new field, a new entity type, a changed image role, a modified `config.json` structure — **update the spec first**, then update the implementation:

1. Edit the relevant file in `../specifications` (e.g. `DATA-FORMAT.md`).
2. Update this app's implementation to match.
3. Note in `COMPONENTS.md` or the relevant spec if the change affects the user-interface, so its `CLAUDE.md` can be updated too.

Never let the implementation drift ahead of the spec. The spec is how the user-interface team (and future agents) learn what to expect from files this app produces.

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

## Testing Strategy

This app is in a volatile prototype state. Keep the test suite **minimal and seam-focused**:

- **Only test stable contracts** — things whose silent failure would be a disaster.
- **Do not test GenServer internals** (Watcher state machine, Config loading) — they change too often.
- **Do not test LiveView interactions** (PubSub updates, DOM state) — defer until features stabilise.
- The integration seam worth testing: Ash resource actions (DB round-trips), `JsonWriter.regenerate_all` (file output contract), and the root route (wiring check).
- All integration tests live in `test/media_manager/integration_test.exs` and use `DataCase`.
- Add a new test only when: (a) a regression just burned you, or (b) a feature is stable and its contract is clear.

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
