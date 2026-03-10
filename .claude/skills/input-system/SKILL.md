---
name: input-system
description: "Use this skill when working with keyboard/gamepad navigation, the focus context state machine, nav graphs, page behaviors, DOM adapter, data-nav attributes, or adding input system support to a new page."
---

Read the full architecture doc at `docs/input-system.md` before making changes.

## Architecture at a Glance

All code lives in `assets/js/input/`. Tests in `assets/js/input/__tests__/` run via `bun test`.

**Data flow:** keydown → semantic action → state machine directive → orchestrator → DOM mutation.

All external dependencies injected via constructors — every layer testable with mocks.

## Key Concepts

### Context Types vs Instance Names

The `Context` enum defines behavior types (`GRID`, `MENU`, `TOOLBAR`, etc.). The `_context` field stores instance names (`"grid"`, `"sidebar"`, `"sections"`). The `contextType()` resolver maps instance names to behavior types:

```js
const INSTANCE_TYPES = {
  sidebar: Context.MENU,
  sections: Context.MENU,
}
```

This lets multiple instances share behavior (sidebar and sections both use MENU navigation rules) while having distinct DOM selectors and nav graph entries.

### Navigation Graph

Cross-context transitions are driven by an adjacency map in `nav_graph.js`. Each zone (watching, library, settings) defines edges between contexts with ordered fallback candidates. The graph is rebuilt from DOM state on every sync.

**Always-populated contexts:** `sidebar` and `sections` are treated as always populated (static content). Add to `isPopulated()` if you add another static context.

### MENU Behavior

The `_menuTransition()` handles all MENU instances. Sidebar gets special treatment (exit_sidebar on right/back, wall on left). Non-sidebar MENU instances use the nav graph for left/right/back transitions.

### Page Behaviors

Page-specific concerns extracted from the orchestrator. Detected via `data-page-behavior` attribute. Duck-typed interface: `onAttach`, `onDetach`, `onEscape`, `onSyncState`, `onZoneChanged` — all optional.

### URL Persistence (data-nav-remember)

Sidebar links with `data-nav-remember` preserve the target page's query params across navigation. Implemented in `root.html.heex`. Pages must use query params + `handle_params` for this to work.

## Checklist: Adding Input Nav to a New Page

1. **Nav graph:** Add zone layout in `LAYOUTS` and `CURSOR_START_PRIORITY` in `nav_graph.js`
2. **Custom contexts:** If needed, add to `INSTANCE_TYPES` (focus_context.js), `CONTEXT_SELECTORS` (dom_adapter.js), `_buildCounts()` (index.js), and `isPopulated()` (nav_graph.js)
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
| `data-page-behavior` | Page behavior to activate (`library`, `settings`) |
| `data-nav-default-zone` | Default zone for pages without zone tabs |
| `data-nav-remember` | Sidebar link preserves target page URL across navigation |
| `data-entity-id` | Stable entity identifier on cards |
| `data-detail-mode` | Presentation shell type (`modal`, `drawer`) |
| `data-captures-keys` | Element handles own keyboard events |

## Test Patterns

Tests use `bun:test`. Three mock factories in `__tests__/index.test.js`:

- **`createMockReader(overrides)`** — controllable reader values
- **`createMockWriter()`** — proxy recording all calls to `calls` array
- **`createMockGlobals()`** — mock document/sessionStorage/rAF with `_dispatchKeyDown`, `_flushRAF` helpers

Pure modules (focus_context, nav_graph, spatial, actions) test directly — no mocks needed.

## Design Rules

- **Nav zone containers must not nest.** Descendant selectors cross-contaminate.
- **Empty-context safety.** Every zone must define both a layout and cursor start priority. The graph prevents transitions into empty contexts; the priority list handles initial placement.
- **Page state lives in the URL.** Use `handle_params` + `live_patch`. Don't duplicate in sessionStorage.
- **DOM access confined to `dom_adapter.js`.** Orchestrator and behaviors never call `document.*` directly.
