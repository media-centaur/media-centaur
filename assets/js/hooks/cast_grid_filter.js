// assets/js/hooks/cast_grid_filter.js
//
// LiveView hook for the More info cast grid filter input. Real-time,
// client-side substring search — toggles per-card visibility on each
// keystroke without a server round-trip. The visible-card cap is
// enforced by the server-side `@max_cast_cards` constant in
// `cast_grid.ex`; this hook reads the cap from the input element's
// `data-max-visible` attribute so there's a single source of truth.
//
// All cast cards are rendered server-side (regardless of cap). Each
// card carries `data-cast-name` and `data-cast-character` attributes,
// pre-lowercased so this hook can do cheap case-insensitive matching
// without re-lowercasing on every keystroke.

/**
 * Pure helper — given a list of card descriptors and a query string,
 * returns the indices of the cards that should be visible, in original
 * order, capped at `maxVisible`.
 *
 * Cards: `[{name, character}, ...]` with both fields already lowercased.
 * Query: any string (or null/undefined — treated as empty).
 *
 * Exported for unit testing without a DOM. The hook below uses it
 * against DOM-derived card descriptors.
 */
export function visibleIndices(cards, query, maxVisible) {
  const q = (query || "").toLowerCase()
  const result = []

  for (let i = 0; i < cards.length; i++) {
    if (result.length >= maxVisible) break
    const card = cards[i]
    const name = card.name || ""
    const character = card.character || ""
    if (q === "" || name.includes(q) || character.includes(q)) {
      result.push(i)
    }
  }

  return result
}

export const CastGridFilter = {
  mounted() {
    this._gridSelector = `#${this.el.dataset.gridId}`
    this._maxVisible = parseInt(this.el.dataset.maxVisible, 10) || 24
    this._emptyStateSelector = this.el.dataset.emptyStateId
      ? `#${this.el.dataset.emptyStateId}`
      : null

    const input = this.el.querySelector("input[type='search']")
    if (!input) return

    this._input = input
    this._onInput = () => this._apply()
    input.addEventListener("input", this._onInput)

    this._apply()
  },

  updated() {
    // LiveView re-render replaces the cast nodes (e.g. when the user
    // navigates to a different series). Re-apply the current filter so
    // the new card set respects whatever query is in the input.
    this._apply()
  },

  destroyed() {
    if (this._input && this._onInput) {
      this._input.removeEventListener("input", this._onInput)
    }
  },

  _apply() {
    const grid = document.querySelector(this._gridSelector)
    if (!grid) return

    const cardEls = Array.from(grid.querySelectorAll("[data-cast-card]"))
    const cards = cardEls.map((el) => ({
      name: el.dataset.castName || "",
      character: el.dataset.castCharacter || ""
    }))

    const query = this._input ? this._input.value : ""
    const visible = new Set(visibleIndices(cards, query, this._maxVisible))

    cardEls.forEach((el, i) => {
      el.style.display = visible.has(i) ? "" : "none"
    })

    if (this._emptyStateSelector) {
      const emptyState = document.querySelector(this._emptyStateSelector)
      if (emptyState) {
        emptyState.hidden = visible.size > 0
      }
    }
  }
}
