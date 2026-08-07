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

The `_menuTransition()` handles all MENU instances. The primaryMenu gets special treatment (exit_sidebar on right/back, wall on left). Non-primary MENU instances use the nav graph for left/right transitions; BACK is a no-op there (lateral movement, including reaching the sidebar, belongs to LEFT). SELECT on any MENU exits the menu into the content area (primary menu skips the click since items are already activated on focus; non-primary menus click after transitioning).

### SHELF Behavior (spatial, unlike MENU)

SHELF covers the home page's media tiles (`hero`, `continue`, `recently`, `coming_up`). A MENU's order is semantic, so it navigates by index; a SHELF's *arrangement* carries the meaning, so it navigates by geometry. Most shelves are a single row; the Coming Up marquee is a mosaic (one large tile beside a stacked column) — same context type, same code path.

`_shelfTransition()` returns a plain `navigate` for all four directions and the orchestrator's `_shelfNavigate()` resolves them by asking, in order: **the layout** (`findNearest()` on live rects), **the nav graph** (cross into a neighbouring zone; empty shelves are skipped by the candidate fallback lists), then **the sequence** (right/down = next tile — this is what carries you from the marquee's top secondary to the one below it). Keeping walls out of the state machine is what lets a row and a mosaic share one rule set.

SELECT activates the focused card; BACK is a no-op.

**Don't add an adjacency table for a new mosaic** — geometry already handles it, and a table goes stale the moment the layout renders a different number of tiles.

### Entry Rules and Scroll Reveal

Two things that bite when adding a page:

- **Entering a context ≠ restoring it.** `_enterContext(context, direction)` handles user-driven crossings and honours a declared `config.entryAnchors` index (the hero always enters at Play) and then memory *constrained to the edge you crossed*. `_restoreContextFocus()` re-asserts focus after a DOM patch and obeys neither — applying entry rules on reconcile drags the cursor on every re-render. The edge constraint is currently gated to SHELF; the gate comes off page by page.
- **`revealItem()` in `dom_adapter.js` is the single owner of "make it visible."** The input system owns *where* the scroll lands; CSS owns *how* it gets there. Never put `scroll-snap-type` on a nav-driven scroll container (it overrides `scrollIntoView` and clips the focused card), and never ask `scrollIntoView` for `behavior: "smooth"` (it stops retargeting under fast input and strands the row) — put `scroll-behavior: smooth` on the container instead.

Verify both with `~/scripts/agents/mc-nav-trace '<keys>'`, which reports the focused context/zone/index per step plus how many px of the focused card fall outside its scrollport. Any non-zero settled clip is a bug.

### BACK and CLEAR Semantics

BACK only peels layers: overlays (modal, drawer) dismiss, sub-focus exits, and the primary menu (sidebar) exits back to the pre-sidebar context. In content contexts (grid, toolbar, zone_tabs, shelf) and non-primary menus (sections, the download zones) BACK is deliberately a **no-op** — reaching the main nav is LEFT's job. Every zone layout gives its left-edge context a `left: ["sidebar"]` edge (or a chain that reaches it), so left-at-the-left-edge is the one idiom for getting to the sidebar. There is no `onEscape` behavior hook.

CLEAR delegates to page behavior `onClear()` in any context. Library implements it (clears the filter, follows focus into the grid); download implements it (clears the omnibox query, falling through to the history search). If no `onClear` exists, the action is silently dropped.

### Page Behaviors

Page-specific concerns extracted from the orchestrator. Detected via `data-page-behavior` attribute. Duck-typed interface: `activateOnFocus`, `onAttach`, `onDetach`, `onAction`, `onClear`, `onSyncState`, `onZoneChanged` — all optional. The `activateOnFocus` property is a string array of menu context names that should click items on focus during up/down nav (page-scoped — the primaryMenu always activates globally).

Pages with clearable state (filters, search) should implement `onClear()`. There is no escape hook — BACK semantics live entirely in the state machine.

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
| `data-detail-view` | Sub-view within modal (`main`, `info`) — read by orchestrator for layered BACK |
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
- **Modal sub-views use deferred refocus.** When a modal has sub-views (e.g. info → main), `_executeDismiss` reads `data-detail-view` via `reader.getDetailView()`. If the view is not "main", it pushes `close_detail` without changing focus context and sets `_pendingModalRefocus = true`. `_syncState` (which fires after the LiveView DOM patch) checks this flag and calls `focusFirst(MODAL)`. Never use `requestAnimationFrame` for post-patch focus — the LiveView round-trip takes longer than a single frame.
- **Dependency directionality.** Core never imports from app layer. App imports from `core/index.js`.
