# Input System Architecture

Unified keyboard, mouse, and gamepad navigation for the media center UI. Implemented in two phases: **5a** (keyboard + spatial nav — complete) and **5b** (gamepad — pending).

## Layered Design

```
  Key/Mouse Event
       │
  ┌────▼────┐    ┌───────────┐
  │ actions  │───>│  focus     │──> FocusDirective
  │ (mapping)│    │  context   │    (pure data)
  └──────────┘    │  (machine) │
                  └───────────┘
                       │
  ┌────────────────────▼──────────────────┐
  │         orchestrator (index.js)        │
  │  routes directives, manages memory,    │
  │  delegates to page behaviors           │
  ├──────────────┬────────────┬───────────┤
  │  DomReader   │  DomWriter │  Globals  │
  │  (reads DOM) │  (writes)  │  (inject) │
  └──────────────┴────────────┴───────────┘
       │                │
  ┌────▼────┐     ┌─────▼─────┐
  │  page   │     │   DOM     │
  │ behavior│     │ mutations │
  └─────────┘     └───────────┘
```

**Data flow:** keydown event → semantic action → state machine directive → orchestrator execution → DOM mutation.

All external dependencies (document, sessionStorage, requestAnimationFrame) are injected via the constructor, making every layer testable with mocks.

## Module Reference

The input system is split into a reusable **framework** (`core/`) and **app-specific** code. Framework modules are parameterized by config and never import from the app layer.

### Framework (`assets/js/input/core/`)

Tests in `core/__tests__/` run via `bun test assets/js/input/core/`.

| Module | Pure? | Role |
|--------|-------|------|
| `actions.js` | Yes | Action vocabulary, key/button → action mapping |
| `spatial.js` | Yes | Grid index arithmetic (fast path for uniform grids) |
| `nav_graph.js` | Yes | Navigation graph builder + cursor start priority (parameterized by layouts) |
| `focus_context.js` | Yes | State machine: context × action → directive (parameterized by instanceTypes, primaryMenu) |
| `input_method.js` | Yes | Tracks mouse/keyboard/gamepad transitions |
| `dom_adapter.js` | No | Factory functions `createDomReader(config)` / `createDomWriter(config)` (parameterized by selectors) |
| `orchestrator.js` | No | Core event loop, memory, directive execution (parameterized by full config) |
| `index.js` | — | Public API — re-exports everything from core modules |

### App Layer (`assets/js/input/`)

Tests in `__tests__/` run via `bun test assets/js/input/__tests__/`.

| Module | Pure? | Role |
|--------|-------|------|
| `config.js` | Yes | All app-specific config: selectors, layouts, instance types, behaviors |
| `index.js` | No | LiveView hook factory — imports core + config, exports `createInputHook()` |
| `page_behavior.js` | No | Registry mapping `data-page-behavior` → behavior factory |
| `library_behavior.js` | Yes* | Library-specific concerns (filter, zone memory, sort) |
| `settings_behavior.js` | Yes | Settings page behavior (activates sections on focus) |

*Library behavior is pure when injected with mock DOM/storage.

### actions.js

Defines the `Action` enum and maps keyboard keys / gamepad buttons to semantic actions. Custom keymaps supported via `keyToAction(key, modifiers, keyMap)`.

### spatial.js

`gridNavigate(currentIndex, columnCount, totalCount, direction)` — returns the next index or `null` (wall). Pure arithmetic, no DOM access.

### focus_context.js — State Machine

The `FocusContextMachine` tracks which navigation context is active and returns `FocusDirective` data objects. Never touches DOM.

**Context types:** `GRID` · `TOOLBAR` · `ZONE_TABS` · `MENU` · `MODAL` · `DRAWER`

**Instance → type mapping:** The `contextType(instance, instanceTypes)` resolver maps instance names to behavior types. Multiple instances can share the same behavior type — for example, both `"sidebar"` and `"sections"` resolve to `MENU`. Instance names not in the map are their own type (e.g., `"grid"` → `GRID`). The map is provided via config, not hardcoded in the framework.

**Public API:**

