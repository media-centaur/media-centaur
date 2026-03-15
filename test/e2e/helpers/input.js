/**
 * Input system assertion and inspection helpers.
 *
 * Provides auto-retrying assertions (via Playwright expect) for focus state,
 * input context, and input method. Also has debug toggle helpers.
 */
import { expect } from "@playwright/test"

/**
 * Assert that a specific element is focused.
 * @param {import("@playwright/test").Page} page
 * @param {string} selector - CSS selector for the expected focused element
 */
export async function expectFocused(page, selector) {
  await expect(page.locator(selector)).toBeFocused()
}

/**
 * Assert the current navigation context.
 * Reads data-nav-context from <html>.
 * @param {import("@playwright/test").Page} page
 * @param {string} context - Expected context value (e.g., "grid", "sidebar")
 */
export async function expectContext(page, context) {
  await expect(page.locator("html")).toHaveAttribute("data-nav-context", context)
}

/**
 * Assert the current input method.
 * Reads data-input from <html>.
 * @param {import("@playwright/test").Page} page
 * @param {string} method - Expected value: "keyboard", "mouse", or "gamepad"
 */
export async function expectInputMethod(page, method) {
  await expect(page.locator("html")).toHaveAttribute("data-input", method)
}

/**
 * Assert the gamepad controller type.
 * @param {import("@playwright/test").Page} page
 * @param {string} type - Expected value: "xbox", "playstation", or "generic"
 */
export async function expectControllerType(page, type) {
  await expect(page.locator("html")).toHaveAttribute("data-gamepad-type", type)
}

/**
 * Get a unique identifier for the currently focused nav item.
 * Returns data-nav-item value if present, data-entity-id if present,
 * otherwise the element's index within its zone. Returns null if
 * nothing with data-nav-item is focused.
 * @param {import("@playwright/test").Page} page
 * @returns {Promise<string|null>}
 */
export async function getFocusedNavItem(page) {
  return page.evaluate(() => {
    const el = document.activeElement
    if (!el?.hasAttribute("data-nav-item")) return null

    // Prefer explicit attribute values for identity
    const navItem = el.getAttribute("data-nav-item")
    if (navItem) return navItem
    const entityId = el.getAttribute("data-entity-id")
    if (entityId) return entityId

    // Fall back to index within zone
    const zone = el.closest("[data-nav-zone]")
    if (!zone) return "unknown-0"
    const items = zone.querySelectorAll("[data-nav-item]")
    for (let i = 0; i < items.length; i++) {
      if (items[i] === el) return `item-${i}`
    }
    return "unknown-0"
  })
}

/**
 * Get the index of the currently focused nav item within its zone.
 * Returns -1 if nothing is focused.
 * @param {import("@playwright/test").Page} page
 * @returns {Promise<number>}
 */
export async function getFocusedIndex(page) {
  return page.evaluate(() => {
    const el = document.activeElement
    if (!el?.hasAttribute("data-nav-item")) return -1
    const zone = el.closest("[data-nav-zone]")
    if (!zone) return -1
    const items = zone.querySelectorAll("[data-nav-item]")
    for (let i = 0; i < items.length; i++) {
      if (items[i] === el) return i
    }
    return -1
  })
}

/**
 * Get the current navigation context from <html>.
 * @param {import("@playwright/test").Page} page
 * @returns {Promise<string|null>}
 */
export async function getInputContext(page) {
  return page.evaluate(() => document.documentElement.getAttribute("data-nav-context"))
}

/**
 * Get the current input method from <html>.
 * @param {import("@playwright/test").Page} page
 * @returns {Promise<string|null>}
 */
export async function getInputMethod(page) {
  return page.evaluate(() => document.documentElement.getAttribute("data-input"))
}

/**
 * Enable input system debug logging.
 * @param {import("@playwright/test").Page} page
 */
export async function enableInputDebug(page) {
  await page.evaluate(() => { window.__inputDebug = true })
}

/**
 * Disable input system debug logging.
 * @param {import("@playwright/test").Page} page
 */
export async function disableInputDebug(page) {
  await page.evaluate(() => { window.__inputDebug = false })
}

/**
 * Get all input debug messages from console.
 * Must have collected console messages via page.on("console", ...).
 * @param {string[]} messages - Collected console message texts
 * @returns {string[]} Messages that start with [input]
 */
export function filterDebugMessages(messages) {
  return messages.filter((m) => m.startsWith("[input]"))
}

/**
 * Count items in a navigation zone.
 * @param {import("@playwright/test").Page} page
 * @param {string} zone - Zone name (e.g., "grid", "sidebar", "sections")
 * @returns {Promise<number>}
 */
export async function getZoneItemCount(page, zone) {
  return page.locator(`[data-nav-zone='${zone}'] [data-nav-item]`).count()
}

/**
 * Assert that focus is within a specific zone.
 * @param {import("@playwright/test").Page} page
 * @param {string} zone - Zone name
 */
export async function expectFocusInZone(page, zone) {
  const focused = page.locator(`[data-nav-zone='${zone}'] [data-nav-item]:focus`)
  await expect(focused).toBeVisible()
}

/**
 * Ensure a nav item has DOM focus in the current context.
 *
 * The input system sets data-nav-context on start but doesn't always focus
 * a DOM element (when the default context has items, _ensureCursorStart
 * returns early). The first action would just focus the first item rather
 * than performing navigation. This helper establishes DOM focus so tests
 * can send actions that navigate immediately.
 *
 * @param {import("@playwright/test").Page} page
 */
export async function establishFocus(page) {
  const focused = await page.evaluate(() => {
    if (document.activeElement?.hasAttribute("data-nav-item")) return true

    const ctx = document.documentElement.getAttribute("data-nav-context") || "grid"
    // Map context names to zone selectors
    const item = document.querySelector(`[data-nav-zone='${ctx}'] [data-nav-item]`)
      || document.querySelector("[data-nav-zone] [data-nav-item]")
    if (item) {
      item.focus()
      return true
    }
    return false
  })
  if (focused) await page.waitForTimeout(30)
}
