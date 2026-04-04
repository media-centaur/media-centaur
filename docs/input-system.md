# Input System Architecture

Unified keyboard, mouse, and gamepad navigation for the media center UI. Implemented in two phases: **5a** (keyboard + spatial nav — complete) and **5b** (gamepad — complete).

## Layered Design

```
  KeyboardSource ──┐
                   ├── onAction(action) ──┐
  GamepadSource  ──┤                      │
                   └── onInputDetected ───┤
                                          │
  ┌───────────────────────────────────────▼──┐
  │           orchestrator.js                 │
  │  source-agnostic action router            │
  │  manages memory, delegates to behaviors   │
  ├──────────┬──────────┬──────────┬─────────┤
  │ actions  │ focus    │ DomReader│DomWriter │
  │ (mapping)│ context  │ (reads)  │(writes)  │
  │          │ (machine)│          │          │
  └──────────┴──────────┴──────────┴─────────┘
       │          │          │          │
       │     FocusDirective  │     DOM mutations
       │     (pure data)     │          │
       │                ┌────▼────┐┌────▼────┐
       │                │  page   ││  hint   │
       │                │ behavior││  bar    │
       │                └─────────┘└─────────┘
```

**Data flow:** raw input event → input source → semantic action → orchestrator → state machine directive → directive execution → DOM mutation.

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
| `keyboard.js` | No | KeyboardSource — keydown listener, text input two-mode handling, key-to-action mapping |
| `gamepad.js` | No | GamepadSource — idle-until-connected rAF polling, button edge detection, analog deadzone + repeat |
| `dom_adapter.js` | No | Factory functions `createDomReader(config)` / `createDomWriter(config)` (parameterized by selectors) |
| `orchestrator.js` | No | Source-agnostic action router, memory, directive execution (parameterized by full config) |
| `index.js` | — | Public API — re-exports everything from core modules |

### App Layer (`assets/js/input/`)

Tests in `__tests__/` run via `bun test assets/js/input/__tests__/`.

| Module | Pure? | Role |
|--------|-------|------|
| `config.js` | Yes | All app-specific config: selectors, layouts, instance types, behaviors |
| `index.js` | No | LiveView hook factory — imports core + config, exports `createInputHook()` |
| `page_behavior.js` | No | Registry mapping `data-page-behavior` → behavior factory |
| `dashboard_behavior.js` | Yes | Dashboard: BACK → sidebar |
| `library_behavior.js` | Yes* | Library: BACK → sidebar, CLEAR → filter, sort tracking |
| `review_behavior.js` | Yes | Review: BACK → sidebar |
| `settings_behavior.js` | Yes | Settings: BACK → sections, activateOnFocus for sections |

*Library behavior is pure when injected with mock DOM.

## Input Source Contract

Input sources are decoupled peers behind a common duck-typed interface. The orchestrator is source-agnostic — it never knows which source produced an action.

**Interface:**
```javascript
// Constructor receives config including two callbacks:
//   onAction(action)        — semantic action produced (from Action enum)
//   onInputDetected(type)   — raw input detected ("keydown", "gamepadbutton", "gamepadaxis")
// Methods:
//   start()  — begin listening/polling
//   stop()   — clean up all listeners/timers
```

**Wiring:** Sources are provided as factory functions in config. Each factory receives `(callbacks, globals)` and returns a source instance. The orchestrator calls `start()` on mount and `stop()` on destroy.

```javascript
sources: [
  (callbacks, globals) => new KeyboardSource({ document: globals.document, ...callbacks }),
  (callbacks, globals) => new GamepadSource({ getGamepads: globals.getGamepads, ...callbacks }),
]
```

**Adding a new input source:** Create a module implementing `start()`/`stop()` that calls `onAction()` with values from the `Action` enum. Add a factory to the `sources` array in `index.js`. No orchestrator changes needed.

## Action Vocabulary

The `Action` enum defines all semantic actions. Sources map raw input events to these actions.

