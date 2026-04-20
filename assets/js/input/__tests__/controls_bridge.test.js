import { describe, test, expect, beforeEach, mock } from "bun:test"
import { ControlsBridge } from "../controls_bridge.js"

function makeEvent(key) {
  return {
    key,
    preventDefault: mock(() => {}),
    stopPropagation: mock(() => {}),
  }
}

function makeWindow() {
  const listeners = new Map()
  return {
    addEventListener: mock((type, fn, opts) => {
      const list = listeners.get(type) ?? []
      list.push({ fn, opts })
      listeners.set(type, list)
    }),
    removeEventListener: mock((type, fn) => {
      const list = listeners.get(type) ?? []
      listeners.set(type, list.filter((l) => l.fn !== fn))
    }),
    dispatch(type, event) {
      const list = [...(listeners.get(type) ?? [])]
      for (const { fn, opts } of list) {
        fn(event)
        if (opts?.once) {
          this.removeEventListener(type, fn)
        }
      }
    },
    dispatchEvent(event) {
      this.dispatch(event.type, event)
    },
  }
}

describe("ControlsBridge", () => {
  let bridge, window, pushEvent

  beforeEach(() => {
    window = makeWindow()
    pushEvent = mock(() => {})
    bridge = new ControlsBridge({ window, pushEvent })
  })

  test("listenKeyboard installs one-shot capture keydown listener", () => {
    bridge.listenKeyboard()
    expect(window.addEventListener).toHaveBeenCalledWith(
      "keydown",
      expect.any(Function),
      expect.objectContaining({ capture: true, once: true })
    )
  })

  test("keyboard capture pushes controls:bind with event.key and id/kind", () => {
    bridge.listenKeyboard({ id: "select" })
    const event = makeEvent("F2")
    window.dispatch("keydown", event)

    expect(event.preventDefault).toHaveBeenCalled()
    expect(event.stopPropagation).toHaveBeenCalled()
    expect(pushEvent).toHaveBeenCalledWith("controls:bind", {
      id: "select",
      kind: "keyboard",
      value: "F2",
    })
  })

  test("Escape during listen pushes controls:cancel and not controls:bind", () => {
    bridge.listenKeyboard({ id: "select" })
    const event = makeEvent("Escape")
    window.dispatch("keydown", event)

    expect(pushEvent).toHaveBeenCalledWith("controls:cancel", {})
    const bindCalls = pushEvent.mock.calls.filter((c) => c[0] === "controls:bind")
    expect(bindCalls.length).toBe(0)
  })

  test("updateMaps emits a window event for the input system to consume", () => {
    const listener = mock(() => {})
    window.addEventListener("input:rebindMaps", listener)
    bridge.updateMaps({ keyboard: { w: "navigate_up" }, gamepad: { 0: "select" } })

    expect(listener).toHaveBeenCalled()
    const payload = listener.mock.calls[0][0]
    expect(payload.detail).toEqual({
      keyboard: { w: "navigate_up" },
      gamepad: { 0: "select" },
    })
  })
})
