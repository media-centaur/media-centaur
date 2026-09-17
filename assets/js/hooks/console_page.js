// assets/js/hooks/console_page.js
//
// Client half of the /console page.
//
// - Client-side text search: the server persists the query (so copy and
//   download honour it, and so it survives a reload) but deliberately does
//   NOT re-stream on a search-only filter change — resetting a stream of
//   thousands of rows on every debounced keystroke is a large diff over the
//   wire for a decision the browser can make from `data-message`.
// - Copy to clipboard (`console:copy` push_event).
// - Download as a .log file (`console:download` push_event).
//
// Scroll pinning is not this hook's business: the log container carries
// `phx-hook="LogTail"`.

export const ConsolePage = {
  mounted() {
    this._searchInput = this.el.querySelector("[data-console-search]")
    this._entriesContainer = this.el.querySelector("#console-entries")

    this._onSearchInput = () => this._applyClientSearch()
    this._onCopy = ({ content }) => this._copy(content)
    this._onDownload = ({ filename, content }) => this._download(filename, content)

    this._searchInput?.addEventListener("input", this._onSearchInput)

    this.handleEvent("console:copy", this._onCopy)
    this.handleEvent("console:download", this._onDownload)

    // After LiveView inserts new rows: re-apply the active query so freshly
    // arriving entries honour it too.
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

    // A reload restores the persisted query into the input; apply it to the
    // rows the first paint brought with it.
    this._applyClientSearch()
  },

  destroyed() {
    this._searchInput?.removeEventListener("input", this._onSearchInput)
    this._observer?.disconnect()
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
