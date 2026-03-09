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

All code lives in `assets/js/input/`. Tests in `assets/js/input/__tests__/` run via `bun test`.

| Module | Pure? | Role |
|--------|-------|------|
| `actions.js` | Yes | Action vocabulary, key/button → action mapping |
| `spatial.js` | Yes | Grid index arithmetic (fast path for uniform grids) |
| `nav_graph.js` | Yes | Navigation graph builder + cursor start priority |
| `focus_context.js` | Yes | State machine: context × action → directive |
| `input_method.js` | Yes | Tracks mouse/keyboard/gamepad transitions |
| `dom_adapter.js` | No | DomReader reads layout, DomWriter applies changes |
| `page_behavior.js` | No | Registry mapping `data-page-behavior` → behavior factory |
| `library_behavior.js` | Yes* | Library-specific concerns (filter, zone memory, sort) |
| `index.js` | No | Orchestrator + LiveView hook factory |

*Library behavior is pure when injected with mock DOM/storage.

### actions.js

Defines the `Action` enum and maps keyboard keys / gamepad buttons to semantic actions. Custom keymaps supported via `keyToAction(key, modifiers, keyMap)`.

### spatial.js

`gridNavigate(currentIndex, columnCount, totalCount, direction)` — returns the next index or `null` (wall). Pure arithmetic, no DOM access.

### focus_context.js — State Machine

The `FocusContextMachine` tracks which navigation context is active and returns `FocusDirective` data objects. Never touches DOM.

**Contexts:** `GRID` · `TOOLBAR` · `ZONE_TABS` · `SIDEBAR` · `MODAL` · `DRAWER`

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

**DomReader** — reads layout state (zone, presentation, focused item, counts, sort order, page behavior). **DomWriter** — applies mutations (focus, sidebar state, input method, flash animation).

All DOM access is confined here. The orchestrator and behaviors never call `document.*` directly.

### index.js — Orchestrator

Bridges all modules. Receives `reader`, `writer`, and `globals` via constructor (dependency injection for testability).

**Responsibilities:**
- Lifecycle: `start(hookEl)`, `destroy()`, `onViewChanged()`
- Event routing: keydown → action → state machine → directive → execution
- Text input mode (focused vs editing)
- `data-captures-keys` bypass
- Context memory (grid entity ID, per-context index)
- Modal/drawer focus restoration (origin entity tracking)
- Sidebar persistence (sessionStorage bridge)
- Page behavior lifecycle (detect, create, delegate, destroy)

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

| Action | GRID | TOOLBAR | ZONE_TABS | SIDEBAR | MODAL | DRAWER |
|--------|------|---------|-----------|---------|-------|--------|
| Up | navigate | → ZONE_TABS | wall | navigate | navigate (wrap) | navigate |
| Down | navigate | → GRID | → TOOLBAR or GRID | navigate | navigate (wrap) | navigate |
| Left | navigate | navigate | navigate | wall | wall | → GRID (row edge) |
| Right | navigate | navigate | navigate | exit sidebar | wall | wall |
| Select | activate | activate | activate | activate | activate | activate |
| Back | — | — | — | exit sidebar | dismiss | dismiss |
| Play | play | — | — | — | play | play |
| Zone± | zone_cycle | zone_cycle | zone_cycle | — | — | zone_cycle |

**Wall transitions** (when navigation reaches the edge):
- Grid up → TOOLBAR (library zone) or ZONE_TABS (watching zone)
- Grid left → SIDEBAR
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
| `data-nav-zone` | Navigation zone container | `grid`, `toolbar`, `sidebar`, `zone-tabs` |
| `data-nav-item` | Focusable element (needs `tabindex="0"`) | — |
| `data-nav-grid` | CSS grid container (column count detection) | — |
| `data-entity-id` | Stable entity identifier on cards | UUID |
| `data-detail-mode` | Presentation shell type | `modal`, `drawer` |
| `data-captures-keys` | Element handles own keyboard events | — |
| `data-sort` | Current sort order value | string |
| `data-page-behavior` | Page behavior to activate | `library` |
| `data-input` | Current input method (set on `<html>`) | `mouse`, `keyboard`, `gamepad` |
| `data-sidebar` | Sidebar state (set on `<html>`) | `collapsed` |
| `data-nav-zone-value` | Zone identifier on tab elements | `watching`, `library` |

