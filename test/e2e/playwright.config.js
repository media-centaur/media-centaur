// @ts-check
import { defineConfig } from "@playwright/test"

const BASE_URL = process.env.BASE_URL ?? "http://127.0.0.1:4001"

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
    trace: "retain-on-failure",
    video: "retain-on-failure",
    actionTimeout: 5_000,
  },

  projects: [
    { name: "keyboard", use: { inputMethod: "keyboard" } },
    { name: "gamepad", use: { inputMethod: "gamepad" } },
  ],
})
