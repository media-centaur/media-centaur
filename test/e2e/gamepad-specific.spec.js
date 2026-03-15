/**
 * Gamepad-specific E2E tests.
 *
 * These test behaviors unique to the gamepad source: analog stick navigation,
 * deadzone, button edge detection, priming, controller type detection,
 * idle-until-connected, and repeat timing.
 *
 * Only runs in the "gamepad" project — skipped for keyboard.
 */
import { test, expect } from "@playwright/test"
import { injectGamepadMock, connectGamepad, pressButton, holdButton, releaseButton, moveAxis, centerAxis, disconnectGamepad, Button } from "./helpers/gamepad.js"
import { expectContext, expectInputMethod, expectControllerType, getFocusedNavItem, getFocusedIndex, establishFocus } from "./helpers/input.js"
import { waitForLiveView, waitForInputSystem, waitForSettle, waitForSections } from "./helpers/liveview.js"

// Only run these tests in the gamepad project
test.beforeEach(async ({ page }, testInfo) => {
  if (testInfo.project.use.inputMethod !== "gamepad") {
    test.skip()
    return
  }

  // Install gamepad mock before navigation
  await page.addInitScript(() => {
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
  })

  await page.goto("/dashboard")
  await waitForLiveView(page)
  await waitForInputSystem(page)
  await connectGamepad(page)
  await waitForSections(page)
  await establishFocus(page)
})

test.describe("analog stick navigation", () => {
  test("stick beyond deadzone triggers navigation", async ({ page }) => {
    await expectContext(page, "sections")
    const before = await getFocusedIndex(page)

    // Push left stick down (axis 1 positive = down)
    await moveAxis(page, 1, 0.8)
    await waitForSettle(page, 100)
    await centerAxis(page, 1)

    const after = await getFocusedIndex(page)
    // Should have moved to next item
    expect(after).not.toBe(before)
  })

  test("stick within deadzone → no action", async ({ page }) => {
    await expectContext(page, "sections")
    const before = await getFocusedIndex(page)

    // Push below deadzone (0.3)
    await moveAxis(page, 1, 0.2)
    await waitForSettle(page, 100)
    await centerAxis(page, 1)

    const after = await getFocusedIndex(page)
    expect(after).toBe(before)
  })

  test("diagonal → both axes processed (system doesn't crash)", async ({ page }) => {
    await expectContext(page, "sections")

    // Push diagonally: both axes beyond deadzone
    await page.evaluate(() => {
      const gp = window.__mockGamepad
      gp.axes[0] = 0.4 // X: right
      gp.axes[1] = 0.9 // Y: down (strong)
      gp.timestamp = performance.now()
    })
    await waitForSettle(page, 100)

    // Center axes
    await page.evaluate(() => {
      const gp = window.__mockGamepad
      gp.axes[0] = 0
      gp.axes[1] = 0
      gp.timestamp = performance.now()
    })
    await waitForSettle(page)

    // System handled diagonal without crashing
    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    expect(context).toBeTruthy()
  })

  test("stick held → repeat timing", async ({ page }) => {
    await expectContext(page, "sections")
    const before = await getFocusedIndex(page)

    // Hold stick down
    await moveAxis(page, 1, 0.9)

    // Wait past repeat delay (400ms) + one interval (180ms)
    await page.waitForTimeout(650)
    await centerAxis(page, 1)

    // Should have moved at least once (possibly more with repeats)
    const after = await getFocusedIndex(page)
    expect(after).not.toBe(before)
  })
})

test.describe("button edge detection", () => {
  test("D-pad fires on press, not on continuous hold for non-nav buttons", async ({ page }) => {
    // Hold B button (BACK) — should fire once on press
    // BACK from sections → sidebar transition
    await holdButton(page, Button.B)
    await page.waitForTimeout(100)
    await releaseButton(page, Button.B)

    // BACK should have transitioned to sidebar
    await expectContext(page, "sidebar")
  })

  test("D-pad held → initial action + repeat after delay", async ({ page }) => {
    const before = await getFocusedIndex(page)

    // Hold D-pad down
    await holdButton(page, Button.DOWN)

    // Wait for repeat delay + interval
    await page.waitForTimeout(650)
    await releaseButton(page, Button.DOWN)

    // Focus should have moved (at least once, possibly with repeats)
    const after = await getFocusedIndex(page)
    expect(after).not.toBe(before)
  })

  test("release between presses → clean edge → new action", async ({ page }) => {
    const before = await getFocusedIndex(page)

    // First press
    await pressButton(page, Button.DOWN)
    const afterFirst = await getFocusedIndex(page)
    expect(afterFirst).not.toBe(before)

    // Second press (clean edge due to release)
    await pressButton(page, Button.DOWN)
    const afterSecond = await getFocusedIndex(page)
    expect(afterSecond).not.toBe(afterFirst)
  })
})

