// CopyButton — one-click copy of a command string to the clipboard.
//
// Expected shape:
//   <button phx-hook="CopyButton" id="..." data-copy-text="...">Copy</button>
//
// On click: writes `data-copy-text` to the clipboard via the browser API,
// briefly swaps the button label to "Copied!" as feedback, then restores.
// No LiveView events — pure client-side.

export const CopyButton = {
  mounted() {
    this._handler = () => this._copy()
    this.el.addEventListener("click", this._handler)
  },

  destroyed() {
    if (this._handler) this.el.removeEventListener("click", this._handler)
  },

  async _copy() {
    const text = this.el.dataset.copyText || ""
    if (!text) return

    try {
      await navigator.clipboard.writeText(text)
    } catch {
      // Fallback for older browsers / insecure contexts.
      const textarea = document.createElement("textarea")
      textarea.value = text
      textarea.setAttribute("readonly", "")
      textarea.style.position = "fixed"
      textarea.style.opacity = "0"
      document.body.appendChild(textarea)
      textarea.select()
      try { document.execCommand("copy") } finally {
        document.body.removeChild(textarea)
      }
    }

    const original = this.el.innerText
    const revertAt = Date.now() + 1500
    this.el.innerText = "Copied!"
    this.el.dataset.revertAt = String(revertAt)
    setTimeout(() => {
      // Only revert if we're still the most recent copy — prevents a rapid
      // second click from being reverted by the first click's timer.
      if (this.el.dataset.revertAt === String(revertAt)) {
        this.el.innerText = original
        delete this.el.dataset.revertAt
      }
    }, 1500)
  }
}
