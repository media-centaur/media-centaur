/**
 * DOM adapter — the ONLY module that reads/writes the DOM.
 *
 * Two interfaces: DomReader (reads layout) and DomWriter (applies changes).
 * The orchestrator receives these as constructor arguments so tests can inject mocks.
 */

import { Context } from "./focus_context"

// Selector for focusable items within each context
const CONTEXT_SELECTORS = {
  [Context.GRID]: "[data-nav-zone='grid'] [data-nav-item]",
  [Context.DRAWER]: "[data-detail-mode='drawer'] [data-nav-item]",
  [Context.MODAL]: "[data-detail-mode='modal'] [data-nav-item]",
  [Context.TOOLBAR]: "[data-nav-zone='toolbar'] [data-nav-item]",
  [Context.SIDEBAR]: "[data-nav-zone='sidebar'] [data-nav-item]",
  [Context.ZONE_TABS]: "[data-nav-zone='zone-tabs'] [data-nav-item]",
}

export const DomReader = {
  /**
   * Get the number of columns in a CSS grid container.
   * Uses computed grid-template-columns to count tracks.
   */
  getGridColumnCount(context) {
    const zoneSelector = context === Context.GRID
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
   * Get the index of the currently focused item within its context.
   */
  getFocusedIndex(context) {
    const active = this.getCurrentFocusedItem()
    if (!active) return -1

    const selector = CONTEXT_SELECTORS[context]
    if (!selector) return -1

    const items = document.querySelectorAll(selector)
    return Array.from(items).indexOf(active)
  },

  /**
   * Get the total number of focusable items in a context.
   */
  getItemCount(context) {
    const selector = CONTEXT_SELECTORS[context]
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
    return activeTab?.dataset?.navZoneValue || "watching"
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

    const selector = CONTEXT_SELECTORS[context]
    if (!selector) return -1

    const items = document.querySelectorAll(selector)
    for (let i = 0; i < items.length; i++) {
      if (items[i].dataset.entityId === entityId) return i
    }
    return -1
  },

  /**
   * Find the active zone tab index (by tab-active class).
   */
  getActiveZoneTabIndex() {
    const tabs = document.querySelectorAll(CONTEXT_SELECTORS[Context.ZONE_TABS])
    for (let i = 0; i < tabs.length; i++) {
      if (tabs[i].classList.contains("tab-active") || tabs[i].classList.contains("zone-tab-active")) return i
    }
    return -1
  },

  /**
   * Find the active toolbar tab index (by tab-active class).
   */
  getActiveToolbarTabIndex() {
    const items = document.querySelectorAll(CONTEXT_SELECTORS[Context.TOOLBAR])
    for (let i = 0; i < items.length; i++) {
      if (items[i].classList.contains("tab-active")) return i
    }
    return -1
  },

  /**
   * Get the total number of zone tabs.
   */
  getZoneTabCount() {
    return document.querySelectorAll(CONTEXT_SELECTORS[Context.ZONE_TABS]).length
  },

  /**
   * Get the sidebar collapsed preference from localStorage.
   */
  getSidebarCollapsed() {
    return localStorage.getItem("phx:sidebar-collapsed") === "true"
  },
}

export const DomWriter = {
  /**
   * Focus a specific element.
   */
  focusElement(element) {
    if (!element) return
    element.focus({ preventScroll: false })
  },

  /**
   * Focus the item at a given index within a context.
   */
  focusByIndex(context, index) {
    const selector = CONTEXT_SELECTORS[context]
    if (!selector) return

    const items = document.querySelectorAll(selector)
    const target = items[index]
    if (target) target.focus({ preventScroll: false })
  },

  /**
   * Focus the first focusable item in a context.
   */
  focusFirst(context) {
    const selector = CONTEXT_SELECTORS[context]
    if (!selector) return

    const first = document.querySelector(selector)
    if (first) first.focus({ preventScroll: false })
  },

  /**
   * Focus a nav item by its entity ID within a context.
   * Returns true if found and focused, false otherwise.
   */
  focusByEntityId(context, entityId) {
    if (!entityId) return false

    const selector = CONTEXT_SELECTORS[context]
    if (!selector) return false

    const items = document.querySelectorAll(selector)
    for (const item of items) {
      if (item.dataset.entityId === entityId) {
        item.focus({ preventScroll: false })
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
    const tabs = document.querySelectorAll(CONTEXT_SELECTORS[Context.ZONE_TABS])
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
}
