// assets/js/hooks/detail_body_scroll.js
//
// Where a cinematic modal's body sits, across sub-view swaps.
//
// The whole detail document scrolls in one port (the enclosing
// `.modal-detail-scroll` — CinematicShell renders one per modal), and the
// body sheet keeps its DOM identity when the sub-view changes — More info and
// Manage replace the sheet's children through a push_patch, not the sheet
// itself.
//
// That rebuild is the whole problem. While morphdom has emptied the sheet there
// is nothing to scroll, so the browser clamps `scrollTop` to 0 on its own, and
// growing the content back does not restore it. Verified against the running
// app with `chromium-probe`: the port goes 2000 → 0 on a view swap with no
// script writing it. So "do nothing and the position carries over" is not an
// available behaviour — standing still has to be actively restored, exactly
// like returning to a remembered offset.
//
// Hence `beforeUpdate`: the last moment the port still holds the position the
// reader actually left. Reading it after the patch reads the clamp, which is
// why tracking it from the port's scroll events did not work — the clamp *is*
// a scroll event.
//
// And hence `_wanted`, kept apart from whatever the port currently holds. The
// two are not the same thing whenever content arrives late: Manage loads its
// file list asynchronously, so it lands as an empty sheet followed by a second
// patch carrying the files. On the first there is nothing to scroll and the
// offset is unreachable; on the second the port is sitting on a clamp the
// reader never chose. A hook that only re-reads the port adopts that clamp as
// the answer, which is precisely how the position was being lost. So an
// unreached goal survives patches until the content can satisfy it.
//
// What happens on a swap, in order of preference:
//
//   a remembered offset      the reader has been in this view before, so put
//                            them back where they were
//   first time, main         centre the resume episode when the server marks
//                            one (`data-scroll-to-resume`), else the top
//   first time, sub-view     do not move. Parking at 0 was tried and reverted:
//                            the orientation block is sticky, so leaving the
//                            pinned position throws the whole 21:9 hero back
//                            into view for a swap that only changed the body.
//
// Entering a *document* still resets, because nothing is being preserved — a
// modal opening, or switching to another title. `data-scroll-key` names the
// document (the library modal keys it by entity id).

const SCROLLPORT = ".modal-detail-scroll"

export const DetailBodyScroll = {
  mounted() {
    this._offsets = {}
    this._scrollKey = this.el.dataset.scrollKey
    this._view = this.el.dataset.view
    this._port = this.el.closest(SCROLLPORT)
    this._offsetBeforePatch = 0
    this._wanted = null

    this._enter(this._view)
  },

  beforeUpdate() {
    if (!this._port) return

    // A goal not yet reached is still the goal. The port is resting on a
    // clamp, not on a position the reader picked, so it must not be captured
    // as one.
    if (this._wanted !== null && this._port.scrollTop !== this._wanted) return

    this._wanted = null
    this._offsetBeforePatch = this._port.scrollTop
  },

  updated() {
    const { scrollKey, view } = this.el.dataset

    // A different title is a different document — its predecessor's offsets
    // mean nothing against it.
    if (scrollKey !== this._scrollKey) {
      this._scrollKey = scrollKey
      this._offsets = {}
      this._view = view
      this._enter(view)
      return
    }

    // Every other patch — a season expanding, an episode disclosure, a files
    // load landing — leaves the reader where they are. Which still takes a
    // write: any patch that rebuilds the sheet clamps the port first.
    if (view === this._view) {
      if (this._wanted === null) {
        this._restore(this._offsetBeforePatch)
        return
      }

      // Carried across exactly one patch — long enough for late content to
      // arrive, short enough that an offset the view simply cannot reach is
      // abandoned instead of overriding the reader forever.
      const goal = this._wanted
      this._wanted = null
      this._restore(goal)
      return
    }

    this._offsets[this._view] = this._offsetBeforePatch
    this._view = view

    const remembered = this._offsets[view]
    if (remembered !== undefined) {
      this._restore(remembered)
      return
    }

    // First time into this view within the title. The main view has a row
    // worth aiming at; a sub-view has nothing to aim at, so the reader stays
    // exactly where the swap found them.
    if (view === "main") this._enter(view)
    else this._restore(this._offsetBeforePatch)
  },

  _enter(view) {
    const target = view === "main" ? this._resumeTarget() : null
    if (!target) {
      this._restore(0)
      return
    }

    // One frame, so the swapped-in list has been laid out and the row's
    // position is real.
    requestAnimationFrame(() => {
      target.scrollIntoView({ block: "center", behavior: "instant" })
    })
  },

  // Ask for an offset; hold it as the goal if it did not land.
  //
  // Two reasons it might not: the new children are in the DOM but not laid
  // out yet (one frame fixes that), or the content that would make room has
  // not arrived at all (only the next patch fixes that). So there is one
  // retry here and one more in `updated()`, and no loop — an offset a short
  // panel can never reach must settle, not fight the reader every frame.
  _restore(offset) {
    if (!this._port) return

    if (this._write(offset)) return
    this._wanted = offset

    requestAnimationFrame(() => {
      if (this._wanted === offset) this._write(offset)
    })
  },

  // Returns whether the port took the offset, clearing the goal if it did.
  _write(offset) {
    this._port.scrollTop = offset
    if (this._port.scrollTop !== offset) return false

    this._wanted = null
    return true
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
