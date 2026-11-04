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
- **`activeMarkers`** — selectors marking a context's current selection (active page/tab/section classes, a segmented control's chosen option)
- **`primaryMenu`** — the menu instance with enter/exit behavior (e.g., "sidebar")
- **`overlays`** — region overlays (`detail`, `plan`, `viewing_menu`): `entry` priority and internal `layout`
- **`entryDefaults`** — selector a context opens on with no memory (`detail_list: [data-resume-target]`, `detail_rail: [data-selected]`)
- **`entryAnchors`** — fixed entry index (`hero: 0`)
- **`glider`** — the page's one scroll animator (`assets/js/scroll_glider.js`)
- **`createBehavior`** — factory function for page behaviors

### Context Types vs Instance Names

The `Context` enum defines behavior types (`GRID`, `MENU`, `TOOLBAR`, etc.). The `_context` field stores instance names (`"grid"`, `"sidebar"`, `"sections"`). The `contextType(instance, instanceTypes)` resolver maps instance names to behavior types.

This lets multiple instances share behavior (sidebar and sections both use MENU navigation rules) while having distinct DOM selectors and nav graph entries. `data-nav-context` on `<html>` carries the instance name. Only the literal `grid` instance uses grid arithmetic (`data-nav-grid`); other GRID-typed instances walk linearly.

### Navigation Graph

Cross-context transitions are driven by an adjacency map in `core/nav_graph.js`. Each layout defines edges between contexts with ordered fallback candidates. The graph is rebuilt from DOM state on every sync and has a node only for a context on the page (its count, or `alwaysPopulated`). **At any wall — every context type, every direction — the graph answers**: a declared edge crosses, no edge stays a wall. The page's layout key is its root's `data-nav-default-zone`; a page opens on the first populated context of its `cursorStartPriority`.

### Input Sources

Keyboard and gamepad are decoupled peers behind a duck-typed contract: `start()`, `stop()`, optional `pause()`/`resume()`, and the `onAction(action)` / `onInputDetected(type)` callbacks they receive in their config. The orchestrator is source-agnostic. `inputSources()` in `index.js` builds them; a remote player's page (`<html data-player="remote">`, the TV app) gets the keyboard source alone. Key and button maps come only from the catalog bindings the layout embeds (`data-input-bindings`); `DEFAULT_KEY_MAP`/`DEFAULT_BUTTON_MAP` are test fixtures.

### MENU Behavior

The `_menuTransition()` handles all MENU instances. The primaryMenu gets special treatment (exit_sidebar on right/back, wall on left). Non-primary MENU instances use the nav graph for left/right transitions; BACK enters the sidebar there, like any content context. SELECT on a MENU is RIGHT plus a click: the primary menu exits to content without clicking (its items activate on focus); a non-primary menu follows its `right` edge if it has one, then clicks the item.

### SHELF Behavior (spatial, unlike MENU)

SHELF covers tiles laid out in space: the home shelves (`hero`, `continue`, `recently`, `coming_up`), Discovery's shelves, `people`, `profile_picker`, `detail_cast` and `plan_grid`. A MENU's order is semantic, so it navigates by index; a SHELF's *arrangement* carries the meaning, so it navigates by geometry. Most shelves are a single row; the Coming Up marquee is a mosaic (one large tile beside a stacked column) — same context type, same code path.

`_shelfTransition()` returns a plain `navigate` for all four directions and the orchestrator's `_shelfNavigate()` resolves them by asking, in order: **the layout** (`findNearest()` on live rects), **the nav graph** (cross into a neighbouring zone; empty shelves are skipped by the candidate fallback lists), then **the sequence** (left/right only — reading order, which is what carries you rightward from the marquee's top secondary to the one below it). UP and DOWN never fall through to the sequence: "the next tile" in a mosaic sits beside you, so a vertical press would move sideways. Keeping walls out of the state machine is what lets a row and a mosaic share one rule set.

SELECT activates the focused card, PLAY plays it; BACK enters the main menu (containment, below).

**Don't add an adjacency table for a new mosaic** — geometry already handles it, and a table goes stale the moment the layout renders a different number of tiles.

### Entry Rules and Scroll Reveal

Two things that bite when adding a page:

