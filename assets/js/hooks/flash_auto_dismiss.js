// FlashAutoDismiss — auto-clears a user-action toast after a short dwell,
// then lets it transition out smoothly. Saving a form and then having to
// click the confirmation toast away is miserable; this removes that step.
//
// Expected shape (set by the user `:info` / `:error` flashes in
// `flash_group/1`):
//   <div phx-hook="FlashAutoDismiss" id="flash-info" data-dismiss-after="4000"
//        phx-click={...clear-flash + hide transition...}>
//
// On expiry it replays the element's OWN `phx-click` via `execJS`, so the
// exit animation and the server-side `lv:clear-flash` are identical to a
// manual close — one dismiss path, not two.
//
// Connection-state toasts (client-error / server-error / update-applying)
// deliberately omit `data-dismiss-after`: they reflect an ongoing condition
// and must persist until it resolves, so they never mount this hook.
//
// Pointer hover or keyboard focus pauses the countdown so a user reading or
// interacting with the toast isn't cut off; leaving restarts it.

export function parseDelay(value) {
  const ms = Number.parseInt(value, 10)
  return Number.isFinite(ms) && ms > 0 ? ms : null
}

export const FlashAutoDismiss = {
  mounted() {
    this._onPause = () => this._pause()
    this._onResume = () => this._start()
    this.el.addEventListener("mouseenter", this._onPause)
    this.el.addEventListener("mouseleave", this._onResume)
    this.el.addEventListener("focusin", this._onPause)
    this.el.addEventListener("focusout", this._onResume)
    this._start()
  },

  updated() {
    // A fresh message reuses the same element (stable id `flash-<kind>`),
    // so `mounted` won't fire again — restart here to give the new toast
    // its full dwell instead of inheriting the previous one's remaining time.
    this._start()
  },

  destroyed() {
    this._pause()
    this.el.removeEventListener("mouseenter", this._onPause)
    this.el.removeEventListener("mouseleave", this._onResume)
    this.el.removeEventListener("focusin", this._onPause)
    this.el.removeEventListener("focusout", this._onResume)
  },

  _start() {
    this._pause()
    const delay = parseDelay(this.el.dataset.dismissAfter)
    if (!delay) return
    this._timer = setTimeout(() => this._dismiss(), delay)
  },

  _pause() {
    if (this._timer) {
      clearTimeout(this._timer)
      this._timer = null
    }
  },

  _dismiss() {
    const js = this.el.getAttribute("phx-click")
    if (js) this.liveSocket.execJS(this.el, js)
  }
}
