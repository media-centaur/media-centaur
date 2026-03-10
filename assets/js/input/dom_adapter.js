/**
 * DOM adapter — the ONLY module that reads/writes the DOM.
 *
 * Two interfaces: DomReader (reads layout) and DomWriter (applies changes).
 * The orchestrator receives these as constructor arguments so tests can inject mocks.
 */

import { Context } from "./focus_context"

// Selector for focusable items within each context.
// Context enum values are used for standard contexts; instance names
// (like "sidebar") are used for MENU instances that share behavior
// but have distinct DOM selectors.
const CONTEXT_SELECTORS = {
  [Context.GRID]: "[data-nav-zone='grid'] [data-nav-item]",
  [Context.DRAWER]: "[data-detail-mode='drawer'] [data-nav-item]",
  [Context.MODAL]: "[data-detail-mode='modal'] [data-nav-item]",
  [Context.TOOLBAR]: "[data-nav-zone='toolbar'] [data-nav-item]",
  sidebar: "[data-nav-zone='sidebar'] [data-nav-item]",
  sections: "[data-nav-zone='sections'] [data-nav-item]",
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
    if (activeTab?.dataset?.navZoneValue) return activeTab.dataset.navZoneValue

    const defaultZone = document.querySelector("[data-nav-default-zone]")
    return defaultZone?.dataset?.navDefaultZone ?? "watching"
  },

  getSortOrder() {
    return document.querySelector("[data-sort]")?.dataset?.sort || null
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
   * Get the total number of zone tabs.
   */
  getZoneTabCount() {
    return document.querySelectorAll(CONTEXT_SELECTORS[Context.ZONE_TABS]).length
  },

  /**
   * Find the index of the item marked active in any context.
   * Checks a standard set of "active" class names used across the app.
   * Replaces per-context active-item finders with a single generic method.
   * Returns -1 if none is active.
   */
  getActiveItemIndex(context) {
    const selector = CONTEXT_SELECTORS[context]
    if (!selector) return -1
    const items = document.querySelectorAll(selector)
    for (let i = 0; i < items.length; i++) {
      const cl = items[i].classList
      if (cl.contains("sidebar-link-active") ||
          cl.contains("tab-active") ||
          cl.contains("zone-tab-active") ||
          cl.contains("menu-item-active")) return i
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

export const DomWriter = {
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
    const selector = CONTEXT_SELECTORS[context]
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
    const selector = CONTEXT_SELECTORS[context]
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

    const selector = CONTEXT_SELECTORS[context]
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
