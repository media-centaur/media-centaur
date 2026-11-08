# Input System Architecture

Keyboard, TV remote, mouse and gamepad navigation for the media center UI. Keyboard (and the TV app's remote, which arrives as key events) and gamepad share one source-agnostic navigation core.

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

The orchestrator receives its reader, writer, globals and input sources by injection. DOM queries live in `dom_adapter.js` and in each page behaviour's default `dom` object, which tests replace; the orchestrator calls `.focus()`/`.click()` on the elements the reader hands it.

## Module Reference

The input system is split into a reusable **framework** (`core/`) and **app-specific** code. Framework modules are parameterized by config and never import from the app layer.

### Framework (`assets/js/input/core/`)

Tests in `core/__tests__/` run via `bun test assets/js/input/core/`.

| Module | Pure? | Role |
|--------|-------|------|
| `actions.js` | Yes | Action vocabulary, key/button → action mapping, `isCursorDriving` |
| `spatial.js` | Yes | Grid index arithmetic (fast path for uniform grids) and `findNearest`, the geometric neighbour search SHELF uses |
| `nav_graph.js` | Yes | Navigation graph builder + cursor start priority (parameterized by layouts) |
| `focus_context.js` | Yes | State machine: context × action → directive (parameterized by instanceTypes, primaryMenu) |
| `input_method.js` | Yes | Tracks mouse/keyboard/gamepad transitions |
| `keyboard.js` | No | KeyboardSource — keydown listener, text input two-mode handling, key-to-action mapping |
| `gamepad.js` | No | GamepadSource — idle-until-connected rAF polling, button edge detection, analog deadzone + repeat |
| `controller_layout.js` | Yes | Maps a non-standard pad (Firefox/Linux evdev) to standard button indices, turns hat-axis D-pads into buttons, `detectControllerType` |
| `dom_adapter.js` | No | Factory functions `createDomReader(config)` / `createDomWriter(config)` (parameterized by selectors) |
| `orchestrator.js` | No | Source-agnostic action router, memory, directive execution, hint projection (parameterized by full config) |
| `scroll_glide.js` | No | The exponential-approach scroll animator (`createScrollGlide`) |
| `debug.js` | No | Toggle-gated `debug()` logger |
| `index.js` | — | Public API — re-exports the modules the app layer uses |

### App Layer (`assets/js/input/`)

Tests in `__tests__/` run via `bun test assets/js/input/__tests__/`.

| Module | Pure? | Role |
|--------|-------|------|
| `config.js` | Yes | All app-specific config: selectors, layouts, overlays, instance types, behaviors |
| `index.js` | No | LiveView hook factory — imports core + config, builds the sources (`inputSources`), exports `createInputHook()` |
| `page_behavior.js` | No | Registry mapping `data-page-behavior` → behavior factory; wraps a page's behavior in `withViewing` while the viewing layer is up |
| `library_behavior.js` | Yes* | Library: CLEAR → the filter (returns `"grid"`), sort tracking |
| `downloads_behavior.js` | Yes* | Downloads: CLEAR → the release search box, then the History search |
| `discovery_behavior.js` | Yes* | Discovery: CLEAR → the media search box |
| `watchlist_behavior.js` | Yes* | Watchlist: CLEAR → the search over the list |
| `settings_behavior.js` | Yes | Settings: `activateOnFocus: ["sections"]` |
| `guide_behavior.js` | Yes | Guide: `activateOnFocus: ["guide_chapters"]` |
| `apps_behavior.js`, `episode_mapping_behavior.js`, `profiles_behavior.js`, `review_behavior.js`, `setup_behavior.js`, `social_behavior.js`, `status_behavior.js`, `watch_history_behavior.js` | Yes | Name the page; no hooks beyond what the layout already says |
| `viewing_behavior.js` | Yes | `withViewing`: while `[data-viewing]` is on the page, keys become playback commands (see Viewing Layer) |
| `wip_notice.js` | No | `withWipNotice`: flashes `[data-wip-notice]` on every action on a page whose navigation is unfinished |
| `input_gate.js` | Yes | `gamepadInputAllowed()` — the gamepad drives the page only when it is focused, visible and not automation |
| `omnibox_clear.js` | No | Shared clear for the search boxes Downloads and Discovery declare |
| `controls_bridge.js` | No | Settings → Controls: one-shot capture of the next key or button (`controls:listen` → `controls:bind` / `controls:cancel`), and the hot swap of the sources' maps when the server pushes `controls:updated` |

`assets/js/scroll_glider.js` (outside `input/`) holds the page's one scroll glide instance.

*Pure when injected with a mock `dom`; each exports its real one.

Settings → Controls makes every entry in the Action Vocabulary table below **user-remappable**. The tables document the *defaults* shipped in `MediaCentaur.Settings.Controls.Catalog`. The runtime maps are built only from the bindings the layout embeds as `data-input-bindings` on the hook element (`index.js` maps catalog ids to actions with `actionForId`); `DEFAULT_KEY_MAP` / `DEFAULT_BUTTON_MAP` in `actions.js` are test fixtures. User overrides are persisted under `controls.keyboard` / `controls.gamepad` in `Settings.Entry`; when they change the server pushes `controls:updated`, and the hook rewrites the running sources' maps (`input:rebindMaps`). A new action needs a catalog binding, an `Action` value, an `actionForId` case, and the wiki's Keyboard-and-Gamepad page.

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
//   pause() / resume() — optional; the orchestrator calls them on visibilitychange
//     (the keyboard keeps its editing state, the gamepad re-primes its buttons)
```

**Wiring:** Sources are provided as factory functions in config. Each factory receives `(callbacks, globals)` and returns a source instance. The orchestrator calls `start()` on mount and `stop()` on destroy. The device a page is served to says which sources it starts: `inputSources(remote, { keyboard, gamepad })` in `index.js` gives a remote player's page (`<html data-player="remote">`, the TV app) the keyboard source alone, so the page holds no gamepad listener and Chromium's gamepad polling thread never runs there (`docs/tv-performance.md`); Settings → Controls offers no Pad slot on such a page, and the controls bridge gets no button capture. A phone running the same app is a touch device (`campaigns/adaptive-layout.md`): it gets the keyboard source like any remote player because the markup is shared, but nothing in the input system is built or verified for a keyboard or pad there — Android's own Back, delivered as BACK, is the one key that matters on it.

The real factories in `index.js` also pass the key/button maps, `onEditingChanged`, `acceptsInput` (the input gate) and `onControllerChanged`.

**Adding a new input source:** Create a module implementing `start()`/`stop()` that calls `onAction()` with values from the `Action` enum. Write its factory in `index.js` and include it in `inputSources`. No orchestrator changes needed.

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
| `PLAY` | p | Start/Menu (button 9) | Play the focused card (it carries `data-entity-id`) |
| `ZONE_NEXT` | ] | RB (button 5) | Next tab of the page's tab strip |
| `ZONE_PREV` | [ | LB (button 4) | Previous tab of the page's tab strip |
| `PLAY_PAUSE` | MediaPlayPause | — | During a viewing: pause/resume. Otherwise the machine treats it as `PLAY` |
| `SEEK_FORWARD` | MediaFastForward | — | During a viewing: seek +30 s |
| `SEEK_BACK` | MediaRewind | — | During a viewing: seek −30 s |
| `MENU` | ContextMenu | — | During a viewing: open/close the track menu |

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

Defines the `Action` enum and maps keyboard keys / gamepad buttons to semantic actions via `keyToAction(key, { targetIsInput }, keyMap)` (null when the target is a text input) and `buttonToAction`. `isCursorDriving(action)` names the actions that claim the cursor for the keyboard (see Input Method Detection).

### spatial.js

`gridNavigate(currentIndex, columnCount, totalCount, direction)` — returns the next index or `null` (wall). Pure arithmetic, no DOM access.

### focus_context.js — State Machine

The `FocusContextMachine` tracks which navigation context is active and returns `FocusDirective` data objects. Never touches DOM.

**Context types:** `GRID` · `TOOLBAR` · `ZONE_TABS` · `MENU` · `SHELF` · `TREE` · `MODAL`

**Instance → type mapping:** The `contextType(instance, instanceTypes)` resolver maps instance names to behavior types. Multiple instances share a type — `"sidebar"` and `"sections"` are MENUs; the home shelves, `people`, `profile_picker` and `detail_cast` are SHELFs; the feed, the watchlist rows, the detail and plan bodies, the plan board's lines and every nested menu list are TREEs. Instance names not in the map are their own type (`"grid"` → `GRID`). The map is `config.instanceTypes`. Only the literal `grid` instance navigates by grid arithmetic (`data-nav-grid` column count); any other GRID-typed instance walks linearly.

**`SHELF` is spatial; `MENU` is a list.** A `MENU`'s order is semantic — it is a list of choices that happens to be drawn vertically — so it navigates by index. A `SHELF` is a set of media tiles whose *arrangement* carries the meaning, so it navigates by geometry. The home page is a stack of shelves: hero CTAs, Continue Watching, Recently Added, and the Coming Up marquee. Most are a single row; the marquee is a mosaic (a lead tile, then columns of up to three stacked tiles, scrolling right). Both are the same thing, so there is one context type and one code path.

All four directions in a `SHELF` return a plain `navigate`; the orchestrator's `_shelfNavigate` resolves them by asking three questions in order:

1. **The layout** — `findNearest()` against the live item rects. This answers anything the arrangement makes unambiguous, and it is why the mosaic needs no adjacency table of its own (its columns change shape with every show count): RIGHT moves between columns, UP and DOWN within one.
2. **The nav graph** — nothing in that direction means we're at the shelf's edge, so try crossing into a neighbouring zone. Empty shelves are skipped by the graph's candidate fallback lists.
3. **The sequence, inline axis only** — a shelf is still an ordered set, and that order reads left to right. When the layout offers nothing and there is nowhere to cross to, "right" means the next tile: this is what carries you *rightward* from a tile in the marquee's last column to the one below it. UP and DOWN deliberately never reach here — "the next tile" in a mosaic is the one beside you, so a vertical press would move the cursor sideways (measured: DOWN on the marquee's lead tile landed on the top tile of its first column, up and to its right). In a single row the fallback only fires at the ends, where the sequence has nothing to offer either.

Keeping wall handling out of the state machine is what lets a row and a mosaic share one rule set — the machine never has to know which it is.

**Perfect alignment ties, and ties break in document order.** A candidate whose cross-axis span lies wholly inside the origin's is *perfectly* aligned and pays no alignment penalty: there is nothing to be more in line with. A tall tile facing a stack of short ones (the marquee's lead tile beside its first column) therefore ties on distance, and document order decides — so RIGHT reaches the **top** tile, which is what "the next one" means to a viewer. Scoring by centre distance instead silently picks the middle of the stack.

**Public API:**

| Method | Purpose |
|--------|---------|
| `transition(action)` | Process action in current context → directive |
| `backStep()` | What BACK would do now, as data (`region`, `sub_focus`, `dismiss`, `exit_menu`, `enter_menu`, `leave_app`, or null) — `_backTransition` acts on it and the hint bar labels B with it |
| `contextWall(context, direction)` | At a wall: follow the nav graph's edge, if any (the directive names the context left as `from`) |
| `getGraphTarget(context, direction)` | Read one graph edge |
| `setNavGraph(graph)` | Install the graph the orchestrator built from the live DOM |
| `presentationChanged(presentation, entryContext, returnTo)` | An overlay opened (`"modal"`, entering `entryContext`) or closed (returning to `returnTo`, the page context it opened over) |
| `forceContext(context)` | Set context directly (sidebar resume, cursor start, restore) |
| `beginSubFocus()` / `clearSubFocus()` | Sub-focus bookkeeping the orchestrator confirms against the DOM |
| `context`, `subFocus`, `inOverlay` | Getters |

**Config options:**

| Option | Purpose |
|--------|---------|
| `instanceTypes` | Map instance names to context behavior types |
| `primaryMenu` | Instance name with enter/exit sidebar behavior |
| `canLeave` | The shell can leave the app (the TV app; derived from `leaveApp`) |
| `initialContext` | Starting context (default: `GRID`); the orchestrator replaces it with the page's cursor start in `start()` |
| `onContextChanged` | Callback `(context) => void` — fires on every actual context change |

### dom_adapter.js

Factory functions `createDomReader(config)` and `createDomWriter(config)` produce reader/writer instances parameterized by `config.contextSelectors`, `config.activeMarkers` and `config.glider`. The orchestrator reads and writes the DOM only through them. Items that are disabled or not rendered (inside a collapsed disclosure, a closed modal) fail `checkVisibility()` and are excluded from every count and focus.

### keyboard.js

`KeyboardSource` — translates keyboard events into semantic actions. Owns keyboard-specific concerns:
- `keydown` event listener on document
- Text input two-mode handling (`_inputEditing` state)
- Key-to-action mapping via `keyToAction()`
- `event.preventDefault()` for handled keys

Implements the **input source contract**: `constructor(config)`, `start()`, `stop()`.

### gamepad.js

`GamepadSource` — translates gamepad input into semantic actions. Idle-until-connected architecture with zero CPU cost when no gamepad is plugged in.

**Lifecycle:**
- `start()` registers passive `gamepadconnected`/`gamepaddisconnected` listeners. Also checks if a gamepad is already connected (handles page reload or hook remount with controller plugged in). When an already-connected gamepad is found, `onInputDetected` is fired so the orchestrator sets the correct input method immediately — this prevents the mouse position priming from stealing focus on the first mousemove.
- On connect → adopt the pad (its type reaches the hint bar through `onControllerChanged`), start the rAF polling loop. Buttons are primed in `start()`, `resume()` and on every gated frame.
- On disconnect → if no gamepads remain, stop rAF loop and reset all state.
- `stop()` removes event listeners, stops polling, resets state.

**Button edge detection:** Compares `gamepad.buttons[i].pressed` against previous frame. Rising edge (false→true) fires the mapped action once. Navigation actions (D-pad: up/down/left/right) get **repeat timing** — after `repeatDelay` (400ms), the action repeats every `repeatInterval` (180ms) while held. Non-navigation buttons (SELECT, BACK, PLAY) fire once on press with no repeat.

**Analog stick:** Deadzone filtering (default 0.3). Each axis is processed on its own, so a diagonal past the deadzone on both axes fires both a horizontal and a vertical action. Same repeat timing as D-pad buttons — initial delay, then interval while held. Direction change resets the repeat timer. On a non-standard layout, `controller_layout.js` turns a hat-axis D-pad into D-pad button presses, which repeat on the button path.

**Button priming:** On start, if a gamepad is already connected, `_primeButtons()` reads the current button state without firing any actions. This prevents false rising edges when buttons are held during a hook remount (e.g., navigating the sidebar with D-pad causes LiveView navigation → hook destroy + mount → new GamepadSource sees held button as "just pressed").

**Input gating:** Every poll frame checks the injected `acceptsInput()` predicate. In production this is the pure policy `gamepadInputAllowed()` (`assets/js/input/input_gate.js`) evaluated against live signals: it returns true only when the surface is **focused** (`document.hasFocus()`), **visible** (`document.visibilityState === "visible"`), and **not an automation context** (`!navigator.webdriver`). When it returns false, all gamepad actions and `onInputDetected` signals are suppressed. The poll loop keeps running and re-priming button state, so input resumes the instant the surface becomes active again and a button held at that moment is not read as a fresh press. Keyboard needs no such gate: the OS only routes key events to the focused window, whereas the Gamepad API exposes global controller state regardless of which surface the user is looking at. The gate is event-independent (does not rely on `blur`/`focus` events firing) and self-healing — if an event were ever missed, the next poll frame still does the right thing.

Each signal closes a distinct hole through which an *invisible* surface could hijack a physical controller:

- **Focus** — the authoritative fix for "gamepad triggers the app while I'm playing a game on another workspace." The Page Visibility API (`document.hidden`, used by the orchestrator's `visibilitychange` pause/resume) does **not** flip on a tiling/multi-monitor WM because the window is still composited — but OS focus moves to the game, so `hasFocus()` is the reliable signal there.
- **Visibility** — a backgrounded tab or occluded window that still reports focus.
- **Automation** — a headless debug browser (e.g. `mc-debug-browser`, which launches with `--enable-automation`) reports `hasFocus:true` **and** `visibilityState:"visible"`, so focus + visibility alone do **not** catch it. `navigator.webdriver` is the deterministic marker — agent-spawned browsers set it intentionally, so this is a trustworthy signal rather than fragile UA fingerprinting. This is the fix for "pressing A launches an episode in a Chromium I can't even see," which happens when an agent leaves a headless instance loaded on the app and a real controller drives it. The E2E suite opts back in with `window.__inputAutomationDrivesGamepad = true`.

**Controller type detection:** `detectControllerType(id)` (`controller_layout.js`, re-exported by `gamepad.js`) strips the `Gamepad.id` to letters and digits and matches `xbox`/`xinput` → `"xbox"`, `playstation`/`dualshock`/`dualsense`/`sony` → `"playstation"`, else `"generic"`. Used by the hint bar to show correct button labels.

**Per-frame cost when active:** ~17 boolean comparisons + 2 float comparisons + 2 timestamp checks. No allocations — `_prevButtons` array and `_axisState` objects are pre-allocated and mutated in place. No gamepad references held across frames (read-and-discard pattern).

Implements the **input source contract**: `constructor(config)`, `start()`, `stop()`.

### orchestrator.js

Source-agnostic action router. Receives full config object including `reader`, `writer`, `globals`, `sources`, and all app-specific settings (dependency injection for testability).

**Responsibilities:**
- Lifecycle: `start(hookEl)`, `destroy()`, `onViewChanged()`
- Input source management: create, start, and stop sources from factory functions
- Action routing: source → `_onSourceAction()` → behavior hook (`onClear`) → `_handleAction()` (behavior `onAction`, then the state machine) → directive → execution
- Input method detection via source `onInputDetected` callbacks
- Nav context projection via `onContextChanged` callback → `setNavContext`
- Hint projection (`_projectHints` → `setHints`) after every action, patch and overlay transition
- Context memory (per-context index; the grid also by entity ID)
- Overlay entry and the return to the context it opened over
- Nested menus taking and releasing the cursor
- Sidebar persistence (sessionStorage bridge)
- Page behavior lifecycle (detect, create, delegate, destroy) — re-detected on every action and sync, keyed by name and by whether the viewing layer is up

**SELECT on MENU.** SELECT in a MENU is RIGHT plus a click. The primary menu (sidebar) exits to content with no click — its items are already activated on focus during up/down navigation. A non-primary menu follows its `right` edge if the layout declares one, then clicks the item it left; one without a `right` edge stays put and clicks.

**CLEAR routing.** The `CLEAR` action (Y / Backspace) is routed to the page behavior's `onClear()` hook before any other handling, in every page context. An open overlay covers the page, so CLEAR does nothing while one is open. If the behavior has no `onClear`, the action is a no-op. `onClear` may return a context name; the cursor follows into it when that context has items (Library's clear returns `"grid"`).

**The tab keys switch the page's tabs.** ZONE_NEXT / ZONE_PREV are answered before the type dispatch, like BACK: from any page context they cycle the page's `zone-tabs` strip (when it has two or more tabs); an open overlay keeps them out.

**BACK peels containment, and is answered once.** `transition()` routes BACK to `_backTransition()` *before* dispatching on context type, so the rule lives in one place instead of a `case Action.BACK` in every transition function. `backStep()` states the step as data and `_backTransition()` acts on it, so the hint bar's B label and the press cannot disagree. In order:

1. **A region** with a `back` edge in the nav graph → leave for that region. One press, however deep the cursor is inside the region (see [UIDR-019](../decisions/user-interface/2026-08-07-019-detail-modal-two-regions.md)) — stepping out one level at a time is LEFT's job. Overlay regions and page zones both use it (the library sort menu). On the return the remembered position wins over a DOM-marked active item, so Escape after opening the sort menu lands on Sort, not on the toolbar's active tab.
2. **Sub-focus** → back out to the item. Reached only in overlays with no inner regions, i.e. the flat ones.
3. **An overlay** → dismiss.
4. **The primary menu** → exit to the pre-sidebar context.
5. **Content** → enter the primary menu. The main nav contains every content region, so BACK from a grid, shelf, toolbar, tree, zone-tab strip or non-primary menu goes there, landing on the active item ([UIDR-028](../decisions/user-interface/2026-08-19-028-back-enters-main-menu.md)). The graph has a node only for a context that is on the page, so a page that renders no sidebar (the setup tour, the profile door) has no menu to enter and BACK stays a no-op there.
6. **The app** → on a shell that can leave it (the TV app, whose WebView registers `MediaCentaurTV` with `leave()`; the app layer passes it as `leaveApp`), BACK in the primary menu, and on a page without one, leaves the app instead (`leave_app`): the platform's own BACK, and Google Play's TV-DB criterion. A browser has no such shell, so steps 4 and 5 stand there.

LEFT is lateral movement within the page and never reaches the sidebar: no zone layout declares a `left: ["sidebar"]` edge. Genuine lateral edges between content zones (settings grid → sections, guide outline → chapters) are unaffected.

**Leaving a nested menu closes it.** A zone that declares `data-nav-dismiss-event` is a list the LiveView owns. Whenever the cursor leaves it — BACK along its `back` edge, or an arrow off its end — the orchestrator pushes that event, so the cursor and the list leave together. An arrow off the end of a zone onto the zone it backs onto returns to the remembered item, as BACK does (the directive's `from`).

**A nested menu takes the cursor when it opens.** When a zone with a `back` edge to the cursor's zone and a `data-nav-dismiss-event` goes from empty to populated — the trigger was pressed — the cursor enters it on its chosen option (`.glass-menu-item-active`), whichever side of the trigger it is drawn on. A trigger that is one of a row's controls leaves its sub-focus behind.

**Activate on focus.** The `primaryMenu` (sidebar) always clicks items on focus during up/down navigation, triggering page navigation. Page behaviors can declare `activateOnFocus` to add the same behavior for their own menus: Settings `["sections"]`, Guide `["guide_chapters"]`.

### page_behavior.js — Behavior Registry

Maps `data-page-behavior` attribute values to zero-argument behavior factories (a behavior that reads the DOM is built with its module's real `dom`). `createPageBehavior(name, options)` wraps the result in `withViewing` while the viewing layer is on the page, with dependencies the orchestrator supplies.

### library_behavior.js — Library Page Behavior

Extracts library-specific concerns from the orchestrator. Receives a `dom` interface (injected, never global). The library page is a single browse surface — a `toolbar` (type tabs + sort dropdown + text filter) above a poster `grid`. Tab, filter, and sort state live in the URL (managed by LiveView `handle_params`) — the input system doesn't persist these. The page declares `data-nav-default-zone="library"` so it resolves to the `library` layout (it has no zone tabs). The toolbar's Sort control is a `GlassMenu.menu_select` whose open list is the `library_sort_menu` zone, a TREE nested in the toolbar: DOWN from the toolbar enters it while it is open (`toolbar: { down: ["library_sort_menu", "grid"] }`), UP and BACK leave for the toolbar, and BACK also closes it through the list's `data-nav-dismiss-event`, landing back on Sort.

| Hook | Purpose |
|------|---------|
| `onClear()` | Clear filter input if non-empty → return `"grid"` so focus follows the unfiltered content |
| `onSyncState(reader)` | Detect sort order change → signal grid memory clear |

## Context Navigation Rules

Actions in each context:

| Action | GRID | TOOLBAR | ZONE_TABS | MENU (sidebar) | MENU (other) | SHELF | TREE | MODAL |
|--------|------|---------|-----------|----------------|--------------|-------|------|-------|
| Up | navigate | graph up | graph up | navigate | navigate | navigate (spatial) | navigate | navigate (wrap) |
| Down | navigate | graph down | graph down | navigate | navigate | navigate (spatial) | navigate | navigate (wrap) |
| Left | navigate | navigate | navigate | wall | graph left | navigate (spatial) | `tree_out` | navigate (wrap) |
| Right | navigate | navigate | navigate | exit sidebar | graph right | navigate (spatial) | `tree_in` | sub-focus / navigate |
| Select | activate | activate | activate | exit sidebar* | graph right + click | activate | activate | activate |
| Play | play | — | — | — | — | play | play | play |

Answered before the type dispatch, the same in every column:

- **Back** — `_backTransition()`, the containment order above (a region's `back` edge, sub-focus, dismiss the overlay, exit or enter the main menu, leave the app).
- **Clear** — the page behavior's `onClear()`, outside an overlay.
- **Zone±** — `zone_cycle` outside an overlay.
- **Play/Pause** (a remote's media key) — `PLAY` when no viewing layer answers it.

\* Primary menu items are already activated on focus — SELECT just exits without clicking.

"navigate" walks the list (or, for the literal `grid`, the grid arithmetic); at the end of a list the **wall** consults the nav graph in that direction for every context type, and with no edge it stays a wall.

**Modal navigation:** UP/DOWN/LEFT navigate linearly with wrapping. RIGHT tries sub-focus first (entering a sub-item within the focused element); if no `[data-nav-sub-item]` exists, falls back to linear navigation. This makes both vertical item lists and horizontal button rows work without per-modal configuration.

**Overlays with regions.** An overlay carrying `data-nav-overlay="<name>"` navigates as several zones instead of one flat list, per `config.overlays[name]`: `entry` is the cursor-start priority among its regions, `layout` its internal edges (merged over the page's graph while it is open). The detail modal declares `detail` — a `detail_actions` TOOLBAR over the body, whose zones follow the sub-view: the season/film/extras lists are a `detail_list` TREE, the Cast view a `detail_cast` SHELF (a photo grid, so adjacency is answered by geometry — the lead/other-episodes sections and the Show more button need no adjacency table), and Manage brings its own pair — `manage_tools`, a TOOLBAR for its toolbar card (a horizontal strip: Delete all, Rematch, Refresh from TMDB, Refresh artwork, the ID links — LEFT/RIGHT move along it, DOWN drops past it), over `manage_list`, a TREE for the folder ledger. `manage_list` is deliberately not a reuse of `detail_list`: per-context cursor memory is keyed by context name, so sharing it let ledger activity overwrite the episode list's remembered position. Only one sub-view's zones are in the DOM at a time; the candidate lists on the `down` edges route to whichever region is populated, and each region's `back` edge gives BACK its first rung. Every region climbs on UP at its top (UIDR-019, twice amended): the cast grid and `manage_tools` to the action row, the tree through `manage_tools` when Manage is showing and to the action row otherwise. BACK stays the one-press way out from any depth; UP is the one-row way up. The detail overlay's other regions: `detail_social` (the social capsule above the row; its zone carries the panel's dismiss event while the panel is open), `detail_finish` (the finish prompt after a finished movie — the first entry candidate while shown) and `detail_rail` (a collection's poster rail, a TOOLBAR between the row and the body, entered on its `[data-selected]` member). The plan modal declares `plan` (UIDR-029 as amended 2026-11-06; campaign `plan-modal.md`): on the board, a `plan_head` TREE (the verdict's controls, in the pinned block) over the `plan_lines` TREE — the manifest: each line an item, its controls and then its episode cells `data-nav-sub-item`s, the open picker's rows beneath their line — over the `plan_foot` TOOLBAR — the cinematic frame's foot, a band pinned at the panel's bottom edge outside the scroll, carrying the acts (Stop searching, Discard, Approve, the watchlist slot). Targeting and movie confirm put their controls in `plan_body` and Cancel + the Download split in `plan_foot`; the error stage's one Close is in `plan_body`. The regions declare no `back` edges — BACK dismisses from anywhere, as it did when the modal was one flat list; they exist so the foot can be reached, not to add depth. The one exception is `plan_menu`, the picker's Download split menu (spec 2026-09-23 follow-up): a glass list nested in `plan_foot`, present only while open, with `up` and `back` to the foot — BACK from the open list returns to the foot and, through the list's `data-nav-dismiss-event`, closes it. Because the plan modal opens on a loading stage with no controls, its entry cannot be resolved at open: while an overlay with a declared model is still outside its regions, `_syncState` re-resolves entry on every patch and steps into the first region that populates. The same `detail` overlay serves every title on every page (UIDR-043): for a title the library does not own, the action row's Download control opens a glass menu — the other planning mode, or the scope — that is a `detail_menu` TREE nested inside the row, present only while open, with `up` and `back` to the row; BACK from the open menu returns to the row and, through the list's `data-nav-dismiss-event`, closes it; the tracking card under the hero is the `detail_tracking` region (an owned title has no card: its switches are the Watchlist page's, UIDR-042 as amended 2026-11-08), and for a followed series the card's Caught up row opens a season or episode list that is a `detail_tracking_menu` TREE nested in the card, present only while open, with `up` and `back` to the card (campaign `discovery.md`, M16). The Cast view's filter input is its own region, `detail_cast_filter` (TOOLBAR), between the row and the cast grid. The pursuit window on Downloads declares `pursuit` (campaign `pursuit-window.md`, completed and removed — see git history): the coverage board `pursuit_board` (TREE: season heads, episode rows, each row's swap control a sub-item) over the release picker `pursuit_decision` (TREE) or the Activity card's controls `pursuit_actions` (TOOLBAR), over `pursuit_history` (TREE: the recent runs, the log's head and its rows, Show more); it opens on the board — every download renders one, and its first control commits nothing — and declares no `back` edges, so BACK closes the window from any region. The Review modal declares `review`: `review_choice` (the sentiments, LEFT/RIGHT) over `review_text` over `review_footer`, no `back` edges — BACK is Cancel from anywhere. The Apps add/edit modal declares `apps_modal`: `apps_controls` (TREE) over `apps_steam` (the Steam picker, a SHELF walked by geometry), entered on the picker when it shows. The Watchlist row's caught-up panel declares `caught_up` (campaign `discovery.md`, M16, amended 2026-11-08): it is not a modal to the eye — a glass panel anchored under the row's state line — but it is one to the input system, so its regions navigate as an overlay and BACK closes it and returns the cursor to the row: `caught_up_head` (TOOLBAR: the season trigger, Latest aired, Nothing yet) over `caught_up_chips` (SHELF: a season's episode chips, a wrapping grid walked by geometry, entered on the selected chip via `entryDefaults`) over `caught_up_foot` (TOOLBAR: Cancel, Set point); no `back` edges, except the open season list, `caught_up_season_menu`, a glass list nested in the head with `up` and `back` to it, which BACK closes first through its `data-nav-dismiss-event`. The viewing layer's track menu declares `viewing_menu`: an Audio and a Subtitles MENU side by side (LEFT/RIGHT between them), entered on Subtitles, no `back` edges, nested in the OSD (`data-detail-nested`). An overlay opens on its entry region's chosen item (an active marker — the playing track), else its `entryDefaults` selector, else the first item. Overlays without the attribute stay flat MODAL, which is right for a confirm or a small form.

**TREE navigation:** a vertical list whose items nest. UP/DOWN walk it as rendered; LEFT and RIGHT are *depth*. The state machine emits only `tree_in` / `tree_out` — what they mean depends on what the cursor is on, which is a DOM question the orchestrator answers:

| Cursor on | `tree_in` (RIGHT) | `tree_out` (LEFT) |
|---|---|---|
| `[aria-expanded='false']` | click it (expand) | — |
| `[aria-expanded='true']` | step into its controls | click it (collapse) |
| A row inside a `[data-nav-group]` | step into its controls | focus the group's expanded head, then click it |
| A row's controls | next control | previous control, then out to the row |

**Contexts can open somewhere other than the top.** `config.entryDefaults[context]` names a CSS selector used when a context has no remembered position — `detail_list` uses `[data-resume-target]` so the body opens on the episode Play would play, `detail_rail` uses `[data-selected]`, `detail_actions` uses the Download split's menu toggle (present only for a title the library does not own — a stray SELECT opens a menu instead of starting a download; an owned title falls back to Play), `manage_tools` uses Refresh from TMDB rather than Delete all, and `profile_picker` uses `[aria-current='true']` so a switch opens on the profile already in use (at the door none is current and it opens on the first tile).

**Wall transitions.** At the end of a list the nav graph answers, for every context type and direction: an edge the layout declares crosses, no edge stays a wall. No content context declares an edge to the sidebar — BACK is the way there. A SHELF resolves every direction itself: geometry first, then the graph, then (left/right only) the sequence — see the SHELF section above.

## Directive Reference

| Directive | Data | Executor action |
|-----------|------|-----------------|
| `navigate` | `direction` | Geometric (SHELF, `findNearest`), grid arithmetic (`grid`), linear otherwise; at a wall, the graph |
| `enter_context` | `context`, `direction`, `from`? | Cross into a context — a declared anchor; on a return (BACK, or an arrow off a region onto the zone it backs onto) the remembered item; else memory constrained to the edge crossed (SHELF) or the context's restore |
| `activate` | — | Click the focused element (or focused sub-item); records the overlay origin and a `data-nav-return-focus` target |
| `dismiss` | — | Push the active modal's `data-dismiss-event` (default `close_detail`). When the modal carries `data-detail-nested="true"`, the cursor stays in the overlay and re-enters it after the patch |
| `play` | — | Push `play` with the focused card's entity ID, flash animation |
| `zone_cycle` | `direction` | Click the next/previous tab of the page's tab strip |
| `enter_sidebar` | — | Focus the sidebar's active item (the Tooltip hook labels it on focus) |
| `exit_sidebar` | — | Restore the pre-sidebar context |
| `leave_app` | — | Call the injected `leaveApp` (the TV app's shell finishes its activity) |
| `enter_sub_focus` / `exit_sub_focus` | — | Step onto the item's first `[data-nav-sub-item]` (none: linear RIGHT) / back to the item |
| `tree_in` / `tree_out` | — | Depth in a TREE — see TREE navigation |
| `none` | — | No-op (wall) |

## DOM Contract

| Attribute | Purpose | Values |
|-----------|---------|--------|
| `data-nav-zone` | Navigation zone container | per-page names declared in `config.js` (`grid`, `toolbar`, `sidebar`, `sections`, `zone-tabs`, `hero`, `feed`, `detail_list`, …) — `config.js` is the authority, and `__tests__/config_coverage.test.js` fails on a template zone with no config |
| `data-nav-item` | Focusable element (needs `tabindex="0"`) | — |
| `data-nav-sub-item` | One of a row's controls: RIGHT steps onto it (TREE depth, MODAL sub-focus) | — |
| `data-nav-grid` | CSS grid container (column count detection, literal `grid` zone only) | — |
| `data-page-behavior` | Page behavior to activate, on the page root | `apps`, `discovery`, `downloads`, `episode-mapping`, `guide`, `library`, `profiles`, `review`, `settings`, `setup`, `social`, `status`, `watch-history`, `watchlist` (Home and Console carry none) |
| `data-nav-default-zone` | The page's layout key, on the page root — every page declares one | `home`, `library`, `settings`, `downloads`, `social`, … (a key of `config.layouts`) |
| `data-nav-transient-params` | On a page root: query params the remember script strips when saving the page's URL — overlay state and one-shot triggers, so leaving a section closes its modals | `title,entity,view,activity` (Downloads adds `selected`, `plan`, `prowlarr_search`) |
| `data-entity-id` | Stable identifier on a card: grid memory, overlay origin, PLAY's target | UUID |
| `data-sort` | Current sort order (Library): a change clears grid memory | string |
| `data-detail-mode` | An open overlay. Set by `<.modal>` (while open with `on_close`), the plan and pursuit modals, the issue view, and the viewing layer's OSD and track menu | `modal` |
| `data-detail-nested` | The overlay sits below its root view (or inside another overlay — the track menu in the OSD): BACK pushes its dismiss event and keeps the cursor in the overlay. Server-owned | `true`, `false` |
| `data-dismiss-event` | The event BACK's dismiss pushes for this overlay | event name (default `close_detail`) |
| `data-nav-overlay` | Overlay navigates as regions per `config.overlays[name]` | `detail`, `plan`, `pursuit`, `review`, `apps_modal`, `viewing_menu`, `caught_up` |
| `data-nav-dismiss-event` | On a zone container: the LiveView event pushed whenever the cursor leaves the zone — a nested menu list closes itself this way; a zone with one and a `back` edge to the cursor's zone also takes the cursor when it appears | `close_sort`, `download_menu_close`, `plan_menu_close`, `caught_up_menu_close`, `rung_menu_close`, `social_panel_close`, `viewing_menu_close` |
| `data-nav-group` | Extent of a disclosure — LEFT inside it collapses via its `[aria-expanded]` head | (bare) |
| `aria-expanded` | Disclosure state on a nav item, read directly rather than mirrored into a `data-` attribute | `true`, `false` |
| `data-resume-target`, `data-selected` | Named by `config.entryDefaults`: where `detail_list` / `detail_rail` open with no memory | (bare) |
| `data-nav-return-focus` | On a control that grows its own list (Show more): after SELECT's patch lands, the cursor returns to the item it came from | — |
| `data-nav-reveal` | The vertical reveal subject: scroll THIS ancestor into view instead of the focused item (hero: the whole backdrop; a home shelf: its section, heading included). Sideways the item still reveals itself | — |
| `data-nav-reveal-block` | Block-axis alignment for the reveal, instead of "scroll the least" | `start`, `center`, `end` |
| `data-nav-reveal-next` | On a zone container: a reveal in this zone also shows the next zone, unless that would push the focused item off screen | — |
| `data-nav-enter-scroll-top` | On a zone container: a spatial crossing into the zone glides its nearest scrollable ancestor to the top (the detail action row). BACK and post-patch restores don't move the scroll | — |
| `data-nav-escape-back` | On a text input: Escape when not editing is BACK and never clears the value — for a value the app supplied (Review's match-bar search) | — |
| `data-nav-focus-target` | Suppress focus ring on this nav item — delegate to `data-nav-focus-ring` children | — |
| `data-nav-focus-ring` | Receive delegated focus ring when ancestor `data-nav-focus-target` item is focused | — |
| `data-viewing`, `data-viewing-prompt`, `data-viewing-tracks` | The viewing layer is on the page; its prompt pill; the paused bar's "Audio & subtitles" button (outside the nav system on purpose) | — |
| `data-input-bindings` | On the hook element: the catalog bindings the sources' maps are built from | JSON |
| `data-wip-notice` | The "navigation in progress" notice `withWipNotice` flashes | — |
| `data-player` | On `<html>`: `remote` on a remote player's page (the TV app) — keyboard source only, no gamepad listener | `remote` |
| `data-nav-remember` | Sidebar link preserves its page's URL across navigation — rendered by `<.sidebar_link remember>` | — |

Projected onto `<html>` by the input system (see Single-Owner DOM Projection): `data-input`, `data-input-editing`, `data-nav-context` (the context **instance** name — `grid`, `detail_actions`, `feed`, …), `data-gamepad-type`, and the hint legend `data-hint-back` / `data-hint-clear` / `data-hint-play` / `data-hint-tabs`.

**A zone may contain a zone; an item counts once, for its nearest zone.** The adapter's item query (`queryContextItems`) keeps an item only when its nearest `[data-nav-zone]` ancestor matches the context selector's zone compound (`[data-nav-zone='X']`), or when it has none, so an outer zone's descendant selector never double-counts a menu list opened inside it. The glass menu (`GlassMenu.menu_list`) relies on this.

**One element owns the modal overlay.** The adapter resolves the *active modal* as the first `[data-detail-mode='modal']` match in DOM order, and derives everything from that one element: `data-detail-nested`, `data-dismiss-event`, and — unlike other contexts, which use flat config selectors — the MODAL context's nav items (`activeModalElement().querySelectorAll("[data-nav-item]")`). This keeps navigation and BACK pointed at the same overlay when modals stack (a confirm dialog over a detail modal, as on the Downloads page; the viewing layer's track menu over its OSD). Pages that stack modals must render the topmost overlay *first* among their `[data-detail-mode]` elements — on `/downloads`, the confirm dialogs render at the top of `:overlays`, before the plan and pursuit modals. The orchestrator remembers the active overlay's `data-nav-overlay` name: a different name while the presentation stays modal is an overlay opening over, or closing back to, another, and is entered fresh like any open (`_syncState`). While an overlay is open the cursor never seeds the page beneath; an empty overlay waits for its items (`_ensureCursorStart`).

## Page Behavior System

Page behaviors extract page-specific concerns from the global orchestrator. The orchestrator detects `data-page-behavior` on the page and delegates to the matching behavior at the right lifecycle points.

**Interface** (duck-typed, all methods optional):

```javascript
/** @typedef {Object} PageBehavior
 *  @property {string[]} [activateOnFocus] - Menu contexts that click on focus during up/down nav
 *  @property {function(): void} [onAttach]
 *  @property {function(): void} [onDetach]
 *  @property {function(string, string, Element): boolean|{transitionTo: string}} [onAction]
 *  @property {function(): (string|void)} [onClear]  - CLEAR action (Y / Backspace); may name a context to follow into
 *  @property {function(string): void} [onZoneChanged]
 *  @property {function(Object): {clearGridMemory: boolean}} [onSyncState]
 */
```

**Lifecycle:**
1. `_detectBehavior()` runs on every sync and every action — reads `data-page-behavior` (and whether `[data-viewing]` is up) from the DOM
2. If that key changed, detach the old behavior, create the new one via the registry
3. `onAttach()` called once on creation
4. `onSyncState(reader)` called every sync cycle
5. `onZoneChanged(context)` called when focus context changes
6. `onAction(action, context, focusedItem)` called at the start of `_handleAction`, before the state machine processes the action. Return `true` to consume, `{ transitionTo: "contextName" }` to transition focus, or `false`/`undefined` to pass through. Today only the decorators use it (`withViewing`, `withWipNotice`); a page's directions belong in its layout.
7. `onClear()` called on CLEAR, before `onAction` and outside an overlay — reset page state (e.g. clear filter)
8. `onDetach()` called on `destroy()` or behavior change

**Dependency injection:** A behavior that reads the DOM takes a `dom` interface at creation; its module exports the real one, which the registry passes, and tests pass a double.

## Focus Memory Model

Two operations, deliberately distinct. **Entering** a context is a user-driven
crossing (`_enterContext`); **restoring** it re-asserts focus the system already
holds after a DOM patch (`_restoreContextFocus`). Only entry obeys the anchor
and edge rules below — applying them on reconcile would drag the cursor around
on every re-render.

- **Every context** remembers its position by index; restore order: active item (DOM marker) → saved index → `entryDefaults` selector → first item.
- **The grid** also remembers by entity ID (stable across stream DOM reorders), tried first; a grid whose items carry no entity id (Settings, History, Apps) keeps its place by index.

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
comes off page by page as each is reviewed.
**A return lands where the cursor left.** BACK along a `back` edge, or an arrow off the end of a region onto the zone it backs onto (a menu list onto its trigger's zone), lands on the remembered item, ahead of a DOM-marked active item.

- **Page start:** A page opens on the first populated context of its `cursorStartPriority` (Settings on its sections menu), unless the sidebar is resumed or an overlay is already open.
- **Layout change:** Clears all position memory (the content is new)
- **Sort change:** Clears grid memory (order changed, positions meaningless)
- **Overlay open / close:** The page context the overlay opened over is recorded (a pointer click on a card names it, with the card's entity id); on close the cursor returns to it — the card by entity id, any other context by its remembered index. With no origin (a deep link), the page's cursor start.
- **Modal sub-view transition:** When BACK fires in a modal carrying `data-detail-nested="true"`, the orchestrator pushes the modal's dismiss event without dismissing focus context. The server owns that flag rather than the client comparing a view name to `"main"` — the detail modal's root view is entity-dependent (a movie with no extras has no body tab and opens on Cast, which *is* its root). Sets `_pendingModalRefocus = true`, and `_syncState` refocuses the overlay's entry region after LiveView patches the DOM. This prevents focus from falling to the grid when morphdom removes the sub-view's focused element. The viewing layer's track menu carries the flag for the same reason: nested in the OSD's overlay, its BACK pushes `viewing_menu_close` alone, and the flat dismiss path — which expects no overlay at all afterwards — never runs while the OSD stays.

**Active item detection:** `reader.getActiveItemIndex(context)` finds the first item in a context matching any selector in `config.activeMarkers` — the current page, tab or section (`.sidebar-link-active`, `.zone-tab-active`, `.menu-item-active`), a glass menu's chosen option (`.glass-menu-item-active`) and a segmented control's chosen option (`.segmented-control [aria-pressed='true']` — the only pick-one group the input system restores to its chosen option on entry; the marker is scoped to it because `aria-pressed` on other nav items also marks independent toggles — the title modal's List, a plan-grid cell — which must never be an entry target). When adding a new context with a current-selection visual, add its selector to `activeMarkers` in `config.js`.

### Post-patch focus reconciliation

Focus *position* is owned state, not a value read from the DOM on demand — the same single-owner-projection discipline the `<html>` `data-*` attributes follow (see below). A LiveView patch can move, replace, or destroy the element the user was on; the worst case is `stream(:grid, …, reset: true)`, which `LibraryLive` fires on any library mutation (e.g. a completed download) — it re-renders the whole grid and drops focus to `<body>`.

Two hooks keep focus stable across patches:

- **`onBeforeViewChange()`** (wired to the hook's `beforeUpdate()`) snapshots the focused position *before* morphdom runs, via `_saveContextMemory()` — entity ID for the grid, saved index for the rest. This covers the idle case (no navigation since landing on the item, so move-time memory would lag by one).
- **`_reconcileFocus()`** (called at the end of `_syncState`, after the nav graph is rebuilt) is the single place that answers "where should focus be now." If focus was dropped, it re-asserts the owned identity for the current context: sub-item for sub-focus, first item for a modal sub-view transition, and `_restoreContextFocus(context)` for every content/menu context (grid, shelf, menu, toolbar, zone tabs). A new content surface that loses focus on a patch is covered without adding another bespoke guard.

Overlay entry and the return to the origin on close are transition-driven (handled in the presentation block of `_syncState`); a nested menu that just opened takes the cursor there too (`_enterOpenedMenu`); empty contexts are left to `_ensureCursorStart`.

**Reconcile only the focus the system owns ([ADR-053](../decisions/architecture/2026-06-06-053-focus-ownership-boundary.md)).** `getCurrentFocusedItem() === null` is ambiguous: it means *either* a patch dropped focus to `<body>` (the system owns this — restore) *or* focus moved to an element outside every managed nav region (the system does not own this — cede). Both `_reconcileFocus` and `_ensureCursorStart` guard on `reader.hasForeignFocus()` and return early when focus is foreign — a live element outside `[data-nav-item]`/`[data-nav-zone]`. This is what keeps an *unmanaged* overlay (a plain `data-state` modal like the Track-new-release dialog, invisible to the input system) usable while the page behind it re-renders: without the guard, every patch re-asserts the page context's focus and yanks the cursor out of the overlay. A managed filter input inside a nav zone is *not* foreign — it still navigates by arrow keys (see Text Input Handling).

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

**Reveal the right subject.** Vertically, `revealItem` scrolls the nearest
`[data-nav-reveal]` ancestor when there is one, else the item itself.
Sideways, the item always reveals itself, so a row scrolls to the focused card
whatever the vertical subject is. The home hero uses it: its CTAs sit low in a
full-bleed backdrop, so revealing a button alone parks it at the viewport's
bottom edge with the title and artwork stranded above. This replaced a page
behavior that scrolled the window separately and raced the reveal for the same
scroll box. Each home shelf declares its section, so the reveal shows the
heading with the row; a `scroll-margin-top` sized to the heading used to stand
in for it.

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
focused item off the opposite edge — possible at large UI scales, where the
subject can outgrow the viewport — the reveal falls back to a minimal one,
because keeping the item on screen beats framing it.

**Show the next zone when the layout looks ahead.** A home shelf rests with
the shelf below it in view. A zone declaring `data-nav-reveal-next` puts the
next zone's subject (its first item, or that item's `[data-nav-reveal]`
ancestor) aligned to the scrollport end first among the vertical
destinations. The next zone's own row is rewound, so only the focused item's
scrollers glide. This replaced a fixed
`scroll-margin-bottom` reserve sized to the tallest shelf, the Coming Up
marquee: with a shorter shelf below, Continue Watching overshot, and the last
shelf, reserving nothing, then pulled the page back up. Measuring the next
zone gives every shelf the same resting position as the shelf below it when
that shelf is last.

**One ordered list of vertical destinations.** The next zone, then the
declared alignment, then the least scrolling: each is tried in turn from the
same sideways offsets, and the first that keeps the focused item whole on
screen wins; the last is kept regardless. A new vertical preference joins the
list rather than adding its own try-check-undo.

**The first line reveals the scroller's start.** `"nearest"` aligns the
first row's leading edge to the scrollport's, which hides whatever stands
above it — the library's title and toolbar — by exactly their own height, so
UP onto the first row never brought the page back to its top. An item on the
first line of its zone (it overlaps the zone's first item along the axis: the
first row of a grid or tree, the first tile of a row, every control of a
toolbar whose controls differ in height) offers the scroller's
start as the destination instead, on each axis the box scrolls, and it is
kept only when the start shows the item whole — the same test the declared
alignment passes (`withinScrollport`), measured the same way (jump, read,
rewind). A declared alignment keeps precedence. A single-line zone is its
own first line, so a shelf in the first screenful reveals the page head with
it; the home shelves declare `"end"` and are unaffected. The library toolbar
relies on this rule alone: it used to declare `start` plus a
`scroll-margin-top: 100vh` the browser clamped to the page top, a second
mechanism for the same resting position. A toolbar wrapped onto two lines
gets the least scrolling on its second line.

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

**One glider.** The page creates one scroll glide instance
(`assets/js/scroll_glider.js`) and hands it to the DOM writer through
`inputConfig.glider` — the writer requires it and builds none of its own; the
`ScrollRow` hook glides a track on an edge-arrow press with the same instance.
So the wheel rule above cancels an arrow glide like any other, and a cursor key
pressed mid-glide retargets the track instead of racing a second animation. A
new scroller that animates its scroll imports that instance; it never creates
its own. The glide's speed is a fraction of the distance remaining, with a
floor of one pixel a frame: a smaller write the browser rounds away, and
without the floor the last few pixels crawled in half-steps and then jumped
into place (measured on the TV, 2026-10-27). The glide also knows when a step
cannot land: under the root zoom a device pixel can be larger than a CSS
pixel, and a write that rounds back to the same offset twice running ends the
glide at the target instead of ticking forever.

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

1. **Focused, not editing:** Arrow keys still navigate. Enter → edit mode, except on an `<input>` inside a `form[phx-submit]`, where Enter submits the form. Printable chars → edit mode + pass through. Backspace / Delete on a non-empty input → edit mode + native delete. Backspace on an empty input → CLEAR (page-level clear filter). Escape on a non-empty input → clears the value; Escape on an empty input falls through to BACK. An input declaring `data-nav-escape-back` is never cleared by Escape — its value is the app's suggestion, not a filter the person typed (Review's match bar pre-fills its search from the ticked rows) — so Escape is BACK at once.
2. **Editing:** All keys pass through. Enter → exit edit mode (value preserved; inside a `form[phx-submit]` the submit still runs). Escape → exit edit mode (value preserved). A second Escape (now in Mode 1) clears the value.

A `<textarea>` composes rather than filters, so three rules differ: Enter on the focused box always enters edit mode (a textarea never submits the form it sits in, so the `form[phx-submit]` exception is an input's); Enter while editing stays in edit mode and reaches the box as a newline; Escape when not editing never clears the words — it is BACK, which on the Review modal is Cancel. The first tenant is the Review modal's text box. Inside an open overlay, every key a text input consumes stops at the input system (a window Escape binding beneath — the detail's — never sees it); outside one the page's window bindings keep their reach (Settings' Escape cancels an edit from its fields).

When focus is not on a text input, every mapped key is `stopPropagation`'d, so a `phx-window-keydown` binding never sees it too.

The mode is surfaced to CSS via `data-input-editing` on `<html>`. `KeyboardSource` owns the state and projects it through the `onEditingChanged` callback wired in `index.js` to `writer.setTextEditing()`. Focused inputs show a brighter ring in edit mode so users can see at a glance whether arrow keys will navigate or type.

## Viewing Layer

While a viewing is on the page (`[data-viewing]`: in-browser play in place, UIDR-027, and a remote player's OSD), `page_behavior.js` wraps the page's behavior in `withViewing` (`viewing_behavior.js`), and keys become playback commands pushed as `viewing_command`:

- LEFT/RIGHT seek ∓10 s, UP/DOWN seek ±60 s; the remote's media keys seek ±30 s (SEEK_FORWARD/SEEK_BACK) and toggle pause (PLAY_PAUSE, PLAY)
- SELECT acts on the prompt pill when one shows (`viewing_prompt`), otherwise toggles pause
- MENU opens and closes the track menu (`viewing_menu`, a regioned overlay nested in the OSD)
- Paused, DOWN focuses the bar's "Audio & subtitles" button (`data-viewing-tracks`, deliberately not a nav item), SELECT on it opens the track menu, UP leaves it
- BACK passes through to containment: the track menu closes (nested), then the OSD's dismiss event stops the viewing

The OSD is an overlay (`data-detail-mode="modal"`), so the page's CLEAR and tab keys never reach the page beneath it. The hint bar is hidden while the layer is up.

## Remote Players (the TV app)

The TV app's WebView marks the page `<html data-player="remote">`. `inputSources` then starts the keyboard source alone — the remote's keys arrive as key events, and no gamepad listener means Chromium's gamepad polling thread never runs there (`docs/tv-performance.md`); Settings → Controls offers no Pad slot. The shell registers `MediaCentaurTV.leave()`, passed to the orchestrator as `leaveApp`: BACK with nothing left to peel (the main menu, or a page without one) leaves the app.

## Sidebar Persistence

SessionStorage bridge for resuming sidebar context across LiveView navigations:

- `destroy()`: if in sidebar context → save `inputSystem:resumeSidebar = true`
- `start()`: if flag set → remove flag, force sidebar context, focus active item

## Input Method Persistence

SessionStorage bridge for preserving the active input method (mouse/keyboard/gamepad) across LiveView navigations:

- `destroy()`: save `inputSystem:inputMethod = <current method>`
- `start()`: if saved → remove key, create `InputMethodDetector` with saved value, write `data-input` immediately

Without this, navigating between pages (each a separate LiveView) would reset the input method to keyboard (the detector's start, and the static `data-input="keyboard"` in `root.html.heex`) and lose a gamepad or mouse mode. Combined with the hint bar living in `root.html.heex` (outside the LiveView boundary), this ensures zero flicker when using a gamepad across page transitions.

## URL Persistence for Sidebar Navigation

The `data-nav-remember` attribute on sidebar links preserves query params across page navigation. Implemented in `root.html.heex` via a capture-phase click handler:

1. **On any nav item click:** Saves `sessionStorage["nav:" + currentPath]` → `currentPath + queryString`, minus the page root's `data-nav-transient-params`
2. **On clicks to links with `data-nav-remember`:** Looks up `sessionStorage["nav:" + targetPath]` and rewrites the `href` before navigation
3. **`phx:nav-remember`:** the server can point another page's sidebar entry at a URL

This means pages that use query params for state (like `/settings?section=logging` or `/library?zone=library&type=movie`) automatically resume at the last-visited section when the user navigates back via the sidebar.

**To opt in:** Pass `remember` to `<.sidebar_link>` in `layouts.ex`. The page must use query params (via `live_patch` / `handle_params`) for any state it wants to persist.

## Gamepad Hint Bar

A button legend fixed at the bottom center of the viewport, shown only in gamepad mode (`[data-input=gamepad]` on `<html>`) and hidden while the viewing layer is up.

**It states what each button does now, derived from the state the press is answered from.** The orchestrator's `_projectHints()` runs after every action, every patch and every overlay transition and writes one legend through `writer.setHints()`:

| `<html>` attribute | Value | Shows |
|---|---|---|
| `data-hint-back` | `focusMachine.backStep()` — absent when BACK does nothing | **B** labelled Back (`region`, `sub_focus`, `exit_menu`), Close (`dismiss`), Menu (`enter_menu`), Exit (`leave_app`) |
| `data-hint-clear` | present when the page behavior has `onClear` and no overlay is open | **Y** Clear |
| `data-hint-play` | present when the focused item carries `data-entity-id` | **Start** Play |
| `data-hint-tabs` | present when the page's tab strip has two or more tabs and no overlay is open | **LB/RB** Tabs |

D-pad Navigate and A Select always show. The bar never lists contexts, so a new zone needs nothing here.

**Always in DOM.** Follows the backdrop-filter rule — never conditionally rendered with `:if`; entries show and hide by CSS over the attributes above.

**Controller-aware labels.** Button labels use `::before` pseudo-elements driven by `[data-gamepad-type]` on `<html>`. Xbox labels show by default (and for generic controllers); PlayStation shows ✕ ○ △ □ and L1/R1. `GamepadSource` reports the adopted pad through `onControllerChanged`, wired to `writer.setControllerType()`.

**Markup:** Lives in `root.html.heex`, outside the LiveView boundary, so it persists across page navigations.

## CSS Integration

- `[data-input=keyboard]` / `[data-input=gamepad]` — focus ring visibility
- `[data-input=mouse]` — hides focus outlines
- `nav-play-flash` — green ring animation (300ms) on play action
- `.gamepad-hint-bar` — fixed bottom-center, translucent dark pill with a 12px backdrop blur, fade+translateY entrance

## Input Method Detection

Three methods: `mouse`, `keyboard`, `gamepad`. The `InputMethodDetector` (pure state machine) tracks the current method; the orchestrator writes it to `data-input` on `<html>`.

**The method is cursor authority, not "last device touched."** Mouse and keyboard are companions: a pointer user clicks into a modal and hits Escape to back out, or types into a field they clicked, without ceding the pointer's ownership of focus and scroll. So only **cursor-driving** keys switch to keyboard mode — arrows, Enter-as-SELECT, and the zone brackets (`isCursorDriving` in `actions.js`). Command keys (Escape, Backspace, `p`), typing into text inputs and unmapped keys still perform their action but leave the method alone. Because BACK and CLEAR can now execute *in* mouse mode, every focus write their execution performs routes through `_restoreOpts()` — the viewport the pointer owns never moves. The gamepad is asymmetric on purpose: everything on a controller is navigation, so every button and axis switches to gamepad mode. New keys default to not switching.

**Mouse detection uses position tracking, not event counting.** Layout shifts from LiveView patches fire synthetic `mousemove` events at the same coordinates (the OS controls cursor position, not the page). The orchestrator only switches to mouse when `clientX`/`clientY` actually change (≥1px delta). The first `mousemove` after a fresh orchestrator primes the baseline position without switching — this prevents false switches during full-page navigations where the initial position is unknown.

**Gamepad presence signaling.** When `GamepadSource.start()` detects an already-connected gamepad (e.g., after a hook remount from sidebar navigation), it fires `onInputDetected("gamepadbutton")` so the orchestrator immediately sets gamepad mode. Without this, the input method would default to mouse until the user presses a button.

## Single-Owner DOM Projection

Each `data-*` attribute on `<html>` is a **projection** of exactly one piece of internal state, synced by a direct callback from the state owner — never piggybacked on an unrelated event.

| Attribute | State Owner | Sync Mechanism |
|-----------|------------|----------------|
| `data-input` | `InputMethodDetector.current` | `_onInputDetected` → `setInputMethod` |
| `data-input-editing` | `KeyboardSource._inputEditing` | `onEditingChanged` → `setTextEditing` |
| `data-nav-context` | `FocusContextMachine.context` | `onContextChanged` callback → `setNavContext` |
| `data-gamepad-type` | `GamepadSource` controller detection | `onControllerChanged` → `setControllerType` |
| `data-hint-back`, `data-hint-clear`, `data-hint-play`, `data-hint-tabs` | The orchestrator's legend (`backStep()`, the behavior's clear, the focused card, the tab strip) | `_projectHints` → `setHints` |

**Design rules:**

1. **Single-owner projection** — each DOM attribute has one state owner and one sync path.
2. **Framework notifies, app reacts** — state machines expose change callbacks; app wiring connects them to DOM writes.
3. **Coincidental coupling is a bug** — if two events "always happen together" during normal use, they will diverge in edge cases (startup, teardown, testing).

## Adding a New Page

### Page behavior (optional)

1. Create `assets/js/input/<name>_behavior.js` exporting a `create<Name>Behavior()` factory; one that reads the DOM takes a `dom` parameter and exports its real one
2. Return an object implementing the `PageBehavior` interface (all hooks optional — most pages need none)
3. Register it in `page_behavior.js`'s `BEHAVIOR_REGISTRY` as a zero-argument closure; while a page's navigation is unfinished, wrap it in `withWipNotice`
4. Add `data-page-behavior="<name>"` to the LiveView template's root element
5. Write tests in `assets/js/input/__tests__/<name>_behavior.test.js` with a mock `dom`
6. Keep page state in the URL (LiveView `handle_params`) — don't duplicate in sessionStorage

### Navigation zone layout (required for keyboard nav)

All app-specific config lives in `config.js`:

1. Add the page's layout under `layouts` (directional edges between its zones, plus its `sidebar` node with `right` candidates) and its `cursorStartPriority`
2. For each zone that is not an existing instance: an `instanceTypes` entry, a `contextSelectors` entry, and — only if it is static content always on the page — `alwaysPopulated`
3. Put `data-nav-default-zone="<layout key>"` on the page root (every page declares it), and `data-nav-transient-params` for any URL-driven overlay
4. Every interactive control is a `data-nav-item tabindex="0"` inside a zone the layout connects, or a `[data-nav-sub-item]` of a row in a TREE.
5. A nested menu list is its own TREE zone with `up` and `back` edges to its trigger's zone and a `data-nav-dismiss-event`; it then takes the cursor on open and closes when the cursor leaves
6. For sidebar URL persistence, pass `remember` to `<.sidebar_link>` in `layouts.ex`
7. Run `bun test assets/js/input/` — `__tests__/config_coverage.test.js` fails when a template's zone, default zone or page behavior has no config — and walk the page with `mc-nav-trace`. The hint bar needs nothing: it is derived from state

## Navigation Graph

Cross-context transitions (e.g., DOWN from toolbar → grid) are driven by a **navigation graph** — an adjacency map rebuilt from DOM state whenever the page updates. The graph is defined in `nav_graph.js` and consumed by the state machine.

Two mechanisms handle empty contexts:

### Candidate fallback lists (arrow key transitions)

Each edge in the static layout is an ordered array of candidate targets. The graph builder picks the first populated candidate. This makes fallback behavior explicit — no implicit directional chaining.

A node exists only for a context on the page (its count, or `alwaysPopulated`): that is how BACK knows whether the page has a main menu.

Example: library, sidebar `right` has candidates `["grid", "toolbar"]`. If the grid is empty, it falls through to the toolbar. Toolbar `down` has `["library_sort_menu", "grid"]` — the sort menu is in the DOM only while open, so DOWN normally falls through to the grid; if both are empty, DOWN from toolbar is blocked (no fallback makes spatial sense).

### Cursor start priority (page entry)

A per-layout priority list determines where a page opens, and where the cursor goes when its context empties or an overlay with no origin closes. Walked in order; first populated context wins. Independent of the graph — no directional logic.

```
library:   grid → toolbar → sidebar
settings:  sections → grid → bindings → sidebar
home:      hero → continue → recently → coming_up → sidebar
setup:     grid                       (no sidebar on the tour)
profiles:  profile_picker → sidebar   (no sidebar at the door)
```

`sections` and `guide_chapters` are always populated (static content); the sidebar is counted, because the setup tour and the profile door render none.

`bindings` is the Controls section's binding table: a TREE zone nested in the settings grid, in the DOM only on that section. Each row (`Components.Settings.BindingRow`) is the item and its two keycaps and two Unbind buttons are its `[data-nav-sub-item]` controls, so UP/DOWN walk rows, RIGHT steps into a row and LEFT back out. The grid's `down` edge enters it and its `up` edge returns; on every other section the candidate is empty and DOWN off the grid stays a wall. The kit's other rows (stepper, choice, list) keep the flat walk — each of their controls is its own item — because each control has its own SELECT and the rows are few; the binding table is ten homogeneous rows with four controls each, the shape the detail modal's episode list already navigates as a tree.

## Design Rules

- **Empty-context safety.** The navigation graph and cursor start priority together ensure the user always has a focusable target. The graph prevents directional transitions into empty contexts. The priority list handles initial placement. Any new zone layout must define both a layout in `config.js` `layouts` and an entry in `cursorStartPriority`.

## Debug Logging

`focus_context.js`, `gamepad.js` and `orchestrator.js` use `debug()` from `core/debug.js` for structured runtime tracing. Silent by default — enable with `window.__inputDebug = true` (`mc-nav-trace --debug` does it and prints the `[input]` lines; `chromium-probe --with-console` returns them). All messages are prefixed `[input]`.

Coverage: context transitions (with caller), actions received, grid navigation state, mouse movement, gamepad axis events, sync state calls. Never use bare `console.log` in core modules — always go through `debug()`.