| Method | Purpose |
|--------|---------|
| `transition(action)` | Process action in current context → directive |
| `gridWall(direction)` | Called when grid nav hits edge → cross-context directive |
| `zoneChanged(zone)` | Zone tab switched — resets context, clears drawer |
| `presentationChanged(p)` | Modal/drawer opened/closed |
| `forceContext(context)` | Set context directly (sidebar resume, exit restore) |
| `syncDrawerState(isOpen)` | Sync drawer flag from DOM |
| `enterSidebarFromWall()` | Left-wall transition from zone tabs/toolbar |

### dom_adapter.js

Factory functions `createDomReader(config)` and `createDomWriter(config)` produce reader/writer instances parameterized by `config.contextSelectors` and `config.activeClassNames`. All DOM access is confined here. The orchestrator and behaviors never call `document.*` directly.

### orchestrator.js

Bridges all modules. Receives full config object including `reader`, `writer`, `globals`, and all app-specific settings (dependency injection for testability). Replaces the former `InputSystem` class in `index.js`.

**Responsibilities:**
- Lifecycle: `start(hookEl)`, `destroy()`, `onViewChanged()`
- Event routing: keydown → action → state machine → directive → execution
- Text input mode (focused vs editing)
- `data-captures-keys` bypass
- Context memory (grid entity ID, per-context index)
- Modal/drawer focus restoration (origin entity tracking)
- Sidebar persistence (sessionStorage bridge)
- Page behavior lifecycle (detect, create, delegate, destroy)

**Activate on focus.** The `primaryMenu` (sidebar) always clicks items on focus during up/down navigation, triggering page navigation. Page behaviors can declare `activateOnFocus: ["sections"]` to add the same behavior for other menu contexts on that page only. This is page-scoped to avoid unintended navigation — e.g., the dashboard and settings pages both use a `sections` zone, but only settings should auto-navigate between sub-pages.

### page_behavior.js — Behavior Registry

Maps `data-page-behavior` attribute values to behavior factories. Each factory receives the orchestrator's `globals` for dependency injection.

### library_behavior.js — Library Page Behavior

Extracts library-specific concerns from the orchestrator. Receives a `dom` interface (injected, never global). Zone, filter, and sort state live in the URL (managed by LiveView `handle_params`) — the input system doesn't persist these.

| Hook | Purpose |
|------|---------|
| `onEscape()` | Clear filter input if non-empty, return true to consume |
| `onSyncState(reader)` | Detect sort order change → signal grid memory clear |

## Context Navigation Rules

Actions in each context:

| Action | GRID | TOOLBAR | ZONE_TABS | MENU (sidebar) | MENU (other) | MODAL | DRAWER |
|--------|------|---------|-----------|----------------|--------------|-------|--------|
| Up | navigate | → ZONE_TABS | wall | navigate | navigate | navigate (wrap) | navigate |
| Down | navigate | → GRID | → TOOLBAR or GRID | navigate | navigate | navigate (wrap) | navigate |
| Left | navigate | navigate | navigate | wall | nav graph left | wall | → GRID (row edge) |
| Right | navigate | navigate | navigate | exit sidebar | nav graph right | wall | wall |
| Select | activate | activate | activate | activate | activate | activate | activate |
| Back | — | — | — | exit sidebar | nav graph left | dismiss | dismiss |
| Play | play | — | — | — | — | play | play |
| Zone± | zone_cycle | zone_cycle | zone_cycle | — | — | — | zone_cycle |

**MENU behavior:** The sidebar instance has hardcoded exit_sidebar on right/back and wall on left. Other MENU instances (like `"sections"`) use the navigation graph for left/right/back — if the graph points to `"sidebar"`, it produces `enter_sidebar`.

**Wall transitions** (when navigation reaches the edge):
- Grid up → TOOLBAR (library zone) or ZONE_TABS (watching zone)
- Grid left → nav graph target (sidebar in library/watching zones, sections in settings zone)
- Grid right → DRAWER (if open)
- Zone tabs/toolbar left at index 0 → SIDEBAR
- Drawer left → GRID (rightmost column, same row)

## Directive Reference

