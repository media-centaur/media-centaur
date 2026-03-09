# Input System Architecture

## Module Structure

All input system code lives in `assets/js/input/`. Tests in `assets/js/input/__tests__/` run via `bun test` (config: `assets/bunfig.toml`).

### Logic/DOM Segregation (Core Principle)

Pure modules (actions, spatial, focus_context, input_method) have **zero DOM dependency**. They operate on abstract data and return data. Only `dom_adapter.js` touches the DOM. The orchestrator (`index.js`) bridges them.

This means: pure modules are unit-tested with synthetic data. DOM interactions are integration-tested manually in-browser.

### Module Responsibilities

| Module | Pure? | Role |
|--------|-------|------|
| `actions.js` | Yes | Action enum, key/button → action mapping |
| `spatial.js` | Yes | Nearest-neighbor on rects, grid index arithmetic |
| `focus_context.js` | Yes | State machine: context × action → directive |
| `input_method.js` | Yes | Tracks mouse/keyboard/gamepad transitions |
| `dom_adapter.js` | No | Reads layout, writes focus, sets attributes |
| `index.js` | No | Orchestrator + LiveView hook factory |

## Focus Context Model

The state machine tracks which **navigation context** is active. Each context has its own rules for how actions translate to directives.

### Contexts

`GRID` · `DRAWER` · `MODAL` · `TOOLBAR` · `SIDEBAR` · `ZONE_TABS`

### Directives

The state machine returns plain data objects (directives), never performs side effects:
- `navigate` — spatial/linear nav within current context
- `focus_context` — switch active context
- `focus_first` — focus first item in a context
- `activate` — click the focused element
- `dismiss` — close modal/drawer
- `play` — trigger playback on focused entity
- `zone_cycle` — cycle zone tabs
- `enter_sidebar` / `exit_sidebar` — sidebar transitions
- `none` — wall / no-op

### Context Transition Rules

- **Zone tabs → Grid**: `down` goes to TOOLBAR (if zone has one) or GRID (if zone has no toolbar)
- **Grid → Zone tabs**: `gridWall("up")` — only triggers when spatial nav hits the top edge
- **Grid → Sidebar**: `gridWall("left")` — only triggers at leftmost column
- **Grid → Drawer**: `right` when drawer is open
- **Drawer → Grid**: `left`
- **Toolbar → Grid**: `down`
- **Toolbar → Zone tabs**: `up`
- **Modal**: focus trapped, vertical nav only, escape dismisses

## Key Patterns

### Zone Changes Preserve Tab Context

When a zone tab is activated, the view re-renders with new content. The `zoneChanged()` method must **not** reset context to GRID if the user is currently in ZONE_TABS — they may want to continue navigating between tabs.

**Anti-pattern:** Unconditionally resetting context on zone change.
**Pattern:** Check if current context is ZONE_TABS and preserve it.

### Native Form Controls Need Special Handling

`<select>`, `<input>`, `<textarea>` capture keyboard events natively. The input system must not intercept keys that the browser needs for these elements.

**Pattern for `<select>`:** Let the browser handle up/down (option cycling). Intercept left/right/escape to blur the element and return control to the nav system.

**Pattern for `<input>`/`<textarea>`:** Ignore all mapped keys (`targetIsInput` flag). The user is typing.

### Keyboard-to-Mouse Cooldown

When keyboard navigation triggers focus changes, the browser may scroll the newly focused element into view. Some browsers fire synthetic `mousemove` events during scroll. Without protection, these flip the input method back to MOUSE, hiding the keyboard focus ring immediately after it appears.

**Pattern:** After any keyboard event, suppress `mousemove` input method transitions for a brief cooldown (~400ms). Only intentional mouse movement after the cooldown triggers the switch.

### Grid Wall Detection

Grid navigation uses fast-path index arithmetic. When it returns null (wall), the orchestrator calls `gridWall(direction)` on the state machine to handle cross-context transitions. This two-step approach keeps spatial logic and context logic separate.

### Presentation State Sync

The orchestrator syncs focus context with DOM state on every view update callback. When a modal/drawer appears or disappears in the DOM, the focus context must match. On modal open, focus moves to the first nav item inside it. On close, context returns to GRID.

## Data Attributes (DOM Contract)

| Attribute | Purpose | Where |
|-----------|---------|-------|
| `data-nav-zone="..."` | Identifies navigation zone (grid, toolbar, sidebar, zone-tabs) | Container elements |
| `data-nav-item` | Marks an element as focusable by the nav system | Cards, buttons, links, selects |
| `data-nav-grid` | Marks the CSS grid container (for column count detection) | Grid wrapper div |
| `data-entity-id="..."` | Entity ID for play actions | Cards, play buttons |
| `data-detail-mode="modal\|drawer"` | Identifies presentation shell | Modal/drawer root elements |
| `data-input="mouse\|keyboard\|gamepad"` | Current input method (set on `<html>`) | Root element |

All `data-nav-item` elements should have `tabindex="0"` for browser focusability.

### Nav Zone Selectors Must Not Nest

`data-nav-zone` containers must **never** be ancestors of other `data-nav-zone` containers. The descendant selectors (`[data-nav-zone='X'] [data-nav-item]`) will match items in nested zones, causing cross-context contamination.

**Anti-pattern:** Putting `data-nav-zone` on a wrapper that contains another `data-nav-zone` child.
**Pattern:** Place `data-nav-zone` on the narrowest container that holds only that context's items.

## CSS Integration

Focus rings are conditional on input method via `[data-input=keyboard]` and `[data-input=gamepad]` selectors. Mouse mode hides focus outlines. This prevents visual clutter during mouse interaction while maintaining keyboard accessibility.

## Hook Wiring

The InputSystem is registered as a LiveView hook via `createInputHook()`. The hook element (`phx-hook="InputSystem"`) should wrap the navigable content area. The hook's `mounted`/`updated`/`destroyed` callbacks manage the system lifecycle.
