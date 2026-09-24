// @ts-check
import { defineConfig } from "@playwright/test"

// The suite owns its server. It used to default to 2160 — the dev daily
// driver, backed by the owner's real library — which made it destructive to
// run, impossible to gate, and therefore free to rot. scripts/e2e-server boots
// a seeded, fixture-stubbed instance on its own port and database instead.
const BASE_URL = process.env.BASE_URL ?? "http://127.0.0.1:49001"

const CROSS_BROWSER = "cross-browser.spec.js"
const CLICK_VIEWPORT = { width: 1600, height: 1000 }

export default defineConfig({
  testDir: ".",
  testMatch: "*.spec.js",
  timeout: 30_000,
  expect: { timeout: 5_000 },
  retries: 0,
  workers: 1, // serial — tests share a dev server
  reporter: "list",

  // Boot the instance unless one is already up (CI always boots its own).
  // The generous timeout covers a cold build root; warm it once by hand with
  // `scripts/e2e-server` if a first run ever trips it.
  webServer: {
    command: "../../scripts/e2e-server",
    url: BASE_URL,
    reuseExistingServer: !process.env.CI,
    timeout: 180_000,
    stdout: "pipe",
    stderr: "pipe",
  },

  use: {
    baseURL: BASE_URL,
    // Pin the emulated window.screen: the shell auto-scales itself from
    // screen.width against the 1920px reference (root.html.heex), and the
    // tiny default headless screen would floor that at 0.7× — shifting
    // every layout the nav tests assert geometry against. A 1080p screen
    // means auto-scale 1, i.e. the reference composition.
    screen: { width: 1920, height: 1080 },
    trace: "retain-on-failure",
    video: "retain-on-failure",
    actionTimeout: 5_000,
  },

  projects: [
    // The navigation suite: Chromium, once per input method.
    { name: "keyboard", testIgnore: CROSS_BROWSER, use: { inputMethod: "keyboard" } },
    { name: "gamepad", testIgnore: CROSS_BROWSER, use: { inputMethod: "gamepad" } },

    // Equal support, not equal verification — see cross-browser.spec.js. It
    // runs in Chromium too, as the control: an assertion that only ever runs
    // where it passes is not a test.
    //
    // These are the only specs that click, so they are the only ones that need
    // a viewport as wide as the composition `screen` above claims. At
    // Playwright's 1280 default the sidebar overlaps the grid's first column
    // and intercepts the pointer.
    { name: "cross-browser-chromium", testMatch: CROSS_BROWSER, use: { browserName: "chromium", viewport: CLICK_VIEWPORT } },
    { name: "cross-browser-firefox", testMatch: CROSS_BROWSER, use: { browserName: "firefox", viewport: CLICK_VIEWPORT } },
  ],
})