| Directive | Data | Executor action |
|-----------|------|-----------------|
| `navigate` | `direction` | Spatial (grid) or linear (other) nav within context |
| `focus_context` | `target` | Restore focus memory in target context |
| `focus_first` | `context` | Restore focus memory (or first item) in context |
| `grid_row_edge` | `side` | Focus leftmost/rightmost item in same grid row |
| `activate` | — | Click the focused element |
| `dismiss` | — | Push `close_detail` event to LiveView |
| `play` | — | Push `play` event with entity ID, flash animation |
| `zone_cycle` | `direction` | Click next/prev zone tab |
| `enter_sidebar` | — | Expand sidebar, focus active item |
| `exit_sidebar` | — | Restore pre-sidebar context and sidebar state |
| `none` | — | No-op (wall) |

## DOM Contract

| Attribute | Purpose | Values |
|-----------|---------|--------|
| `data-nav-zone` | Navigation zone container | `grid`, `toolbar`, `sidebar`, `sections`, `zone-tabs` |
| `data-nav-item` | Focusable element (needs `tabindex="0"`) | — |
| `data-nav-grid` | CSS grid container (column count detection) | — |
| `data-entity-id` | Stable entity identifier on cards | UUID |
| `data-detail-mode` | Presentation shell type | `modal`, `drawer` |
| `data-captures-keys` | Element handles own keyboard events | — |
| `data-sort` | Current sort order value | string |
| `data-page-behavior` | Page behavior to activate | `library`, `settings` |
| `data-nav-default-zone` | Default zone for pages without zone tabs | `settings` |
| `data-nav-remember` | Sidebar link preserves target page URL across navigation | — |
| `data-input` | Current input method (set on `<html>`) | `mouse`, `keyboard`, `gamepad` |
| `data-sidebar` | Sidebar state (set on `<html>`) | `collapsed` |
| `data-nav-zone-value` | Zone identifier on tab elements | `watching`, `library` |

**Nav zone containers must not nest.** Descendant selectors cross-contaminate.

## Page Behavior System

Page behaviors extract page-specific concerns from the global orchestrator. The orchestrator detects `data-page-behavior` on the page and delegates to the matching behavior at the right lifecycle points.

**Interface** (duck-typed, all methods optional):

```javascript
/** @typedef {Object} PageBehavior
 *  @property {string[]} [activateOnFocus] - Menu contexts that click on focus during up/down nav
 *  @property {function(): void} [onAttach]
 *  @property {function(): void} [onDetach]
 *  @property {function(): boolean} [onEscape]
 *  @property {function(string): void} [onZoneChanged]
 *  @property {function(Object): {clearGridMemory: boolean}} [onSyncState]
 */
```

**Lifecycle:**
1. `_syncState()` calls `_detectBehavior()` — reads `data-page-behavior` from DOM
2. If behavior name changed, detach old behavior, create new one via registry
3. `onAttach()` called on creation
4. `onSyncState(reader)` called every sync cycle
5. `onZoneChanged(zone)` called when zone changes
6. `onEscape()` called before normal Escape handling — return `true` to consume
7. `onDetach()` called on `destroy()` or behavior change

**Dependency injection:** Behavior factories receive their DOM interface at creation time. No global scope access — keeps behaviors testable with mocks.

## Focus Memory Model

- **Grid:** Remembers by entity ID (stable across stream DOM reorders)
- **All other contexts:** Active item (DOM marker) → saved index memory → first item
- **Zone change:** Clears grid + toolbar memory (content is new)
- **Sort change:** Clears grid memory (order changed, positions meaningless)
- **Modal/drawer dismiss:** Restores to the originating card via `_originEntityId`

**Active item detection:** `reader.getActiveItemIndex(context)` finds the first item in a context with any "active" marker class from `config.activeClassNames`. When adding a new context with an active-item visual, add the class to the `activeClassNames` array in `config.js`.

## Text Input Handling

Two modes for `<input>` and `<textarea>` elements:

1. **Focused, not editing:** Arrow keys still navigate. Enter → edit mode. Printable chars → edit mode + pass through.
2. **Editing:** All keys pass through. Enter → exit edit mode. Escape → clear value + exit edit mode.

## Sidebar Persistence

SessionStorage bridge for resuming sidebar context across LiveView navigations:

