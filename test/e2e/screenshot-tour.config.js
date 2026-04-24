// Separate Playwright config for the screenshot tour. Isolated from
// playwright.config.js so:
//   1. Screenshot captures aren't duplicated across keyboard + gamepad projects.
//   2. `mix test` / scripts/input-test don't accidentally pick up tour files.
//
// Invoked by scripts/screenshot-tour.
//
// Two projects run the same tour at different pixel densities:
//   - `web` — deviceScaleFactor 1, writes to docs-site/assets/screenshots/.
//   - `4k`  — deviceScaleFactor 2.7428571 (≈3840px wide),
//             writes to docs-site/assets/screenshots/4k/.
//
// The 4K variant supersamples the exact same layout (viewport stays at
// 1400×900 logical pixels), so text, icons, and borders render crisply
// enough for click-to-zoom linkouts from the marketing site and wiki.
const { defineConfig } = require("@playwright/test")

// Defaults to 4003 (showcase override), since this tour is only meant
// to run against seeded showcase data — pointing it at dev (1080) or
// prod (2160) would capture personal library content.
const BASE_URL = process.env.BASE_URL || "http://127.0.0.1:4003"

// 1400 × 2.7428571 = 3840 — the horizontal UHD target.
const FOUR_K_SCALE = 3840 / 1400

const sharedUse = {
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
}

module.exports = defineConfig({
  testDir: ".",
  testMatch: "*.tour.js",
  // Generous timeout — we wait for LiveView mount + network idle at each stop.
  timeout: 60_000,
  expect: { timeout: 10_000 },
  retries: 0,
  workers: 1,
  reporter: "list",

  projects: [
    {
      name: "web",
      use: { ...sharedUse, deviceScaleFactor: 1 },
      metadata: { outSubdir: "" },
    },
    {
      name: "4k",
      use: { ...sharedUse, deviceScaleFactor: FOUR_K_SCALE },
      metadata: { outSubdir: "4k" },
    },
  ],
})
