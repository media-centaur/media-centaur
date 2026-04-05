# Add input-system coverage to the Console drawer

**Source:** design-audit 2026-04-06, DS19
**Severity:** Moderate
**Scope:** `lib/media_centaur_web/components/console_components.ex`, `assets/js/input/`

## Context

The Console is mouse-only today. None of its interactive elements (component chips, level-filter buttons, search input, footer action buttons) carry `data-nav-item` / `tabindex="0"`, and neither `ConsoleLive` nor `ConsolePageLive` is registered as an input-system page behavior.

`grep -rn "data-nav-item" lib/media_centaur_web/components/console_components.ex` returns nothing. Keyboard and gamepad users who open the console drawer (backtick) can't focus anything inside it without clicking.

The console is the primary debugging tool — it must be usable via keyboard and gamepad.

## What to do

1. **Drawer overlay is a top-level context.** Pick a new context key like `console` and wire it into `assets/js/input/config.js`:
   - Add `contextSelectors.console = "[data-nav-zone='console'] [data-nav-item]"`.
   - Add a `console` layout entry with internal rows (chips row, level buttons row, search input row, log list, footer buttons). Decide whether the log list itself should be a navigable context or just a scroll target.
   - Decide what BACK / Escape does from the console — my default recommendation: close the drawer.
2. **Tag the elements.** In `console_components.ex`:
   - Each chip button in `chip_row/1` → `data-nav-item tabindex="0"`, grouped under `data-nav-zone="console-chips"` (or whatever sub-zone keys you pick).
   - Each level button → `data-nav-item tabindex="0"`.
   - The search input → `data-nav-item tabindex="0"` with `data-captures-keys` so arrow keys don't steal from the input while typing (see how the library filter does it in `library_cards.ex`).
   - Every footer button (pause, clear, copy, download, full page, rescan) → `data-nav-item tabindex="0"`.
3. **Page behavior.** The console is rendered by `ConsoleLive` as a sticky live_render — it's not a top-level page. Rather than a page behavior, extend `ConsoleLive`'s root element to set `data-page-behavior="console"` when open. Or have the parent page's behavior delegate to a console sub-behavior when the drawer is `data-state="open"`. Pick whichever is cleaner once you start wiring.
4. **Full-page `/console`.** `ConsolePageLive` needs the same tagging. Since it reuses `console_components.ex`, adding the attributes there covers both.
5. **Tests.** Add a Playwright spec at `test/e2e/console.spec.js` that:
   - Opens the drawer via backtick
   - Navigates right through chips and asserts focus moves
   - Navigates to the footer, presses SELECT on clear, confirms the `data-confirm` fires (or mocks it)
   - Presses BACK to close the drawer
   Run under both `--project=keyboard` and `--project=gamepad` per project convention.

## Acceptance criteria

- Every interactive console element is reachable by keyboard and gamepad.
- Backtick opens the drawer with focus on a sensible first element (probably the search input or the first chip).
- BACK / Escape closes the drawer and restores focus to the underlying page.
- `bun test assets/js/input/` clean, `scripts/input-test console` (or equivalent) clean.
- `mix precommit` clean.