- `destroy()`: if in sidebar context → save `inputSystem:resumeSidebar = true`
- `start()`: if flag set → remove flag, force sidebar context, focus active item

## URL Persistence for Sidebar Navigation

The `data-nav-remember` attribute on sidebar links preserves query params across page navigation. Implemented in `root.html.heex` via a global click handler:

1. **On any nav item click:** Saves `sessionStorage["nav:" + currentPath]` → `currentPath + queryString`
2. **On clicks to links with `data-nav-remember`:** Looks up `sessionStorage["nav:" + targetPath]` and rewrites the `href` before navigation

This means pages that use query params for state (like `/settings?section=logging` or `/library?zone=library&type=movie`) automatically resume at the last-visited section when the user navigates back via the sidebar.

**To opt in:** Add `data-nav-remember` to the sidebar link in `layouts.ex`. The page must use query params (via `live_patch` / `handle_params`) for any state it wants to persist.

## CSS Integration

- `[data-input=keyboard]` / `[data-input=gamepad]` — focus ring visibility
- Mouse mode hides focus outlines
- `nav-play-flash` — green ring animation (300ms) on play action
- Keyboard-to-mouse cooldown (400ms) prevents synthetic mousemove during scroll

## Adding a New Page

### Page behavior (optional)

1. Create `assets/js/input/<name>_behavior.js` — export a `create<Name>Behavior(dom)` factory
2. Accept all external dependencies as parameters (no global scope access)
3. Return an object implementing the `PageBehavior` interface (all methods optional)
4. Register in `page_behavior.js` — add entry to `BEHAVIOR_REGISTRY` mapping name → factory
5. Add `data-page-behavior="<name>"` to the LiveView template's root element
6. Write tests in `assets/js/input/__tests__/<name>_behavior.test.js` using mock DOM
7. Keep page state in the URL (LiveView `handle_params`) — don't duplicate in sessionStorage

### Navigation zone layout (required for keyboard nav)

All app-specific config lives in `config.js`:

1. Add a zone layout in `config.js` `layouts` — defines directional edges between contexts
2. Add a cursor start priority in `config.js` `cursorStartPriority` — ordered fallback for initial focus
3. If the page has custom context instances (like `"sections"`):
   - Add the instance → type mapping in `config.js` `instanceTypes`
   - Add a selector in `config.js` `contextSelectors`
   - If always populated (static content), add to `config.js` `alwaysPopulated`
4. If the page has no zone tabs, add `data-nav-default-zone="<zone>"` to the template
5. For sidebar URL persistence, add `data-nav-remember` to the sidebar link in `layouts.ex`
6. Write nav graph tests and focus context tests for the new zone

## Navigation Graph

Cross-context transitions (e.g., DOWN from toolbar → grid) are driven by a **navigation graph** — an adjacency map rebuilt from DOM state whenever the page updates. The graph is defined in `nav_graph.js` and consumed by the state machine.

Two mechanisms handle empty contexts:

### Candidate fallback lists (arrow key transitions)

Each edge in the static layout is an ordered array of candidate targets. The graph builder picks the first populated candidate. This makes fallback behavior explicit — no implicit directional chaining.

Example: library zone, sidebar `right` has candidates `["grid", "toolbar", "zone_tabs"]`. If grid is empty, it falls through to toolbar. If both are empty, zone_tabs. Toolbar `down` has only `["grid"]` — if grid is empty, DOWN from toolbar is blocked (no fallback makes spatial sense).

### Cursor start priority (page entry / zone change)

A per-zone priority list determines the initial focus context. Walked in order; first populated context wins. Independent of the graph — no directional logic.

```
watching:  grid → zone_tabs → sidebar
library:   grid → toolbar → zone_tabs → sidebar
settings:  sections → grid → sidebar
```

Sidebar and sections are always populated (static content), guaranteeing a viable terminal.

## Design Rules

- **Empty-context safety.** The navigation graph and cursor start priority together ensure the user always has a focusable target. The graph prevents directional transitions into empty contexts. The priority list handles initial placement. Any new zone layout must define both a layout in `config.js` `layouts` and an entry in `cursorStartPriority`.
