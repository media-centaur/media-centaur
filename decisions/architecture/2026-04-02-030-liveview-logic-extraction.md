---
status: accepted
date: 2026-04-02
---
# Extract LiveView behavior into tested pure functions

## Context and Problem Statement

LiveView components accumulate conditional logic — state classification, label computation, variant selection, absence detection, data transformation — inlined in templates and private component functions. This logic is untestable without rendering HTML, which is fragile and couples tests to DOM structure rather than behavior.

A concrete example: `detail_panel.ex` accessed `file.state == :absent` on a `WatchedFile` struct after the `state` field was removed during the data decoupling refactor (ADR-029). The inlined logic was invisible to the test suite. A pure function `file_absent?(file_info)` would have been unit tested and the broken field access caught immediately.

The existing policy said "extract testable logic into pure functions" as optional guidance. This decision makes extraction mandatory.

## Decision Outcome

Chosen option: "Mandatory extraction of all non-trivial LiveView logic into public pure functions with unit tests", because it catches logic bugs with fast async tests, forces clear boundaries between data logic and presentation, and makes extracted functions reusable across views.

### Rules

1. **LiveViews are thin wiring.** A LiveView module handles mount, event dispatch, and template rendering. Any logic beyond trivial assignment (an `if`, `case`, `cond`, or `Enum` pipeline on domain data) must be extracted into a public function.
2. **Extract into the same module or a dedicated helper.** Small helpers (1–3 functions) can live as public functions in the LiveView or component module. Larger clusters belong in a dedicated module (e.g., `DetailPanelHelpers`).
3. **Extracted functions must have unit tests.** Use `async: true` with `build_*` factory helpers — no database, no rendering. Test inputs and outputs directly.
4. **Never assert on rendered HTML.** No `render_component`, no `=~` on markup, no CSS selector assertions on rendered output. LiveView integration tests (mount, patch, event handling via `Phoenix.LiveViewTest`) are acceptable — they test navigation and data flow, not DOM structure.

### Examples of logic that must be extracted

- State classification: `file_absent?(file_info)`, `episode_status(episode, progress)`
- Label computation: `progress_label(progress)`, `duration_display(seconds)`
- Variant selection: `icon_for_state(state)`, `badge_class(type)`
- Data transformation: `group_episodes_by_season(episodes)`, `sort_files(files)`
- Conditional display: `show_progress_bar?(entity)`, `resumable?(progress)`

### Consequences

* Good, because logic bugs are caught by fast async unit tests that run in milliseconds
* Good, because it forces clear API boundaries between data logic and presentation
* Good, because extracted functions are reusable across LiveViews and components
* Good, because refactors that change schemas or data structures break tests at the function level, not at the HTML rendering level
* Bad, because it introduces more public functions and potentially more modules — but each is small, focused, and independently testable
