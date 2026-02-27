---
name: coding-guidelines
description: "Use this skill for any implementation task — adding features, fixing bugs, modifying resources, changing pipeline stages, or updating channels. Always consult this before writing code."
---

## Workflow

1. **Write tests first.** The test is the executable specification. If you can't write the test, the requirements aren't clear enough — stop and clarify before writing any implementation code.
2. **Implement the minimum change** to make the tests pass.
3. **Run `mix precommit`** before finishing. Fix all warnings and failures — zero warnings policy.

## Test Patterns by Domain

### Ash Resources (Entity, WatchedFile, WatchProgress, Image)

- Use `DataCase` (not async — SQLite limitation).
- Use `create_*` factory helpers to persist via Ash actions.
- Test Ash actions against the real database — never stub the data layer.
- Bulk operations: always pass `return_errors?: true` and assert `error_count`.

### Pipeline Stages (Parse, Search, FetchMetadata, DownloadImages, Ingest)

- Call stage `run/1` or `Pipeline.process_payload/1` directly — no Broadway topology in tests.
- Stub TMDB with `TmdbStubs` helpers (`stub_search_movie/1`, `stub_routes/1`, etc.) — never mock.
- Images use `NoopImageDownloader` via config — no HTTP or file I/O.
- Test orchestration and state transitions, not leaf functions (Parser, Mapper have their own suites).
- **Never delete or weaken pipeline tests.**

### Channels (LibraryChannel, PlaybackChannel)

- Use `ChannelCase`.
- Verify wire format with `json_roundtrip/1` — encode to JSON and decode back.
- Test the contract (message shapes, event names), not internal state.

### Pure Functions (Parser, Serializer, Mapper, Confidence, Resume)

- Use `async: true` with `ExUnit.Case`.
- Use `build_*` factory helpers — plain structs, no database.

### What NOT to Test

- GenServer internals (Watcher, Config, MpvSession, PlaybackManager).
- LiveView DOM — test the data contracts they consume.
- External API calls in normal runs — tag `@tag :external` and exclude.

## Factory

All tests use `MediaManager.TestFactory`. Never inline `Ash.Changeset.for_create` boilerplate.

- `build_*` — pure structs for async tests (fast, no I/O).
- `create_*` — persisted via Ash actions for DataCase tests.
