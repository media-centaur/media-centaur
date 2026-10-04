// assets/js/hooks/log_follow.js
//
// LiveView hook for a log view (`ConsoleComponents.log_view/1`): a scroller
// whose rows run oldest at the top to newest at the bottom, the live edge.
//
// The view is either following — it keeps the live edge in sight — or held —
// it stays where the reader scrolled while lines keep arriving below. Lines
// are appended below the viewport, so a held view does not move and nothing
// is dropped. The state is the viewport's alone, so the browser owns it.
//
// - Following pins on every size change of the rows (arrivals, the stream
//   limit trimming the oldest, the console's search hiding rows, wrapping) and
//   of the scroller (window resize). One ResizeObserver is the only trigger.
// - Only the reader's own scroll holds the view: a scroll event landing more
//   than EDGE_PX from the live edge, at a position the hook did not set.
// - Returning to the live edge — scrolling, the End key, or the jump
//   control — resumes following.
// - While held, the jump control counts the visible rows that arrived after
//   the last row present when the view was held.
// - `data-following` on the scroller drives CSS: scroll anchoring is off
//   while following (an anchoring adjustment would read as the reader
//   leaving) and on while held (so trimming the oldest rows above the
//   viewport does not shift the lines being read).
//
// DOM contract: the scroller carries the hook; `[data-log-rows]` holds the
// rows; `[data-log-jump]` is the control, inside a `phx-update="ignore"`
// seat so a patch never resets what this hook sets on it, with its text in
// `[data-log-jump-label]`.

const EDGE_PX = 24

export function jumpLabel(count) {
  if (count === 0) return "Jump to latest"
  if (count === 1) return "1 new line"
  return `${count} new lines`
}

export const LogFollow = {
  mounted() {
    this._rows = this.el.querySelector("[data-log-rows]")
    this._jump = this.el.querySelector("[data-log-jump]")
    this._jumpLabel = this._jump?.querySelector("[data-log-jump-label]")
    this._following = true
    this._heldAfter = null
    this._pinnedTop = null

    this._onScroll = () => this._readerScrolled()
    this._onJump = () => this._follow()
    this.el.addEventListener("scroll", this._onScroll, { passive: true })
    this._jump?.addEventListener("click", this._onJump)

    this._resizes = new ResizeObserver(() => this._keepEdge())
    this._resizes.observe(this._rows)
    this._resizes.observe(this.el)

    this._mutations = new MutationObserver(() => this._render())
    this._mutations.observe(this._rows, { childList: true })

    this._pin()
    this._render()
  },

  // A patch re-renders the scroller's attributes from the template.
  updated() {
    this._render()
  },

  destroyed() {
    this.el.removeEventListener("scroll", this._onScroll)
    this._jump?.removeEventListener("click", this._onJump)
    this._resizes?.disconnect()
    this._mutations?.disconnect()
  },

  following() {
    return this._following
  },

  _follow() {
    this._following = true
    this._heldAfter = null
    this._pin()
    this._render()
  },

  _hold() {
    this._following = false
    this._heldAfter = this._rows.lastElementChild
    this._render()
  },

  _readerScrolled() {
    // The hook's own pin, reported after the fact — possibly after more rows
    // landed, so the distance alone would misread it.
    if (this.el.scrollTop === this._pinnedTop) return

    const atEdge = this._distanceFromEdge() <= EDGE_PX
    if (atEdge && !this._following) this._follow()
    if (!atEdge && this._following) this._hold()
  },

  _keepEdge() {
    if (this._following) this._pin()
  },

  _distanceFromEdge() {
    return this.el.scrollHeight - this.el.clientHeight - this.el.scrollTop
  },

  _pin() {
    this.el.scrollTop = this.el.scrollHeight
    // The browser clamps; remember where it actually landed.
    this._pinnedTop = this.el.scrollTop
  },

  // Visible rows after the last row present when the view was held. A reset
  // that removed that row starts the count over from the new last row.
  _arrivedSinceHold() {
    if (this._heldAfter?.parentNode !== this._rows) {
      this._heldAfter = this._rows.lastElementChild
      return 0
    }

    let count = 0
    for (let row = this._heldAfter.nextElementSibling; row; row = row.nextElementSibling) {
      if (row.style.display !== "none") count++
    }
    return count
  },

  _render() {
    this.el.dataset.following = String(this._following)
    if (!this._jump) return

    this._jump.hidden = this._following
    if (!this._following && this._jumpLabel) {
      this._jumpLabel.textContent = jumpLabel(this._arrivedSinceHold())
    }
  },
}
