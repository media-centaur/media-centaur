/**
 * Debug logging for the input system.
 *
 * Disabled by default. Enable at runtime from browser console or
 * Chrome DevTools MCP:
 *
 *   window.__inputDebug = true   // enable
 *   window.__inputDebug = false  // disable
 */
export function debug(...args) {
  if (typeof window !== "undefined" && window.__inputDebug) {
    console.log("[input]", ...args)
  }
}
