// Separate Playwright config for the screenshot tour. Isolated from
// playwright.config.js so:
//   1. Screenshot captures aren't duplicated across keyboard + gamepad projects.
//   2. `mix test` / scripts/input-test don't accidentally pick up tour files.
//
// Invoked by scripts/screenshot-tour.
//
// Two projects run the same tour at different pixel densities:
//   - `web`    — deviceScaleFactor 1, writes to docs-site/assets/screenshots/.
//   - `hires`  — deviceScaleFactor ≈2.057 (2880px wide, 3/4 of UHD),
//                writes to docs-site/assets/screenshots/4k/ (legacy path,
//                still served from the assets repo via jsDelivr).
//
// The hi-res variant supersamples the exact same layout (viewport stays
// at 1400×900 logical pixels), so text, icons, and borders render crisply
// enough for click-to-zoom linkouts from the marketing site and wiki.
// Full UHD was overkill — 2880px wide is sharp on every common display
// while keeping the assets repo and jsDelivr payload reasonable.
const { defineConfig } = require("@playwright/test")

// Defaults to 4003 (showcase override), since this tour is only meant
// to run against seeded showcase data — pointing it at dev (1080) or
// prod (2160) would capture personal library content.
const BASE_URL = process.env.BASE_URL || "http://127.0.0.1:4003"

// 1400 × (2880/1400) = 2880 — three-quarters of UHD width.
const HIRES_SCALE = 2880 / 1400

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
      use: { ...sharedUse, deviceScaleFactor: HIRES_SCALE },
      metadata: { outSubdir: "4k" },
    },
  ],
})
