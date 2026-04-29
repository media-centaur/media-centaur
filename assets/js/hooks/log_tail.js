// assets/js/hooks/log_tail.js
//
// LiveView hook for a scrollable log container that should follow the
// live edge of the stream — "tail -f" behavior. Which edge counts as
// the tail is declared via the `data-pin-to` attribute:
//
//   data-pin-to="top"     (default) — stream prepends at position 0,
//                         newest entries at the top. Pin to scrollTop=0.
//
//   data-pin-to="bottom"  — stream appends at position -1, newest
//                         entries at the bottom. Pin to scrollHeight
//                         (journalctl -f style).
//
// Tail-following is sticky in both directions: if the user scrolls away
// from the live edge we stop following so they can read history, and we
// resume automatically the moment they scroll back.

const THRESHOLD = 10

export const LogTail = {
  mounted() {
    this._pinTo = this.el.dataset.pinTo === "bottom" ? "bottom" : "top"
    this._followTail = true

    this._onScroll = () => this._trackPosition()
    this.el.addEventListener("scroll", this._onScroll, { passive: true })

    this._observer = new MutationObserver(() => this._maintain())
    this._observer.observe(this.el, { childList: true, subtree: false })

    // External re-pin trigger. The Console drawer dispatches this when it
    // opens, because the systemd journal_list may have been laid out off
    // the live edge while the panel was hidden by transform — opening the
    // drawer is the user's signal that they want to see the tail.
    this._onRepin = () => {
      this._followTail = true
      this._pin()
    }
    window.addEventListener("mc:log-tail:repin", this._onRepin)

    // Pin immediately in case the container was rendered with existing
    // entries (e.g. tab switch replays a snapshot). The second rAF lets
    // layout settle so scrollHeight reflects final row heights.
    requestAnimationFrame(() => requestAnimationFrame(() => this._pin()))
  },

  updated() {
    // `data-pin-to` can't change without the element being re-mounted,
    // but re-read defensively so tests and future refactors don't
    // silently regress.
    this._pinTo = this.el.dataset.pinTo === "bottom" ? "bottom" : "top"
    // Re-pin on server-driven re-renders too. Stream resets (tab switches,
    // filter changes) replace the children without a separate mutation
    // event the observer can latch on to before layout finalises.
    if (this._followTail) this._pin()
  },

  destroyed() {
    this.el.removeEventListener("scroll", this._onScroll)
    window.removeEventListener("mc:log-tail:repin", this._onRepin)
    this._observer?.disconnect()
  },

  _trackPosition() {
    this._followTail = this._atLiveEdge()
  },

  _maintain() {
    if (this._followTail) this._pin()
  },

  _atLiveEdge() {
    if (this._pinTo === "bottom") {
      const distance = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight
      return distance <= THRESHOLD
    }
    return this.el.scrollTop <= THRESHOLD
  },

  _pin() {
    if (this._pinTo === "bottom") {
      this.el.scrollTop = this.el.scrollHeight
    } else {
      this.el.scrollTop = 0
    }
  },
}