- **Entering a context ≠ restoring it.** `_enterContext(context, direction)` handles user-driven crossings and honours a declared `config.entryAnchors` index (the hero always enters at Play) and then memory *constrained to the edge you crossed*. `_restoreContextFocus()` re-asserts focus after a DOM patch and obeys neither — applying entry rules on reconcile drags the cursor on every re-render. The edge constraint is currently gated to SHELF; the gate comes off page by page.
- **`revealItem()` in `dom_adapter.js` is the single owner of "make it visible."** The input system owns the scroll outright — destination *and* motion. Never put `scroll-snap-type` on a nav-driven container (it overrides `scrollIntoView` and clips the focused card) and never put `scroll-behavior` on one either (it hijacks the glide's per-frame `scrollLeft` writes). Motion lives in `scroll_glide.js`, which chases a moving target instead of restarting an easing curve — both browser smooth-scroll routes collapse under held input. Use `data-nav-reveal` on an ancestor when the item is not the thing worth showing vertically (sideways the item always reveals itself, so a shelf section can be the subject while its row still scrolls); don't add a page behavior that scrolls the window separately. An item on the first line of its zone reveals the scroller's *start* when the start shows it whole (UP onto the library's first row returns the page to its title and toolbar; a row's first tile returns the row to 0); a declared `data-nav-reveal-block` keeps precedence. A zone declaring `data-nav-reveal-next` also shows the zone after it (the home shelves); never size a scroll-margin reserve to "the next shelf" or to a heading — it is a guess the next layout breaks. Vertical destinations are one ordered list in `revealItem` (next zone, declared alignment, least scrolling; first that keeps the item whole wins): add a preference there, not a new try-check-undo.
- **The wheel takes scroll authority.** A wheel event is the pointer claiming the scroll: the orchestrator cancels every glide where it stands (`writer.cancelScrollMotion()`) and switches to mouse mode. While the method is mouse, restores the user didn't ask for (post-patch reconciles, cursor-start seeding) pass `{ reveal: false }` to the writer's focus calls — focus survives the patch, the viewport never moves. The next cursor-driving keypress (arrows, Enter, zone brackets — `isCursorDriving` in `actions.js`) flips the method back before its action runs, so cursor navigation reveals as before; command keys (Escape, Backspace, `p`) and typing act without flipping, and BACK/CLEAR focus writes route through `_restoreOpts()` since they can run in mouse mode. Never add a reveal that can fire in mouse mode without routing through `_restoreOpts()`.
- **The navigation owns mount-time scroll.** During `start()` the window still carries the previous page's offset; LiveView writes the navigation's own scroll (reset on redirect, restore on back/forward) one frame later. A reveal measured then chases a stale absolute target *after* that write — home's scroll used to leak onto the next page this way. So `start()` runs with `_mounting` set and every mount-time focus write passes `{ reveal: false }` regardless of input method; the first user action reveals as always. Never add a focus call to the mount path that bypasses `_restoreOpts()`.

Motion is measured on the TV app, the performance floor ([`docs/tv-performance.md`](../../../docs/tv-performance.md)): a glide is a main-thread scroll, so each frame costs a commit and raster there — never add per-frame work to it, and check a change to `scroll_glide.js` or `revealItem` with `mc-tv-smooth` interleaved against the base.

Verify both with `~/scripts/agents/mc-nav-trace '<keys>'`, which reports the focused context/zone/index per step plus how many px of the focused card fall outside its scrollport. Any non-zero settled clip is a bug.

### TREE Behavior (nesting vertical list)

`_treeTransition()` handles every vertical list whose rows carry controls or nest: the detail modal's body (seasons contain episodes; an episode contains its own controls), the feed, the watchlist rows, the plan bodies, `bindings`, and every nested menu list. UP/DOWN walk it as rendered. LEFT and RIGHT are **depth**, not lateral movement, and the machine emits only `tree_in` / `tree_out` because what they mean depends on what the cursor is on: RIGHT expands a collapsed `[aria-expanded]` head, else steps along the item's `[data-nav-sub-item]` controls; LEFT walks back out of those, then collapses the enclosing `[data-nav-group]`'s expanded head, landing on it. Read `aria-expanded` — never mirror disclosure state into a parallel `data-` attribute.

A TREE can also sit inside a page: Settings → Controls wraps its binding table in a `bindings` zone under the settings grid (`grid.down → bindings`, `bindings.up → grid`), each row an item with its keycaps and Unbind buttons as `[data-nav-sub-item]`s. The rest of Settings stays the flat walk — every stepper/choice/list control its own item — so a many-row table of rows-with-controls is the case for a nested tree, not a reason to retype the page.

### Overlays With Regions

An overlay carrying `data-nav-overlay="<name>"` navigates as several zones per `config.overlays[name]` (`entry` = cursor-start priority among its regions, `layout` = its internal edges, merged over the page graph while open). The detail modal declares `detail`: a `detail_actions` TOOLBAR over a per-sub-view body — a `detail_list` TREE for the season/film/extras lists, a `detail_cast` SHELF (geometry-resolved photo grid) for Cast, and for Manage its own pair: `manage_tools` (TOOLBAR card — LEFT/RIGHT along it, DOWN drops past) over `manage_list` (TREE ledger). `manage_list` is deliberately not `detail_list` — cursor memory is keyed by context name, and sharing it let ledger activity clobber the episode list's remembered position. One sub-view's zones in the DOM at a time; the `down` candidate lists route to whichever is populated. Every region climbs on UP at its top (UIDR-019, twice amended): cast grid and `manage_tools` to the actions row, the tree through `manage_tools` when Manage is showing, else to the actions row. The orchestrator consults the graph at a TREE's up/down wall the same way it does for MENU. The plan modal declares `plan` (UIDR-029): `plan_head` TREE over `plan_grid` SHELF (episode cells by geometry) over `plan_body` TREE on the board; earlier stages put everything in `plan_body`; the regions declare no `back` edges, so BACK dismisses from anywhere — except the picker's open Download menu, a `plan_menu` TREE nested in the body with `up` and `back` to it, which BACK closes first. It opens on an empty loading stage, so entry is re-resolved on each sync until a region populates (`_ensureCursorStart`: an open overlay keeps the cursor and never seeds the page beneath, which is what it covers). The orchestrator knows the active overlay by its `data-nav-overlay` name, so an overlay opening over another while the presentation stays modal — the viewing layer's track menu over its OSD — is entered like an open, and closing back to the one beneath re-enters it. Overlays without the attribute stay flat MODAL — right for confirms and small forms; a flat overlay whose one item arrives after it opened (the OSD's prompt pill) gets the cursor from the post-patch reconciler. See [UIDR-019](../../../decisions/user-interface/2026-08-07-019-detail-modal-two-regions.md).

