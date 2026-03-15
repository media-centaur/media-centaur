/**
 * Debug logging for the input system.
 *
 * Disabled by default. Enable at runtime from browser console or
 * Chrome DevTools MCP:
 *
 *   window.__inputDebug = true   // enable
 *   window.__inputDebug = false  // disable
 *
 * Two call forms:
 *
 *   debug("simple message", value)          // variadic — args evaluated eagerly
 *   debug(() => ["expensive", costlyFn()])  // lazy — callback only runs when enabled
 *
 * Use the lazy form when args are expensive to compute (e.g. stack traces).
 * Both forms are zero-cost when disabled — the lazy form avoids constructing
 * values that would be thrown away.
 */
export function debug(...args) {
  if (typeof window === "undefined" || !window.__inputDebug) return
  if (args.length === 1 && typeof args[0] === "function") {
    console.log("[input]", ...args[0]())
  } else {
    console.log("[input]", ...args)
  }
}
