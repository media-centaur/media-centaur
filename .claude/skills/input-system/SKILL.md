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

`_shelfTransition()` returns a plain `navigate` for all four directions and the orchestrator's `_shelfNavigate()` resolves them by asking, in order: **the layout** (`findNearest()` on live rects), **the nav graph** (cross into a neighbouring zone; empty shelves are skipped by the candidate fallback lists), then **the sequence** (left/right only — reading order, which is what carries you rightward from the marquee's top secondary to the one below it). UP and DOWN never fall through to the sequence: "the next tile" in a mosaic sits beside you, so a vertical press would move sideways. Keeping walls out of the state machine is what lets a row and a mosaic share one rule set.

SELECT activates the focused card; BACK is a no-op.

**Don't add an adjacency table for a new mosaic** — geometry already handles it, and a table goes stale the moment the layout renders a different number of tiles.

### Entry Rules and Scroll Reveal

Two things that bite when adding a page:

- **Entering a context ≠ restoring it.** `_enterContext(context, direction)` handles user-driven crossings and honours a declared `config.entryAnchors` index (the hero always enters at Play) and then memory *constrained to the edge you crossed*. `_restoreContextFocus()` re-asserts focus after a DOM patch and obeys neither — applying entry rules on reconcile drags the cursor on every re-render. The edge constraint is currently gated to SHELF; the gate comes off page by page.
- **`revealItem()` in `dom_adapter.js` is the single owner of "make it visible."** The input system owns the scroll outright — destination *and* motion. Never put `scroll-snap-type` on a nav-driven container (it overrides `scrollIntoView` and clips the focused card) and never put `scroll-behavior` on one either (it hijacks the glide's per-frame `scrollLeft` writes). Motion lives in `scroll_glide.js`, which chases a moving target instead of restarting an easing curve — both browser smooth-scroll routes collapse under held input. Use `data-nav-reveal` on an ancestor when the item is not the thing worth showing; don't add a page behavior that scrolls the window separately.
- **The wheel takes scroll authority.** A wheel event is the pointer claiming the scroll: the orchestrator cancels every glide where it stands (`writer.cancelScrollMotion()`) and switches to mouse mode. While the method is mouse, restores the user didn't ask for (post-patch reconciles, cursor-start seeding) pass `{ reveal: false }` to the writer's focus calls — focus survives the patch, the viewport never moves. The next cursor-driving keypress (arrows, Enter, zone brackets — `isCursorDriving` in `actions.js`) flips the method back before its action runs, so cursor navigation reveals as before; command keys (Escape, Backspace, `p`) and typing act without flipping, and BACK/CLEAR focus writes route through `_restoreOpts()` since they can run in mouse mode. Never add a reveal that can fire in mouse mode without routing through `_restoreOpts()`.
- **The navigation owns mount-time scroll.** During `start()` the window still carries the previous page's offset; LiveView writes the navigation's own scroll (reset on redirect, restore on back/forward) one frame later. A reveal measured then chases a stale absolute target *after* that write — home's scroll used to leak onto the next page this way. So `start()` runs with `_mounting` set and every mount-time focus write passes `{ reveal: false }` regardless of input method; the first user action reveals as always. Never add a focus call to the mount path that bypasses `_restoreOpts()`.

Verify both with `~/scripts/agents/mc-nav-trace '<keys>'`, which reports the focused context/zone/index per step plus how many px of the focused card fall outside its scrollport. Any non-zero settled clip is a bug.

### TREE Behavior (nesting vertical list)

`_treeTransition()` handles the detail modal's body — a vertical list whose items nest (seasons contain episodes; an episode contains its own controls). UP/DOWN walk it as rendered. LEFT and RIGHT are **depth**, not lateral movement, and the machine emits only `tree_in` / `tree_out` because what they mean depends on what the cursor is on: RIGHT expands a collapsed `[aria-expanded]` head, else steps along the item's `[data-nav-sub-item]` controls; LEFT walks back out of those, then collapses the enclosing `[data-nav-group]`'s expanded head, landing on it. Read `aria-expanded` — never mirror disclosure state into a parallel `data-` attribute.

### Overlays With Regions

An overlay carrying `data-nav-overlay="<name>"` navigates as several zones per `config.overlays[name]` (`entry` = cursor-start priority among its regions, `layout` = its internal edges, merged over the page graph while open). The detail modal declares `detail`: a `detail_actions` TOOLBAR over a per-sub-view body — a `detail_list` TREE for the season/film/extras lists, a `detail_cast` SHELF (geometry-resolved photo grid) for Cast, and for Manage its own pair: `manage_tools` (TOOLBAR card — LEFT/RIGHT along it, DOWN drops past) over `manage_list` (TREE ledger). `manage_list` is deliberately not `detail_list` — cursor memory is keyed by context name, and sharing it let ledger activity clobber the episode list's remembered position. One sub-view's zones in the DOM at a time; the `down` candidate lists route to whichever is populated. Every region climbs on UP at its top (UIDR-019, twice amended): cast grid and `manage_tools` to the actions row, the tree through `manage_tools` when Manage is showing, else to the actions row. The orchestrator consults the graph at a TREE's up/down wall the same way it does for MENU. Overlays without the attribute stay flat MODAL — right for confirms and small forms. See [UIDR-019](../../../decisions/user-interface/2026-08-07-019-detail-modal-two-regions.md).

### BACK and CLEAR Semantics

BACK is answered by `_backTransition()` **before** the context-type dispatch — one function, not a `case Action.BACK` in each. It peels containment in order: an overlay region with a nav-graph `back` edge leaves for that region (one press, however deep — stepping out a level at a time is LEFT's job) → sub-focus exits → an overlay dismisses → the primary menu exits to the pre-sidebar context → content does nothing. In content contexts (grid, toolbar, zone_tabs, shelf) and non-primary menus (sections, the download zones) BACK is therefore a **no-op** — reaching the main nav is LEFT's job. Every zone layout gives its left-edge context a `left: ["sidebar"]` edge (or a chain that reaches it), so left-at-the-left-edge is the one idiom for getting to the sidebar. There is no `onEscape` behavior hook.

Adding a BACK case to a transition function is a smell: express it as containment instead.

CLEAR delegates to page behavior `onClear()` in any context. Library implements it (clears the filter, follows focus into the grid); download implements it (clears the omnibox query, falling through to the history search). If no `onClear` exists, the action is silently dropped.

### Page Behaviors

Page-specific concerns extracted from the orchestrator. Detected via `data-page-behavior` attribute. Duck-typed interface: `activateOnFocus`, `onAttach`, `onDetach`, `onAction`, `onClear`, `onSyncState`, `onZoneChanged` — all optional. The `activateOnFocus` property is a string array of menu context names that should click items on focus during up/down nav (page-scoped — the primaryMenu always activates globally).

Pages with clearable state (filters, search) should implement `onClear()`. There is no escape hook — BACK semantics live entirely in the state machine.

### URL Persistence (data-nav-remember)

Sidebar links with `data-nav-remember` preserve the target page's query params across navigation. Implemented in `root.html.heex`. Pages must use query params + `handle_params` for this to work.

Pages declare modal/overlay params (and one-shot triggers) in `data-nav-transient-params` on their root element — the remember script strips those before saving, so leaving a section closes its modals rather than re-opening them on return. A page that adds a URL-driven modal must add its param to that list.

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
| `data-nav-transient-params` | On a page root: params stripped from the remembered URL (modal state, one-shot triggers) |
| `data-entity-id` | Stable entity identifier on cards |
| `data-detail-mode` | Presentation shell type (`modal`, `drawer`) |
| `data-detail-nested` | Modal is below its root view (`true`/`false`) — read by orchestrator for layered BACK. Server-owned: the root view is entity-dependent |
| `data-captures-keys` | Element handles own keyboard events |
| `data-nav-defer-activate` | Skip activate-on-focus — only activate on explicit SELECT |
| `data-nav-action` | Custom event name dispatched on SELECT instead of `.click()` |
| `data-nav-return-focus` | On a control that grows its own list (Show more): after SELECT's patch lands, the cursor returns to the item it came from |
| `data-nav-reveal` | Scroll THIS ancestor into view instead of the focused item — required when a surface's items differ in height, or each frames itself |
| `data-nav-reveal-block` | Block-axis alignment for the reveal (`start`/`center`/`end`), so a surface rests in one place whichever way it was approached |
| `data-nav-enter-scroll-top` | On a zone container: spatially crossing into the zone glides its nearest scrollable ancestor to the top — for pinned zones where reveal is a no-op (detail action row). BACK/restores don't move the scroll |
| `data-nav-focus-target` | Suppress focus ring on this nav item — delegate to `data-nav-focus-ring` children |
| `data-nav-focus-ring` | Receive delegated focus ring when ancestor `data-nav-focus-target` item is focused |
| `data-nav-overlay` | Overlay navigates as regions per `config.overlays[name]` (`detail`) |
| `data-nav-group` | Extent of a disclosure — LEFT inside it collapses via its `[aria-expanded]` head |
| `aria-expanded` | Disclosure state on a nav item, read directly by TREE navigation |
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
- **Modal sub-views use deferred refocus.** When a modal is below its root view, `_executeDismiss` reads `data-detail-nested` via `reader.isDetailNested()` and pushes `close_detail` without changing focus context, setting `_pendingModalRefocus = true`. Never re-derive "am I nested" on the client by comparing the view name to `"main"` — which view is root depends on the entity. `_syncState` (which fires after the LiveView DOM patch) checks this flag and calls `focusFirst(MODAL)`. Never use `requestAnimationFrame` for post-patch focus — the LiveView round-trip takes longer than a single frame.
- **Dependency directionality.** Core never imports from app layer. App imports from `core/index.js`.
