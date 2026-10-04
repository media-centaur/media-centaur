import { describe, expect, test, beforeEach, afterEach } from "bun:test"
import { LogFollow, jumpLabel } from "./log_follow"
import {
  installMutationObserver,
  installResizeObserver,
  installSyncAnimationFrame,
  restoreGlobals,
} from "../test_support/dom_stubs"

// Browser globals, installed fresh before every test — see
// `test_support/dom_stubs.js`. The lists are rebound each time so `[0]` is
// always the observer the hook under test constructed.
let mutationObservers = []
let resizeObservers = []

const ROW_HEIGHT = 20

// A rows container whose children carry the sibling links the hook walks.
function buildRows(count) {
  const rows = {
    children: [],
    get lastElementChild() {
      return this.children[this.children.length - 1] || null
    },
    append(n = 1) {
      for (let index = 0; index < n; index++) {
        const row = {
          style: { display: "" },
          parentNode: rows,
          get nextElementSibling() {
            const position = rows.children.indexOf(this)
            return rows.children[position + 1] || null
          },
        }
        rows.children.push(row)
      }
    },
    // A stream reset: every row replaced.
    replaceAll(n) {
      this.children.forEach((row) => (row.parentNode = null))
      this.children = []
      this.append(n)
    },
    get visibleCount() {
      return this.children.filter((row) => row.style.display !== "none").length
    },
  }
  rows.append(count)
  return rows
}

function buildJump() {
  const listeners = {}
  const count = { textContent: "" }
  return {
    hidden: true,
    count,
    querySelector: (selector) => (selector === "[data-log-jump-label]" ? count : null),
    addEventListener(event, handler) {
      listeners[event] = handler
    },
    removeEventListener(event, handler) {
      if (listeners[event] === handler) delete listeners[event]
    },
    click() {
      listeners.click?.()
    },
  }
}

// A scroller whose geometry follows its rows, with the browser's clamping of
// `scrollTop` to [0, scrollHeight - clientHeight].
function buildScroller({ rowCount = 50, clientHeight = 200 } = {}) {
  const listeners = {}
  const rows = buildRows(rowCount)
  const jump = buildJump()
  let top = 0

  const el = {
    rows,
    jump,
    clientHeight,
    dataset: {},
    get scrollHeight() {
      return rows.visibleCount * ROW_HEIGHT
    },
    get scrollTop() {
      return top
    },
    set scrollTop(value) {
      top = Math.max(0, Math.min(value, this.scrollHeight - this.clientHeight))
    },
    querySelector(selector) {
      if (selector === "[data-log-rows]") return rows
      if (selector === "[data-log-jump]") return jump
      return null
    },
    addEventListener(event, handler) {
      listeners[event] = handler
    },
    removeEventListener(event, handler) {
      if (listeners[event] === handler) delete listeners[event]
    },
    // The reader scrolls: the position changes, then the event fires.
    readerScrollsTo(value) {
      this.scrollTop = value
      listeners.scroll?.()
    },
    fireScroll() {
      listeners.scroll?.()
    },
    hasScrollListener() {
      return Boolean(listeners.scroll)
    },
  }
  return el
}

function bottomOf(scroller) {
  return scroller.scrollHeight - scroller.clientHeight
}

function mountedOn(scroller) {
  const hook = Object.create(LogFollow)
  hook.el = scroller
  hook.mounted()
  return hook
}

// Lines arrive: rows appended, then the browser reports the mutation and the
// size change, in that order.
function arrive(scroller, n) {
  scroller.rows.append(n)
  mutationObservers[0].fire()
  resizeObservers[0].fire()
}

beforeEach(() => {
  mutationObservers = installMutationObserver()
  resizeObservers = installResizeObserver()
  installSyncAnimationFrame()
})

afterEach(restoreGlobals)

describe("LogFollow — following", () => {
  test("mounts following, at the live edge, with the jump control hidden", () => {
    const scroller = buildScroller()
    mountedOn(scroller)

    expect(scroller.scrollTop).toBe(bottomOf(scroller))
    expect(scroller.dataset.following).toBe("true")
    expect(scroller.jump.hidden).toBe(true)
  })

  test("observes the rows and the scroller for size changes", () => {
    const scroller = buildScroller()
    mountedOn(scroller)

    expect(resizeObservers[0].targets).toEqual([scroller.rows, scroller])
  })

  test("keeps the live edge in view as lines arrive", () => {
    const scroller = buildScroller()
    mountedOn(scroller)

    arrive(scroller, 5)

    expect(scroller.scrollTop).toBe(bottomOf(scroller))
  })

  test("its own pin does not count as the reader leaving", () => {
    const scroller = buildScroller()
    const hook = mountedOn(scroller)

    arrive(scroller, 5)
    // The browser reports the pin as a scroll event after the fact.
    scroller.fireScroll()
    // More lines land before that event was handled.
    scroller.rows.append(3)
    scroller.fireScroll()

    expect(hook.following()).toBe(true)
  })

  test("a small nudge within the threshold keeps following", () => {
    const scroller = buildScroller()
    const hook = mountedOn(scroller)

    scroller.readerScrollsTo(bottomOf(scroller) - 10)

    expect(hook.following()).toBe(true)
  })

  test("re-pins when rows shrink while following (search hiding rows)", () => {
    const scroller = buildScroller({ rowCount: 50 })
    mountedOn(scroller)

    scroller.rows.children.slice(0, 30).forEach((row) => (row.style.display = "none"))
    resizeObservers[0].fire()

    expect(scroller.scrollTop).toBe(bottomOf(scroller))
  })
})

