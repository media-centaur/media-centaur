// whenIdle — run a callback once the page is idle, within a bound.
//
// `requestIdleCallback` with a timeout, so work that should wait for the
// launch to settle (pre-decoding images the first glide will need) still
// runs on a page that is never idle; a setTimeout where the API is missing.

export const whenIdle = globalThis.requestIdleCallback
  ? (callback) => globalThis.requestIdleCallback(callback, { timeout: 4000 })
  : (callback) => setTimeout(callback, 1500)
