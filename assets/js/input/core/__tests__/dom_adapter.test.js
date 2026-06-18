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

// ---------------------------------------------------------------------------
// Modal item scoping — stacked [data-detail-mode='modal'] overlays.
//
// A confirm dialog can render *over* a detail modal (downloads: the
// cancel-download confirm stacks on the pursuit modal). The adapter already
// resolves the *active* modal as the first [data-detail-mode='modal'] match
// for detailView and dismissEvent; item queries must use the same owner, or
// MODAL navigation would walk the union of both overlays' items — including
// ones hidden behind the topmost backdrop.
// ---------------------------------------------------------------------------

import { createDomWriter } from "../dom_adapter.js"

const MODAL_ITEM_SELECTOR = "[data-detail-mode='modal'] [data-nav-item]"
const SCOPED_CONFIG = {
  contextSelectors: {
    modal: MODAL_ITEM_SELECTOR,
    sidebar: "[data-nav-zone='sidebar'] [data-nav-item]",
  },
}

function fakeNavItem(label) {
  return {
    label,
    dataset: {},
    hasAttribute(name) { return name === "data-nav-item" },
    checkVisibility() { return true },
    focus() { globalThis.document.activeElement = this },
    scrollIntoView() {},
  }
}

function fakeModalElement(items) {
  return {
    querySelectorAll(selector) {
      return selector === "[data-nav-item]" ? items : []
    },
  }
}

/**
 * Stub a document holding `modals` (in DOM order) plus unrelated sidebar
 * items, mimicking querySelector's first-match and querySelectorAll's
 * document-order union semantics.
 */
function stubModalDocument({ modals = [], sidebarItems = [] } = {}) {
  const real = globalThis.document
  globalThis.document = {
    activeElement: null,
    body: {},
    documentElement: {},
    querySelector(selector) {
      if (selector === "[data-detail-mode='modal']") return modals[0] ?? null
      return this.querySelectorAll(selector)[0] ?? null
    },
    querySelectorAll(selector) {
      if (selector === MODAL_ITEM_SELECTOR) {
        return modals.flatMap(modal => Array.from(modal.querySelectorAll("[data-nav-item]")))
      }
      if (selector === "[data-nav-zone='sidebar'] [data-nav-item]") return sidebarItems
      return []
    },
  }
  restore = () => { globalThis.document = real }
}

describe("modal item scoping (reader)", () => {
  const scopedReader = createDomReader(SCOPED_CONFIG)

  test("single open modal → items come from it", () => {
    const items = [fakeNavItem("close"), fakeNavItem("cancel")]
    stubModalDocument({ modals: [fakeModalElement(items)] })
    expect(scopedReader.getItemCount("modal")).toBe(2)
    expect(scopedReader.getItemAt("modal", 1)).toBe(items[1])
  })

  test("stacked modals → only the active (first-match) modal's items count", () => {
    const confirmItems = [fakeNavItem("keep"), fakeNavItem("confirm")]
    const detailItems = [fakeNavItem("a"), fakeNavItem("b"), fakeNavItem("c")]
    stubModalDocument({ modals: [fakeModalElement(confirmItems), fakeModalElement(detailItems)] })
    expect(scopedReader.getItemCount("modal")).toBe(2)
    expect(scopedReader.getItemAt("modal", 0)).toBe(confirmItems[0])
    expect(scopedReader.getItemAt("modal", 2)).toBeNull()
  })

  test("focused item inside the active modal → its scoped index", () => {
    const confirmItems = [fakeNavItem("keep"), fakeNavItem("confirm")]
    stubModalDocument({ modals: [fakeModalElement(confirmItems), fakeModalElement([fakeNavItem("hidden")])] })
    globalThis.document.activeElement = confirmItems[1]
    expect(scopedReader.getFocusedIndex("modal")).toBe(1)
  })

  test("focused item inside the covered modal → -1 (not in scope)", () => {
    const hiddenItem = fakeNavItem("hidden")
    stubModalDocument({ modals: [fakeModalElement([fakeNavItem("keep")]), fakeModalElement([hiddenItem])] })
    globalThis.document.activeElement = hiddenItem
    expect(scopedReader.getFocusedIndex("modal")).toBe(-1)
  })

  test("no modal open → zero items", () => {
    stubModalDocument({ modals: [] })
    expect(scopedReader.getItemCount("modal")).toBe(0)
    expect(scopedReader.getItemAt("modal", 0)).toBeNull()
  })

  test("non-modal contexts keep the flat config selector", () => {
    const sidebarItems = [fakeNavItem("home"), fakeNavItem("library")]
    stubModalDocument({ modals: [fakeModalElement([fakeNavItem("x")])], sidebarItems })
    expect(scopedReader.getItemCount("sidebar")).toBe(2)
  })
})

describe("modal item scoping (writer)", () => {
  const scopedWriter = createDomWriter(SCOPED_CONFIG)

  test("focusFirst lands on the active modal's first item, not the covered modal's", () => {
    const confirmItems = [fakeNavItem("keep"), fakeNavItem("confirm")]
    const detailItems = [fakeNavItem("a")]
    stubModalDocument({ modals: [fakeModalElement(confirmItems), fakeModalElement(detailItems)] })
    expect(scopedWriter.focusFirst("modal")).toBe(true)
    expect(globalThis.document.activeElement).toBe(confirmItems[0])
  })

  test("focusByIndex resolves within the active modal only", () => {
    const confirmItems = [fakeNavItem("keep"), fakeNavItem("confirm")]
    stubModalDocument({ modals: [fakeModalElement(confirmItems), fakeModalElement([fakeNavItem("hidden")])] })
    expect(scopedWriter.focusByIndex("modal", 1)).toBe(true)
    expect(globalThis.document.activeElement).toBe(confirmItems[1])
    expect(scopedWriter.focusByIndex("modal", 2)).toBe(false)
  })
})

