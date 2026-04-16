---
status: accepted
date: 2026-03-03
---
# Coding standards: human-readable names, domain-driven structure

## Context and Problem Statement

As the codebase grows, inconsistent naming and ad-hoc module organization make it harder for contributors to navigate and understand the code. Abbreviated variable names (`wf`, `e`, `res`) save keystrokes but force readers to mentally decode every binding. Modules organized by technical role rather than domain concept scatter related logic across the project. Modules named after design patterns (`Processor`, `Handler`, `Worker`) require architecture knowledge before the name communicates anything.

## Decision Outcome

Chosen option: "human-readable naming and domain-purpose module structure", because code is read far more often than it is written, and the project's primary maintenance cost is comprehension, not typing.

**Variable naming:**
- Never abbreviate variables to save keystrokes. `file` not `wf`, `movie` not `e`, `season` not `s`, `result` not `res`.
- Name the variable what the value *is*, not what type it came from. A `WatchedFile` representing a user's video file should be called `file` or `video_file`, not `watched_file` or `wf`.
- This applies everywhere: tests, GenServers, LiveViews, pipeline stages.
- Short idioms are fine: `id`, `ok`, `msg`, `pid`, `ref`, `acc` (in reducers).

**Module naming:**
- Name modules for what they *do* in the domain, not what pattern they *are*: `ExtractMetadata` not `MetadataProcessor`, `Tmdb` not `TmdbImporter`, `PeriodicallyRefreshMetadata` not `MetadataRefreshWorker`.
- The test: ask "what does this do?" — if the name only makes sense to someone who knows the pattern, rename it.
- Stable identifiers (table names, PubSub topic strings, data structs describing what they *are*) don't change.

**Module structure:**
- Organize by domain context, not by technical role. Group related types, functions, and processes under the domain they serve (e.g., `Library`, `Pipeline`, `Playback`).
- Each domain context has a clear public API surface. Internal modules are implementation details.
- Cross-context interaction uses PubSub events, not direct function calls into another context's internals.

**Readability:**
- Write code for humans to read first, compilers second.
- Prefer explicit, boring code over clever abstractions. Three similar lines are better than a premature abstraction.

### Consequences

* Good, because new contributors can read the code and module tree without a glossary of abbreviations or architecture knowledge
* Good, because domain-driven structure makes it obvious where new code belongs
* Good, because explicit naming catches incorrect assumptions early — a misnamed variable reveals a misunderstood data flow
* Bad, because longer names require more horizontal space — acceptable trade-off for clarity
