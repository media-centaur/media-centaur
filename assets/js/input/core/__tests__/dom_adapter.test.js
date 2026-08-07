import { describe, test, expect, afterEach, beforeEach } from "bun:test"
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
// for detailNested and dismissEvent; item queries must use the same owner, or
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
    scrollIntoView(options) { this.scrolledWith = options },
    getBoundingClientRect() {
      return { x: 0, y: 0, width: 10, height: 10, top: 0, left: 0, right: 10, bottom: 10 }
    },
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

// "Make the focused item visible" is one decision, so it has one owner and one
// implementation. Four writer entry points reach it; none may answer the
// question differently, and none may leave the item to CSS to place (a
// scroll-snap container silently overrides scrollIntoView and parks the
// focused card partly outside the scrollport).
describe("reveal — a single owner for making the focused item visible", () => {
  // Reveal works by scrolling instantly to learn the destination, restoring
  // the offsets, and handing that destination to the glide. So the assertion
  // that matters is what the glide was ASKED for, and that the page was left
  // where it started for the animation to run from.
  let glided
  let root

  function writerWithFakeGlide() {
    glided = []
    return createDomWriter({
      ...GRID_CONFIG,
      glider: { glide: (box, target) => glided.push({ box, target }) },
    })
  }

  function stubScrollingDocument(items, { clientHeight = 1000 } = {}) {
    stubGridDocument(items)
    globalThis.document.documentElement = { clientHeight }
    // The one scroll container in play: no item has a parentElement, so the
    // ancestor walk finds nothing and stops at the scrolling root.
    root = {
      scrollLeft: 120,
      scrollTop: 40,
      // scrollIntoView is stubbed on the items, so nothing actually moves the
      // root; the recorded destination is therefore its current offset. That
      // is enough to pin the contract — measure, restore, glide.
    }
    globalThis.document.scrollingElement = root
  }

  // A pinned ancestor (position: sticky/fixed) decouples the item from every
  // scroller outside it — scrolling one moves the item too, so scrollIntoView
  // has no fixed point to reach and each call asks for a little more. Measured
  // in the detail modal, whose action row lives in a sticky block: walking
  // left/right along Play / More info / Manage ratcheted the panel
  // 123 -> 325 -> 527 -> 729px, in BOTH directions, never coming back.
  describe("items pinned by a sticky or fixed ancestor", () => {
    function pinnedItem(position) {
      const item = fakeGridItem("pinned")
      const box = { scrollLeft: 0, scrollTop: 300, scrollHeight: 2000, clientHeight: 500 }
      const pin = { parentElement: box, __style: { position, overflowX: "visible", overflowY: "visible" } }
      box.__style = { position: "relative", overflowX: "hidden", overflowY: "auto" }
      box.parentElement = null
      item.parentElement = pin
      return { item, box }
    }

    let realComputed
    beforeEach(() => {
      realComputed = globalThis.getComputedStyle
      globalThis.getComputedStyle = node => node.__style ?? { position: "static", overflowX: "visible", overflowY: "visible" }
    })
    afterEach(() => { globalThis.getComputedStyle = realComputed })

    test.each([["sticky"], ["fixed"]])("a %s ancestor means there is nothing to reveal", (position) => {
      const writer = writerWithFakeGlide()
      const { item, box } = pinnedItem(position)
      stubScrollingDocument([item])

      writer.focusFirst("grid")

      // Focus still moves instantly — only the scroll is skipped.
      expect(globalThis.document.activeElement).toBe(item)
      expect(item.scrolledWith).toBeUndefined()
      expect(glided).toEqual([])
      expect(box.scrollTop).toBe(300)
    })
  })

  test("focusByIndex glides toward where the item would have landed", () => {
    const writer = writerWithFakeGlide()
    const items = [fakeGridItem("a"), fakeGridItem("b")]
    stubScrollingDocument(items)

    writer.focusByIndex("grid", 1)

    expect(globalThis.document.activeElement).toBe(items[1])
    expect(glided.length).toBe(1)
    expect(glided[0].box).toBe(root)
    expect(glided[0].target).toEqual({ left: 120, top: 40 })
  })

  test("the measuring jump is instant and is undone before the glide runs", () => {
    // "instant" here is load-bearing in the opposite direction from usual: it
    // must NOT be smooth, because this scroll exists only to be read back and
    // reverted. The visible motion is entirely the glide's.
    const writer = writerWithFakeGlide()
    const items = [fakeGridItem("a")]
    stubScrollingDocument(items)

    writer.focusFirst("grid")

    expect(items[0].scrolledWith).toEqual({
      block: "nearest", inline: "nearest", behavior: "instant",
    })
    expect(root.scrollLeft).toBe(120)
    expect(root.scrollTop).toBe(40)
  })

  test("focusByEntityId reveals the item it focused", () => {
    const writer = writerWithFakeGlide()
    const items = [fakeGridItem("a"), fakeGridItem("b")]
    items[1].dataset = { entityId: "e-9" }
    stubScrollingDocument(items)

    writer.focusByEntityId("grid", "e-9")

    expect(globalThis.document.activeElement).toBe(items[1])
    expect(glided.length).toBe(1)
  })

  test("focusElement reveals the item it focused", () => {
    const writer = writerWithFakeGlide()
    const item = fakeGridItem("a")
    stubScrollingDocument([item])

    writer.focusElement(item)

    expect(globalThis.document.activeElement).toBe(item)
    expect(glided.length).toBe(1)
  })

  // A shelf has one canonical resting position, and arriving at it from above
  // or from below must land on the same one. "nearest" cannot do that — it
  // aligns to whichever edge you came from — so the surface declares the
  // alignment it wants and the reveal honours it.
  test("data-nav-reveal-block declares how the subject is aligned", () => {
    const writer = writerWithFakeGlide()
    const item = fakeGridItem("card")
    const shelf = {}
    item.closest = (selector) =>
      selector === "[data-nav-reveal-block]" ? { dataset: { navRevealBlock: "end" } } : null
    stubScrollingDocument([item])

    writer.focusElement(item)

    expect(item.scrolledWith.block).toBe("end")
  })

  // A declared alignment is a preference, not a promise. At large UI scales a
  // shelf's reserve can exceed the viewport, and honouring "end" would then
  // push the focused card off the TOP of the screen — worse than not framing
  // it at all. Falling back to a minimal reveal keeps the card on screen.
  test("a declared alignment is abandoned when it would push the item off screen", () => {
    const writer = writerWithFakeGlide()
    const item = fakeGridItem("card")
    item.closest = (selector) =>
      selector === "[data-nav-reveal-block]" ? { dataset: { navRevealBlock: "end" } } : null
    // Reports a rect above the viewport top — what an over-tall reserve does.
    item.getBoundingClientRect = () => ({ x: 0, y: -200, width: 10, height: 300, top: -200, left: 0, right: 10, bottom: 100 })
    stubScrollingDocument([item])

    writer.focusElement(item)

    expect(item.scrolledWith.block).toBe("nearest")
  })

  // Some items are not the thing worth looking at. The home hero's Play button
  // sits low in a full-bleed backdrop: revealing the BUTTON when arriving from
  // below parks it at the bottom of the viewport with the title and artwork
  // above it off-screen. `data-nav-reveal` on an ancestor says "show this
  // instead", so the reveal is still one mechanism rather than a page behavior
  // racing it with a second scroll of the same box.
  test("reveal targets the nearest [data-nav-reveal] ancestor when there is one", () => {
    const writer = writerWithFakeGlide()
    const section = { ...fakeGridItem("hero-section"), scrolledWith: undefined }
    const item = fakeGridItem("play")
    item.closest = (selector) => (selector === "[data-nav-reveal]" ? section : null)
    stubScrollingDocument([item])

    writer.focusElement(item)

    // Focus lands on the button; the SECTION is what gets scrolled into view.
    expect(globalThis.document.activeElement).toBe(item)
    expect(section.scrolledWith).toEqual({
      block: "nearest", inline: "nearest", behavior: "instant",
    })
    expect(item.scrolledWith).toBeUndefined()
  })
})