| Action | Keyboard | Gamepad | Purpose |
|--------|----------|---------|---------|
| `NAVIGATE_UP` | Arrow Up | D-pad Up / Left Stick Up | Move focus up |
| `NAVIGATE_DOWN` | Arrow Down | D-pad Down / Left Stick Down | Move focus down |
| `NAVIGATE_LEFT` | Arrow Left | D-pad Left / Left Stick Left | Move focus left |
| `NAVIGATE_RIGHT` | Arrow Right | D-pad Right / Left Stick Right | Move focus right |
| `SELECT` | Enter | A (Xbox) / Cross (PS) | Activate focused item |
| `BACK` | Escape | B (Xbox) / Circle (PS) | Dismiss / go back |
| `CLEAR` | Backspace | Y (Xbox) / Triangle (PS) | Clear page state (e.g. filter) |
| `PLAY` | P | Start/Menu (button 9) | Play focused media |
| `ZONE_NEXT` | ] | RB (button 5) | Next zone tab |
| `ZONE_PREV` | [ | LB (button 4) | Previous zone tab |

### Gamepad Button Map

Standard gamepad button indices (Gamepad API):

| Index | Xbox | PlayStation | Action |
|-------|------|-------------|--------|
| 0 | A | Cross | SELECT |
| 1 | B | Circle | BACK |
| 3 | Y | Triangle | CLEAR |
| 4 | LB | L1 | ZONE_PREV |
| 5 | RB | R1 | ZONE_NEXT |
| 9 | Menu/Start | Options | PLAY |
| 12 | D-pad Up | D-pad Up | NAVIGATE_UP |
| 13 | D-pad Down | D-pad Down | NAVIGATE_DOWN |
| 14 | D-pad Left | D-pad Left | NAVIGATE_LEFT |
| 15 | D-pad Right | D-pad Right | NAVIGATE_RIGHT |

Unmapped buttons (2, 6, 7, 8, 10, 11, 16) are ignored.

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

**Config options:**

| Option | Purpose |
|--------|---------|
| `instanceTypes` | Map instance names to context behavior types |
| `primaryMenu` | Instance name with enter/exit sidebar behavior |
| `initialContext` | Starting context (default: `GRID`) |
| `onContextChanged` | Callback `(context) => void` — fires on every actual context change |

### dom_adapter.js

Factory functions `createDomReader(config)` and `createDomWriter(config)` produce reader/writer instances parameterized by `config.contextSelectors` and `config.activeClassNames`. All DOM access is confined here. The orchestrator and behaviors never call `document.*` directly.

### keyboard.js

`KeyboardSource` — translates keyboard events into semantic actions. Owns keyboard-specific concerns:
- `keydown` event listener on document
- `data-captures-keys` bypass (reads `event.target`)
- Text input two-mode handling (`_inputEditing` state)
- Key-to-action mapping via `keyToAction()`
- `event.preventDefault()` for handled keys

Implements the **input source contract**: `constructor(config)`, `start()`, `stop()`.

### gamepad.js

`GamepadSource` — translates gamepad input into semantic actions. Idle-until-connected architecture with zero CPU cost when no gamepad is plugged in.

**Lifecycle:**
- `start()` registers passive `gamepadconnected`/`gamepaddisconnected` listeners. Also checks if a gamepad is already connected (handles page reload or hook remount with controller plugged in). When an already-connected gamepad is found, `onInputDetected` is fired so the orchestrator sets the correct input method immediately — this prevents the mouse position priming from stealing focus on the first mousemove.
- On connect → detect controller type, prime button state, start rAF polling loop.
- On disconnect → if no gamepads remain, stop rAF loop and reset all state.
- `stop()` removes event listeners, stops polling, resets state.

**Button edge detection:** Compares `gamepad.buttons[i].pressed` against previous frame. Rising edge (false→true) fires the mapped action once. Navigation actions (D-pad: up/down/left/right) get **repeat timing** — after `repeatDelay` (400ms), the action repeats every `repeatInterval` (180ms) while held. Non-navigation buttons (SELECT, BACK, PLAY) fire once on press with no repeat.

**Analog stick:** Deadzone filtering (default 0.3). Values above the threshold snap to cardinal directions. Same repeat timing as D-pad buttons — initial delay, then interval while held. Direction change resets the repeat timer.

**Button priming:** On start, if a gamepad is already connected, `_primeButtons()` reads the current button state without firing any actions. This prevents false rising edges when buttons are held during a hook remount (e.g., navigating the sidebar with D-pad causes LiveView navigation → hook destroy + mount → new GamepadSource sees held button as "just pressed").

**Controller type detection:** `detectControllerType(id)` parses the `Gamepad.id` string to identify `"xbox"`, `"playstation"`, or `"generic"`. Used by the hint bar to show correct button labels.

**Per-frame cost when active:** ~17 boolean comparisons + 2 float comparisons + 2 timestamp checks. No allocations — `_prevButtons` array and `_axisState` objects are pre-allocated and mutated in place. No gamepad references held across frames (read-and-discard pattern).

Implements the **input source contract**: `constructor(config)`, `start()`, `stop()`.

### orchestrator.js

Source-agnostic action router. Receives full config object including `reader`, `writer`, `globals`, `sources`, and all app-specific settings (dependency injection for testability).

**Responsibilities:**
- Lifecycle: `start(hookEl)`, `destroy()`, `onViewChanged()`
- Input source management: create, start, and stop sources from factory functions
- Action routing: source → `_onSourceAction()` → behavior hooks (`onClear`, `onEscape`) → `_handleAction()` → state machine → directive → execution
- Input method detection via source `onInputDetected` callbacks
- Nav context projection via `onContextChanged` callback → `setNavContext`
- Context memory (grid entity ID, per-context index)
- Modal/drawer focus restoration (origin entity tracking)
- Sidebar persistence (sessionStorage bridge)
- Page behavior lifecycle (detect, create, delegate, destroy)
- Hint bar controller type updates (`setControllerType`)

**SELECT on MENU.** When SELECT is pressed in any MENU context, the orchestrator remaps it to NAVIGATE_RIGHT (exit the menu into the content area). For the primary menu (sidebar), no click is needed — items are already activated on focus during up/down navigation. For non-primary menus (like settings sections), the focused item is clicked after the transition completes. This means A/Enter on a menu item "confirms" the selection and moves focus into the page.

**CLEAR routing.** The `CLEAR` action (Y / Backspace) is routed to the page behavior's `onClear()` hook before any other handling. If the behavior has no `onClear`, the action is a no-op. This separates "reset page state" (clear filter) from "go back" (navigate toward sidebar).

**BACK context gating.** The orchestrator's `_onSourceAction()` lets page behavior `onEscape()` intercept BACK, but only in content contexts (grid, toolbar, zone_tabs). BACK in overlays (modal, drawer) and menus (sidebar, sections, or any MENU-type instance) bypasses `onEscape()` entirely — these contexts have their own BACK semantics (dismiss, exit, nav graph left).

**onEscape return values.** `onEscape()` supports three return types:
- **`false`** — not consumed, falls through to normal BACK handling
- **`true`** — consumed by behavior (action stops)
- **`string`** — navigate to the named context. If the target is the primary menu, the full enter-sidebar flow runs (expand sidebar, record pre-sidebar context). Otherwise, `forceContext` + `restoreContextFocus`.

**Activate on focus.** The `primaryMenu` (sidebar) always clicks items on focus during up/down navigation, triggering page navigation. Page behaviors can declare `activateOnFocus: ["sections"]` to add the same behavior for other menu contexts on that page only. This is page-scoped to avoid unintended navigation — e.g., the dashboard and settings pages both use a `sections` zone, but only settings should auto-navigate between sub-pages.

### page_behavior.js — Behavior Registry

Maps `data-page-behavior` attribute values to behavior factories. Each factory receives the orchestrator's `globals` for dependency injection.

### library_behavior.js — Library Page Behavior

Extracts library-specific concerns from the orchestrator. Receives a `dom` interface (injected, never global). Zone, filter, and sort state live in the URL (managed by LiveView `handle_params`) — the input system doesn't persist these.

| Hook | Purpose |
|------|---------|
| `onAction(action, context, focused)` | Calendar left/right → month nav; tracking SELECT → grid drill-in |
| `onEscape()` | Returns `"upcoming"` from tracking grid, `"sidebar"` otherwise |
| `onClear()` | Clear filter input if non-empty |
| `onZoneChanged(context)` | Track tracking drill-in state (preserved through modal/drawer overlays) |
| `onSyncState(reader)` | Detect sort order change → signal grid memory clear |

## Context Navigation Rules

Actions in each context:

| Action | GRID | TOOLBAR | ZONE_TABS | MENU (sidebar) | MENU (other) | MODAL | DRAWER |
|--------|------|---------|-----------|----------------|--------------|-------|--------|
| Up | navigate | → ZONE_TABS | wall | navigate | navigate (wall → graph) | navigate (wrap) | navigate |
| Down | navigate | → GRID | → TOOLBAR or GRID | navigate | navigate (wall → graph) | navigate (wrap) | navigate |
| Left | navigate | navigate | navigate | wall | nav graph left | navigate (wrap) | → GRID (row edge) |
| Right | navigate | navigate | navigate | exit sidebar | nav graph right | sub-focus / navigate | wall |
| Select | activate | activate | activate | exit sidebar* | click + nav right | activate | activate |
| Back | onEscape | onEscape | onEscape | exit sidebar | nav graph left | dismiss | dismiss |
| Clear | onClear | onClear | onClear | — | — | — | — |
| Play | play | — | — | — | — | play | play |
| Zone± | zone_cycle | zone_cycle | zone_cycle | — | — | — | zone_cycle |

\* Primary menu items are already activated on focus — SELECT just exits without clicking.

**BACK behavior:** In content contexts (grid/toolbar/zone_tabs), BACK delegates to the page behavior's `onEscape()`. String returns navigate to the named context (all current behaviors return `"sidebar"`). Boolean `true` consumes the action. `false` falls through to the normal handler (no-op for content contexts). In modal/drawer, BACK always dismisses. In any MENU context (sidebar, sections), BACK bypasses `onEscape()` and uses the state machine's own semantics (exit sidebar, or nav graph left for non-primary menus).

**CLEAR behavior:** In any context, CLEAR delegates to the page behavior's `onClear()` hook. Currently only the library behavior implements this (clears the filter input). If no `onClear` exists, the action is silently dropped.

**MENU behavior:** The sidebar instance has hardcoded exit_sidebar on right/back and wall on left. Other MENU instances (like `"sections"`, `"upcoming"`) use the navigation graph for left/right/back — if the graph points to `"sidebar"`, it produces `enter_sidebar`. Non-primary menus also support wall-to-graph fallback on up/down: hitting the top or bottom of the list consults the nav graph for that direction (e.g., up from the first `upcoming` item transitions to `zone_tabs`).

**Modal navigation:** UP/DOWN/LEFT navigate linearly with wrapping. RIGHT tries sub-focus first (entering a sub-item within the focused element); if no `[data-nav-sub-item]` exists, falls back to linear navigation. This makes both vertical item lists and horizontal button rows work without per-modal configuration.

**Wall transitions** (when navigation reaches the edge):
- Grid up → TOOLBAR (library zone) or ZONE_TABS (watching zone)
- Grid left → nav graph target (sidebar in library/watching zones, sections in settings zone)
- Grid right → DRAWER (if open)
- MENU up/down → nav graph target for that direction (if defined)
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
| `dismiss` | — | Push dismiss event to LiveView (`data-dismiss-event` or `close_detail`) |
| `play` | — | Push `play` event with entity ID, flash animation |
| `zone_cycle` | `direction` | Click next/prev zone tab |
| `enter_sidebar` | — | Expand sidebar, focus active item |
| `exit_sidebar` | — | Restore pre-sidebar context and sidebar state |
| `none` | — | No-op (wall) |

## DOM Contract

| Attribute | Purpose | Values |
|-----------|---------|--------|
| `data-nav-zone` | Navigation zone container | `grid`, `toolbar`, `sidebar`, `sections`, `upcoming`, `zone-tabs` |
| `data-nav-item` | Focusable element (needs `tabindex="0"`) | — |
| `data-nav-grid` | CSS grid container (column count detection) | — |
| `data-entity-id` | Stable entity identifier on cards | UUID |
| `data-detail-mode` | Presentation shell type | `modal`, `drawer` |
| `data-detail-view` | Sub-view within modal (read by orchestrator for layered BACK) | `main`, `info` |
| `data-dismiss-event` | Custom event pushed on modal dismiss instead of `close_detail` | event name string |
| `data-section-type` | Section identifier for page behavior `onAction` dispatch | `calendar`, `tracking`, `scan`, etc. |
| `data-captures-keys` | Element handles own keyboard events | — |
| `data-sort` | Current sort order value | string |
| `data-page-behavior` | Page behavior to activate | `dashboard`, `library`, `review`, `settings` |
| `data-nav-default-zone` | Default zone for pages without zone tabs | `settings` |
| `data-nav-remember` | Sidebar link preserves target page URL across navigation | — |
| `data-input` | Current input method (set on `<html>`) | `mouse`, `keyboard`, `gamepad` |
| `data-sidebar` | Sidebar state (set on `<html>`) | `collapsed` |
| `data-nav-zone-value` | Zone identifier on tab elements | `watching`, `library`, `upcoming` |
| `data-nav-defer-activate` | Skip activate-on-focus — only activate on explicit SELECT | — |
| `data-nav-action` | Custom event name dispatched on SELECT instead of `.click()` | event name string |
| `data-nav-focus-target` | Suppress focus ring on this nav item — delegate to `data-nav-focus-ring` children | — |
| `data-nav-focus-ring` | Receive delegated focus ring when ancestor `data-nav-focus-target` item is focused | — |
| `data-nav-context` | Current focus context for hint bar (set on `<html>`) | `grid`, `sidebar`, `modal`, etc. |
| `data-gamepad-type` | Controller type for hint bar labels (set on `<html>`) | `xbox`, `playstation`, `generic` |

**Nav zone containers must not nest.** Descendant selectors cross-contaminate. Exception: a zone using a direct-child selector (`> [data-nav-item]`) can contain a nested zone without double-counting items. The `upcoming` zone uses this pattern — its tracking section nav item wraps a nested `grid` zone.

## Page Behavior System

Page behaviors extract page-specific concerns from the global orchestrator. The orchestrator detects `data-page-behavior` on the page and delegates to the matching behavior at the right lifecycle points.

**Interface** (duck-typed, all methods optional):

```javascript
/** @typedef {Object} PageBehavior
 *  @property {string[]} [activateOnFocus] - Menu contexts that click on focus during up/down nav
 *  @property {function(): void} [onAttach]
 *  @property {function(): void} [onDetach]
 *  @property {function(string, string, Element): boolean|{transitionTo: string}} [onAction]
 *  @property {function(): boolean|string} [onEscape] - true to consume, string to navigate
 *  @property {function(): void} [onClear]  - CLEAR action (Y / Backspace)
 *  @property {function(string): void} [onZoneChanged]
 *  @property {function(Object): {clearGridMemory: boolean}} [onSyncState]
 */
```

**Lifecycle:**
1. `_syncState()` calls `_detectBehavior()` — reads `data-page-behavior` from DOM
2. If behavior name changed, detach old behavior, create new one via registry
3. `onAttach()` called on creation
4. `onSyncState(reader)` called every sync cycle
5. `onZoneChanged(context)` called when focus context changes
6. `onAction(action, context, focusedItem)` called at the start of `_handleAction`, before the state machine processes the action. Return `true` to consume, `{ transitionTo: "contextName" }` to transition focus, or `false`/`undefined` to pass through. Used for per-item directional overrides (e.g., calendar left/right → month nav) and custom drill-in transitions (e.g., tracking SELECT → grid).
7. `onClear()` called on CLEAR action — reset page state (e.g. clear filter)
8. `onEscape()` called before normal BACK handling in content contexts — return `true` to consume, string to navigate to context
9. `onDetach()` called on `destroy()` or behavior change

**Dependency injection:** Behavior factories receive their DOM interface at creation time. No global scope access — keeps behaviors testable with mocks.

## Focus Memory Model

- **Grid:** Remembers by entity ID (stable across stream DOM reorders)
- **All other contexts:** Active item (DOM marker) → saved index memory → first item
- **Zone change:** Clears grid + toolbar memory (content is new)
- **Sort change:** Clears grid memory (order changed, positions meaningless)
- **Modal/drawer dismiss:** Restores to the originating card via `_originEntityId`
- **Modal sub-view transition:** When BACK fires in a modal with `data-detail-view != "main"`, the orchestrator pushes `close_detail` without dismissing focus context. Sets `_pendingModalRefocus = true`, and `_syncState` refocuses the first modal item after LiveView patches the DOM. This prevents focus from falling to the grid when morphdom removes the sub-view's focused element.

**Active item detection:** `reader.getActiveItemIndex(context)` finds the first item in a context with any "active" marker class from `config.activeClassNames`. When adding a new context with an active-item visual, add the class to the `activeClassNames` array in `config.js`.

## Text Input Handling

Two modes for `<input>` and `<textarea>` elements:

1. **Focused, not editing:** Arrow keys still navigate. Enter → edit mode. Printable chars → edit mode + pass through.
2. **Editing:** All keys pass through. Enter → exit edit mode. Escape → clear value + exit edit mode.

## Sidebar Persistence

SessionStorage bridge for resuming sidebar context across LiveView navigations:

- `destroy()`: if in sidebar context → save `inputSystem:resumeSidebar = true`
- `start()`: if flag set → remove flag, force sidebar context, focus active item

## Input Method Persistence

SessionStorage bridge for preserving the active input method (mouse/keyboard/gamepad) across LiveView navigations:

- `destroy()`: save `inputSystem:inputMethod = <current method>`
- `start()`: if saved → remove key, create `InputMethodDetector` with saved value, write `data-input` immediately

Without this, navigating between pages (each a separate LiveView) would reset input method to mouse. Combined with the hint bar living in `root.html.heex` (outside the LiveView boundary), this ensures zero flicker when using a gamepad across page transitions.

## URL Persistence for Sidebar Navigation

The `data-nav-remember` attribute on sidebar links preserves query params across page navigation. Implemented in `root.html.heex` via a global click handler:

1. **On any nav item click:** Saves `sessionStorage["nav:" + currentPath]` → `currentPath + queryString`
2. **On clicks to links with `data-nav-remember`:** Looks up `sessionStorage["nav:" + targetPath]` and rewrites the `href` before navigation

This means pages that use query params for state (like `/settings?section=logging` or `/library?zone=library&type=movie`) automatically resume at the last-visited section when the user navigates back via the sidebar.

**To opt in:** Add `data-nav-remember` to the sidebar link in `layouts.ex`. The page must use query params (via `live_patch` / `handle_params`) for any state it wants to persist.

## Gamepad Hint Bar

A contextual button legend fixed at the bottom center of the viewport. Shows relevant gamepad controls for the current navigation context.

**Always in DOM.** Follows the backdrop-filter rule — never conditionally rendered with `:if`. Visibility is pure CSS, driven by `[data-input=gamepad]` on `<html>`.

**Context-driven groups.** Multiple `.hint-group` divs with `data-hint-context` attributes. CSS selectors like `[data-nav-context=grid] [data-hint-context=grid]` show the appropriate group. The `FocusContextMachine` fires its `onContextChanged` callback on every context transition; the orchestrator wires this to `writer.setNavContext()` which updates `data-nav-context` on `<html>`.

**Controller-aware labels.** Button labels use `::before` pseudo-elements driven by `[data-gamepad-type]` on `<html>`. Xbox labels shown by default (and for generic controllers). PlayStation controllers show Cross/Circle/L1/R1 instead of A/B/LB/RB. The `GamepadSource` detects controller type from `Gamepad.id` and calls `writer.setControllerType()`.

**Markup:** Lives in `root.html.heex`, outside the LiveView boundary. This ensures the hint bar DOM persists across cross-LiveView navigations (sidebar page changes) without being destroyed and recreated.

**Contexts and their hints:**

| Context | Hints shown |
|---------|-------------|
| `grid` | D-pad Navigate, A Select, B Back, Y Clear, Start Play, LB/RB Zone |
| `modal` | D-pad Navigate, A Select, B Close, Start Play |
| `drawer` | D-pad Navigate, A Select, B Close, Start Play |
| `sidebar` | D-pad Navigate, A Select, B Exit, LB/RB Zone |

## CSS Integration

- `[data-input=keyboard]` / `[data-input=gamepad]` — focus ring visibility
- `[data-input=mouse]` — hides focus outlines
- `nav-play-flash` — green ring animation (300ms) on play action
- `.gamepad-hint-bar` — fixed bottom-center, glass-nav background, fade+translateY entrance

## Input Method Detection

Three methods: `mouse`, `keyboard`, `gamepad`. Switched by detecting raw input events. The `InputMethodDetector` (pure state machine) tracks the current method; the orchestrator writes it to `data-input` on `<html>`.

**Mouse detection uses position tracking, not event counting.** Layout shifts from LiveView patches fire synthetic `mousemove` events at the same coordinates (the OS controls cursor position, not the page). The orchestrator only switches to mouse when `clientX`/`clientY` actually change (≥1px delta). The first `mousemove` after a fresh orchestrator primes the baseline position without switching — this prevents false switches during full-page navigations where the initial position is unknown.

**Gamepad presence signaling.** When `GamepadSource.start()` detects an already-connected gamepad (e.g., after a hook remount from sidebar navigation), it fires `onInputDetected("gamepadbutton")` so the orchestrator immediately sets gamepad mode. Without this, the input method would default to mouse until the user presses a button.

## Single-Owner DOM Projection

Each `data-*` attribute on `<html>` is a **projection** of exactly one piece of internal state, synced by a direct callback from the state owner — never piggybacked on an unrelated event.

| Attribute | State Owner | Sync Mechanism |
|-----------|------------|----------------|
| `data-input` | `InputMethodDetector.current` | `_onInputDetected` → `setInputMethod` |
| `data-nav-context` | `FocusContextMachine.context` | `onContextChanged` callback → `setNavContext` |
| `data-gamepad-type` | `GamepadSource` controller detection | `setControllerType` on connect |
| `data-sidebar` | `localStorage` | Inline script in `root.html.heex` |

**Design rules:**

1. **Single-owner projection** — each DOM attribute has one state owner and one sync path.
2. **Framework notifies, app reacts** — state machines expose change callbacks; app wiring connects them to DOM writes.
3. **Coincidental coupling is a bug** — if two events "always happen together" during normal use, they will diverge in edge cases (startup, teardown, testing).

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
6. If the page has unique navigation contexts (not grid/modal/drawer/sidebar), add a `hint-group` with the appropriate `data-hint-context` in `root.html.heex` and show/hide CSS in `app.css`
7. Write nav graph tests and focus context tests for the new zone

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

## Debug Logging

All core modules use `debug()` from `core/debug.js` for structured runtime tracing. Silent by default — enable with `window.__inputDebug = true` in the browser console or via the Chrome DevTools MCP. All messages are prefixed `[input]`.

Coverage: context transitions (with caller), actions received, grid navigation state, mouse movement, gamepad axis events, sync state calls. Never use bare `console.log` in core modules — always go through `debug()`.