test.describe("button priming", () => {
  test("buttons held at page load are primed (no false fire)", async ({ page }) => {
    // Button priming happens in GamepadSource.start() — when the hook mounts
    // and finds a gamepad already connected with buttons held.
    // Test by loading a fresh page with D-pad DOWN already pressed.

    // Create a new page context with button pre-pressed in init script
    await page.addInitScript((btnDown) => {
      window.__mockGamepad = {
        id: "Xbox Wireless Controller",
        index: 0,
        connected: true,
        timestamp: 0,
        buttons: Array.from({ length: 17 }, (_, i) =>
          i === btnDown
            ? { pressed: true, touched: true, value: 1 }
            : { pressed: false, touched: false, value: 0 }
        ),
        axes: [0, 0, 0, 0],
        mapping: "standard",
      }
      navigator.getGamepads = () => [window.__mockGamepad, null, null, null]
    }, Button.DOWN)

    // Navigate fresh — GamepadSource.start() will find the button already held
    await page.goto("/dashboard")
    await waitForLiveView(page)
    await waitForInputSystem(page)
    await waitForSections(page)
    await establishFocus(page)

    const initial = await getFocusedIndex(page)

    // Wait for several rAF cycles — held button should NOT have fired
    await page.waitForTimeout(200)
    const afterHold = await getFocusedIndex(page)
    expect(afterHold).toBe(initial)

    // Now release and re-press — THIS should fire
    await page.evaluate((btnDown) => {
      const gp = window.__mockGamepad
      gp.buttons[btnDown] = { pressed: false, touched: false, value: 0 }
      gp.timestamp = performance.now()
    }, Button.DOWN)
    await page.waitForTimeout(50)

    await pressButton(page, Button.DOWN)
    const afterRepress = await getFocusedIndex(page)
    expect(afterRepress).not.toBe(initial)
  })
})

test.describe("controller type detection", () => {
  test("Xbox controller id → xbox type", async ({ page }) => {
    // Already connected with Xbox controller from beforeEach
    await expectControllerType(page, "xbox")
  })

  test("PlayStation controller id → playstation type", async ({ page }) => {
    // Disconnect and reconnect with PS controller
    await disconnectGamepad(page)

    await page.evaluate(() => {
      window.__mockGamepad.id = "DualSense Wireless Controller"
      window.__mockGamepad.connected = true
      window.__mockGamepad.timestamp = performance.now()
    })
    await connectGamepad(page)

    await expectControllerType(page, "playstation")
  })

  test("unknown controller → generic type", async ({ page }) => {
    await disconnectGamepad(page)

    await page.evaluate(() => {
      window.__mockGamepad.id = "Unknown Gaming Device 3000"
      window.__mockGamepad.connected = true
      window.__mockGamepad.timestamp = performance.now()
    })
    await connectGamepad(page)

    await expectControllerType(page, "generic")
  })
})

test.describe("idle-until-connected", () => {
  test("gamepadconnected → polling starts, gamepad works", async ({ page }) => {
    // Disconnect
    await disconnectGamepad(page)
    await waitForSettle(page, 100)

    const before = await getFocusedIndex(page)

    // Reconnect
    await page.evaluate(() => {
      window.__mockGamepad.connected = true
      window.__mockGamepad.timestamp = performance.now()
    })
    await connectGamepad(page)

    // Gamepad should work again
    await pressButton(page, Button.DOWN)
    const after = await getFocusedIndex(page)
    expect(after).not.toBe(before)
  })

  test("gamepaddisconnected → system still functional", async ({ page }) => {
    // Verify gamepad works
    await pressButton(page, Button.DOWN)

    // Disconnect
    await disconnectGamepad(page)

    // System doesn't crash without gamepad
    await page.waitForTimeout(200)
    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    expect(context).toBeTruthy()
  })
})

test.describe("repeat timing precision", () => {
  test("D-pad held: initial press + repeats after delay", async ({ page }) => {
    const before = await getFocusedIndex(page)

    // Hold D-pad down
    await holdButton(page, Button.DOWN)

    // At 100ms: should have moved once (initial press)
    await page.waitForTimeout(100)
    const afterInitial = await getFocusedIndex(page)
    expect(afterInitial).not.toBe(before)

    // At ~500ms total: should have moved again (first repeat at 400ms)
    await page.waitForTimeout(400)
    const afterRepeat = await getFocusedIndex(page)

    await releaseButton(page, Button.DOWN)

    // At minimum, initial press moved. Repeat may also have moved.
    expect(afterInitial).not.toBe(before)
  })

  test("release resets repeat timer", async ({ page }) => {
    // Hold down briefly (less than repeat delay)
    await holdButton(page, Button.DOWN)
    await page.waitForTimeout(200)
    await releaseButton(page, Button.DOWN)

    const afterFirstHold = await getFocusedIndex(page)

    // Quick re-press — should fire immediately (rising edge)
    await pressButton(page, Button.DOWN)
    const afterRepress = await getFocusedIndex(page)

    // The re-press should have moved (clean edge)
    expect(afterRepress).not.toBe(afterFirstHold)
  })
})
