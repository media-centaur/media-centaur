---
status: accepted
date: 2026-04-02
---
# Extract LiveView behavior into tested pure functions

## Context and Problem Statement

Logic inlined in templates and private component functions — state classification, label computation, variant selection, data transformation — is invisible to the test suite unless a test renders HTML, which couples tests to DOM structure.

## Decision Outcome

Extraction of non-trivial LiveView logic into public pure functions with unit tests is mandatory.

1. LiveViews are thin wiring: mount, event dispatch, rendering. Any `if`, `case`, `cond`, or `Enum` pipeline over domain data is extracted into a public function.
2. One to three small helpers may live as public functions on the LiveView or component module; larger clusters get a dedicated module (the per-component `Logic` modules under `components/`).
3. Extracted functions have `async: true` unit tests built on `build_*` factory helpers — no database, no rendering.
4. Tests do not assert on markup. No `render_component` for markup checks, no `=~` against attributes or tag structure (MC0024 fails attribute-shaped substrings; use `has_element?/2`). Asserting on user-visible copy with `=~` is fine. LiveView integration tests cover navigation and data flow, not DOM shape.

### Consequences

* More public functions and more small modules; each is independently testable.