### BACK and CLEAR Semantics

BACK is answered by `_backTransition()` **before** the context-type dispatch — one function, not a `case Action.BACK` in each. `backStep()` states the step as data and `_backTransition()` acts on it; the hint bar labels B with the same value. It peels containment in order: an overlay region with a nav-graph `back` edge leaves for that region (one press, however deep — stepping out a level at a time is LEFT's job) → sub-focus exits → an overlay dismisses → the primary menu exits to the pre-sidebar context → content enters the primary menu. On a shell that can leave (the TV app, `leaveApp` from `MediaCentaurTV.leave`), BACK in the primary menu — and on a menu-less page — leaves the app (`leave_app`) instead of doing nothing. In content contexts (grid, toolbar, zone_tabs, shelf) and non-primary menus (sections, the download zones) BACK is therefore **the way to the main nav** (UIDR-028); LEFT is lateral movement within the page and never reaches the sidebar — no zone layout declares a `left: ["sidebar"]` edge. Each layout still declares its sidebar node (with `right` candidates for exiting); the node is in the graph only when the sidebar is on the page, which is what tells BACK the page has a main menu — a sidebar-less page (the setup tour, the profile door) stays a no-op, or leaves the app on the TV. There is no `onEscape` behavior hook.

Adding a BACK case to a transition function is a smell: express it as containment instead.

CLEAR delegates to page behavior `onClear()` in any page context, before `onAction`. Library (clears the filter and returns `"grid"`, which the cursor follows when the grid has items), Downloads (the release search, then the History search), Discovery (its search) and Watchlist (its search) implement it. An open overlay keeps CLEAR — and the tab keys — out: it covers the page. If no `onClear` exists, the action is dropped.

ZONE_NEXT/ZONE_PREV (`]` `[`, RB LB) are also answered before the type dispatch: from any page context they cycle the page's `zone-tabs` strip.

### Nested Menus

A GlassMenu list nested in its trigger's zone is its own TREE zone with `up` and `back` edges to that zone and a `data-nav-dismiss-event`. It **takes the cursor when it opens** (`_enterOpenedMenu`: the zone went from empty to populated while the cursor was in its `back` target), on its chosen option; a trigger that was a row's sub-item leaves its sub-focus behind. **Leaving it in any direction pushes its dismiss event**, so the list closes; an arrow off its end returns to the trigger, as BACK does (the `enter_context` directive's `from`). Users: `library_sort_menu`, `watchlist_rung_menu`, `detail_menu`, `detail_tracking_menu`, `plan_menu`.

### Overlay Entry and Return

An overlay opens on its entry region's chosen item (active marker — the playing subtitle track), else `entryDefaults`, else the first. The page context it opened over is recorded (a click on a card names it with the entity id); on close the cursor returns there — a card by entity id, any other context (a feed row, a pursuit) by its remembered index; with no origin (a deep link), the page's cursor start. Every context remembers its index; the grid also its entity id.

### Hint Bar

The gamepad hint bar is derived, never listed: `_projectHints()` writes `data-hint-back` (= `backStep()`), `data-hint-clear` (page `onClear`, no overlay), `data-hint-play` (focused item has `data-entity-id`) and `data-hint-tabs` (≥2 tabs, no overlay) on `<html>` after every action, patch and overlay transition; CSS in `app.css` shows the entries. A new zone needs nothing for it.

### Page Behaviors

Page-specific concerns extracted from the orchestrator. Detected via `data-page-behavior` attribute. Duck-typed interface: `activateOnFocus`, `onAttach`, `onDetach`, `onAction` (returns `true` to consume, `{transitionTo}` to move, falsy to pass), `onClear` (may return a context name), `onSyncState`, `onZoneChanged` — all optional; most pages need none. The `activateOnFocus` property is a string array of menu context names that should click items on focus during up/down nav (Settings `sections`, Guide `guide_chapters`; the primaryMenu always activates).

Two decorators wrap a behavior: `withViewing` (`viewing_behavior.js`) while `[data-viewing]` is up — arrows seek, SELECT pauses or takes the prompt, MENU toggles the track menu, DOWN/UP drive the paused bar's tracks button, BACK passes through — and `withWipNotice` (`wip_notice.js`) on a page whose navigation is unfinished. The gamepad's `input_gate.js` lets a pad drive the page only when it is focused, visible and not automation (E2E opts in with `window.__inputAutomationDrivesGamepad`).

Pages with clearable state (filters, search) should implement `onClear()`. There is no escape hook — BACK semantics live entirely in the state machine.

### URL Persistence (data-nav-remember)

Sidebar links rendered with `<.sidebar_link remember>` carry `data-nav-remember` and preserve the target page's query params across navigation. Implemented in `root.html.heex`. Pages must use query params + `handle_params` for this to work.

Pages declare modal/overlay params (and one-shot triggers) in `data-nav-transient-params` on their root element — the remember script strips those before saving, so leaving a section closes its modals rather than re-opening them on return. A page that adds a URL-driven modal must add its param to that list.

## Checklist: Adding Input Nav to a New Page

1. **Layout:** in `config.js`, the page's `layouts` entry (edges between its zones, plus a `sidebar` node with `right` candidates) and `cursorStartPriority`
2. **Zones:** for each new zone an `instanceTypes` and `contextSelectors` entry; `alwaysPopulated` only for static content always on the page
3. **Template:** `data-nav-default-zone="<layout key>"` and `data-page-behavior` on the page root; every interactive control a `data-nav-item tabindex="0"` inside a connected zone, or a `[data-nav-sub-item]` of a TREE row; `data-nav-transient-params` for URL-driven overlays. **Never `data-captures-keys` on a control or field the input system navigates** — the keyboard source ignores every key there, a trap
4. **Nested menus and overlays:** a menu list as above (Nested Menus); a regioned overlay in `config.overlays`
5. **Page behavior** (only if needed): `<name>_behavior.js`, registered in `page_behavior.js` as a zero-argument closure (wrapped in `withWipNotice` while unfinished)
6. **Sidebar link:** `<.sidebar_link remember>` in `layouts.ex` if the page uses query params
7. **Verify:** `bun test assets/js/input/` (`__tests__/config_coverage.test.js` fails on a template zone, default zone or behavior with no config), then walk every surface with `mc-nav-trace`: no trap, no unreachable control, no clipped focus

## DOM Contract

| Attribute | Purpose |
|-----------|---------|
| `data-nav-zone` | Navigation zone container (names per `config.js`) |
| `data-nav-item` | Focusable element (needs `tabindex="0"`) |
| `data-nav-sub-item` | One of a row's controls — RIGHT steps onto it |
| `data-nav-grid` | CSS grid container (column count, literal `grid` zone) |
| `data-page-behavior` | Page behavior, on the page root: `apps`, `discovery`, `downloads`, `episode-mapping`, `guide`, `library`, `profiles`, `review`, `settings`, `setup`, `social`, `status`, `watch-history`, `watchlist` (Home and Console carry none) |
| `data-nav-default-zone` | The page's layout key, on the page root — every page |
| `data-nav-remember` | Sidebar link preserves target page URL across navigation (`<.sidebar_link remember>`) |
| `data-nav-transient-params` | On a page root: params stripped from the remembered URL (modal state, one-shot triggers) |
| `data-entity-id` | Stable card identifier: grid memory, overlay origin, PLAY's target |
| `data-detail-mode` | An open overlay (`modal`) |
| `data-detail-nested` | The overlay is below its root view (or inside another — the track menu in the OSD): BACK pushes its dismiss event and keeps the cursor in the overlay. Server-owned |
| `data-dismiss-event` | The event BACK's dismiss pushes (default `close_detail`) |
| `data-nav-overlay` | Overlay navigates as regions per `config.overlays[name]` (`detail`, `plan`, `viewing_menu`) |
| `data-nav-dismiss-event` | On a zone container: pushed whenever the cursor leaves the zone — a nested menu closes itself |
| `data-nav-group` | Extent of a disclosure — LEFT inside it collapses via its `[aria-expanded]` head |
| `aria-expanded` | Disclosure state on a nav item, read directly by TREE navigation |
| `data-resume-target`, `data-selected` | Where `detail_list` / `detail_rail` open (via `entryDefaults`) |
| `data-captures-keys` | Element handles its own keys; the keyboard source ignores them all. Never on a navigated control |
| `data-nav-return-focus` | On a control that grows its own list (Show more): after SELECT's patch lands, the cursor returns to the item it came from |
| `data-nav-reveal` | Vertical reveal subject: scroll THIS ancestor into view instead of the focused item. Sideways the item still reveals itself |
| `data-nav-reveal-block` | Block-axis alignment for the reveal (`start`/`center`/`end`) |
| `data-nav-reveal-next` | On a zone container: a reveal there also shows the next zone's subject at the scrollport end |
| `data-nav-enter-scroll-top` | On a zone container: spatially crossing into the zone glides its nearest scrollable ancestor to the top |
| `data-nav-focus-target` / `data-nav-focus-ring` | Delegate the focus ring from an item to its children |
| `data-viewing`, `data-viewing-prompt`, `data-viewing-tracks` | Viewing layer present; its prompt pill; the paused bar's tracks button (not a nav item) |
| `data-input-bindings` | On the hook element: the catalog bindings the sources' maps are built from |
| `data-player` | On `<html>`: `remote` on the TV app — keyboard source only |
| `data-input`, `data-input-editing`, `data-nav-context`, `data-gamepad-type`, `data-hint-*` | Projected onto `<html>` by the input system |

## Test Patterns

Tests use `bun:test`. Three mock factories in `core/__tests__/orchestrator.test.js`:

- **`createMockReader(overrides)`** — controllable reader values
- **`createMockWriter()`** — proxy recording all calls to `calls` array
- **`createMockGlobals()`** — mock document/sessionStorage/rAF with `_dispatchKeyDown`, `_dispatchMouseMove(x, y)`, `_dispatchClick`, `_dispatchWheel`, `_dispatchVisibilityChange`, `_flushRAF` helpers

They are module-local (not exported); a `setup(readerOverrides, configOverrides)` helper there builds an orchestrator. Pure modules (focus_context, nav_graph, spatial, actions) test directly — no mocks needed. Behavior tests inject a `dom` double. Browser-level coverage lives in Playwright (`test/e2e/*.spec.js`, e.g. `gamepad-specific.spec.js`).

## Runtime Debugging

The input system has built-in debug logging that is silent by default. Toggle
it at runtime — no rebuild needed. **Do not use the chrome-devtools MCP tools;
they do not work on this machine.** The agent tooling in `~/scripts/agents/`
is the door:

- **Trace a key sequence:** `mc-nav-trace [--url <url>] [--step-ms N] [--debug] [--json] '<keys>'`
  — the first tool for any navigation question. It drives keys through the
  real pipeline and reports which item holds focus after each step, flagging
  clipped focus in a `.row-scroll` track. **On the live dev server it acts on
  the owner's real library: never send Enter/`p` inside a title modal, plan
  modal, tracking card or settings control** — a stray press there has
  started a real download.
- **Evaluate JS in a live page:** `chromium-probe [--with-console] <url> '<expr>'`
  — e.g. `chromium-probe --with-console http://127.0.0.1:2160/library
  'window.__inputDebug = true; document.activeElement?.outerHTML'`. With
  `--with-console` the `[input]` trace comes back with the result.
- **Screenshot:** `page-shot --url <url> --viewport 1920x1080 --wait-ms 3000`
  (default viewport 1600x1000; `--eval` runs JS first, e.g. set
  `document.documentElement.dataset.input = "gamepad"` to show the hint bar),
  then Read the PNG.

The headless tools pass the profile gate themselves; `chromium-probe` takes an
expression, so wrap statements in `(async () => { … })()`.

Caveats: `chromium-probe` runs headless — there are no window-focus events and
CSS transitions never settle, so assert on the state that drives an
animation, not on animated property values. Dispatch a synthetic keydown on
an element (the focused one), never on `document` itself.

**What the logs cover:**
- Context transitions (`_setContext`) with caller stack trace
- Actions received with current context and input method
- Grid navigation details (index, columns, total, direction)
- Mouse movement deltas and method transitions
- Gamepad axis direction changes and center returns
- `_syncState` / `onViewChanged` calls with caller info

**Implementation:** `debug()` from `assets/js/input/core/debug.js`. Import and use in any core module. Never use bare `console.log` — always go through `debug()`.

## Design Rules

- **A zone may contain a zone; an item counts once, for its nearest zone.** An item counts for a context only when its nearest `[data-nav-zone]` ancestor matches the context selector's zone compound, or when it has none (`ownedByScope` in `dom_adapter.js`). A zone may declare `data-nav-dismiss-event`, pushed whenever the cursor leaves it — a menu list closes itself this way.
- **Empty-context safety.** Every zone must define both a layout and cursor start priority. The graph prevents transitions into empty contexts; the priority list handles initial placement.
- **Page state lives in the URL.** Use `handle_params` + `live_patch`. Don't duplicate in sessionStorage.
- **DOM access goes through the reader/writer.** The orchestrator never calls `document.*`; a behavior that reads the DOM takes an injected `dom` (its module exports the real one).
- **Single-owner DOM projection.** Each `data-*` attribute on `<html>` has one state owner and one sync path (state change → callback → DOM write). Never piggyback DOM syncs on unrelated events. See "Single-Owner DOM Projection" in `docs/input-system.md`.
- **Modal sub-views use deferred refocus.** When a modal is below its root view, `_executeDismiss` reads `data-detail-nested` via `reader.isDetailNested()` and pushes `close_detail` without changing focus context, setting `_pendingModalRefocus = true`. Never re-derive "am I nested" on the client by comparing the view name to `"main"` — which view is root depends on the entity. `_syncState` (which fires after the LiveView DOM patch) checks this flag and focuses the overlay's entry region. Never use `requestAnimationFrame` for post-patch focus — the LiveView round-trip takes longer than a single frame.
- **Dependency directionality.** Core never imports from app layer. App imports from `core/index.js`.
