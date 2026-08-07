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

import { Context } from "./focus_context"
import { createScrollGlide } from "./scroll_glide"

/**
 * The element that owns the active modal overlay — the first
 * `[data-detail-mode='modal']` match in DOM order. detailNested, dismissEvent,
 * and item queries all derive from this one element so a stacked overlay
 * (a confirm dialog rendered before — and over — a detail modal) owns
 * navigation and BACK together. Pages that stack modals must render the
 * topmost overlay first among their `[data-detail-mode]` elements.
 */
function activeModalElement() {
  return document.querySelector("[data-detail-mode='modal']")
}

/**
 * A disabled or hidden control is never a nav target: the browser refuses to
 * focus it, so including it would make focusByIndex fail and jam the cursor on
 * the item before it (unable to step past to reach later ones). Filter it out
 * at the single chokepoint so count, index, and focus all agree.
 *
 * Hidden covers more than `display: none`: a control inside a collapsed
 * `<details>` is hidden via `content-visibility`, so it still matches the
 * selector and reports client rects, yet cannot be focused. `checkVisibility()`
 * is the one predicate that catches every such case (the Settings → System
 * "Prefer the terminal?" disclosure wraps Copy buttons this way, which used to
 * wall off the "Update now" button from keyboard navigation).
 */
function isNavigable(el) {
  return !el.disabled && !el.hasAttribute("disabled") && el.checkVisibility()
}

/**
 * Resolve the nav items for a context. MODAL items are scoped to the active
 * modal element (see `activeModalElement`); every other context uses its
 * flat config selector. Disabled items are excluded (see `isNavigable`).
 * Returns an array (possibly empty).
 */
function queryContextItems(selectors, context) {
  if (context === Context.MODAL) {
    const modal = activeModalElement()
    return modal ? Array.from(modal.querySelectorAll("[data-nav-item]")).filter(isNavigable) : []
  }
  const selector = selectors[context]
  if (!selector) return []
  return Array.from(document.querySelectorAll(selector)).filter(isNavigable)
}

/**
 * Focus an element and bring it into view — the single owner of "make the
 * focused item visible". Every writer entry point routes through here, so the
 * question is answered once.
 *
 * The split with CSS: **the input system owns where the scroll lands; CSS owns
 * how it gets there.** Those are genuinely different concerns, and each side
 * must stay out of the other's.
 *
 * CSS must not touch the destination. A `scroll-snap-type: … mandatory`
 * container re-snaps after `scrollIntoView` to the nearest snap boundary,
 * which undershoots and parks the focused card partly outside the scrollport —
 * measured at ~100px, a third of a card, on every home-shelf card past the
 * fold. Scroll snap is a *pointer* affordance (flick, release, settle
 * somewhere sensible); with a focus cursor there is nothing to settle, because
 * the focused element already IS the resting position. So `.row-scroll` does
 * not snap.
 *
 * The transition is ours too, but it is a separate concern with its own module
 * (`scroll_glide.js`) — neither of the browser's smooth-scroll routes survives
 * held input, and that docstring records the measurements. What stays here is
 * only the question of *where*, answered the way it always was: by asking the
 * browser.
 *
 * We do that by scrolling instantly, reading where that landed, putting the
 * offsets back, and gliding to the recorded destination. It looks roundabout,
 * and the alternative is worse: computing the destination ourselves means
 * reimplementing `scrollIntoView`'s "nearest" algorithm including
 * `scroll-padding`, borders, and writing modes — a pile of geometry the engine
 * already gets right. Nothing paints between the jump and the restore (it is
 * all one task), so there is no flicker.
 *
 * Focus itself is always instantaneous: `focus()` is synchronous and the
 * scroll animates behind it. The cursor is never where the animation is, so
 * SELECT mid-glide activates the card the user is actually on.
 */
