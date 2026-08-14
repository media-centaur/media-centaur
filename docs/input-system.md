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
| `home_behavior.js` | Yes | Home (`/`): hero scroll pinning. Shelves don't activate-on-focus |
| `library_behavior.js` | Yes* | Library: CLEAR → filter, sort tracking |
| `review_behavior.js` | Yes | Review: no page-specific hooks |
| `settings_behavior.js` | Yes | Settings: activateOnFocus for sections |
| `incoming_behavior.js` | Yes | Incoming (`/incoming`) page navigation |
| `status_behavior.js` | Yes | Status (`/status`) page navigation |
| `watch_history_behavior.js` | Yes | Watch History (`/history`) page — filter pills, date badge, event list, pagination |
| `controls_bridge.js` | No | Listens for `controls:updates` from `MediaCentaur.Controls` and rewrites the keyboard/gamepad source maps at runtime so user rebindings take effect without reload |

*Library behavior is pure when injected with mock DOM.

Settings → Controls (v0.16.0) makes every entry in the Action Vocabulary table below **user-remappable**. The tables here document the *defaults* shipped in `MediaCentaur.Controls.Catalog`. User overrides are persisted under `controls.keyboard` / `controls.gamepad` in `Settings.Entry` and are pushed to the browser via `controls_bridge.js`, which swaps the key→action / button→action maps live on the running `KeyboardSource` and `GamepadSource` instances.

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

**Context types:** `GRID` · `TOOLBAR` · `ZONE_TABS` · `MENU` · `SHELF` · `TREE` · `MODAL` · `DRAWER`

**Instance → type mapping:** The `contextType(instance, instanceTypes)` resolver maps instance names to behavior types. Multiple instances can share the same behavior type — for example, both `"sidebar"` and `"sections"` resolve to `MENU`, and the home page's `"hero"`/`"continue"`/`"recently"`/`"coming_up"` shelves all resolve to `SHELF`. Instance names not in the map are their own type (e.g., `"grid"` → `GRID`). The map is provided via config, not hardcoded in the framework.

**`SHELF` is spatial; `MENU` is a list.** A `MENU`'s order is semantic — it is a list of choices that happens to be drawn vertically — so it navigates by index. A `SHELF` is a set of media tiles whose *arrangement* carries the meaning, so it navigates by geometry. The home page is a stack of shelves: hero CTAs, Continue Watching, Recently Added, and the Coming Up marquee. Most are a single row; the marquee is a mosaic (one large tile beside a stacked column). Both are the same thing, so there is one context type and one code path.

All four directions in a `SHELF` return a plain `navigate`; the orchestrator's `_shelfNavigate` resolves them by asking three questions in order:

1. **The layout** — `findNearest()` against the live item rects. This answers anything the arrangement makes unambiguous, and it is why the mosaic needs no adjacency table of its own (one would be wrong the moment the marquee renders a fourth tile).
2. **The nav graph** — nothing in that direction means we're at the shelf's edge, so try crossing into a neighbouring zone. Empty shelves are skipped by the graph's candidate fallback lists.
3. **The sequence, inline axis only** — a shelf is still an ordered set, and that order reads left to right. When the layout offers nothing and there is nowhere to cross to, "right" means the next tile: this is what carries you from the marquee's top secondary *rightward* to the one below it. UP and DOWN deliberately never reach here — "the next tile" in a mosaic is the one beside you, so a vertical press would move the cursor sideways (measured: DOWN on the marquee's large tile landed on the top secondary, up and to its right). In a single row the fallback only fires at the ends, where the sequence has nothing to offer either.

Keeping wall handling out of the state machine is what lets a row and a mosaic share one rule set — the machine never has to know which it is.

**Perfect alignment ties, and ties break in document order.** A candidate whose cross-axis span lies wholly inside the origin's is *perfectly* aligned and pays no alignment penalty: there is nothing to be more in line with. A tall tile facing a stack of short ones (the marquee's large tile beside its secondaries) therefore ties on distance, and document order decides — so RIGHT reaches the **top** secondary, which is what "the next one" means to a viewer. Scoring by centre distance instead silently picks the middle of the stack.

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

**Input gating:** Every poll frame checks the injected `acceptsInput()` predicate. In production this is the pure policy `gamepadInputAllowed()` (`assets/js/input/input_gate.js`) evaluated against live signals: it returns true only when the surface is **focused** (`document.hasFocus()`), **visible** (`document.visibilityState === "visible"`), and **not an automation context** (`!navigator.webdriver`). When it returns false, all gamepad actions and `onInputDetected` signals are suppressed. The poll loop keeps running and re-priming button state, so input resumes the instant the surface becomes active again and a button held at that moment is not read as a fresh press. Keyboard needs no such gate: the OS only routes key events to the focused window, whereas the Gamepad API exposes global controller state regardless of which surface the user is looking at. The gate is event-independent (does not rely on `blur`/`focus` events firing) and self-healing — if an event were ever missed, the next poll frame still does the right thing.

