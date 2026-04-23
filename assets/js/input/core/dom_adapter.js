/**
 * DOM adapter — the ONLY module that reads/writes the DOM.
 *
 * Factory functions create reader/writer instances parameterized by config.
 * The orchestrator receives these as constructor arguments so tests can
 * inject mocks.
 *
 * @param {Object} config
 * @param {Object} config.contextSelectors - Maps context keys to CSS selectors
 * @param {string[]} config.activeClassNames - CSS classes indicating active state
 */

/**
 * Create a DomReader that queries the DOM using the given config.
 * @param {Object} [config={}]
 * @returns {Object} DomReader interface
 */
export function createDomReader(config = {}) {
  const selectors = config.contextSelectors ?? {}
  const activeClasses = config.activeClassNames ?? []

  return {
    /**
     * Get the number of columns in a CSS grid container.
     * Uses computed grid-template-columns to count tracks.
     */
    getGridColumnCount(context) {
      const zoneSelector = context === "grid"
        ? "[data-nav-zone='grid']"
        : `[data-nav-zone='${context}']`
      const container = document.querySelector(zoneSelector)
      if (!container) return 1

      const gridEl = container.querySelector("[data-nav-grid]") || container
      const columns = getComputedStyle(gridEl).gridTemplateColumns
      if (!columns || columns === "none") return 1
      return columns.split(" ").length
    },

    /**
     * Get the currently focused element if it's a nav item.
     */
    getCurrentFocusedItem() {
      const active = document.activeElement
      return active?.hasAttribute("data-nav-item") ? active : null
    },

    /**
     * Get the currently focused element if it's a nav sub-item.
     */
    getCurrentFocusedSubItem() {
      const active = document.activeElement
      return active?.hasAttribute("data-nav-sub-item") ? active : null
    },

    /**
     * Get the nav item at a given index within a context.
     */
    getItemAt(context, index) {
      const selector = selectors[context]
      if (!selector) return null
      const items = document.querySelectorAll(selector)
      return items[index] ?? null
    },

    /**
     * Get the index of the currently focused item within its context.
     */
    getFocusedIndex(context) {
      const active = this.getCurrentFocusedItem()
      if (!active) return -1

      const selector = selectors[context]
      if (!selector) return -1

      const items = document.querySelectorAll(selector)
      return Array.from(items).indexOf(active)
    },

    /**
     * Get the total number of focusable items in a context.
     */
    getItemCount(context) {
      const selector = selectors[context]
      if (!selector) return 0
      return document.querySelectorAll(selector).length
    },

    /**
     * Check if the drawer is currently open.
     */
    isDrawerOpen() {
      return !!document.querySelector("[data-detail-mode='drawer']")
    },

    /**
     * Check if a modal is currently open.
     */
    isModalOpen() {
      return !!document.querySelector("[data-detail-mode='modal']")
    },

    /**
     * Get current zone from the page.
     */
    getZone() {
      const tabGroup = document.querySelector("[data-nav-zone='zone-tabs']")
      const activeTab = tabGroup?.querySelector(".tab-active, .zone-tab-active")
      if (activeTab?.dataset?.navZoneValue) return activeTab.dataset.navZoneValue

      const defaultZone = document.querySelector("[data-nav-default-zone]")
      return defaultZone?.dataset?.navDefaultZone ?? "watching"
    },

    getSortOrder() {
      return document.querySelector("[data-sort]")?.dataset?.sort || null
    },

    /**
     * Get the current detail view within an open modal.
     * Returns "main" or "info", or null if no modal is open.
     */
    getDetailView() {
      return document.querySelector("[data-detail-mode='modal']")?.dataset?.detailView ?? null
    },

    /**
     * Get the custom dismiss event name for the current modal, or null if not specified.
     * The orchestrator falls back to "close_detail" when null.
     */
    getDismissEvent() {
      return document.querySelector("[data-detail-mode='modal']")?.dataset?.dismissEvent ?? null
    },

    /**
     * Get the current presentation mode.
     */
    getPresentation() {
      if (this.isModalOpen()) return "modal"
      if (this.isDrawerOpen()) return "drawer"
      return null
    },

    /**
     * Get the index of a nav item by its entity ID within a context.
     */
    getEntityIndex(context, entityId) {
      if (!entityId) return -1

      const selector = selectors[context]
      if (!selector) return -1

      const items = document.querySelectorAll(selector)
      for (let i = 0; i < items.length; i++) {
        if (items[i].dataset.entityId === entityId) return i
      }
      return -1
    },

    /**
     * Find the active zone tab index (by active class).
     */
    getActiveZoneTabIndex() {
      const selector = selectors["zone_tabs"]
      if (!selector) return -1
      const tabs = document.querySelectorAll(selector)
      for (let i = 0; i < tabs.length; i++) {
        if (activeClasses.some(cls => tabs[i].classList.contains(cls))) return i
      }
      return -1
    },

    /**
     * Get the total number of zone tabs.
     */
    getZoneTabCount() {
      const selector = selectors["zone_tabs"]
      if (!selector) return 0
      return document.querySelectorAll(selector).length
    },

    /**
     * Find the index of the item marked active in any context.
     * Checks the configured active class names.
     * Returns -1 if none is active.
     */
    getActiveItemIndex(context) {
      const selector = selectors[context]
      if (!selector) return -1
      const items = document.querySelectorAll(selector)
      for (let i = 0; i < items.length; i++) {
        const cl = items[i].classList
        if (activeClasses.some(cls => cl.contains(cls))) return i
      }
      return -1
    },

    /**
     * Get the sidebar collapsed preference from localStorage.
     */
    getSidebarCollapsed() {
      return localStorage.getItem("phx:sidebar-collapsed") === "true"
    },

    /**
     * Get the page behavior name from the data-page-behavior attribute.
     * Returns null if no behavior is set.
     */
    getPageBehavior() {
      return document.querySelector("[data-page-behavior]")?.dataset?.pageBehavior ?? null
    },
  }
}

