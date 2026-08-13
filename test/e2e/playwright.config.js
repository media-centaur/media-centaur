// @ts-check
import { defineConfig } from "@playwright/test"

const BASE_URL = process.env.BASE_URL ?? "http://127.0.0.1:2160"

export default defineConfig({
  testDir: ".",
  testMatch: "*.spec.js",
  timeout: 30_000,
  expect: { timeout: 5_000 },
  retries: 0,
  workers: 1, // serial — tests share a dev server
  reporter: "list",

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
    { name: "keyboard", use: { inputMethod: "keyboard" } },
    { name: "gamepad", use: { inputMethod: "gamepad" } },
  ],
})
