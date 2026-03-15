/**
 * Playwright fixture for parameterized input method testing.
 *
 * Extends the base test with an `inputAction` function that dispatches
 * navigation actions via keyboard or gamepad depending on the project config.
 *
 * Usage in specs:
 *   import { test, expect } from "../fixtures/input-method.js"
 *   test("arrow down moves focus", async ({ page, inputAction }) => {
 *     await inputAction("NAVIGATE_DOWN")
 *   })
 */
import { test as base, expect } from "@playwright/test"
import { pressButton, connectGamepad, Button } from "../helpers/gamepad.js"
import { waitForLiveView, waitForInputSystem } from "../helpers/liveview.js"
import { establishFocus } from "../helpers/input.js"

/** Map semantic actions to keyboard keys */
const ACTION_TO_KEY = {
  NAVIGATE_UP: "ArrowUp",
  NAVIGATE_DOWN: "ArrowDown",
  NAVIGATE_LEFT: "ArrowLeft",
  NAVIGATE_RIGHT: "ArrowRight",
  SELECT: "Enter",
  BACK: "Escape",
  PLAY: "p",
  CLEAR: "Backspace",
  ZONE_NEXT: "]",
  ZONE_PREV: "[",
}

/** Map semantic actions to gamepad button indices */
const ACTION_TO_BUTTON = {
  NAVIGATE_UP: Button.UP,
  NAVIGATE_DOWN: Button.DOWN,
  NAVIGATE_LEFT: Button.LEFT,
  NAVIGATE_RIGHT: Button.RIGHT,
  SELECT: Button.A,
  BACK: Button.B,
  PLAY: Button.START,
  CLEAR: Button.Y,
  ZONE_NEXT: Button.RB,
  ZONE_PREV: Button.LB,
}

export { expect }

/**
 * Init script source for gamepad mock injection.
 * Extracted so it can be added once per page context.
 */
const GAMEPAD_INIT_SCRIPT = () => {
  window.__mockGamepad = {
    id: "Xbox Wireless Controller",
    index: 0,
    connected: true,
    timestamp: 0,
    buttons: Array.from({ length: 17 }, () => ({ pressed: false, touched: false, value: 0 })),
    axes: [0, 0, 0, 0],
    mapping: "standard",
  }
  navigator.getGamepads = () => [window.__mockGamepad, null, null, null]
}

export const test = base.extend({
  /** Whether this project uses gamepad input */
  inputMethod: [async ({}, use, testInfo) => {
    const method = testInfo.project.use.inputMethod ?? "keyboard"
    await use(method)
  }, { option: true }],

  /**
   * Dispatch a semantic action via the configured input method.
   * @param {string} action - Action name (e.g., "NAVIGATE_DOWN", "SELECT")
   */
  inputAction: async ({ page, inputMethod }, use) => {
    const dispatch = async (action) => {
      if (inputMethod === "gamepad") {
        const buttonIndex = ACTION_TO_BUTTON[action]
        if (buttonIndex === undefined) {
          throw new Error(`No gamepad button mapping for action: ${action}`)
        }
        await pressButton(page, buttonIndex)
      } else {
        const key = ACTION_TO_KEY[action]
        if (!key) {
          throw new Error(`No keyboard key mapping for action: ${action}`)
        }
        await page.keyboard.press(key)
        // Small delay for input system to process
        await page.waitForTimeout(30)
      }
    }
    await use(dispatch)
  },

  /**
   * Navigate to a page with full setup for the configured input method.
   * Handles gamepad mock injection, LiveView wait, and DOM focus establishment.
   */
  navigateTo: async ({ page, inputMethod }, use) => {
    let initScriptAdded = false

    const navigate = async (path) => {
      if (inputMethod === "gamepad" && !initScriptAdded) {
        // Install gamepad mock as init script so it's available before hook mounts.
        // addInitScript persists across full page loads but only needs adding once.
        await page.addInitScript(GAMEPAD_INIT_SCRIPT)
        initScriptAdded = true
      }

      await page.goto(path)
      await waitForLiveView(page)
      await waitForInputSystem(page)

      if (inputMethod === "gamepad") {
        // Dispatch gamepadconnected in case the hook didn't pick it up from init script
        await connectGamepad(page)
      }

      // Ensure a nav item has DOM focus so subsequent actions navigate
      // rather than just establishing focus (see orchestrator._gridNavigate)
      await establishFocus(page)
    }
    await use(navigate)
  },
})
