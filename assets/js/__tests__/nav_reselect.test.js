import { describe, test, expect, beforeEach } from "bun:test"
import { installNavReselect } from "../nav_reselect.js"

function mockWindow({ pathname = "/", search = "" } = {}) {
  return {
    location: { pathname, search, href: `http://localhost:2160${pathname}${search}` },
    scrollCalls: [],
    scrollTo(options) {
      this.scrollCalls.push(options)
    },
  }
}

// A click on an anchor: `closest` resolves to the link when the click landed
// inside the sidebar, to nothing otherwise.
function clickOn(doc, { href, inSidebar = true }) {
  const link = {
    getAttribute(name) {
      return name === "href" ? href : null
    },
  }
  const event = {
    target: {
      closest(selector) {
        return selector === "#sidebar a[href]" && inSidebar ? link : null
      },
    },
    defaultPrevented: false,
    propagationStopped: false,
    preventDefault() {
      this.defaultPrevented = true
    },
    stopPropagation() {
      this.propagationStopped = true
    },
  }
  doc.dispatch("click", event)
  return event
}

function mockDocument() {
  const listeners = {}
  return {
    captures: [],
    addEventListener(type, fn, capture) {
      ;(listeners[type] ||= []).push(fn)
      this.captures.push(capture)
    },
    dispatch(type, event) {
      ;(listeners[type] || []).forEach((fn) => fn(event))
    },
  }
}

describe("installNavReselect", () => {
  let doc

  beforeEach(() => {
    doc = mockDocument()
  })

  test("re-selecting the current page scrolls to the top instead of navigating", () => {
    const win = mockWindow({ pathname: "/" })
    installNavReselect(doc, win)

    const event = clickOn(doc, { href: "/" })

    expect(win.scrollCalls).toEqual([{ top: 0, behavior: "smooth" }])
    expect(event.defaultPrevented).toBe(true)
    expect(event.propagationStopped).toBe(true)
  })

  test("a link to a different page navigates untouched", () => {
    const win = mockWindow({ pathname: "/" })
    installNavReselect(doc, win)

    const event = clickOn(doc, { href: "/settings" })

    expect(win.scrollCalls).toEqual([])
    expect(event.defaultPrevented).toBe(false)
  })

  test("same page with live query params: navigation proceeds, scroll still goes to the top", () => {
    // /incoming?q=beach → clicking Incoming clears the search via a real
    // navigation; the reselect principle still puts the reader at the top.
    const win = mockWindow({ pathname: "/incoming", search: "?q=beach" })
    installNavReselect(doc, win)

    const event = clickOn(doc, { href: "/incoming" })

    expect(win.scrollCalls).toEqual([{ top: 0, behavior: "smooth" }])
    expect(event.defaultPrevented).toBe(false)
  })

  test("clicks outside the sidebar are none of its business", () => {
    const win = mockWindow({ pathname: "/" })
    installNavReselect(doc, win)

    const event = clickOn(doc, { href: "/", inSidebar: false })

    expect(win.scrollCalls).toEqual([])
    expect(event.defaultPrevented).toBe(false)
  })

  test("listens in the capture phase so it beats LiveView's own link handling", () => {
    installNavReselect(doc, mockWindow())

    expect(doc.captures).toEqual([true])
  })
})