function revealItem(element, glider) {
  element.focus({ preventScroll: true })

  // What to show is not always the item itself. A `[data-nav-reveal]` ancestor
  // claims the reveal for a larger region — the home hero's Play button sits
  // low in a full-bleed backdrop, so revealing the button alone would park it
  // at the bottom edge with the title and artwork above it off-screen.
  const subject = element.closest?.("[data-nav-reveal]") ?? element

  // "nearest" scrolls as little as possible, which means it aligns to whichever
  // edge you arrived from — so a row sits in a different place depending on
  // whether you reached it going up or going down. A surface that wants ONE
  // resting position regardless of approach declares the alignment instead.
  const declared = element.closest?.("[data-nav-reveal-block]")?.dataset?.navRevealBlock

  const boxes = scrollableAncestors(element)
  // Nothing can move this element relative to the viewport — it is pinned. Skip
  // the measuring jump too: it would scroll boxes we have not recorded and so
  // cannot put back.
  if (boxes.length === 0) return

  const before = boxes.map(box => [box.scrollLeft, box.scrollTop])
  const rewind = () => boxes.forEach((box, i) => {
    box.scrollLeft = before[i][0]
    box.scrollTop = before[i][1]
  })

  subject.scrollIntoView({ block: declared ?? "nearest", inline: "nearest", behavior: "instant" })

  // The declared alignment is a preference, not a promise. A shelf's reserve
  // can outgrow the viewport at large UI scales, and honouring the alignment
  // then pushes the focused item off the opposite edge — worse than not framing
  // it. Keeping the item on screen wins.
  if (declared && !isFullyInView(element)) {
    rewind()
    subject.scrollIntoView({ block: "nearest", inline: "nearest", behavior: "instant" })
  }

  const after = boxes.map(box => [box.scrollLeft, box.scrollTop])
  rewind()
  boxes.forEach((box, i) => glider.glide(box, { left: after[i][0], top: after[i][1] }))
}

/** Whether the element's block extent lies wholly within the viewport. */
function isFullyInView(element) {
  const rect = element.getBoundingClientRect()
  return rect.top >= 0 && rect.bottom <= document.documentElement.clientHeight
}

/**
 * Every scroll container between `element` and the document that could have
 * been moved by scrollIntoView — a media row, then the page.
 *
 * The walk stops at a **pinned** ancestor (`position: sticky` or `fixed`),
 * because scrollers outside one cannot reveal anything inside it: scrolling
 * them moves the ancestor by the same amount, so the element never arrives.
 * `scrollIntoView` does not detect this and does not converge — asked again
 * from the position it just produced, it asks for a little more.
 *
 * Measured in the detail modal, whose action row sits in a sticky orientation
 * block: walking left/right along Play / More info / Manage ratcheted the panel
 * 123 → 325 → 527 → 729px, in *both* directions, never coming back. There was
 * nothing to reveal — a pinned row is visible by construction, which is the
 * entire point of pinning it.
 *
 * Scrollers *inside* the pinned ancestor are still collected: they move
 * relative to it, so they can still reveal.
 */
