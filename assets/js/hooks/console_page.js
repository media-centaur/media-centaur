// assets/js/hooks/console_page.js
//
// Client half of the /console page.
//
// - The text search is the browser's, and only the browser's: the rows are
//   already on the page, so hiding them by `data-message` needs no server,
//   and re-streaming thousands of rows per keystroke would be a large diff
//   for nothing. The query survives a reload in localStorage (a per-viewer
//   convenience; the page works without it).
// - Copy and download: the buttons dispatch `console:request`, and this hook
//   pushes the event with the query, because the server holds none. The
//   server answers with `console:copy` / `console:download`.
//
// Scroll pinning is not this hook's business: the log container carries
// `phx-hook="LogTail"`.

const STORAGE_KEY = "console:search"

function readStoredQuery() {
  try {
    return globalThis.localStorage?.getItem(STORAGE_KEY) || ""
  } catch (_error) {
    return ""
  }
}

function storeQuery(query) {
  try {
    globalThis.localStorage?.setItem(STORAGE_KEY, query)
  } catch (_error) {
    // Blocked storage costs only the reload persistence.
  }
}

export const ConsolePage = {
  mounted() {
    this._searchInput = this.el.querySelector("[data-console-search]")
    this._entriesContainer = this.el.querySelector("#console-entries")

    this._onSearchInput = () => {
      storeQuery(this._searchInput?.value || "")
      this._applyClientSearch()
    }
    this._onRequest = (event) => {
      const name = event.detail?.event
      if (name) this.pushEvent(name, { search: this._searchInput?.value || "" })
    }
    this.el.addEventListener?.("console:request", this._onRequest)

    if (this._searchInput && !this._searchInput.value) {
      this._searchInput.value = readStoredQuery()
    }
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

    // A reload restored the stored query into the input above; apply it to
    // the rows the first paint brought with it.
    this._applyClientSearch()
  },

  destroyed() {
    this._searchInput?.removeEventListener("input", this._onSearchInput)
    this.el.removeEventListener?.("console:request", this._onRequest)
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