Each signal closes a distinct hole through which an *invisible* surface could hijack a physical controller:

- **Focus** — the authoritative fix for "gamepad triggers the app while I'm playing a game on another workspace." The Page Visibility API (`document.hidden`, used by the orchestrator's `visibilitychange` pause/resume) does **not** flip on a tiling/multi-monitor WM because the window is still composited — but OS focus moves to the game, so `hasFocus()` is the reliable signal there.
- **Visibility** — a backgrounded tab or occluded window that still reports focus.
- **Automation** — a headless debug browser (e.g. `mc-debug-browser`, which launches with `--enable-automation`) reports `hasFocus:true` **and** `visibilityState:"visible"`, so focus + visibility alone do **not** catch it. `navigator.webdriver` is the deterministic marker — agent-spawned browsers set it intentionally, so this is a trustworthy signal rather than fragile UA fingerprinting. This is the fix for "pressing A launches an episode in a Chromium I can't even see," which happens when an agent leaves a headless instance loaded on the app and a real controller drives it.

**Controller type detection:** `detectControllerType(id)` parses the `Gamepad.id` string to identify `"xbox"`, `"playstation"`, or `"generic"`. Used by the hint bar to show correct button labels.

**Per-frame cost when active:** ~17 boolean comparisons + 2 float comparisons + 2 timestamp checks. No allocations — `_prevButtons` array and `_axisState` objects are pre-allocated and mutated in place. No gamepad references held across frames (read-and-discard pattern).

Implements the **input source contract**: `constructor(config)`, `start()`, `stop()`.

### orchestrator.js

Source-agnostic action router. Receives full config object including `reader`, `writer`, `globals`, `sources`, and all app-specific settings (dependency injection for testability).

**Responsibilities:**
- Lifecycle: `start(hookEl)`, `destroy()`, `onViewChanged()`
- Input source management: create, start, and stop sources from factory functions
- Action routing: source → `_onSourceAction()` → behavior hook (`onClear`) → `_handleAction()` → state machine → directive → execution
- Input method detection via source `onInputDetected` callbacks
- Nav context projection via `onContextChanged` callback → `setNavContext`
- Context memory (grid entity ID, per-context index)
- Modal/drawer focus restoration (origin entity tracking)
- Sidebar persistence (sessionStorage bridge)
- Page behavior lifecycle (detect, create, delegate, destroy)
- Hint bar controller type updates (`setControllerType`)

**SELECT on MENU.** When SELECT is pressed in any MENU context, the orchestrator remaps it to NAVIGATE_RIGHT (exit the menu into the content area). For the primary menu (sidebar), no click is needed — items are already activated on focus during up/down navigation. For non-primary menus (like settings sections), the focused item is clicked after the transition completes. This means A/Enter on a menu item "confirms" the selection and moves focus into the page.

**CLEAR routing.** The `CLEAR` action (Y / Backspace) is routed to the page behavior's `onClear()` hook before any other handling. If the behavior has no `onClear`, the action is a no-op. This separates "reset page state" (clear filter) from "go back" (navigate toward sidebar).

**BACK peels containment, and is answered once.** `transition()` routes BACK to `_backTransition()` *before* dispatching on context type, so the rule lives in one place instead of a `case Action.BACK` in every transition function. In order:

1. **An overlay region** with a `back` edge in the nav graph → leave for that region. One press, however deep the cursor is inside the region (see [UIDR-019](../decisions/user-interface/2026-08-07-019-detail-modal-two-regions.md)) — stepping out one level at a time is LEFT's job.
2. **Sub-focus** → back out to the item. Reached only in overlays with no inner regions, i.e. the flat ones.
3. **An overlay** → dismiss.
4. **The primary menu** → exit to the pre-sidebar context.
5. **Content** → nothing.

Lateral movement toward the sidebar belongs to LEFT: every zone layout gives its left-edge context a `left: ["sidebar"]` edge (or a chain that reaches it), so left-at-the-left-edge is the one idiom for reaching the main nav.

**Activate on focus.** The `primaryMenu` (sidebar) always clicks items on focus during up/down navigation, triggering page navigation. Page behaviors can declare `activateOnFocus: ["sections"]` to add the same behavior for other menu contexts on that page only. This is page-scoped to avoid unintended navigation — e.g., the dashboard and settings pages both use a `sections` zone, but only settings should auto-navigate between sub-pages.

### page_behavior.js — Behavior Registry

Maps `data-page-behavior` attribute values to behavior factories. Each factory receives the orchestrator's `globals` for dependency injection.

### library_behavior.js — Library Page Behavior

Extracts library-specific concerns from the orchestrator. Receives a `dom` interface (injected, never global). The library page is a single browse surface — a `toolbar` (type tabs + sort dropdown + text filter) above a poster `grid`. Tab, filter, and sort state live in the URL (managed by LiveView `handle_params`) — the input system doesn't persist these. The page declares `data-nav-default-zone="library"` so it resolves to the `library` layout (it has no zone tabs).

| Hook | Purpose |
|------|---------|
| `onClear()` | Clear filter input if non-empty → return `"grid"` so focus follows the unfiltered content |
| `onZoneChanged(context)` | Pin the page to the top when focus reaches the `toolbar` (the topmost context) |
| `onSyncState(reader)` | Detect sort order change → signal grid memory clear |

## Context Navigation Rules

Actions in each context:

| Action | GRID | TOOLBAR | ZONE_TABS | MENU (sidebar) | MENU (other) | SHELF | TREE | MODAL | DRAWER |
|--------|------|---------|-----------|----------------|--------------|-------|------|-------|--------|
| Up | navigate | nav graph up | wall | navigate | navigate (wall → graph) | navigate (spatial) | navigate | navigate (wrap) | navigate |
| Down | navigate | nav graph down | → TOOLBAR or GRID | navigate | navigate (wall → graph) | navigate (spatial) | navigate | navigate (wrap) | navigate |
| Left | navigate | navigate | navigate | wall | nav graph left | navigate (spatial) | `tree_out` | navigate (wrap) | → GRID (row edge) |
| Right | navigate | navigate | navigate | exit sidebar | nav graph right | navigate (spatial) | `tree_in` | sub-focus / navigate | wall |
| Select | activate | activate | activate | exit sidebar* | click + nav right | activate | activate | activate | activate |
| Back | no-op | no-op | no-op | exit sidebar | no-op | no-op | graph `back` | dismiss | dismiss |
| Clear | onClear | onClear | onClear | — | — | onClear | — | — | — |
| Play | play | — | — | — | — | play | play | play | play |

A TOOLBAR *inside an overlay* (the detail modal's action row) reads the same as
the column above except for BACK, which the containment order resolves to
`dismiss` — the region has no `back` edge, so the overlay itself is the next
layer out.
| Zone± | zone_cycle | zone_cycle | zone_cycle | — | — | — | — | zone_cycle |

\* Primary menu items are already activated on focus — SELECT just exits without clicking.

**BACK behavior:** answered by `_backTransition()` before the type dispatch — see the containment order above. The table's BACK column is what that order resolves to per context.

**CLEAR behavior:** In any context, CLEAR delegates to the page behavior's `onClear()` hook. Currently only the library behavior implements this (clears the filter input). If no `onClear` exists, the action is silently dropped.

**MENU behavior:** The sidebar instance has hardcoded exit_sidebar on right/back and wall on left. Other MENU instances (like `"sections"`, `"rail"`) use the navigation graph for left/right — if the graph points to `"sidebar"`, it produces `enter_sidebar`; BACK is a no-op there. Non-primary menus also support wall-to-graph fallback on up/down: hitting the top or bottom of the list consults the nav graph for that direction (e.g., up from the first `rail` item transitions to `actions`).

**Modal navigation:** UP/DOWN/LEFT navigate linearly with wrapping. RIGHT tries sub-focus first (entering a sub-item within the focused element); if no `[data-nav-sub-item]` exists, falls back to linear navigation. This makes both vertical item lists and horizontal button rows work without per-modal configuration.

**Overlays with regions.** An overlay carrying `data-nav-overlay="<name>"` navigates as several zones instead of one flat list, per `config.overlays[name]`: `entry` is the cursor-start priority among its regions, `layout` its internal edges (merged over the page's graph while it is open). The detail modal declares `detail` — a `detail_actions` TOOLBAR over the body, whose zones follow the sub-view: the season/film/extras lists are a `detail_list` TREE, the Cast view a `detail_cast` SHELF (a photo grid, so adjacency is answered by geometry — the lead/other-episodes sections and the Show more button need no adjacency table), and Manage brings its own pair — `manage_tools`, a TOOLBAR for its toolbar card (a horizontal strip: Delete all, Rematch, Refresh artwork, the ID links — LEFT/RIGHT move along it, DOWN drops past it), over `manage_list`, a TREE for the folder ledger. `manage_list` is deliberately not a reuse of `detail_list`: per-context cursor memory is keyed by context name, so sharing it let ledger activity overwrite the episode list's remembered position. Only one sub-view's zones are in the DOM at a time; the candidate lists on the `down` edges route to whichever region is populated, and each region's `back` edge gives BACK its first rung. Every region climbs on UP at its top (UIDR-019, twice amended): the cast grid and `manage_tools` to the action row, the tree through `manage_tools` when Manage is showing and to the action row otherwise. BACK stays the one-press way out from any depth; UP is the one-row way up. Overlays without the attribute stay flat MODAL, which is right for a confirm or a small form.

**TREE navigation:** a vertical list whose items nest. UP/DOWN walk it as rendered; LEFT and RIGHT are *depth*. The state machine emits only `tree_in` / `tree_out` — what they mean depends on what the cursor is on, which is a DOM question the orchestrator answers:

| Cursor on | `tree_in` (RIGHT) | `tree_out` (LEFT) |
|---|---|---|
| `[aria-expanded='false']` | click it (expand) | — |
| `[aria-expanded='true']` | step into its controls | click it (collapse) |
| A row inside a `[data-nav-group]` | step into its controls | focus the group's expanded head, then click it |
| A row's controls | next control | previous control, then out to the row |

**Contexts can open somewhere other than the top.** `config.entryDefaults[context]` names a CSS selector used when a context has no remembered position — `detail_list` uses `[data-resume-target]` so the body opens on the episode Play would play.

**Wall transitions** (when navigation reaches the edge):
- Grid up → TOOLBAR (library zone) or ZONE_TABS (watching zone)
- Grid left → nav graph target (sidebar in library/watching zones, sections in settings zone)
- Grid right → DRAWER (if open)
- MENU up/down → nav graph target for that direction (if defined)
- TOOLBAR up/down → nav graph target for that instance (the standard toolbar reaches zone_tabs/grid; the upcoming mini-month reaches actions/stragglers)
- SHELF, any direction with no spatial neighbour → nav graph, then (left/right only) the sequence — see the SHELF section above; left at the left edge therefore reaches the sidebar, and up/down with no neighbour and no graph edge is inert
- Zone tabs / toolbar left at index 0 → nav graph left edge (SIDEBAR for the standard top-left contexts; the rail for the upcoming mini-month)
- Drawer left → GRID (rightmost column, same row)

## Directive Reference

| Directive | Data | Executor action |
|-----------|------|-----------------|
| `navigate` | `direction` | Spatial (grid) or linear (other) nav within context |
| `focus_context` | `target` | Restore focus memory in target context |
| `enter_context` | `context`, `direction` | Cross into a context — declared anchor, else memory constrained to the edge crossed |
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
| `data-nav-zone` | Navigation zone container | `grid`, `toolbar`, `sidebar`, `sections`, `zone-tabs`, `hero`, `continue`, `recently`, `coming_up`, upcoming: `rail`, `stragglers`, `actions`, `mini-month` |
| `data-nav-item` | Focusable element (needs `tabindex="0"`) | — |
| `data-nav-grid` | CSS grid container (column count detection) | — |
| `data-entity-id` | Stable entity identifier on cards | UUID |
| `data-detail-mode` | Presentation shell type | `modal`, `drawer` |
| `data-detail-nested` | Modal is below its root view, so BACK returns instead of dismissing (read by orchestrator for layered BACK) | `true`, `false` |
| `data-nav-overlay` | Overlay navigates as regions per `config.overlays[name]` | `detail` |
| `data-nav-transient-params` | On a page root: query params the remember script strips when saving the page's URL — overlay/modal state and one-shot triggers, so leaving a section closes its modals | `selected,view,autoplay` |
| `data-nav-group` | Extent of a disclosure — LEFT inside it collapses via its `[aria-expanded]` head | (bare) |
| `aria-expanded` | Disclosure state on a nav item. Standard markup, read directly rather than mirrored into a `data-` attribute | `true`, `false` |
| `data-dismiss-event` | Custom event pushed on modal dismiss instead of `close_detail` | event name string |
| `data-section-type` | Section identifier for page behavior `onAction` dispatch | `calendar`, `tracking`, `scan`, etc. |
| `data-captures-keys` | Element handles own keyboard events | — |
| `data-sort` | Current sort order value | string |
| `data-page-behavior` | Page behavior to activate | `home`, `library`, `review`, `settings`, `status`, `download`, `watch-history` |
| `data-nav-default-zone` | Default zone for pages without zone tabs | `home`, `library`, `settings`, `status`, `review`, `watch_history` |
| `data-nav-remember` | Sidebar link preserves target page URL across navigation | — |
| `data-input` | Current input method (set on `<html>`) | `mouse`, `keyboard`, `gamepad` |
| `data-input-editing` | Text input is in edit mode (set on `<html>`) | `true` or absent |
| `data-sidebar` | Sidebar state (set on `<html>`) | `collapsed` |
| `data-nav-zone-value` | Zone identifier on tab elements | `watching`, `library`, `upcoming` |
| `data-nav-defer-activate` | Skip activate-on-focus — only activate on explicit SELECT | — |
| `data-nav-action` | Custom event name dispatched on SELECT instead of `.click()` | event name string |
| `data-nav-return-focus` | On a control that grows its own list (Show more): after SELECT's patch lands, the cursor returns to the item it came from — grounding the user before the new items get walked | — |
| `data-nav-reveal` | Scroll THIS ancestor into view instead of the focused item (hero: show the whole backdrop, not just the CTA) | — |
| `data-nav-reveal-block` | Block-axis alignment for the reveal, instead of "scroll the least" | `start`, `center`, `end` |
| `data-nav-enter-scroll-top` | On a zone container: a spatial crossing into the zone glides its nearest scrollable ancestor to the top. For pinned zones, where reveal is rightly a no-op (detail action row: climbing out of the episode list brings the hero back). BACK and post-patch restores don't move the scroll | — |
| `data-nav-focus-target` | Suppress focus ring on this nav item — delegate to `data-nav-focus-ring` children | — |
| `data-nav-focus-ring` | Receive delegated focus ring when ancestor `data-nav-focus-target` item is focused | — |
| `data-nav-context` | Current focus context for hint bar (set on `<html>`) | `grid`, `sidebar`, `modal`, etc. |
| `data-gamepad-type` | Controller type for hint bar labels (set on `<html>`) | `xbox`, `playstation`, `generic` |

**Nav zone containers must not nest.** Descendant selectors cross-contaminate. Exception: a zone whose selector uses a direct-child combinator (`> [data-nav-item]`) can contain a nested zone without double-counting items, should a future layout need it.

**One element owns the modal overlay.** The adapter resolves the *active modal* as the first `[data-detail-mode='modal']` match in DOM order, and derives everything from that one element: `data-detail-nested`, `data-dismiss-event`, and — unlike other contexts, which use flat config selectors — the MODAL context's nav items (`activeModalElement().querySelectorAll("[data-nav-item]")`). This keeps navigation and BACK pointed at the same overlay when modals stack (a confirm dialog over a detail modal, as on the Incoming page). Pages that stack modals must render the topmost overlay *first* among their `[data-detail-mode]` elements — on `/incoming`, the confirm dialogs render at the top of `:overlays`, before the plan and pursuit modals.

## Page Behavior System

Page behaviors extract page-specific concerns from the global orchestrator. The orchestrator detects `data-page-behavior` on the page and delegates to the matching behavior at the right lifecycle points.

**Interface** (duck-typed, all methods optional):

```javascript
/** @typedef {Object} PageBehavior
 *  @property {string[]} [activateOnFocus] - Menu contexts that click on focus during up/down nav
 *  @property {function(): void} [onAttach]
 *  @property {function(): void} [onDetach]
 *  @property {function(string, string, Element): boolean|{transitionTo: string}} [onAction]
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
8. `onDetach()` called on `destroy()` or behavior change

**Dependency injection:** Behavior factories receive their DOM interface at creation time. No global scope access — keeps behaviors testable with mocks.

## Focus Memory Model

Two operations, deliberately distinct. **Entering** a context is a user-driven
crossing (`_enterContext`); **restoring** it re-asserts focus the system already
holds after a DOM patch (`_restoreContextFocus`). Only entry obeys the anchor
and edge rules below — applying them on reconcile would drag the cursor around
on every re-render.

- **Grid:** Remembers by entity ID (stable across stream DOM reorders)
- **All other contexts:** Active item (DOM marker) → saved index memory → first item

### Entry rules

**A declared anchor wins.** Some zones exist to be entered at one specific
item. `config.entryAnchors` names them (`{ hero: 0 }`): the home hero's whole
job is "press play", so arriving from any direction lands on Play rather than
on whichever CTA was focused last. This is a product rule, so it is declared
rather than inferred — geometry would pick *Cast* when you arrive from a
right-ward Continue Watching card, and plain memory would pick whatever you
touched last. Anchors do **not** apply on reconcile.

**Otherwise memory is constrained to the edge you crossed.** You should land on
something adjacent to where you came from, so a remembered item that doesn't
touch the entry edge is not a candidate; the first item that does wins instead.
This is the whole of "coming down into the Coming Up marquee never lands on the
bottom tile" — that tile doesn't touch the mosaic's top edge. In a single-row
shelf every tile touches the top and bottom edges, so memory always survives
and the rule is invisible, which is exactly right.

The constraint is currently gated to `SHELF` contexts. The mechanism is
uniform — every `enter_context` directive carries its direction — and the gate
comes off page by page as each is reviewed. See
[`campaigns/input-system-1.0-pass.md`](../campaigns/input-system-1.0-pass.md).
- **Zone change:** Clears grid + toolbar memory (content is new)
- **Sort change:** Clears grid memory (order changed, positions meaningless)
- **Modal/drawer dismiss:** Restores to the originating card via `_originEntityId`
- **Modal sub-view transition:** When BACK fires in a modal carrying `data-detail-nested="true"`, the orchestrator pushes `close_detail` without dismissing focus context. The server owns that flag rather than the client comparing a view name to `"main"` — the detail modal's root view is entity-dependent (a movie with no extras has no body tab and opens on Cast, which *is* its root). Sets `_pendingModalRefocus = true`, and `_syncState` refocuses the overlay's entry region after LiveView patches the DOM. This prevents focus from falling to the grid when morphdom removes the sub-view's focused element.

**Active item detection:** `reader.getActiveItemIndex(context)` finds the first item in a context with any "active" marker class from `config.activeClassNames`. When adding a new context with an active-item visual, add the class to the `activeClassNames` array in `config.js`.

### Post-patch focus reconciliation

Focus *position* is owned state, not a value read from the DOM on demand — the same single-owner-projection discipline the `<html>` `data-*` attributes follow (see below). A LiveView patch can move, replace, or destroy the element the user was on; the worst case is `stream(:grid, …, reset: true)`, which `LibraryLive` fires on any library mutation (e.g. a completed download) — it re-renders the whole grid and drops focus to `<body>`.

Two hooks keep focus stable across patches:

- **`onBeforeViewChange()`** (wired to the hook's `beforeUpdate()`) snapshots the focused position *before* morphdom runs, via `_saveContextMemory()` — entity ID for the grid, saved index for the rest. This covers the idle case (no navigation since landing on the item, so move-time memory would lag by one).
- **`_reconcileFocus()`** (called at the end of `_syncState`, after the nav graph is rebuilt) is the single place that answers "where should focus be now." If focus was dropped, it re-asserts the owned identity for the current context: sub-item for sub-focus, first item for a modal sub-view transition, and `_restoreContextFocus(context)` for every content/menu context (grid, shelf, menu, toolbar, zone tabs). A new content surface that loses focus on a patch is covered without adding another bespoke guard.

Drawer focus on open and origin-card restore on overlay close are transition-driven (handled in the presentation block of `_syncState`); empty contexts are left to `_ensureCursorStart`.

**Reconcile only the focus the system owns ([ADR-053](../decisions/architecture/2026-06-06-053-focus-ownership-boundary.md)).** `getCurrentFocusedItem() === null` is ambiguous: it means *either* a patch dropped focus to `<body>` (the system owns this — restore) *or* focus moved to an element outside every managed nav region (the system does not own this — cede). Both `_reconcileFocus` and `_ensureCursorStart` guard on `reader.hasForeignFocus()` and return early when focus is foreign — a live element outside `[data-nav-item]`/`[data-nav-zone]`, or one that captures its own keys. This is what keeps an *unmanaged* overlay (a plain `data-state` modal like the Track-new-release dialog, invisible to the input system) usable while the page behind it re-renders: without the guard, every patch re-asserts the page context's focus and yanks the cursor out of the overlay. A managed filter input inside a nav zone is *not* foreign — it still navigates by arrow keys (see Text Input Handling).

## Scroll Reveal

Making the focused item visible is one decision, so it has one owner:
`revealItem()` in `dom_adapter.js`. All four writer entry points
(`focusElement`, `focusByIndex`, `focusFirst`, `focusByEntityId`) route through
it.

**The input system owns the scroll — destination and motion both.** Neither
half may be left to CSS, and each was tried:

- **`scroll-snap-type` fights the destination.** `.row-scroll` used to carry
  `scroll-snap-type: x mandatory`. Snap re-snaps *after* `scrollIntoView` to
  the nearest boundary, undershooting and parking the focused card ~100px — a
  third of it — outside the scrollport, on every home-shelf card past the fold.
  Scroll snap is a pointer affordance (flick, release, settle somewhere
  sensible); with a focus cursor there is nothing to settle, because the
  focused element already *is* the resting position. Never put snap on a
  nav-driven scroll container.
- **Neither browser smooth-scroll route survives held input.**
  `scrollIntoView({behavior: "smooth"})` stops retargeting altogether and
  strands the row. CSS `scroll-behavior: smooth` does retarget, but restarts
  its ease-in curve from rest each time; a held arrow repeats every ~33ms
  against a ~450ms curve, so the row never escapes the slow opening — measured,
  the cursor ran 3015px off-screen while `scrollLeft` stayed at 3, then the row
  lurched the whole way on key-up.

So the motion is ours: `scroll_glide.js` eases each container toward a target,
closing a fixed fraction of the remaining gap per frame. Speed therefore
depends only on distance remaining, so a target that keeps running away is
chased *harder*, and retargeting is just a new number — there is no per-animation
state to restart. Measured steady-state lag at the gamepad's 180ms repeat:
~70px, well under a quarter card.

`scroll-behavior` must stay off every nav-driven container, including `html`:
the property intercepts direct `scrollLeft`/`scrollTop` assignment too, so it
would launch a competing browser animation on each of the glide's per-frame
writes.

**Reveal the right subject.** `revealItem` scrolls the nearest
`[data-nav-reveal]` ancestor when there is one, else the item itself. The home
hero uses it: its CTAs sit low in a full-bleed backdrop, so revealing a button
alone parks it at the viewport's bottom edge with the title and artwork
stranded above. This replaced a page behavior that scrolled the window
separately and raced the reveal for the same scroll box.

The default — frame the item — is right only while every item in the surface
shares a bottom edge. Rows satisfy that by construction. A surface whose items
differ in **height** does not, and each item will frame itself: the Coming Up
mosaic (one tall primary beside two half-height secondaries) scrolled the page
up 129px on the way to a secondary, whose shorter bottom edge aligned to the
viewport bottom sits higher. Such a surface declares `data-nav-reveal` on the
composition. A declared subject must also carry the ring reserve — it is what
actually gets scrolled, and the CSS reserves on `[data-nav-reveal]` for exactly
that reason.

**Declare an alignment when one resting position matters.** Default
`"nearest"` scrolls as little as possible, so a surface comes to rest in a
different place depending on whether it was approached from above or below.
`data-nav-reveal-block` states the alignment instead; the home shelves use
`"end"`, which is why descending to a shelf and ascending to it land on the
same offset. It is a preference, not a promise: if honouring it would push the
focused item off the opposite edge — possible at large UI scales, where a
reserve can outgrow the viewport — the reveal falls back to a minimal one,
because keeping the item on screen beats framing it.

**How the destination is computed.** `revealItem` scrolls instantly, reads
where that landed, restores the offsets, and glides to the recorded target.
Roundabout on purpose: computing it directly would mean reimplementing
`scrollIntoView`'s "nearest" algorithm including `scroll-padding`, borders, and
writing modes. Nothing paints between the jump and the restore, so there is no
flicker.

**The wheel takes scroll authority.** Owning the scroll only holds while the
cursor is driving it. A wheel event is the pointer claiming the scroll, so the
orchestrator's `_onWheel` cancels every glide where it stands
(`writer.cancelScrollMotion()`) and switches the input method to mouse —
without either, an in-flight reveal overrode the user's scrolling on every
frame until it arrived. While the method is mouse, restores the user didn't
ask for (post-patch reconciles, cursor-start seeding) pass `{ reveal: false }`
to the writer's focus calls: focus is re-asserted with `preventScroll`, and
the viewport stays where the user put it. The next cursor-driving keypress or
gamepad input flips the method back before its action executes, so
cursor-driven navigation reveals exactly as before.

**The navigation owns mount-time scroll.** When `start()` runs — every live
navigation and the initial load — the window still carries the *previous*
page's scroll offset, and the navigation's own scroll write lands one frame
later: LiveView resets to top on a redirect, restores the saved position on
back/forward, and the browser restores on a fresh load. A reveal issued while
seeding focus would be measured against that doomed offset, and because a
glide chases an absolute target, it would re-assert the stale destination
*after* LiveView's write — scroll down on home, enter the sidebar, descend to
Library, and Library landed scrolled to wherever home had been. So the whole
of `start()` runs with `_mounting` set and `_restoreOpts()` returns
`{ reveal: false }` for every method, not just mouse: mount-time focus
seeding never moves the viewport. The first user action takes scroll
authority back and reveals as always — the same idiom as the mouse-mode
restore above. (`destroy()` guards the other side of the same seam: it
cancels the old page's in-flight glides, whose scroll containers —
`documentElement` — outlive the orchestrator.)


## Text Input Handling

Two modes for `<input>` and `<textarea>` elements:

1. **Focused, not editing:** Arrow keys still navigate. Enter → edit mode. Printable chars → edit mode + pass through. Backspace / Delete on a non-empty input → edit mode + native delete. Backspace on an empty input → CLEAR (page-level clear filter). Escape on a non-empty input → clears the value; Escape on an empty input falls through to BACK.
2. **Editing:** All keys pass through. Enter → exit edit mode (value preserved). Escape → exit edit mode (value preserved). A second Escape (now in Mode 1) clears the value.

The mode is surfaced to CSS via `data-input-editing` on `<html>`. `KeyboardSource` owns the state and projects it through the `onEditingChanged` callback wired in `index.js` to `writer.setTextEditing()`. Focused inputs show a brighter ring in edit mode so users can see at a glance whether arrow keys will navigate or type.

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
| `shelf` (home shelves: hero/continue/recently/coming_up) | D-pad Navigate, A Select, B Back, Start Play |

## CSS Integration

- `[data-input=keyboard]` / `[data-input=gamepad]` — focus ring visibility
- `[data-input=mouse]` — hides focus outlines
- `nav-play-flash` — green ring animation (300ms) on play action
- `.gamepad-hint-bar` — fixed bottom-center, glass-nav background, fade+translateY entrance

## Input Method Detection

Three methods: `mouse`, `keyboard`, `gamepad`. The `InputMethodDetector` (pure state machine) tracks the current method; the orchestrator writes it to `data-input` on `<html>`.

**The method is cursor authority, not "last device touched."** Mouse and keyboard are companions: a pointer user clicks into a modal and hits Escape to back out, or types into a field they clicked, without ceding the pointer's ownership of focus and scroll. So only **cursor-driving** keys switch to keyboard mode — arrows, Enter-as-SELECT, and the zone brackets (`isCursorDriving` in `actions.js`). Command keys (Escape, Backspace, `p`), typing into text inputs, unmapped keys, and keys inside `data-captures-keys` still perform their action but leave the method alone. Because BACK and CLEAR can now execute *in* mouse mode, every focus write their execution performs routes through `_restoreOpts()` — the viewport the pointer owns never moves. The gamepad is asymmetric on purpose: everything on a controller is navigation, so every button and axis switches to gamepad mode. New keys default to not switching.

**Mouse detection uses position tracking, not event counting.** Layout shifts from LiveView patches fire synthetic `mousemove` events at the same coordinates (the OS controls cursor position, not the page). The orchestrator only switches to mouse when `clientX`/`clientY` actually change (≥1px delta). The first `mousemove` after a fresh orchestrator primes the baseline position without switching — this prevents false switches during full-page navigations where the initial position is unknown.

**Gamepad presence signaling.** When `GamepadSource.start()` detects an already-connected gamepad (e.g., after a hook remount from sidebar navigation), it fires `onInputDetected("gamepadbutton")` so the orchestrator immediately sets gamepad mode. Without this, the input method would default to mouse until the user presses a button.

## Single-Owner DOM Projection

Each `data-*` attribute on `<html>` is a **projection** of exactly one piece of internal state, synced by a direct callback from the state owner — never piggybacked on an unrelated event.

| Attribute | State Owner | Sync Mechanism |
|-----------|------------|----------------|
| `data-input` | `InputMethodDetector.current` | `_onInputDetected` → `setInputMethod` |
| `data-input-editing` | `KeyboardSource._inputEditing` | `onEditingChanged` → `setTextEditing` |
| `data-nav-context` | `FocusContextMachine.context` | `onContextChanged` callback → `setNavContext` |
| `data-gamepad-type` | `GamepadSource` controller detection | `setControllerType` on connect |
| `data-sidebar` | `localStorage` | Inline script in `root.html.heex` |
| `data-sidebar-hover` | Pointer position over the rail | Delegated `mouseover` listener in `root.html.heex` |

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
home:      hero → continue → recently → coming_up → sidebar
```

Sidebar and sections are always populated (static content), guaranteeing a viable terminal.

## Design Rules

- **Empty-context safety.** The navigation graph and cursor start priority together ensure the user always has a focusable target. The graph prevents directional transitions into empty contexts. The priority list handles initial placement. Any new zone layout must define both a layout in `config.js` `layouts` and an entry in `cursorStartPriority`.

## Debug Logging

All core modules use `debug()` from `core/debug.js` for structured runtime tracing. Silent by default — enable with `window.__inputDebug = true` in the browser console or via the Chrome DevTools MCP. All messages are prefixed `[input]`.

Coverage: context transitions (with caller), actions received, grid navigation state, mouse movement, gamepad axis events, sync state calls. Never use bare `console.log` in core modules — always go through `debug()`.
