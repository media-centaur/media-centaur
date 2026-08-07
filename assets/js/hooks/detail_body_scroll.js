// assets/js/hooks/detail_body_scroll.js
//
// Where the detail modal's body sits, across sub-view swaps.
//
// The whole detail document scrolls in one port (`#detail-scrollport`), and the
// body sheet keeps its DOM identity when the sub-view changes — More info and
// Manage replace the sheet's children through a push_patch, not the sheet
// itself. So with no owner, `scrollTop` simply carries over: opening More info
// from an episode list scrolled halfway down drops you halfway down the cast
// grid.
//
// Each sub-view therefore gets its own remembered offset, kept for as long as
// one title stays open. A view being entered for the first time gets its entry
// rule instead:
//
//   main            centre the resume episode when the server marks one
//                   (`data-scroll-to-resume`), else the top
//   credits, info   the top — More info and Manage are documents, read from
//                   their start
//
// The live offset is tracked from the port's scroll events rather than read at
// patch time. Swapping a long episode list for a short panel shortens the
// content and the browser clamps `scrollTop` before `updated()` runs, so the
// position read back after the patch is not the one the user left.

const SCROLLPORT = "#detail-scrollport"

export const DetailBodyScroll = {
  mounted() {
    this._offsets = {}
    this._entityId = this.el.dataset.entityId
    this._view = this.el.dataset.view
    this._port = this.el.closest(SCROLLPORT)

    if (this._port) {
      this._onScroll = () => {
        this._offsets[this._view] = this._port.scrollTop
      }
      this._port.addEventListener("scroll", this._onScroll, { passive: true })
    }

    this._enter(this._view)
  },

  updated() {
    const { entityId, view } = this.el.dataset

    // A different title is a different document — its predecessor's offsets
    // mean nothing against it.
    if (entityId !== this._entityId) {
      this._entityId = entityId
      this._offsets = {}
      this._view = view
      this._enter(view)
      return
    }

    // Every other patch — a season expanding, an episode disclosure, a files
    // load landing — leaves the reader where they are.
    if (view === this._view) return

    this._view = view
    const remembered = this._offsets[view]
    if (remembered === undefined) {
      this._enter(view)
    } else if (this._port) {
      this._port.scrollTop = remembered
    }
  },

  destroyed() {
    if (this._port && this._onScroll) {
      this._port.removeEventListener("scroll", this._onScroll)
    }
  },

  _enter(view) {
    const target = view === "main" ? this._resumeTarget() : null
    if (!target) {
      if (this._port) this._port.scrollTop = 0
      return
    }

    // One frame, so the swapped-in list has been laid out and the row's
    // position is real.
    requestAnimationFrame(() => {
      target.scrollIntoView({ block: "center", behavior: "instant" })
    })
  },

  // `data-scroll-to-resume` is the only signal for whether to centre a row —
  // the server decides (`DetailPanel.autoscroll_resume?/1`). A target row can
  // exist without being somewhere to return to: an unstarted series highlights
  // its first episode but opens on the hero. The attribute describes the
  // title, not the view, so it stays on while More info shows; only the main
  // view has a row for it to point at.
  _resumeTarget() {
    if (this.el.dataset.scrollToResume === undefined) return null
    return this.el.querySelector("[data-resume-target]")
  },
}
