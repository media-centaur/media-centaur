---
status: accepted
date: 2026-03-26
---
# Bounded context decoupling via PubSub

## Context and Problem Statement

The backend started as a monolith where Library, Pipeline, Review, Watcher, and Settings modules freely imported each other's internals. This created a web of compile-time dependencies: changing one context required understanding all its callers, pipeline stages directly mutated library records, and the Review UI reached into Library to destroy entities.

The goal was to isolate each context behind a clear boundary so that changes within a context don't ripple across the codebase.

## Decision Outcome

Chosen option: "Bounded contexts communicating primarily via PubSub events, with cross-context dependencies declared explicitly and enforced at compile time." This matches OTP's message-passing model, requires minimal infrastructure, and makes both the data flow and the deliberate exceptions traceable.

### The contexts

Ten bounded contexts plus `MediaCentarr.TMDB` (an external-integration adapter, not a domain context):

| Context | Table prefix | Responsibility |
|---------|-------------|----------------|
| Library | `library_` | Movies, TV series, movie series, video objects, seasons, episodes, extras, images, identifiers, watched files, watch/extra progress |
| Pipeline | `pipeline_` | Discovery, Import, and image-download Broadway pipelines; image queue; the file-path Parser |
| Review | `review_` | PendingFile lifecycle for human review |
| Watcher | `watcher_` (in-memory) | File detection, mount resilience, file presence tracking |
| Settings | `settings_` | Runtime configuration entries; Danger Zone admin operations |
| ReleaseTracking | `release_tracking_` | Upcoming/tracked TMDB releases, refresh state |
| Playback | _(in-memory sessions)_ | MPV sessions, progress broadcasting, resume targets |
| Console | _(in-memory ring buffer)_ | Log buffer, per-user filter state |
| Acquisition | `acquisition_` | Prowlarr search + qBittorrent download orchestration |
| WatchHistory | `watch_history_` | Append-only completion events |

### Rules

1. **Cross-context references are declared in `use Boundary, deps: [...]`** at the top of each context's facade module. The default is no coupling — every additional `dep:` is a deliberate decision visible in the code. The Boundary library fails compilation on any cross-boundary call without a declared dep.
2. **Cross-context communication prefers PubSub events.** Events carry plain data (maps, lists, atoms) — never structs from another context. Direct calls are reserved for the sanctioned deps below; new direct couplings should default to PubSub unless there's a specific reason.
3. **`Settings` doubles as shared infrastructure.** Any context that needs per-user or per-installation persistence without justifying its own table may declare a `Settings` dep and write to `Settings.Entry` directly. The coupling is one-directional — Settings carries no domain logic of its own.
4. **`MediaCentarr.TMDB` is an adapter boundary, not a domain context.** Pipeline, ReleaseTracking, and Review all declare `MediaCentarr.TMDB` deps because TMDB is the external metadata source they all integrate against.
5. **PubSub listener GenServers don't start in test mode.** Tests call public API functions directly. This avoids sandbox race conditions where GenServers process PubSub messages after the test sandbox is torn down.

### Sanctioned cross-context deps

These are the inter-context `deps` declarations currently in the codebase. Each represents a deliberate architectural choice. New deps require user-level review.

| Dep | Why |
|-----|-----|
| `Pipeline → TMDB` | Pipeline stages call TMDB.Client/Mapper/Confidence to enrich parsed metadata |
| `Pipeline → Library` | Pipeline reads `library_watched_files` for dedup; broadcasts entity changes through Library facade |
| `Pipeline → Watcher` | Discovery.Producer gates scan triggers on Watcher.Supervisor health |
| `ReleaseTracking → TMDB` | Adapter access for release polling and metadata refresh |
| `ReleaseTracking → Library` | Cross-references `library_external_ids` to skip already-acquired releases |
| `Review → TMDB` | Rematch UI calls TMDB.Client for re-search |
| `Watcher → Library` | Watcher reads `library_watched_files` for presence/dedup checks |
| `Console → Settings` | Console persists filter state and buffer cap via Settings.Entry |
| `Settings → Library` | `Settings.Admin` Danger Zone clears Library tables (clear_database, refresh_image_cache) |
| `Settings → Watcher` | `Settings.Admin` calls `Watcher.Supervisor.pause_during/1` during destructive ops |
| `WatchHistory → Library` | History queries preload Library schemas (Movie, Episode, etc.) for display |
| `Playback → Library` | Playback fundamentally acts on Library data — Resolver loads entities, MpvSession writes WatchProgress, SessionRecovery rehydrates state |

The reverse coupling (`Library → Playback`) was deliberately removed: `Playback.play/1` replaced `Library.Browser.play/1`, and `EpisodeList`/`MovieList`/`ProgressSummary` (pure presentation helpers over library data) moved into the Library namespace. Library has zero outbound Playback deps.

### Consequences

* Good, because each context can be understood, tested, and modified independently
* Good, because the PubSub event flow is explicit — `Topics.ex` centralizes all topic strings
* Good, because cross-context deps are now visible in every context facade and enforced at compile time — accidental couplings can't sneak in via review
* Good, because the rationale for each sanctioned dep is captured in this ADR rather than discovered case-by-case during refactors
* Bad, because rematch became async (fire-and-forget broadcast instead of synchronous call) — the UI must react to incoming events rather than waiting for a result
* Bad, because direct deps still couple the calling context to the called context's public API surface — moving a function in `Library.Browser` ripples to every context with a `Library` dep
