import { describe, test, expect, afterEach } from "bun:test"
import { createDomReader } from "../dom_adapter.js"

const reader = createDomReader()

// createDomReader reads the global `document` lazily inside each method, so we
// can stub it per-test. bun's test env has no DOM, so every test that calls
// hasForeignFocus must install (and restore) a fake document.
let restore = () => {}
afterEach(() => restore())

function stubDocument({ activeElement, body = {}, documentElement = {} }) {
  const real = globalThis.document
  globalThis.document = { activeElement, body, documentElement }
  restore = () => { globalThis.document = real }
}

// A focusable element whose closest() reports whether it sits inside a managed
// nav region and/or a key-capturing region — the only DOM facts the predicate
// consults.
function fakeElement({ navManaged = false, capturesKeys = false } = {}) {
  return {
    closest(selector) {
      if (selector === "[data-captures-keys]") return capturesKeys ? this : null
      if (selector.includes("data-nav-item")) return navManaged ? this : null
      return null
    },
  }
}

describe("hasForeignFocus — focus ownership by containment", () => {
  test("no active element → not foreign (focus genuinely absent)", () => {
    stubDocument({ activeElement: null })
    expect(reader.hasForeignFocus()).toBe(false)
  })

  test("<body> focused → not foreign (a patch dropped focus; system owns the recovery)", () => {
    const body = {}
    stubDocument({ activeElement: body, body })
    expect(reader.hasForeignFocus()).toBe(false)
  })

  test("<html> focused → not foreign", () => {
    const documentElement = {}
    stubDocument({ activeElement: documentElement, documentElement })
    expect(reader.hasForeignFocus()).toBe(false)
  })

  test("a managed nav item (inside a nav zone) → not foreign", () => {
    stubDocument({ activeElement: fakeElement({ navManaged: true }) })
    expect(reader.hasForeignFocus()).toBe(false)
  })

  test("an element outside all managed regions (an unmanaged overlay's input or button) → foreign", () => {
    stubDocument({ activeElement: fakeElement({ navManaged: false }) })
    expect(reader.hasForeignFocus()).toBe(true)
  })

  test("a key-capturing element → foreign even if it sits inside a nav region", () => {
    stubDocument({ activeElement: fakeElement({ navManaged: true, capturesKeys: true }) })
    expect(reader.hasForeignFocus()).toBe(true)
  })
})
