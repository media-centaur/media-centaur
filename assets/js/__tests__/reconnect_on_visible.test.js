import { describe, test, expect, beforeEach } from "bun:test"
import { installReconnectOnVisible } from "../reconnect_on_visible.js"

function mockEventTarget() {
  const listeners = {}
  return {
    listeners,
    addEventListener(type, fn) {
      ;(listeners[type] ||= []).push(fn)
    },
    dispatch(type) {
      ;(listeners[type] || []).forEach((fn) => fn())
    },
  }
}

function mockDocument({ visibilityState = "visible" } = {}) {
  const target = mockEventTarget()
  target.visibilityState = visibilityState
  return target
}

function mockLiveSocket({ connected = false } = {}) {
  return {
    connected,
    connectCalls: 0,
    isConnected() {
      return this.connected
    },
    connect() {
      this.connectCalls += 1
    },
  }
}

describe("installReconnectOnVisible", () => {
  let doc, win

  beforeEach(() => {
    doc = mockDocument()
    win = mockEventTarget()
  })

  test("reconnects when the page becomes visible with a dead socket", () => {
    const liveSocket = mockLiveSocket({ connected: false })
    installReconnectOnVisible(liveSocket, doc, win)

    doc.dispatch("visibilitychange")

    expect(liveSocket.connectCalls).toBe(1)
  })

  test("does not reconnect when the socket is already connected", () => {
    const liveSocket = mockLiveSocket({ connected: true })
    installReconnectOnVisible(liveSocket, doc, win)

    doc.dispatch("visibilitychange")
    win.dispatch("focus")
    win.dispatch("pageshow")

    expect(liveSocket.connectCalls).toBe(0)
  })

  test("does not reconnect while the page is still hidden", () => {
    doc = mockDocument({ visibilityState: "hidden" })
    const liveSocket = mockLiveSocket({ connected: false })
    installReconnectOnVisible(liveSocket, doc, win)

    doc.dispatch("visibilitychange")

    expect(liveSocket.connectCalls).toBe(0)
  })

  test("window focus and pageshow also trigger a reconnect", () => {
    const liveSocket = mockLiveSocket({ connected: false })
    installReconnectOnVisible(liveSocket, doc, win)

    win.dispatch("focus")
    win.dispatch("pageshow")

    expect(liveSocket.connectCalls).toBe(2)
  })
})
