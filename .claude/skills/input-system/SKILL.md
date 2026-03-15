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

**Data flow:** raw input event → input source → semantic action → orchestrator → state machine directive → directive execution → DOM mutation.

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

### Input Sources

Keyboard and gamepad are decoupled peers behind a duck-typed contract: `start()`, `stop()`, `onAction(action)`, `onInputDetected(type)`. The orchestrator is source-agnostic. Sources are wired as factory functions in config.

### MENU Behavior

The `_menuTransition()` handles all MENU instances. The primaryMenu gets special treatment (exit_sidebar on right/back, wall on left). Non-primary MENU instances use the nav graph for left/right/back transitions. SELECT on any MENU exits the menu into the content area (primary menu skips the click since items are already activated on focus; non-primary menus click after transitioning).

### BACK and CLEAR Context Gating

BACK delegates to page behavior `onEscape()` only in content contexts (grid, toolbar, zone_tabs). Overlays (modal, drawer) and all MENU-type instances (sidebar, sections) have their own BACK semantics (dismiss, exit, nav graph left) that bypass `onEscape()` entirely.

`onEscape()` supports three return types: `false` (not consumed → fall through), `true` (consumed → stop), or a **string** (navigate to that context). All current behaviors return `"sidebar"` or `"sections"`. When the target is the primary menu, the full enter-sidebar flow runs (expand, record pre-sidebar context).

CLEAR delegates to page behavior `onClear()` in any context. Currently only library implements this (clears filter). If no `onClear` exists, the action is silently dropped.

### Page Behaviors

Page-specific concerns extracted from the orchestrator. Detected via `data-page-behavior` attribute. Duck-typed interface: `activateOnFocus`, `onAttach`, `onDetach`, `onEscape`, `onClear`, `onSyncState`, `onZoneChanged` — all optional. The `activateOnFocus` property is a string array of menu context names that should click items on focus during up/down nav (page-scoped — the primaryMenu always activates globally).

Every page behavior should implement `onEscape()` returning `"sidebar"` (or an intermediate context like `"sections"`) so BACK consistently navigates toward the main nav. Pages with clearable state (filters, search) should implement `onClear()`.

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
| `data-page-behavior` | Page behavior to activate (`dashboard`, `library`, `review`, `settings`) |
| `data-nav-default-zone` | Default zone for pages without zone tabs |
| `data-nav-remember` | Sidebar link preserves target page URL across navigation |
| `data-entity-id` | Stable entity identifier on cards |
| `data-detail-mode` | Presentation shell type (`modal`, `drawer`) |
| `data-captures-keys` | Element handles own keyboard events |
| `data-nav-defer-activate` | Skip activate-on-focus — only activate on explicit SELECT |
| `data-nav-action` | Custom event name dispatched on SELECT instead of `.click()` |
| `data-nav-focus-target` | Suppress focus ring on this nav item — delegate to `data-nav-focus-ring` children |
| `data-nav-focus-ring` | Receive delegated focus ring when ancestor `data-nav-focus-target` item is focused |
| `data-input` | Current input method on `<html>` (`mouse`, `keyboard`, `gamepad`) |
| `data-nav-context` | Current focus context for hint bar on `<html>` |
| `data-gamepad-type` | Controller type for hint bar labels on `<html>` (`xbox`, `playstation`, `generic`) |

## Test Patterns

Tests use `bun:test`. Three mock factories in `core/__tests__/orchestrator.test.js`:

- **`createMockReader(overrides)`** — controllable reader values
- **`createMockWriter()`** — proxy recording all calls to `calls` array
- **`createMockGlobals()`** — mock document/sessionStorage/rAF with `_dispatchKeyDown`, `_dispatchMouseMove(x, y)`, `_flushRAF` helpers

Pure modules (focus_context, nav_graph, spatial, actions) test directly — no mocks needed.

## Runtime Debugging via Chrome DevTools MCP

The input system has built-in debug logging that is silent by default. Toggle it at runtime through the Chrome DevTools MCP — no rebuild needed.

**Enable/disable:**
```
evaluate_script: () => { window.__inputDebug = true; return "enabled" }
evaluate_script: () => { window.__inputDebug = false; return "disabled" }
```

**Read logs:** `list_console_messages` with `types: ["log"]`. All input debug messages are prefixed `[input]`.

**Simulate input:** `press_key` sends keyboard events (e.g., `ArrowDown`, `ArrowUp`, `Enter`, `Escape`). This triggers the full input pipeline — key source → action → state machine → directive → DOM.

**Visual verification:** `take_screenshot` captures the current viewport. Use to confirm focus rings, scroll position, and layout state after navigation.

**Typical debug workflow:**
1. `select_page` — pick the Media Centaur tab
2. `evaluate_script` — enable `window.__inputDebug`
3. `press_key` — simulate the failing input sequence
4. `list_console_messages` — read the `[input]` trace
5. `take_screenshot` — verify visual state

**What the logs cover:**
- Context transitions (`_setContext`) with caller stack trace
- Actions received with current context and input method
- Grid navigation details (index, columns, total, direction)
- Mouse movement deltas and method transitions
- Gamepad axis direction changes and center returns
- `_syncState` / `onViewChanged` calls with caller info

**Implementation:** `debug()` from `assets/js/input/core/debug.js`. Import and use in any core module. Never use bare `console.log` — always go through `debug()`.

## Design Rules

- **Nav zone containers must not nest.** Descendant selectors cross-contaminate.
- **Empty-context safety.** Every zone must define both a layout and cursor start priority. The graph prevents transitions into empty contexts; the priority list handles initial placement.
- **Page state lives in the URL.** Use `handle_params` + `live_patch`. Don't duplicate in sessionStorage.
- **DOM access confined to `core/dom_adapter.js`.** Orchestrator and behaviors never call `document.*` directly.
- **Single-owner DOM projection.** Each `data-*` attribute on `<html>` has one state owner and one sync path (state change → callback → DOM write). Never piggyback DOM syncs on unrelated events. See "Single-Owner DOM Projection" in `docs/input-system.md`.
- **Dependency directionality.** Core never imports from app layer. App imports from `core/index.js`.
