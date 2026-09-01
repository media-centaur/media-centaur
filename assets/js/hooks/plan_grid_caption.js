// PlanGridCaption — the plan board's episode grid captions the cell under
// the pointer or the cursor (UIDR-029): the caption line beneath the grid
// shows that episode's outcome and best release, replacing per-cell
// tooltips, which a gamepad or keyboard cursor never sees.
//
// Expected shape:
//   <div phx-hook="PlanGridCaption" id="plan-grid">
//     … <span data-nav-item data-caption="E03 — Show.S01E03.1080p">3</span> …
//     <p data-plan-caption></p>
//   </div>
//
// Pure client-side: focus and hover are presentation, not state the server
// needs — a round trip per hovered cell would lag a held d-pad.

/**
 * The caption to show: the hovered cell's, else the focused cell's, else
 * nothing. The pointer is the more deliberate signal, so it wins while it
 * rests on a cell even if the cursor sits elsewhere.
 */
export function captionFor(hovered, focused) {
  return hovered?.dataset?.caption ?? focused?.dataset?.caption ?? ""
}

export const PlanGridCaption = {
  mounted() {
    this._hovered = null
    this._onOver = event => { this._hovered = this._cell(event.target); this._render() }
    this._onOut = event => {
      if (this._cell(event.target) === this._hovered) this._hovered = null
      this._render()
    }
    this._onFocus = () => this._render()
    this.el.addEventListener("mouseover", this._onOver)
    this.el.addEventListener("mouseout", this._onOut)
    this.el.addEventListener("focusin", this._onFocus)
    this.el.addEventListener("focusout", this._onFocus)
    this._render()
  },

  // A patch can replace the cell the cursor is on; re-read after each one.
  updated() {
    this._render()
  },

  destroyed() {
    this.el.removeEventListener("mouseover", this._onOver)
    this.el.removeEventListener("mouseout", this._onOut)
    this.el.removeEventListener("focusin", this._onFocus)
    this.el.removeEventListener("focusout", this._onFocus)
  },

  _cell(target) {
    return target instanceof Element ? target.closest("[data-caption]") : null
  },

  _render() {
    const focused = this._cell(document.activeElement)
    const hovered = this._hovered?.isConnected ? this._hovered : null
    const line = this.el.querySelector("[data-plan-caption]")
    if (line) line.textContent = captionFor(hovered, focused)
  },
}
