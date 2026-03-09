# Input System Architecture

Unified keyboard, mouse, and gamepad navigation for the library page. Implemented in two phases: **5a** (keyboard + spatial nav — complete) and **5b** (gamepad — pending).

## Status

**Phase 5a complete.** Keyboard spatial navigation works across all contexts: grid, toolbar, zone tabs, sidebar, modal, and drawer. Focus memory preserves position across context switches. Input method detection shows/hides focus rings appropriately.

**Phase 5b pending.** Gamepad support: `gamepad.js` module (pure state interpretation), gamepad polling loop in DOM adapter, hint bar UI, controller-type icon detection.

## Module Structure

All input system code lives in `assets/js/input/`. Tests in `assets/js/input/__tests__/` run via `bun test` (config: `assets/bunfig.toml`).

### Logic/DOM Segregation (Core Principle)

Pure modules have **zero DOM dependency**. They operate on abstract data and return data. Only `dom_adapter.js` touches the DOM. The orchestrator (`index.js`) bridges them.

Pure modules are unit-tested with synthetic data. DOM interactions are integration-tested manually in-browser.

### Module Responsibilities

| Module | Pure? | Role |
|--------|-------|------|
| `actions.js` | Yes | Action enum, key/button → action mapping |
| `spatial.js` | Yes | Grid index arithmetic (fast path for uniform grids) |
| `focus_context.js` | Yes | State machine: context × action → directive |
| `input_method.js` | Yes | Tracks mouse/keyboard/gamepad transitions |
| `dom_adapter.js` | No | Reads layout, writes focus, sets attributes |
| `index.js` | No | Orchestrator + LiveView hook factory |

### DOM Adapter Discipline

**All DOM access goes through `DomReader` and `DomWriter`.** The orchestrator must never call `document.*`, `localStorage`, or `classList` directly. This keeps the orchestrator testable with mock reader/writer and prevents DOM coupling from spreading.

## Focus Context Model

The state machine tracks which **navigation context** is active. Each context has its own rules for how actions translate to directives.

### Contexts

`GRID` · `DRAWER` · `MODAL` · `TOOLBAR` · `SIDEBAR` · `ZONE_TABS`

### Directives

The state machine returns plain data objects (directives), never performs side effects:
- `navigate` — spatial/linear nav within current context
- `focus_context` — switch active context, restore remembered position
- `focus_first` — restore remembered position in a context (or first item if no memory)
- `grid_row_edge` — focus the edge item in the same grid row as the last focused item
- `activate` — click the focused element
- `dismiss` — close modal/drawer, restore focus to originating card
- `play` — trigger playback on focused entity
- `zone_cycle` — cycle zone tabs via bracket keys or bumpers
- `enter_sidebar` / `exit_sidebar` — sidebar expand/collapse transitions
- `none` — wall / no-op

### Context Transition Rules

All cross-context transitions happen at **walls** — when spatial/linear navigation reaches the edge of the current context. The state machine never short-circuits navigation within a context.

- **Zone tabs → down**: TOOLBAR (if zone has one) or GRID (if no toolbar)
- **Grid → up wall**: TOOLBAR (library zone) or ZONE_TABS (watching zone)
- **Grid → left wall**: SIDEBAR
- **Grid → right wall**: DRAWER (if open), otherwise wall
- **Drawer → left**: GRID (rightmost column, same row as last focused card)
- **Toolbar → down**: GRID
- **Toolbar → up**: ZONE_TABS
- **Modal**: focus trapped, vertical nav wraps, escape dismisses

## Focus Memory

The orchestrator maintains **per-context focus memory** so returning to a context restores the last position instead of jumping to the first item.

- **Grid**: remembers by entity ID (stable across stream DOM updates that reorder/replace elements)
- **All other contexts**: remembers by index
- **Zone changes**: clear grid and toolbar memory (content changes between zones)
- **Modal/drawer dismiss**: restores focus to the originating card (tracked by entity ID)

## Key Patterns

### Wall-Based Cross-Context Navigation

Navigation within a context is always spatial/linear. Cross-context transitions only happen when navigation hits a wall (returns null). The orchestrator calls `gridWall(direction)` on the state machine, which decides the target context. This two-step approach keeps spatial logic and context logic separate.

