/**
 * LiveView wait helpers for E2E tests.
 *
 * These functions handle the async nature of LiveView — waiting for
 * WebSocket connection, DOM settling after patches, and stream items.
 */

/**
 * Wait for LiveView to connect (phx-connected class on root).
 * @param {import("@playwright/test").Page} page
 */
export async function waitForLiveView(page) {
  await page.locator("[data-phx-main]").waitFor({ state: "attached" })
  await page.locator("[data-phx-main].phx-connected").waitFor({ state: "attached" })
}

/**
 * Wait for the input system hook to mount.
 * The hook sets data-nav-context on <html> once the orchestrator starts.
 * @param {import("@playwright/test").Page} page
 */
export async function waitForInputSystem(page) {
  await page.locator("html[data-nav-context]").waitFor({ state: "attached" })
}

/**
 * Wait for grid items to appear in the DOM.
 * @param {import("@playwright/test").Page} page
 * @param {object} [opts]
 * @param {number} [opts.min=1] - Minimum number of items to wait for
 */
export async function waitForGridItems(page, { min = 1 } = {}) {
  await page.locator("[data-nav-zone='grid'] [data-nav-item]").nth(min - 1).waitFor({ state: "attached" })
}

/**
 * Wait for section items to appear.
 * @param {import("@playwright/test").Page} page
 * @param {object} [opts]
 * @param {number} [opts.min=1]
 */
export async function waitForSections(page, { min = 1 } = {}) {
  await page.locator("[data-nav-zone='sections'] [data-nav-item]").nth(min - 1).waitFor({ state: "attached" })
}

/**
 * Wait for review list items to appear.
 * @param {import("@playwright/test").Page} page
 * @param {object} [opts]
 * @param {number} [opts.min=1]
 */
export async function waitForReviewItems(page, { min = 1 } = {}) {
  await page.locator("[data-nav-zone='review-list'] [data-nav-item]").nth(min - 1).waitFor({ state: "attached" })
}

/**
 * Wait for a short period after an action to let LiveView settle.
 * Use sparingly — prefer explicit waitFor conditions.
 * @param {import("@playwright/test").Page} page
 * @param {number} [ms=100]
 */
export async function waitForSettle(page, ms = 100) {
  await page.waitForTimeout(ms)
}

/**
 * Navigate to a page and wait for LiveView + input system to be ready.
 * @param {import("@playwright/test").Page} page
 * @param {string} path - URL path (e.g., "/", "/status")
 */
export async function navigateAndWait(page, path) {
  await page.goto(path)
  await waitForLiveView(page)
  await waitForInputSystem(page)
}
