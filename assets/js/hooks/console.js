// assets/js/hooks/console.js
//
// LiveView hook for the Guake-style dropdown console.
// Handles:
// - Open/close toggle (driven by the global backtick listener in app.js via
//   a `mc:console:toggle` custom event on window)
// - data-captures-keys attribute flip so the spatial-nav input system yields
//   keyboard input to the console when open
// - Client-side text search via data-message attributes on log entries
// - Copy to clipboard (console:copy push_event)
// - Download as .log file (console:download push_event)
// - Escape / backtick inside the console also close it
// - `/` inside the console focuses the search input

export const Console = {
  mounted() {
    this._root = this.el  // <div id="console-sticky-root">
    this._panel = this._root.querySelector(".console-panel")
    this._searchInput = this._root.querySelector("[data-console-search]")
    this._entriesContainer = this._root.querySelector("#console-entries")
    this._previousState = this._root.dataset.state || "closed"

    this._onToggle = () => this._pushToggle()
    this._onKeyDown = (event) => this._handleKeyDown(event)
    this._onSearchInput = () => this._applyClientSearch()
    this._onBackdropClick = (event) => this._handleBackdropClick(event)
    this._onCopy = ({ content }) => this._copy(content)
    this._onDownload = ({ filename, content }) => this._download(filename, content)

    window.addEventListener("mc:console:toggle", this._onToggle)
    this._root.addEventListener("keydown", this._onKeyDown)
    this._root.addEventListener("click", this._onBackdropClick)
    this._searchInput?.addEventListener("input", this._onSearchInput)

    this.handleEvent("console:copy", this._onCopy)
    this.handleEvent("console:download", this._onDownload)

    // After LiveView inserts new entries: re-apply the client search filter
    // so freshly arriving log lines honor the active query. Tail-pinning
    // (keeping scrollTop at the live edge) lives in the LogTail hook on
    // each log container — drawer and full-page inherit it automatically.
    this._observer = new MutationObserver(() => {
      if (this._searchInput?.value) {
        this._applyClientSearch()
      }
    })
    if (this._entriesContainer) {
      this._observer.observe(this._entriesContainer, {
        childList: true,
        subtree: false,
      })
    }
  },

  // Phoenix LiveView calls `updated` after every server-driven re-render
  // of this element. We detect the closed→open transition and focus the
  // search input, and open→closed to blur it. Opening the drawer also
  // tells the active LogTail container to re-pin, since its layout may
  // have drifted while the panel was hidden behind a translateY(-100%).
  updated() {
    const currentState = this._root.dataset.state || "closed"
    if (currentState !== this._previousState) {
      if (currentState === "open") {
        requestAnimationFrame(() => {
          this._searchInput?.focus()
          window.dispatchEvent(new CustomEvent("mc:log-tail:repin"))
        })
      } else {
        this._searchInput?.blur()
      }
      this._previousState = currentState
    }
  },

  destroyed() {
    window.removeEventListener("mc:console:toggle", this._onToggle)
    this._root?.removeEventListener("keydown", this._onKeyDown)
    this._root?.removeEventListener("click", this._onBackdropClick)
    this._searchInput?.removeEventListener("input", this._onSearchInput)
    this._observer?.disconnect()
  },

  // Server owns open/close state. The hook pushes a `toggle_console` event
  // and the LiveView's `handle_event` flips the `:open` assign. The
  // re-render updates `data-state` and `data-captures-keys` in the template,
  // and `updated()` above picks up the DOM transition to move focus.
  _pushToggle() {
    this.pushEvent("toggle_console", {})
  },

  _isOpen() {
    return this._root.dataset.state === "open"
  },

  _handleKeyDown(event) {
    if (!this._isOpen()) return

    if (event.key === "Escape" || event.key === "`") {
      event.preventDefault()
      event.stopPropagation()
      this._pushToggle()
      return
    }

    if (event.key === "/" && document.activeElement !== this._searchInput) {
      event.preventDefault()
      this._searchInput?.focus()
    }
  },

  _handleBackdropClick(event) {
    // Clicking the dimmed area outside the panel closes the drawer.
    // When the panel is clicked, the event's `target` is inside `._panel`.
    if (!this._isOpen()) return
    if (this._panel && !this._panel.contains(event.target)) {
      this._pushToggle()
    }
  },

  _applyClientSearch() {
    if (!this._entriesContainer) return

    const query = (this._searchInput?.value || "").toLowerCase().trim()
    const entries = this._entriesContainer.querySelectorAll("[data-message]")

    entries.forEach((node) => {
      const message = node.dataset.message || ""
      const matches = query === "" || message.includes(query)
      node.style.display = matches ? "" : "none"
    })
  },

  _copy(content) {
    if (!navigator.clipboard) {
      console.error("[console] clipboard API unavailable")
      return
    }
    navigator.clipboard.writeText(content).catch((error) => {
      console.error("[console] copy failed:", error)
    })
  },

  _download(filename, content) {
    const blob = new Blob([content], { type: "text/plain;charset=utf-8" })
    const url = URL.createObjectURL(blob)
    const anchor = document.createElement("a")
    anchor.href = url
    anchor.download = filename
    document.body.appendChild(anchor)
    anchor.click()
    document.body.removeChild(anchor)
    URL.revokeObjectURL(url)
  },
}
