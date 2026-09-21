import { describe, expect, test, afterEach } from "bun:test"
import {
  installGlobal,
  installWindow,
  installMutationObserver,
  installSyncAnimationFrame,
  restoreGlobals,
} from "./dom_stubs"

// Bun runs every test file in one process, in whatever order the filesystem
// hands it the files. A global a test installs and never puts back is seen by
// every file loaded after it — on the GitHub runner that turned `URL` into a
// plain object for nav_reselect.test.js and made uPlot believe it had a
// window (2026-09-17 to 2026-09-21, CI red on every push).
describe("restoreGlobals", () => {
  afterEach(restoreGlobals)

  test("puts back what installWindow replaced — no window where there was none", () => {
    expect(typeof window).toBe("undefined")
    installWindow()
    expect(typeof window).toBe("object")

    restoreGlobals()

    expect(typeof window).toBe("undefined")
  })

  test("restores a replaced constructor to the native one", () => {
    const nativeUrl = globalThis.URL
    installGlobal("URL", { createObjectURL: () => "blob:stub" })
    expect(globalThis.URL).not.toBe(nativeUrl)

    restoreGlobals()

    expect(globalThis.URL).toBe(nativeUrl)
    expect(new URL("/a", "http://localhost/").pathname).toBe("/a")
  })

  test("undoes every installer, in one call, and is safe to call twice", () => {
    installMutationObserver()
    installSyncAnimationFrame()
    installWindow()

    restoreGlobals()
    restoreGlobals()

    expect(typeof MutationObserver).toBe("undefined")
    expect(typeof requestAnimationFrame).toBe("undefined")
    expect(typeof window).toBe("undefined")
  })

  test("a global replaced twice goes back to the original, not the first stub", () => {
    const nativeUrl = globalThis.URL
    installGlobal("URL", "first")
    installGlobal("URL", "second")

    restoreGlobals()

    expect(globalThis.URL).toBe(nativeUrl)
  })
})
