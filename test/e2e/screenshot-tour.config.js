// Separate Playwright config for the screenshot tour. Isolated from
// playwright.config.js so:
//   1. Screenshot captures aren't duplicated across keyboard + gamepad projects.
//   2. `mix test` / scripts/input-test don't accidentally pick up tour files.
//
// Invoked by scripts/screenshot-tour.
const { defineConfig } = require("@playwright/test")

const BASE_URL = process.env.BASE_URL || "http://127.0.0.1:4001"

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
  },
})