// ---------------------------------------------------------------------------
// Non-focusable item filtering — a disabled control (e.g. a form's submit
// button that's disabled until the field is valid) is never a nav target. A
// browser refuses to focus it, so if the adapter included it in the item set
// the orchestrator would call focusByIndex, fail, and the cursor would jam on
// the item before it — unable to step past to later items. queryContextItems
// is the single chokepoint feeding count/index/focus, so it filters there.
// ---------------------------------------------------------------------------

const GRID_SELECTOR = "[data-nav-zone='grid'] [data-nav-item]"
const GRID_CONFIG = { contextSelectors: { grid: GRID_SELECTOR } }

function fakeGridItem(label, { disabled = false, hidden = false } = {}) {
  return {
    label,
    disabled,
    dataset: {},
    hasAttribute(name) {
      if (name === "data-nav-item") return true
      if (name === "disabled") return disabled
      return false
    },
    // Mirrors Element.checkVisibility(): false for an item that is rendered in
    // the DOM but not actually visible — notably a control inside a collapsed
    // <details> (the browser hides the content via content-visibility, so it
    // still matches querySelectorAll and has client rects, yet cannot be
    // focused). focus() is a no-op on such an element in a real browser.
    checkVisibility() { return !hidden },
    focus() { if (!hidden) globalThis.document.activeElement = this },
    scrollIntoView() {},
  }
}

function stubGridDocument(items) {
  const real = globalThis.document
  globalThis.document = {
    activeElement: null,
    body: {},
    documentElement: {},
    querySelector(selector) { return this.querySelectorAll(selector)[0] ?? null },
    querySelectorAll(selector) { return selector === GRID_SELECTOR ? items : [] },
  }
  restore = () => { globalThis.document = real }
}

describe("non-focusable item filtering", () => {
  const gridReader = createDomReader(GRID_CONFIG)
  const gridWriter = createDomWriter(GRID_CONFIG)

  test("disabled items are excluded from the count", () => {
    stubGridDocument([
      fakeGridItem("a"),
      fakeGridItem("b", { disabled: true }),
      fakeGridItem("c"),
    ])
    expect(gridReader.getItemCount("grid")).toBe(2)
  })

  test("indexing skips the disabled item (c is index 1, not 2)", () => {
    const items = [fakeGridItem("a"), fakeGridItem("b", { disabled: true }), fakeGridItem("c")]
    stubGridDocument(items)
    expect(gridReader.getItemAt("grid", 1)).toBe(items[2])
  })

  test("focusByIndex lands on the next focusable item, not the disabled one", () => {
    const items = [fakeGridItem("a"), fakeGridItem("b", { disabled: true }), fakeGridItem("c")]
    stubGridDocument(items)
    expect(gridWriter.focusByIndex("grid", 1)).toBe(true)
    expect(globalThis.document.activeElement).toBe(items[2])
  })

  test("a disabled item between focusables doesn't jam the focused index", () => {
    const items = [fakeGridItem("a"), fakeGridItem("b", { disabled: true }), fakeGridItem("c")]
    stubGridDocument(items)
    globalThis.document.activeElement = items[2]
    expect(gridReader.getFocusedIndex("grid")).toBe(1)
  })

  // Regression: the Settings → System "Prefer the terminal?" disclosure wraps
  // its Copy buttons (data-nav-item) in a collapsed <details>. They match the
  // grid selector and have client rects, but the browser refuses to focus
  // content inside a closed <details> — so before they were filtered, the
  // cursor jammed on the wall of hidden items and could not reach the "Update
  // now" button on the other side of them. Visibility must be filtered at the
  // same chokepoint as disabled, so count/index/focus all agree.
  test("hidden items (inside a collapsed <details>) are excluded from the count", () => {
    stubGridDocument([
      fakeGridItem("update-now"),
      fakeGridItem("copy", { hidden: true }),
      fakeGridItem("restart"),
    ])
    expect(gridReader.getItemCount("grid")).toBe(2)
  })

  test("indexing skips the hidden item (restart is index 1, not 2)", () => {
    const items = [fakeGridItem("update-now"), fakeGridItem("copy", { hidden: true }), fakeGridItem("restart")]
    stubGridDocument(items)
    expect(gridReader.getItemAt("grid", 1)).toBe(items[2])
  })

  test("focusByIndex steps over a wall of hidden items to the next visible one", () => {
    const items = [
      fakeGridItem("update-now"),
      fakeGridItem("copy-1", { hidden: true }),
      fakeGridItem("copy-2", { hidden: true }),
      fakeGridItem("restart"),
    ]
    stubGridDocument(items)
    expect(gridWriter.focusByIndex("grid", 1)).toBe(true)
    expect(globalThis.document.activeElement).toBe(items[3])
  })

  test("a hidden item between focusables doesn't jam the focused index", () => {
    const items = [fakeGridItem("update-now"), fakeGridItem("copy", { hidden: true }), fakeGridItem("restart")]
    stubGridDocument(items)
    globalThis.document.activeElement = items[2]
    expect(gridReader.getFocusedIndex("grid")).toBe(1)
  })
})
