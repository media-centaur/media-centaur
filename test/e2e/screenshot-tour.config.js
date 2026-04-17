// Separate Playwright config for the screenshot tour. Isolated from
// playwright.config.js so:
//   1. Screenshot captures aren't duplicated across keyboard + gamepad projects.
//   2. `mix test` / scripts/input-test don't accidentally pick up tour files.
//
// Invoked by scripts/screenshot-tour.
const { defineConfig } = require("@playwright/test")

// Defaults to 4003 (showcase override), since this tour is only meant
// to run against seeded showcase data — pointing it at dev (1080) or
// prod (2160) would capture personal library content.
const BASE_URL = process.env.BASE_URL || "http://127.0.0.1:4003"

module.exports = defineConfig({
  testDir: ".",
  testMatch: "*.tour.js",
  // Generous timeout — we wait for LiveView mount + network idle at each stop.
  timeout: 60_000,
  expect: { timeout: 10_000 },
  retries: 0,
  workers: 1,
  reporter: "list",

  use: {
    baseURL: BASE_URL,
    viewport: { width: 1400, height: 900 },
    actionTimeout: 10_000,
    // No trace/video needed — screenshots are the artefact.
    trace: "off",
    video: "off",
    // Force XWayland + set WM_CLASS so Hyprland can match a single
    // surgical rule against this specific browser instance without
    // touching the user's other Chromium windows. On native Wayland
    // (Ozone), Chromium derives app_id from the URL and ignores
    // --class; XWayland honours --class reliably.
    launchOptions: {
      args: ["--ozone-platform=x11", "--class=media-centarr"],
    },
  },
})