function scrollableAncestors(element) {
  const boxes = []
  for (let node = element.parentElement; node; node = node.parentElement) {
    const style = getComputedStyle(node)
    if (style.position === "sticky" || style.position === "fixed") return boxes
    const overflow = `${style.overflowX} ${style.overflowY}`
    if (!/auto|scroll|overlay/.test(overflow)) continue
    if (node.scrollWidth > node.clientWidth || node.scrollHeight > node.clientHeight) {
      boxes.push(node)
    }
  }
  const root = document.scrollingElement
  if (root) boxes.push(root)
  return boxes
}

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
     * True when focus currently lives on an element the input system does NOT
     * own — the ownership-by-containment signal the post-patch reconciler uses
     * to decide whether to re-assert nav focus.
     *
     * Focus is the system's to manage only when it sits inside a managed nav
     * region (`[data-nav-item]` / `[data-nav-zone]`), or when it has genuinely
     * dropped to `<body>` / `<html>` / nothing (a patch destroyed the focused
     * item — the reconciler restores it). Focus is *foreign* when a real
     * element outside every managed region holds it: an unmanaged overlay's
     * input, button, or card (the Track-new-release modal is a plain
     * `data-state` overlay, not a `data-detail-mode` context), or anything that
     * captures its own keys. Re-asserting nav focus over foreign focus yanks
     * the cursor mid-interaction, so the reconciler cedes. See ADR-053.
     *
     * This is the containment generalization of "is the user typing": it
     * protects an overlay's non-editable controls too, and — unlike a
     * tag-based editable check — it does NOT cede for a managed filter input
     * that lives inside a nav zone (those still navigate by arrow keys).
     */
    hasForeignFocus() {
      const active = document.activeElement
      if (!active || active === document.body || active === document.documentElement) return false
      if (active.closest("[data-captures-keys]")) return true
      return !active.closest("[data-nav-item],[data-nav-zone]")
    },

    /**
     * Get the nav item at a given index within a context.
     */
    getItemAt(context, index) {
      return queryContextItems(selectors, context)[index] ?? null
    },

    /**
     * Get the index of the currently focused item within its context.
     */
    getFocusedIndex(context) {
      const active = this.getCurrentFocusedItem()
      if (!active) return -1
      return queryContextItems(selectors, context).indexOf(active)
    },

    /**
     * Get the total number of focusable items in a context.
     */
    getItemCount(context) {
      return queryContextItems(selectors, context).length
    },

    /**
     * Get the on-screen rect of every navigable item in a context, in DOM
     * order — the geometry spatial navigation reasons over.
     *
     * Rects are viewport coordinates, so they are post-UI-scale and post-scroll
     * and every candidate is measured in the same frame. That makes them
     * internally consistent, which is all `findNearest` needs; they must never
     * be mixed with the layout-px `scrollLeft`/`offsetLeft` family.
     */
    getItemRects(context) {
      return queryContextItems(selectors, context).map(el => {
        const r = el.getBoundingClientRect()
        return { x: r.x, y: r.y, width: r.width, height: r.height }
      })
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
     * Whether the open detail modal is showing something other than its root
     * view, so BACK returns within the overlay instead of dismissing it.
     *
     * The server decides this, not us: the root view is not always the same
     * one. A title with no contents of its own (a movie with no extras) has
     * no body tab and opens on More info, which *is* its root. Comparing a
     * view name against "main" here got that case wrong in both directions.
     */
    isDetailNested() {
      return activeModalElement()?.dataset?.detailNested === "true"
    },

    /**
     * The name of the open overlay's navigation model, or null when the overlay
     * doesn't declare one and is therefore a flat list of items. Names an entry
     * in `config.overlays` — which regions it has and how they relate.
     */
    getOverlayName() {
      return activeModalElement()?.dataset?.navOverlay ?? null
    },

    /**
     * Get the custom dismiss event name for the current modal, or null if not specified.
     * The orchestrator falls back to "close_detail" when null.
     */
    getDismissEvent() {
      return activeModalElement()?.dataset?.dismissEvent ?? null
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
     * The index of the first nav item in a context matching a CSS selector,
     * or -1. Lets config name a context's opening position declaratively —
     * the detail body's `[data-resume-target]` — instead of the orchestrator
     * knowing what a resume target is.
     */
    getMatchingIndex(context, selector) {
      return queryContextItems(selectors, context).findIndex(el => el.matches?.(selector))
    },

    /**
     * Get the index of a nav item by its entity ID within a context.
     */
    getEntityIndex(context, entityId) {
      if (!entityId) return -1

      const items = queryContextItems(selectors, context)
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
      const items = queryContextItems(selectors, context)
      for (let i = 0; i < items.length; i++) {
        const cl = items[i].classList
        if (activeClasses.some(cls => cl.contains(cls))) return i
      }
      return -1
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
 * @param {Object} [config.glider] - Scroll glide instance; defaults to a real
 *   one driven by rAF. Injected so tests can drive frames by hand.
 * @returns {Object} DomWriter interface
 */
export function createDomWriter(config = {}) {
  const selectors = config.contextSelectors ?? {}
  const glider = config.glider ?? createScrollGlide({
    requestAnimationFrame: fn => globalThis.requestAnimationFrame(fn),
    now: () => performance.now(),
  })

  return {
    /**
     * Focus a specific element.
     */
    focusElement(element) {
      if (!element) return
      revealItem(element, glider)
    },

    /**
     * Focus the item at a given index within a context.
     * Returns true if the element was found and focused, false otherwise.
     */
    focusByIndex(context, index) {
      const target = queryContextItems(selectors, context)[index]
      if (!target) return false
      revealItem(target, glider)
      return document.activeElement === target
    },

    /**
     * Focus the first focusable item in a context.
     * Returns true if the element was found and focused, false otherwise.
     */
    focusFirst(context) {
      const first = queryContextItems(selectors, context)[0]
      if (!first) return false
      revealItem(first, glider)
      return document.activeElement === first
    },

    /**
     * Focus a nav item by its entity ID within a context.
     * Returns true if found and focused, false otherwise.
     */
    focusByEntityId(context, entityId) {
      if (!entityId) return false

      const items = queryContextItems(selectors, context)
      for (const item of items) {
        if (item.dataset.entityId === entityId) {
          revealItem(item, glider)
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