**Nav zone containers must not nest.** Descendant selectors cross-contaminate.

## Page Behavior System

Page behaviors extract page-specific concerns from the global orchestrator. The orchestrator detects `data-page-behavior` on the page and delegates to the matching behavior at the right lifecycle points.

**Interface** (duck-typed, all methods optional):

```javascript
/** @typedef {Object} PageBehavior
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
- **Zone tabs / toolbar:** Restores to the active tab (DOM state, not memory)
- **Other contexts:** Remembers by index
- **Zone change:** Clears grid + toolbar memory (content is new)
- **Sort change:** Clears grid memory (order changed, positions meaningless)
- **Modal/drawer dismiss:** Restores to the originating card via `_originEntityId`

## Text Input Handling

Two modes for `<input>` and `<textarea>` elements:

1. **Focused, not editing:** Arrow keys still navigate. Enter → edit mode. Printable chars → edit mode + pass through.
2. **Editing:** All keys pass through. Enter → exit edit mode. Escape → clear value + exit edit mode.

## Sidebar Persistence

SessionStorage bridge for resuming sidebar context across LiveView navigations:

- `destroy()`: if in sidebar context → save `inputSystem:resumeSidebar = true`
- `start()`: if flag set → remove flag, force sidebar context, focus active item

## CSS Integration

- `[data-input=keyboard]` / `[data-input=gamepad]` — focus ring visibility
- Mouse mode hides focus outlines
- `nav-play-flash` — green ring animation (300ms) on play action
- Keyboard-to-mouse cooldown (400ms) prevents synthetic mousemove during scroll

## Adding a New Page Behavior

1. Create `assets/js/input/<name>_behavior.js` — export a `create<Name>Behavior(dom)` factory
2. Accept all external dependencies as parameters (no global scope access)
3. Return an object implementing the `PageBehavior` interface (all methods optional)
4. Register in `page_behavior.js` — add entry to `BEHAVIOR_REGISTRY` mapping name → factory
5. Add `data-page-behavior="<name>"` to the LiveView template's root element
6. Write tests in `assets/js/input/__tests__/<name>_behavior.test.js` using mock DOM
7. Keep page state in the URL (LiveView `handle_params`) — don't duplicate in sessionStorage

## Navigation Graph

Cross-context transitions (e.g., DOWN from toolbar → grid) are driven by a **navigation graph** — an adjacency map rebuilt from DOM state whenever the page updates. The graph is defined in `nav_graph.js` and consumed by the state machine.

Two mechanisms handle empty contexts:

### Candidate fallback lists (arrow key transitions)

Each edge in the static layout is an ordered array of candidate targets. The graph builder picks the first populated candidate. This makes fallback behavior explicit — no implicit directional chaining.

Example: library zone, sidebar `right` has candidates `["grid", "toolbar", "zone_tabs"]`. If grid is empty, it falls through to toolbar. If both are empty, zone_tabs. Toolbar `down` has only `["grid"]` — if grid is empty, DOWN from toolbar is blocked (no fallback makes spatial sense).

### Cursor start priority (page entry / zone change)

A per-zone priority list determines the initial focus context. Walked in order; first populated context wins. Independent of the graph — no directional logic.

```
watching: grid → zone_tabs → sidebar
library:  grid → toolbar → zone_tabs → sidebar
```

Sidebar is always populated (static content), guaranteeing a viable terminal.

## Design Rules

- **Empty-context safety.** The navigation graph and cursor start priority together ensure the user always has a focusable target. The graph prevents directional transitions into empty contexts. The priority list handles initial placement. Any new zone layout must define both a layout in `LAYOUTS` and an entry in `CURSOR_START_PRIORITY`.
