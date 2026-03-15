/**
 * Gamepad mock — injects a controllable navigator.getGamepads() override.
 *
 * Strategy: override navigator.getGamepads BEFORE the LiveView hook mounts,
 * then dispatch gamepadconnected to wake GamepadSource from idle. The rAF
 * polling loop reads our mock state naturally.
 */

/** Standard gamepad button indices */
export const Button = {
  A: 0,       // Select / Cross
  B: 1,       // Back / Circle
  X: 2,       // Square
  Y: 3,       // Clear / Triangle
  LB: 4,      // Zone prev / L1
  RB: 5,      // Zone next / R1
  START: 9,   // Play / Menu
  UP: 12,     // D-pad up
  DOWN: 13,   // D-pad down
  LEFT: 14,   // D-pad left
  RIGHT: 15,  // D-pad right
}

/**
 * Inject mock gamepad into page BEFORE LiveView hook mounts.
 * Call this after page.goto() but it works best via page.addInitScript().
 * @param {import("@playwright/test").Page} page
 * @param {object} [opts]
 * @param {string} [opts.id="Xbox Wireless Controller"] - Controller ID string
 */
export async function injectGamepadMock(page, { id = "Xbox Wireless Controller" } = {}) {
  await page.evaluate((controllerId) => {
    window.__mockGamepad = {
      id: controllerId,
      index: 0,
      connected: true,
      timestamp: 0,
      buttons: Array.from({ length: 17 }, () => ({ pressed: false, touched: false, value: 0 })),
      axes: [0, 0, 0, 0],
      mapping: "standard",
    }
    navigator.getGamepads = () => [window.__mockGamepad, null, null, null]
  }, id)
}

/**
 * Wake GamepadSource by dispatching gamepadconnected event.
 * Call after injectGamepadMock and after LiveView/input system has mounted.
 * @param {import("@playwright/test").Page} page
 */
export async function connectGamepad(page) {
  await page.evaluate(() => {
    const event = new Event("gamepadconnected")
    event.gamepad = window.__mockGamepad
    window.dispatchEvent(event)
  })
  // Wait for rAF poll cycle to pick up the gamepad
  await page.waitForTimeout(50)
}

/**
 * Press and release a gamepad button.
 * Simulates a complete press-release cycle with time for rAF polling.
 * @param {import("@playwright/test").Page} page
 * @param {number} buttonIndex - Button index (use Button constants)
 */
export async function pressButton(page, buttonIndex) {
  // Press
  await page.evaluate((i) => {
    const gp = window.__mockGamepad
    gp.buttons[i] = { pressed: true, touched: true, value: 1 }
    gp.timestamp = performance.now()
  }, buttonIndex)

  // Wait for at least one rAF cycle to process the press
  await page.waitForTimeout(50)

  // Release
  await page.evaluate((i) => {
    const gp = window.__mockGamepad
    gp.buttons[i] = { pressed: false, touched: false, value: 0 }
    gp.timestamp = performance.now()
  }, buttonIndex)

  // Wait for release to be processed
  await page.waitForTimeout(50)
}

/**
 * Hold a gamepad button down (without releasing).
 * Useful for testing repeat timing.
 * @param {import("@playwright/test").Page} page
 * @param {number} buttonIndex
 */
export async function holdButton(page, buttonIndex) {
  await page.evaluate((i) => {
    const gp = window.__mockGamepad
    gp.buttons[i] = { pressed: true, touched: true, value: 1 }
    gp.timestamp = performance.now()
  }, buttonIndex)
  await page.waitForTimeout(50)
}

/**
 * Release a held gamepad button.
 * @param {import("@playwright/test").Page} page
 * @param {number} buttonIndex
 */
export async function releaseButton(page, buttonIndex) {
  await page.evaluate((i) => {
    const gp = window.__mockGamepad
    gp.buttons[i] = { pressed: false, touched: false, value: 0 }
    gp.timestamp = performance.now()
  }, buttonIndex)
  await page.waitForTimeout(50)
}

/**
 * Move an analog stick axis.
 * @param {import("@playwright/test").Page} page
 * @param {number} axisIndex - 0=left X, 1=left Y, 2=right X, 3=right Y
 * @param {number} value - -1.0 to 1.0
 */
export async function moveAxis(page, axisIndex, value) {
  await page.evaluate(({ axis, val }) => {
    const gp = window.__mockGamepad
    gp.axes[axis] = val
    gp.timestamp = performance.now()
  }, { axis: axisIndex, val: value })
  await page.waitForTimeout(50)
}

/**
 * Return analog stick to center (below deadzone).
 * @param {import("@playwright/test").Page} page
 * @param {number} axisIndex
 */
export async function centerAxis(page, axisIndex) {
  await moveAxis(page, axisIndex, 0)
}

/**
 * Disconnect the mock gamepad.
 * @param {import("@playwright/test").Page} page
 */
export async function disconnectGamepad(page) {
  await page.evaluate(() => {
    window.__mockGamepad.connected = false
    const event = new Event("gamepaddisconnected")
    event.gamepad = window.__mockGamepad
    window.dispatchEvent(event)
  })
  await page.waitForTimeout(50)
}
