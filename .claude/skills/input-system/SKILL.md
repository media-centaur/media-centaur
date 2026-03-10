---
name: input-system
description: "Use this skill when working with keyboard/gamepad navigation, the focus context state machine, nav graphs, page behaviors, DOM adapter, data-nav attributes, or adding input system support to a new page."
---

Read the full architecture doc at `docs/input-system.md` before making changes.

## Architecture at a Glance

The input system is split into a reusable **framework** (`assets/js/input/core/`) and **app-specific** code (`assets/js/input/`). Framework modules are parameterized by config and never import from the app layer.

- **Framework tests:** `bun test assets/js/input/core/`
- **App tests:** `bun test assets/js/input/__tests__/`
- **All tests:** `bun test assets/js/input/`

**Data flow:** keydown → semantic action → state machine directive → orchestrator → DOM mutation.

All external dependencies injected via config object — every layer testable with mocks.

## Key Concepts

### Configuration-Driven Framework

All app-specific knowledge lives in `config.js`. The framework core is parameterized:

- **`contextSelectors`** — maps context keys to CSS selectors
- **`instanceTypes`** — maps instance names to context behavior types (e.g., sidebar → MENU)
- **`layouts`** — spatial zone layouts for the nav graph
- **`cursorStartPriority`** — ordered fallback for initial focus per zone
- **`alwaysPopulated`** — contexts that skip item count checks
- **`activeClassNames`** — CSS classes indicating active state
- **`primaryMenu`** — the menu instance with enter/exit behavior (e.g., "sidebar")
- **`createBehavior`** — factory function for page behaviors

### Context Types vs Instance Names

The `Context` enum defines behavior types (`GRID`, `MENU`, `TOOLBAR`, etc.). The `_context` field stores instance names (`"grid"`, `"sidebar"`, `"sections"`). The `contextType(instance, instanceTypes)` resolver maps instance names to behavior types.

This lets multiple instances share behavior (sidebar and sections both use MENU navigation rules) while having distinct DOM selectors and nav graph entries.

### Navigation Graph

Cross-context transitions are driven by an adjacency map in `core/nav_graph.js`. Each zone defines edges between contexts with ordered fallback candidates. The graph is rebuilt from DOM state on every sync. Layouts and alwaysPopulated lists come from config.

### MENU Behavior

The `_menuTransition()` handles all MENU instances. The primaryMenu gets special treatment (exit_sidebar on right/back, wall on left). Non-primary MENU instances use the nav graph for left/right/back transitions.

### Page Behaviors

Page-specific concerns extracted from the orchestrator. Detected via `data-page-behavior` attribute. Duck-typed interface: `onAttach`, `onDetach`, `onEscape`, `onSyncState`, `onZoneChanged` — all optional.

### URL Persistence (data-nav-remember)

Sidebar links with `data-nav-remember` preserve the target page's query params across navigation. Implemented in `root.html.heex`. Pages must use query params + `handle_params` for this to work.

## Checklist: Adding Input Nav to a New Page

All config changes go in `config.js`:

1. **Nav graph:** Add zone layout in `layouts` and `cursorStartPriority`
2. **Custom contexts:** If needed, add to `instanceTypes`, `contextSelectors`, and `alwaysPopulated`
3. **Page behavior:** Create `<name>_behavior.js`, register in `page_behavior.js`
4. **Template:** Add `data-page-behavior`, `data-nav-default-zone` (if no zone tabs), `data-nav-zone`, `data-nav-item`, `data-nav-grid` attributes
5. **Sidebar link:** Add `data-nav-remember` to the sidebar link in `layouts.ex` if the page uses query params
6. **Tests:** Nav graph zone tests, focus context instance tests, behavior tests
7. **Verify:** `bun test assets/js/input/` — all pass, then manual keyboard nav test

## DOM Contract

| Attribute | Purpose |
|-----------|---------|
| `data-nav-zone` | Navigation zone container (`grid`, `toolbar`, `sidebar`, `sections`, `zone-tabs`) |
| `data-nav-item` | Focusable element (needs `tabindex="0"`) |
| `data-nav-grid` | CSS grid container (column count detection) |
| `data-page-behavior` | Page behavior to activate (`library`, `settings`) |
| `data-nav-default-zone` | Default zone for pages without zone tabs |
| `data-nav-remember` | Sidebar link preserves target page URL across navigation |
| `data-entity-id` | Stable entity identifier on cards |
| `data-detail-mode` | Presentation shell type (`modal`, `drawer`) |
| `data-captures-keys` | Element handles own keyboard events |

## Test Patterns

Tests use `bun:test`. Three mock factories in `core/__tests__/orchestrator.test.js`:

- **`createMockReader(overrides)`** — controllable reader values
- **`createMockWriter()`** — proxy recording all calls to `calls` array
- **`createMockGlobals()`** — mock document/sessionStorage/rAF with `_dispatchKeyDown`, `_flushRAF` helpers

Pure modules (focus_context, nav_graph, spatial, actions) test directly — no mocks needed.

## Design Rules

- **Nav zone containers must not nest.** Descendant selectors cross-contaminate.
- **Empty-context safety.** Every zone must define both a layout and cursor start priority. The graph prevents transitions into empty contexts; the priority list handles initial placement.
- **Page state lives in the URL.** Use `handle_params` + `live_patch`. Don't duplicate in sessionStorage.
- **DOM access confined to `core/dom_adapter.js`.** Orchestrator and behaviors never call `document.*` directly.
- **Dependency directionality.** Core never imports from app layer. App imports from `core/index.js`.