describe("getItemRects — geometry for spatial navigation", () => {
  const gridReader = createDomReader(GRID_CONFIG)

  test("returns one rect per navigable item, in DOM order", () => {
    const items = [fakeGridItem("a"), fakeGridItem("b", { hidden: true }), fakeGridItem("c")]
    stubGridDocument(items)
    const rects = gridReader.getItemRects("grid")
    expect(rects.length).toBe(2)
    expect(rects[0]).toMatchObject({ x: 0, y: 0, width: 10, height: 10 })
  })

  test("an unknown context yields no rects rather than throwing", () => {
    stubGridDocument([])
    expect(gridReader.getItemRects("nope")).toEqual([])
  })
})

// ---------------------------------------------------------------------------
// Reveal suppression — a focus call with { reveal: false } re-asserts focus
// without moving any scroll container. Used for patch-driven restores while
// the pointer owns the scroll (mouse mode): the cursor must survive the
// patch, but yanking the viewport to it would fight the user's wheel.
// ---------------------------------------------------------------------------

describe("writer reveal suppression", () => {
  const REVEAL_CONFIG = { contextSelectors: { grid: "[data-nav-zone='grid'] [data-nav-item]" } }

  function scrollableItem() {
    const box = {
      scrollLeft: 0, scrollTop: 400,
      scrollWidth: 100, clientWidth: 100,
      scrollHeight: 2000, clientHeight: 500,
      parentElement: null,
    }
    const scrollIntoViewCalls = []
    const item = {
      dataset: {},
      hasAttribute: () => false,
      checkVisibility: () => true,
      closest: () => null,
      parentElement: box,
      focusOpts: null,
      focus(opts) {
        this.focusOpts = opts
        globalThis.document.activeElement = this
      },
      scrollIntoView(...args) { scrollIntoViewCalls.push(args) },
    }
    return { item, box, scrollIntoViewCalls }
  }

  function stubScrollableDocument(item) {
    const realDocument = globalThis.document
    const realGetComputedStyle = globalThis.getComputedStyle
    globalThis.document = {
      activeElement: null,
      body: {},
      documentElement: {},
      scrollingElement: null,
      querySelectorAll: (selector) =>
        selector === REVEAL_CONFIG.contextSelectors.grid ? [item] : [],
      querySelector: () => null,
    }
    globalThis.getComputedStyle = () =>
      ({ position: "static", overflowX: "auto", overflowY: "auto" })
    restore = () => {
      globalThis.document = realDocument
      globalThis.getComputedStyle = realGetComputedStyle
    }
  }

  function glideSpy() {
    const glideCalls = []
    return {
      glideCalls,
      glide(...args) { glideCalls.push(args) },
      cancel() {},
      cancelAll() { glideCalls.push("cancelAll") },
      isGliding: () => false,
    }
  }

  test("focusFirst reveals by default", () => {
    const { item, scrollIntoViewCalls } = scrollableItem()
    stubScrollableDocument(item)
    const glider = glideSpy()
    const writer = createDomWriter({ ...REVEAL_CONFIG, glider })

    expect(writer.focusFirst("grid")).toBe(true)

    expect(scrollIntoViewCalls.length).toBe(1)
    expect(glider.glideCalls.length).toBe(1)
  })

  test("focusFirst with { reveal: false } focuses without touching scroll", () => {
    const { item, box, scrollIntoViewCalls } = scrollableItem()
    stubScrollableDocument(item)
    const glider = glideSpy()
    const writer = createDomWriter({ ...REVEAL_CONFIG, glider })

    expect(writer.focusFirst("grid", { reveal: false })).toBe(true)

    expect(globalThis.document.activeElement).toBe(item)
    expect(item.focusOpts).toEqual({ preventScroll: true })
    expect(scrollIntoViewCalls.length).toBe(0)
    expect(glider.glideCalls.length).toBe(0)
    expect(box.scrollTop).toBe(400)
  })

  test("focusByIndex and focusByEntityId honor { reveal: false }", () => {
    const { item, scrollIntoViewCalls } = scrollableItem()
    item.dataset.entityId = "movie-1"
    stubScrollableDocument(item)
    const glider = glideSpy()
    const writer = createDomWriter({ ...REVEAL_CONFIG, glider })

    expect(writer.focusByIndex("grid", 0, { reveal: false })).toBe(true)
    expect(writer.focusByEntityId("grid", "movie-1", { reveal: false })).toBe(true)

    expect(scrollIntoViewCalls.length).toBe(0)
    expect(glider.glideCalls.length).toBe(0)
  })

  test("cancelScrollMotion stops every glide in flight", () => {
    const { item } = scrollableItem()
    stubScrollableDocument(item)
    const glider = glideSpy()
    const writer = createDomWriter({ ...REVEAL_CONFIG, glider })

    writer.cancelScrollMotion()

    expect(glider.glideCalls).toEqual(["cancelAll"])
  })
})
