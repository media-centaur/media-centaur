// assets/js/test_support/dom_stubs.js
//
// Browser globals for hook unit tests. Bun ships no DOM, and the hooks reach
// for `window`, `MutationObserver` and `requestAnimationFrame` directly.
//
// Every installer assigns **unconditionally** and is meant to be called from a
// `beforeEach`. That is the whole point of this module. These are process-wide
// globals shared by every file in a `bun test` run, so the guarded idiom these
// stubs replace —
//
//     if (typeof window === "undefined") { globalThis.window = ... }
//
// — silently inherits whatever the previously loaded test file left behind.
// That is how the Console hook's tests spent three months passing on their own
// and failing whenever log_tail.test.js happened to load first: they were
// running against log_tail's `window`, which has no `dispatchEvent`.
//
// Installing per test also means no test can observe a listener another test
// registered.

// A `window` whose `dispatchEvent` actually reaches handlers registered
// through `addEventListener`, so a test can drive a hook the way the browser
// does instead of reaching into a listener registry by name.
export function installWindow() {
  const listeners = {}

  const stub = {
    addEventListener(type, handler) {
      if (!listeners[type]) listeners[type] = []
      listeners[type].push(handler)
    },

    removeEventListener(type, handler) {
      listeners[type] = (listeners[type] || []).filter((entry) => entry !== handler)
    },

    // Copy before iterating: a handler is free to remove itself.
    dispatchEvent(event) {
      const handlers = [...(listeners[event.type] || [])]
      handlers.forEach((handler) => handler(event))
      return true
    },

    // For asserting that a hook registered — and later released — its
    // listeners, which is otherwise invisible from outside.
    listenerCount(type) {
      return (listeners[type] || []).length
    },
  }

  globalThis.window = stub
  return stub
}

// Returns the live list of observers constructed since the install, so a test
// can fire a mutation callback imperatively via `observers[0].fire()`.
export function installMutationObserver() {
  const observers = []

  globalThis.MutationObserver = class StubMutationObserver {
    constructor(callback) {
      this._callback = callback
      this.observing = false
      observers.push(this)
    }

    observe(_target, _options) {
      this.observing = true
    }

    disconnect() {
      this.observing = false
    }

    fire() {
      this._callback([])
    }
  }

  return observers
}

// Synchronous, so work a hook defers to the next frame is observable in the
// same tick as the call that scheduled it.
export function installSyncAnimationFrame() {
  globalThis.requestAnimationFrame = (callback) => callback(0)
}
