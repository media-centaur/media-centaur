---
status: accepted
date: 2026-03-03
---
# Coding standards: human-readable names, domain-driven structure

## Context and Problem Statement

As the codebase grows, inconsistent naming and ad-hoc module organization make it harder for contributors to navigate and understand the code. Abbreviated variable names (`wf`, `e`, `res`) save keystrokes but force readers to mentally decode every binding. Modules organized by technical role rather than domain concept scatter related logic across the project.

## Decision Outcome

Chosen option: "human-readable naming and domain-driven module structure", because code is read far more often than it is written, and the project's primary maintenance cost is comprehension, not typing.

**Naming:**
- Never abbreviate variables to save keystrokes. `file` not `wf`, `movie` not `e`, `season` not `s`, `result` not `res`.
- Name the variable what the value *is*, not what type it came from. A `WatchedFile` representing a user's video file should be called `file` or `video_file`, not `watched_file` or `wf`.
- This applies everywhere: tests, GenServers, LiveViews, Ash changes, pipeline stages.

**Module structure:**
- Organize by domain context, not by technical role. Group related types, functions, and processes under the domain they serve (e.g., `Library`, `Pipeline`, `Playback`).
- Each domain context has a clear public API surface. Internal modules are implementation details.
- Cross-context interaction uses PubSub events, not direct function calls into another context's internals.

**Readability:**
- Write code for humans to read first, compilers second.
- Prefer explicit, boring code over clever abstractions. Three similar lines are better than a premature abstraction.
- Functions and modules should be understandable from their names alone — a domain-driven design practitioner should be able to navigate the codebase by intuition.

### Consequences

* Good, because new contributors can read the code without a glossary of abbreviations
* Good, because domain-driven structure makes it obvious where new code belongs
* Good, because explicit naming catches incorrect assumptions early — a misnamed variable reveals a misunderstood data flow
* Bad, because longer names require more horizontal space — acceptable trade-off for clarity
