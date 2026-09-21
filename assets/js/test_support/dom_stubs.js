// assets/js/test_support/dom_stubs.js
//
// Browser globals for hook unit tests. Bun ships no DOM, and the hooks reach
// for `window`, `MutationObserver` and `requestAnimationFrame` directly.
//
// Bun runs every test file in **one process**, in whatever order the
// filesystem hands it the files — and that order differs between this
// machine, the GitHub runner and macOS. So a global is process-wide state
// shared by every file in the run, and the rule is two-sided:
//
//   * install unconditionally, from a `beforeEach`, so a test never inherits
//     whatever a previously loaded file left behind (the Console hook's tests
//     once spent three months passing on their own and failing whenever
//     log_tail.test.js happened to load first: they were running against
//     log_tail's `window`, which has no `dispatchEvent`);
//   * restore unconditionally, from `afterEach(restoreGlobals)`, so a file
//     loaded later finds the process as bun started it (a `URL` left as a
//     plain object broke nav_reselect.test.js on the runner, and a leftover
//     `window` made uPlot read `devicePixelRatio` at import and abort
//     strip_chart.test.js — CI red on every push, 2026-09-17 to 09-21).
//
// Every installer goes through `installGlobal`, which remembers what it
// replaced; `restoreGlobals` puts all of it back, in reverse.

const installed = []

// Replaces `globalThis[name]` with `value`, remembering the prior binding
// (or its absence) for `restoreGlobals`.
export function installGlobal(name, value) {
  const hadOwn = Object.prototype.hasOwnProperty.call(globalThis, name)
  installed.push({ name, hadOwn, previous: hadOwn ? globalThis[name] : undefined })
  globalThis[name] = value
  return value
}

// Undoes every `installGlobal` since the last restore, newest first, so a
// global replaced twice goes back to the original. Idempotent.
export function restoreGlobals() {
  while (installed.length > 0) {
    const { name, hadOwn, previous } = installed.pop()
    if (hadOwn) {
      globalThis[name] = previous
    } else {
      delete globalThis[name]
    }
  }
}

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

  return installGlobal("window", stub)
}

// Returns the live list of observers constructed since the install, so a test
// can fire a mutation callback imperatively via `observers[0].fire()`.
export function installMutationObserver() {
  const observers = []

  installGlobal(
    "MutationObserver",
    class StubMutationObserver {
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
  )

  return observers
}

// Synchronous, so work a hook defers to the next frame is observable in the
// same tick as the call that scheduled it.
export function installSyncAnimationFrame() {
  installGlobal("requestAnimationFrame", (callback) => callback(0))
}