**Anti-pattern:** Checking drawer/sidebar state inside the grid transition and short-circuiting navigation.
**Pattern:** Let grid navigation run. Only on wall (null result), ask the state machine where to go.

### Zone Changes Preserve Tab Context

When a zone tab is activated, the view re-renders with new content. The `zoneChanged()` method must **not** reset context to GRID if the user is currently in ZONE_TABS — they may want to continue navigating between tabs.

**Anti-pattern:** Unconditionally resetting context on zone change.
**Pattern:** Check if current context is ZONE_TABS and preserve it.

### Native Form Controls Need Special Handling

`<select>`, `<input>`, `<textarea>` capture keyboard events natively. The input system must not intercept keys that the browser needs for these elements.

**Pattern for `<select>`:** Let the browser handle up/down (option cycling). Intercept left/right/escape to return control to the nav system. Do **not** blur the select before dispatching the action — the element must retain focus so the linear navigator can find its index and move to the correct neighbor.

**Pattern for `<input>`/`<textarea>`:** Ignore all mapped keys (`targetIsInput` flag). The user is typing.

### Keyboard-to-Mouse Cooldown

When keyboard navigation triggers focus changes, the browser may scroll the newly focused element into view. Some browsers fire synthetic `mousemove` events during scroll. Without protection, these flip the input method back to MOUSE, hiding the keyboard focus ring immediately after it appears.

**Pattern:** After any keyboard event, suppress `mousemove` input method transitions for a brief cooldown (~400ms). Only intentional mouse movement after the cooldown triggers the switch.

### Drawer State Sync

The orchestrator always syncs `_drawerOpen` from the DOM on every view update, regardless of current focus context. Without this, navigating from drawer to grid (leaving context as GRID) and then the drawer closing via LiveView would leave stale state.

### Presentation State Sync

The orchestrator syncs focus context with DOM state on every view update callback. When a modal/drawer appears or disappears in the DOM, the focus context must match. On modal open, focus moves to the first nav item inside it. On close, focus restores to the originating card.

## Data Attributes (DOM Contract)

| Attribute | Purpose | Where |
|-----------|---------|-------|
| `data-nav-zone="..."` | Identifies navigation zone (grid, toolbar, sidebar, zone-tabs) | Container elements |
| `data-nav-item` | Marks an element as focusable by the nav system | Cards, buttons, links, selects |
| `data-nav-grid` | Marks the CSS grid container (for column count detection) | Grid wrapper div |
| `data-entity-id="..."` | Entity ID for play/focus-restore actions | Cards, play buttons |
| `data-detail-mode="modal\|drawer"` | Identifies presentation shell | Modal/drawer root elements |
| `data-input="mouse\|keyboard\|gamepad"` | Current input method (set on `<html>`) | Root element |

All `data-nav-item` elements should have `tabindex="0"` for browser focusability.

### Nav Zone Selectors Must Not Nest

`data-nav-zone` containers must **never** be ancestors of other `data-nav-zone` containers. The descendant selectors (`[data-nav-zone='X'] [data-nav-item]`) will match items in nested zones, causing cross-context contamination.

**Anti-pattern:** Putting `data-nav-zone` on a wrapper that contains another `data-nav-zone` child.
**Pattern:** Place `data-nav-zone` on the narrowest container that holds only that context's items.

## CSS Integration

Focus rings are conditional on input method via `[data-input=keyboard]` and `[data-input=gamepad]` selectors. Mouse mode hides focus outlines. This prevents visual clutter during mouse interaction while maintaining keyboard accessibility.

Play action feedback uses a green ring flash animation (`nav-play-flash` class, 300ms).

Drawer uses fade-in only (no translateX slide) since the container space is always reserved.

## Hook Wiring

The InputSystem is registered as a LiveView hook via `createInputHook()` in `app.js`. The hook element (`phx-hook="InputSystem"`) should wrap the navigable content area. The hook's `mounted`/`updated`/`destroyed` callbacks manage the system lifecycle.

Event pushing (dismiss, play) uses `this._hookEl.pushEvent()` directly on the hook context — this is a LiveView hook API, not a DOM operation, so it stays in the orchestrator rather than the DOM adapter.
