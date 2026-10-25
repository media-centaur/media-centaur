// assets/js/scroll_glider.js
//
// The page's one scroll animator. The input system's DOM writer glides a
// scroller toward the focused card with it (`inputConfig.glider`), and the
// scroll row hook glides a track on an edge-arrow press with it. One
// instance, so the orchestrator's wheel rule — a wheel event cancels every
// glide where it stands — covers both, and a cursor key pressed mid-glide
// retargets the same track instead of racing a second animation.
//
// The browser globals are read lazily, per call, so importing this module
// under bun (no `requestAnimationFrame`) is harmless.
import { createScrollGlide } from "./input/core/scroll_glide.js"

export const scrollGlider = createScrollGlide({
  requestAnimationFrame: (fn) => globalThis.requestAnimationFrame(fn),
  now: () => performance.now(),
})

// The debug handle, in the pattern of `window.__inputDebug`: a measurement
// on the TV (`mc-tv-smooth --cond js:<file>`) swaps `glide` for another
// animator through it, so two animators are compared on one page without a
// code change between rounds.
globalThis.__scrollGlider = scrollGlider