/**
 * Create a DomWriter that modifies the DOM using the given config.
 * @param {Object} [config={}]
 * @returns {Object} DomWriter interface
 */
export function createDomWriter(config = {}) {
  const selectors = config.contextSelectors ?? {}

  return {
    /**
     * Focus a specific element.
     */
    focusElement(element) {
      if (!element) return
      element.focus({ preventScroll: true })
      element.scrollIntoView({ block: "nearest", behavior: "instant" })
    },

    /**
     * Focus the item at a given index within a context.
     * Returns true if the element was found and focused, false otherwise.
     */
    focusByIndex(context, index) {
      const selector = selectors[context]
      if (!selector) return false

      const items = document.querySelectorAll(selector)
      const target = items[index]
      if (!target) return false
      target.focus({ preventScroll: true })
      target.scrollIntoView({ block: "nearest", behavior: "instant" })
      return document.activeElement === target
    },

    /**
     * Focus the first focusable item in a context.
     * Returns true if the element was found and focused, false otherwise.
     */
    focusFirst(context) {
      const selector = selectors[context]
      if (!selector) return false

      const first = document.querySelector(selector)
      if (!first) return false
      first.focus({ preventScroll: true })
      first.scrollIntoView({ block: "nearest", behavior: "instant" })
      return document.activeElement === first
    },

    /**
     * Focus a nav item by its entity ID within a context.
     * Returns true if found and focused, false otherwise.
     */
    focusByEntityId(context, entityId) {
      if (!entityId) return false

      const selector = selectors[context]
      if (!selector) return false

      const items = document.querySelectorAll(selector)
      for (const item of items) {
        if (item.dataset.entityId === entityId) {
          item.focus({ preventScroll: true })
          item.scrollIntoView({ block: "nearest", behavior: "instant" })
          return true
        }
      }
      return false
    },

    /**
     * Set the current input method on the <html> element.
     * Used by CSS to show/hide focus rings.
     */
    setInputMethod(method) {
      document.documentElement.dataset.input = method
    },

    /**
     * Project keyboard-source text-input edit mode onto <html>.
     * Used by CSS to visually distinguish nav mode from edit mode.
     */
    setTextEditing(editing) {
      if (editing) {
        document.documentElement.dataset.inputEditing = "true"
      } else {
        delete document.documentElement.dataset.inputEditing
      }
    },

    /**
     * Set inert attribute on elements matching selector (for focus trapping).
     */
    setInert(selector, value) {
      document.querySelectorAll(selector).forEach(el => {
        if (value) {
          el.setAttribute("inert", "")
        } else {
          el.removeAttribute("inert")
        }
      })
    },

    /**
     * Flash a visual feedback class on an element.
     */
    flashElement(element, className = "nav-flash", duration = 300) {
      if (!element) return
      element.classList.add(className)
      setTimeout(() => element.classList.remove(className), duration)
    },

    /**
     * Click a zone tab by index to trigger navigation.
     */
    clickZoneTab(index) {
      const selector = selectors["zone_tabs"]
      if (!selector) return
      const tabs = document.querySelectorAll(selector)
      tabs[index]?.click()
    },

    /**
     * Set sidebar expanded/collapsed state on <html>.
     */
    setSidebarState(collapsed) {
      if (collapsed) {
        document.documentElement.dataset.sidebar = "collapsed"
      } else {
        delete document.documentElement.dataset.sidebar
      }
    },

    /**
     * Set the current nav context on <html> for hint bar CSS.
     */
    setNavContext(context) {
      document.documentElement.dataset.navContext = context
    },

    /**
     * Set the controller type on <html> for hint bar button labels.
     */
    setControllerType(type) {
      document.documentElement.dataset.gamepadType = type
    },
  }
}
