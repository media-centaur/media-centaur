# Front-End Tests — Bun Unit + Playwright E2E

Read this when writing JavaScript unit tests or Playwright E2E. Not needed for
Elixir work.

```bash
bun test assets/js/input/                   # all input-system unit tests
bun test assets/js/input/__tests__/nav_graph.test.js

scripts/input-test                          # all E2E, both input methods
scripts/input-test --project=keyboard       # one input method
scripts/input-test library                  # one page, both methods
scripts/input-test --help                   # --debug, --trace, --ui, …
```

E2E requires the dev server at `http://127.0.0.1:2160`.

---

## JavaScript Unit Tests (Bun)

Tests use `bun:test` imports (`describe`, `expect`, `test`, `beforeEach`, `mock`).

**Pure modules** (`nav_graph.js`, `spatial.js`, `actions.js`, `input_method.js`) —
test directly, no mocks, assert on return values.

**State machine** (`focus_context.js`) — construct `FocusContextMachine` with
config, set the graph via `setNavGraph(buildNavGraph(...))`, assert on
`transition(action)` and `machine.context`.

**Orchestrator** (`core/__tests__/orchestrator.test.js`) — full mock injection via
three factories:

- `createMockReader(overrides)` — controllable reader values, e.g.
  `getItemCount: (ctx) => 8`
- `createMockWriter()` — proxy recording every call into `calls`. Assert with
  `calls.filter(c => c.method === "focusByIndex")`. The proxy returns `undefined`
  from all calls; real `DomWriter.focusFirst()`/`focusByIndex()` return `boolean`,
  but orchestrator tests don't depend on that.
- `createMockGlobals()` — mock document/sessionStorage/rAF, with
  `_dispatchKeyDown(key, opts)`, `_dispatchMouseMove(x, y)`, `_flushRAF()`

**Page behaviors** (`__tests__/*_behavior.test.js`) — mock only the DOM methods
needed, test behavior return values, e.g. `mockDom({ filterValue: "" })`.

**Import boundaries:** `core/` never imports from the app layer, validated by
dependency-cruiser via `mix boundaries` (`.dependency-cruiser.cjs`). Tests in
`__tests__/` are exempt.

---

## E2E Tests (Playwright)

Location `test/e2e/`. Every navigation test runs twice — keyboard and gamepad — via
Playwright projects, kept input-method-agnostic by the `inputAction` fixture.
Current specs: `ls test/e2e/*.spec.js`.

### Parameterized input method

```javascript
// Import from the fixture, NOT from @playwright/test
import { test, expect } from "./fixtures/input-method.js"

test("arrow down moves focus", async ({ page, inputAction, navigateTo }) => {
  await navigateTo("/library")        // auto-sets up the gamepad mock if needed
  await inputAction("NAVIGATE_DOWN")  // keyboard: ArrowDown, gamepad: D-pad down
  await expectContext(page, "sections")
})
```

Fixtures from `fixtures/input-method.js`: `inputMethod` (`"keyboard"`/`"gamepad"`),
`inputAction(action)`, `navigateTo(path)`.

Semantic actions: `NAVIGATE_UP`, `NAVIGATE_DOWN`, `NAVIGATE_LEFT`,
`NAVIGATE_RIGHT`, `SELECT`, `BACK`, `PLAY`, `CLEAR`, `ZONE_NEXT`, `ZONE_PREV`.

### Gamepad mock

The mock overrides `navigator.getGamepads()` before the LiveView hook mounts, so
GamepadSource's rAF polling loop reads mock state naturally — no patching of
internal code.

```javascript
import { injectGamepadMock, connectGamepad, pressButton, Button } from "./helpers/gamepad.js"

await injectGamepadMock(page, { id: "Xbox Wireless Controller" })
await connectGamepad(page)             // dispatches gamepadconnected
await pressButton(page, Button.DOWN)   // full press-release cycle
await holdButton(page, Button.DOWN)    // press without release (repeat tests)
await releaseButton(page, Button.DOWN)
await moveAxis(page, 1, 0.8)           // analog stick (axis 1 = left Y)
await centerAxis(page, 1)
await disconnectGamepad(page)
```

`Button`: `A` 0 select, `B` 1 back, `Y` 3 clear, `LB` 4 zone-prev, `RB` 5
zone-next, `START` 9 play, `UP` 12, `DOWN` 13, `LEFT` 14, `RIGHT` 15.

### Wait & assertion helpers

```javascript
import { waitForLiveView, waitForInputSystem, waitForGridItems, navigateAndWait } from "./helpers/liveview.js"
import { expectContext, expectFocused, expectInputMethod, expectControllerType,
         expectFocusInZone, getFocusedNavItem, getZoneItemCount } from "./helpers/input.js"
```

Waiters: `waitForLiveView` (phx-connected), `waitForInputSystem`
(`data-nav-context` on `<html>`), `waitForGridItems(page, {min: 1})`,
`waitForSections`, `waitForSettle(page, 100)`, `navigateAndWait(page, "/settings")`.

Assertions: `expectContext(page, "grid")`, `expectFocused(page,
"[data-nav-item='entity-id']")`, `expectInputMethod(page, "keyboard")`,
`expectControllerType(page, "xbox")`, `expectFocusInZone(page, "sections")`.
Readers: `getFocusedNavItem(page)`, `getZoneItemCount(page, "grid")`.

### Writing new E2E tests

**Parameterized** (both input methods): import from `./fixtures/input-method.js`;
use `navigateTo` for setup; use `inputAction` for all navigation — never
`page.keyboard.press` directly; guard optional content with `getZoneItemCount()` +
`test.skip()`; assert on data attributes, not DOM structure.

**Gamepad-only:** import from `@playwright/test` directly, skip with
`test.skip(testInfo.project.use.inputMethod !== "gamepad")`, install the mock via
`page.addInitScript()` before navigating.

**Keyboard-only:** import from the fixture, skip with
`test.skip(inputMethod === "gamepad", "keyboard-only test")`.

### Debug

```javascript
await enableInputDebug(page)             // window.__inputDebug = true
await disableInputDebug(page)
const msgs = filterDebugMessages(logs)   // filter for [input] prefix
```
