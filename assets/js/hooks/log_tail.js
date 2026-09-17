// assets/js/hooks/log_tail.js
//
// LiveView hook for a scrollable log container that should follow the
// live edge of the stream — "tail -f" behavior. The stream prepends at
// position 0, so the newest entry is at the top and the live edge is
// scrollTop 0.
//
// Tail-following is sticky in both directions: if the user scrolls away
// from the live edge we stop following so they can read history, and we
// resume automatically the moment they scroll back.

const THRESHOLD = 10

export const LogTail = {
  mounted() {
    this._followTail = true

    this._onScroll = () => this._trackPosition()
    this.el.addEventListener("scroll", this._onScroll, { passive: true })

    this._observer = new MutationObserver(() => this._maintain())
    this._observer.observe(this.el, { childList: true, subtree: false })

    // Pin immediately in case the container was rendered with existing
    // entries (e.g. tab switch replays a snapshot). The second rAF lets
    // layout settle so scrollHeight reflects final row heights.
    requestAnimationFrame(() => requestAnimationFrame(() => this._pin()))
  },

  updated() {
    // Re-pin on server-driven re-renders too. Stream resets (tab switches,
    // filter changes) replace the children without a separate mutation
    // event the observer can latch on to before layout finalises.
    if (this._followTail) this._pin()
  },

  destroyed() {
    this.el.removeEventListener("scroll", this._onScroll)
    this._observer?.disconnect()
  },

  _trackPosition() {
    this._followTail = this._atLiveEdge()
  },

  _maintain() {
    if (this._followTail) this._pin()
  },

  _atLiveEdge() {
    return this.el.scrollTop <= THRESHOLD
  },

  _pin() {
    this.el.scrollTop = 0
  },
}
