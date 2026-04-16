---
name: coding-guidelines
description: "Use this skill for any implementation task — adding features, fixing bugs, modifying resources, changing pipeline stages, or updating channels. Always consult this before writing code."
---

## Workflow

1. **Write tests first.** The test is the executable specification. If you can't write the test, the requirements aren't clear enough — stop and clarify before writing any implementation code. Load the `automated-testing` skill for patterns and policies.
2. **Implement the minimum change** to make the tests pass.
3. **Run `mix precommit`** before finishing. Fix all warnings and failures — zero warnings policy.

## Test Patterns by Domain

### Ecto Schemas (Movie, TVSeries, MovieSeries, VideoObject, WatchedFile, WatchProgress, Image)

- Use `DataCase` (not async — SQLite limitation).
- Use `create_*` factory helpers to persist via the relevant context module
  (`MediaCentarr.Library`, `MediaCentarr.Review`, `MediaCentarr.ReleaseTracking`,
  `MediaCentarr.Settings`).
- Test through the context's public API against the real database — never stub
  the data layer, never call `Repo` directly from tests.
- For bulk operations, wrap in `Ecto.Multi` and assert on the transaction result.

### Pipeline Stages (Parse, Search, FetchMetadata, DownloadImages, Ingest)

- Call stage `run/1` or `Pipeline.process_payload/1` directly — no Broadway topology in tests.
- Stub TMDB with `TmdbStubs` helpers (`stub_search_movie/1`, `stub_routes/1`, etc.) — never mock.
- Images use `NoopImageDownloader` via config — no HTTP or file I/O.
- Test orchestration and state transitions, not leaf functions (Parser, Mapper have their own suites).
- **Never delete or weaken pipeline tests.**

### Pure Functions (Parser, Serializer, Mapper, Confidence, Resume)

- Use `async: true` with `ExUnit.Case`.
- Use `build_*` factory helpers — plain structs, no database.

### LiveView Logic Extraction (Mandatory)

Extract all non-trivial LiveView/component logic into public pure functions and unit test them ([ADR-030]). LiveViews are thin wiring. Any `if`/`case`/`cond` on domain data → extracted function with a test.

### What NOT to Test

- GenServer internals (Watcher, Config, MpvSession).
- Rendered HTML — no `render_component`, no `=~` on markup. Integration tests (mount, patch, events) are fine.
- External API calls in normal runs — tag `@tag :external` and exclude.

## Factory

All tests use `MediaCentarr.TestFactory`. Never inline `Ecto.Changeset.cast` / `Repo.insert!` boilerplate.

- `build_*` — pure structs for async tests (fast, no I/O).
- `create_*` — persisted via context-module functions for DataCase tests.