describe("LogFollow — held", () => {
  test("scrolling up past the threshold holds the view and shows the jump control", () => {
    const scroller = buildScroller()
    const hook = mountedOn(scroller)

    scroller.readerScrollsTo(100)

    expect(hook.following()).toBe(false)
    expect(scroller.dataset.following).toBe("false")
    expect(scroller.jump.hidden).toBe(false)
    expect(scroller.jump.count.textContent).toBe("Jump to latest")
  })

  test("arriving lines do not move a held view", () => {
    const scroller = buildScroller()
    mountedOn(scroller)
    scroller.readerScrollsTo(100)

    arrive(scroller, 5)

    expect(scroller.scrollTop).toBe(100)
  })

  test("counts the lines that arrived since the view was held", () => {
    const scroller = buildScroller()
    mountedOn(scroller)
    scroller.readerScrollsTo(100)

    arrive(scroller, 1)
    expect(scroller.jump.count.textContent).toBe("1 new line")

    arrive(scroller, 2)
    expect(scroller.jump.count.textContent).toBe("3 new lines")
  })

  test("does not count arrivals the search hides", () => {
    const scroller = buildScroller()
    mountedOn(scroller)
    scroller.readerScrollsTo(100)

    scroller.rows.append(3)
    scroller.rows.children.at(-1).style.display = "none"
    mutationObservers[0].fire()

    expect(scroller.jump.count.textContent).toBe("2 new lines")
  })

  test("a reset of the rows while held starts the count over", () => {
    const scroller = buildScroller()
    mountedOn(scroller)
    scroller.readerScrollsTo(100)
    arrive(scroller, 4)

    scroller.rows.replaceAll(60)
    mutationObservers[0].fire()

    expect(scroller.jump.count.textContent).toBe("Jump to latest")

    arrive(scroller, 2)
    expect(scroller.jump.count.textContent).toBe("2 new lines")
  })
})

describe("LogFollow — resuming", () => {
  test("scrolling back to the live edge resumes following and clears the count", () => {
    const scroller = buildScroller()
    const hook = mountedOn(scroller)
    scroller.readerScrollsTo(100)
    arrive(scroller, 3)

    scroller.readerScrollsTo(bottomOf(scroller))

    expect(hook.following()).toBe(true)
    expect(scroller.jump.hidden).toBe(true)

    scroller.readerScrollsTo(100)
    expect(scroller.jump.count.textContent).toBe("Jump to latest")
  })

  test("the jump control scrolls to the live edge and resumes following", () => {
    const scroller = buildScroller()
    const hook = mountedOn(scroller)
    scroller.readerScrollsTo(100)
    arrive(scroller, 3)

    scroller.jump.click()

    expect(hook.following()).toBe(true)
    expect(scroller.scrollTop).toBe(bottomOf(scroller))
    expect(scroller.jump.hidden).toBe(true)

    arrive(scroller, 2)
    expect(scroller.scrollTop).toBe(bottomOf(scroller))
  })
})

describe("LogFollow — LiveView patches", () => {
  test("updated() restores the state a patch reset on the scroller", () => {
    const scroller = buildScroller()
    const hook = mountedOn(scroller)
    scroller.readerScrollsTo(100)

    // The patch re-renders the scroller's attributes from the template.
    delete scroller.dataset.following
    hook.updated()

    expect(scroller.dataset.following).toBe("false")
  })

  test("destroyed() releases the listener and both observers", () => {
    const scroller = buildScroller()
    const hook = mountedOn(scroller)

    hook.destroyed()

    expect(scroller.hasScrollListener()).toBe(false)
    expect(mutationObservers[0].observing).toBe(false)
    expect(resizeObservers[0].targets).toEqual([])
  })
})

describe("jumpLabel", () => {
  test("names the count of new lines, or the way back when there are none", () => {
    expect(jumpLabel(0)).toBe("Jump to latest")
    expect(jumpLabel(1)).toBe("1 new line")
    expect(jumpLabel(12)).toBe("12 new lines")
  })
})
