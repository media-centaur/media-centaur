// Tooltip — the one glass label for anything carrying data-tip.
//
// Expected shape:
//   <div id="app-tooltip" class="app-tooltip" phx-hook="Tooltip"></div>
//   ...anywhere in the document: <button data-tip="Review">…</button>
//   <aside id="sidebar" data-tip-placement="right">…links with data-tip…</aside>
//
// This is the app's only tooltip. The native `title` attribute is banned
// (Credo MC0042): the browser draws it outside the page in its own chrome,
// so it ignores the theme and the UI scale, and Chromium clips its box.
// daisyUI tooltips are ::before/::after pseudo-elements of the anchor, so the
// sidebar rail (overflow-y: auto) clips them at its 52px width, and every
// other surface would have to match their look by hand. This hook is ONE
// element in <body> (position: fixed, so nothing clips it), listening on the
// document and moving next to whichever anchor is hovered or focused,
// reading the label from that anchor's data-tip. Placement comes from the
// nearest data-tip-placement — "right" on the sidebar rail, "bottom"
// (centered under the anchor) everywhere else; a tip with no room beneath
// flips above, and every tip is kept inside the viewport's edge margin
// (fitToViewport), since a label may be a full file path on an anchor at
// the window's edge.
//
// Feel: the first hover waits a beat (COLD_DELAY_MS); while the tooltip is
// warm — visible, or hidden less than WARM_WINDOW_MS ago — the next anchor's
// label shows instantly, and because position lives entirely in `transform`
// (transitioned), the open tooltip glides between neighbouring anchors.
// Keyboard/gamepad focus shows immediately: focus is deliberate, not a
// pass-through, so there is nothing to debounce.
//
// The sidebar's icon-only links are the hook's first tenant: the tip is the
// link's name, shown beside the rail.

import { parseUiScale } from "../ui_scale"

export { parseUiScale }

export const COLD_DELAY_MS = 300
export const WARM_WINDOW_MS = 250

// Beside the rail the label has room to breathe; beneath a small icon
// button the same gap read as detached, so the bottom gap is tighter.
const GAP_RIGHT_PX = 14
const GAP_BELOW_PX = 8

// The least the tip keeps between itself and the viewport's edge.
export const EDGE_MARGIN_PX = 8

/**
 * Should a tooltip show at all? Only a label is required.
 * @param {{label: string|undefined}} args
 * @returns {boolean}
 */
export function shouldShow({ label }) {
  return !!label
}

/**
 * Should focus reveal the tooltip? Only when the person is steering by
 * keyboard or gamepad — the same rule as the focus ring. A pointer click
 * that opens a modal lands programmatic focus on its first action, and a
 * tooltip popping there would be noise the person did not ask for.
 * @param {string|undefined} inputMode - value of <html data-input>
 * @returns {boolean}
 */
export function focusReveals(inputMode) {
  return inputMode === "keyboard" || inputMode === "gamepad"
}

/**
 * Delay before revealing: instant while warm, a beat when cold.
 * @param {{visible: boolean, hiddenAt: number|null, now: number}} state
 * @returns {number} milliseconds
 */
export function showDelay({ visible, hiddenAt, now }) {
  if (visible) return 0
  if (hiddenAt != null && now - hiddenAt < WARM_WINDOW_MS) return 0
  return COLD_DELAY_MS
}

/**
 * Anchor point. "right": right of the anchor with a 14px gap, vertically
 * centered. "bottom": under the anchor with an 8px gap, horizontally
 * centered.
 * The rect comes from getBoundingClientRect — viewport coordinates, already
 * multiplied by the root `zoom` UI scale — while the tooltip's transform
 * lengths are multiplied by that zoom again at render. Dividing by the scale
 * keeps (X/S)×S = X physical (the modal-clamp idiom); the gap stays in local
 * units so it scales with the UI like every other length.
 * @param {{left: number, right: number, top: number, bottom: number, width: number, height: number}} rect
 * @param {number} scale - effective root UI scale (1 when unscaled)
 * @param {"right"|"bottom"} placement
 * @returns {{x: number, y: number}}
 */
export function tooltipPosition(rect, scale, placement = "bottom") {
  if (placement === "right") {
    return { x: rect.right / scale + GAP_RIGHT_PX, y: (rect.top + rect.height / 2) / scale }
  }
  return { x: (rect.left + rect.width / 2) / scale, y: rect.bottom / scale + GAP_BELOW_PX }
}

/**
 * Keep the tip on screen. `position` is tooltipPosition's anchor point,
 * `size` the tip's own box and `viewport` the window — all in local units.
 * "bottom": x is clamped so the centred tip stays inside the edge margin,
 * and when the tip would run past the bottom it flips above the anchor
 * ("top", bottom edge on `anchorTop` minus the gap). "right": y is clamped
 * the same way; the rail's tips never reach the right edge.
 * @param {{position: {x: number, y: number}, placement: "right"|"bottom", size: {width: number, height: number}, viewport: {width: number, height: number}, anchorTop: number}} args
 * @returns {{x: number, y: number, placement: "right"|"bottom"|"top"}}
 */
export function fitToViewport({ position, placement, size, viewport, anchorTop }) {
  if (placement === "right") {
    const y = clamp(position.y, EDGE_MARGIN_PX + size.height / 2, viewport.height - EDGE_MARGIN_PX - size.height / 2)
    return { x: position.x, y, placement }
  }
  const x = clamp(position.x, EDGE_MARGIN_PX + size.width / 2, viewport.width - EDGE_MARGIN_PX - size.width / 2)
  if (position.y + size.height <= viewport.height - EDGE_MARGIN_PX) {
    return { x, y: position.y, placement: "bottom" }
  }
  return { x, y: anchorTop - GAP_BELOW_PX, placement: "top" }
}

// Lower bound wins when the range is inverted (a tip wider than the
// viewport), so the tip pins to the leading margin instead of oscillating.
function clamp(value, low, high) {
  return Math.max(low, Math.min(value, high))
}

/**
 * Should a click hide the tooltip? Only a real pointer click (detail ≥ 1)
 * means the user is acting — keyboard nav activates links via
 * element.click() (detail 0) on focus, and hiding on those would kill the
 * tooltip the instant focus reveals it.
 * @param {{detail: number}} event
 * @returns {boolean}
 */
export function clickHides(event) {
  return event.detail > 0
}

/**
 * Transform strings for the two visual states. Position lives entirely in
 * `transform` (never top/left) so movement stays compositor-only and the
 * open tooltip can glide; `entrance` starts a few px back along the
 * placement axis for the slide-in.
 * @param {{x: number, y: number}} position
 * @param {"right"|"bottom"|"top"} placement
 * @returns {{resting: string, entrance: string}}
 */
export function tooltipTransforms({ x, y }, placement = "bottom") {
  if (placement === "right") {
    const resting = `translate3d(${x}px, ${y}px, 0) translateY(-50%)`
    return { resting, entrance: `${resting} translateX(-6px)` }
  }
  if (placement === "top") {
    const resting = `translate3d(${x}px, ${y}px, 0) translate(-50%, -100%)`
    return { resting, entrance: `${resting} translateY(6px)` }
  }
  const resting = `translate3d(${x}px, ${y}px, 0) translateX(-50%)`
  return { resting, entrance: `${resting} translateY(-6px)` }
}

/** The placement declared by the nearest ancestor, "bottom" by default. */
export function placementFor(anchor) {
  return anchor.closest("[data-tip-placement]")?.dataset.tipPlacement ?? "bottom"
}

export const Tooltip = {
  mounted() {
    this.tip = this.el
    this.tip.dataset.state = "closed"
    this.tip.setAttribute("aria-hidden", "true")
    this.currentAnchor = null
    this.showTimer = null
    this.visible = false
    this.hiddenAt = null

    this.onMouseOver = (event) => {
      const anchor = event.target.closest?.("[data-tip]")
      if (!anchor || anchor === this.currentAnchor) return
      this.currentAnchor = anchor
      this.show(anchor, { immediate: false })
    }
    this.onMouseOut = (event) => {
      const anchor = event.target.closest?.("[data-tip]")
      if (!anchor || anchor.contains(event.relatedTarget)) return
      this.hide()
    }
    // Focus under keyboard/gamepad steering is deliberate — reveal without
    // delay. Focus a pointer click caused (a modal landing its cursor) is
    // not, and reveals nothing.
    this.onFocusIn = (event) => {
      const anchor = event.target.closest?.("[data-tip]")
      if (!anchor || !focusReveals(document.documentElement.dataset.input)) return
      this.currentAnchor = anchor
      this.show(anchor, { immediate: true })
    }
    this.onFocusOut = () => this.hide()
    // A pointer click acts on the anchor — it navigates, toggles, opens.
    // Keyboard activate-on-focus clicks (detail 0) keep the tooltip.
    this.onClick = (event) => {
      if (clickHides(event)) this.hide()
    }
    this.onScroll = () => this.hide()

    document.addEventListener("mouseover", this.onMouseOver)
    document.addEventListener("mouseout", this.onMouseOut)
    document.addEventListener("focusin", this.onFocusIn)
    document.addEventListener("focusout", this.onFocusOut)
    document.addEventListener("click", this.onClick)
    document.addEventListener("scroll", this.onScroll, { passive: true, capture: true })
  },

  destroyed() {
    this.hide()
    document.removeEventListener("mouseover", this.onMouseOver)
    document.removeEventListener("mouseout", this.onMouseOut)
    document.removeEventListener("focusin", this.onFocusIn)
    document.removeEventListener("focusout", this.onFocusOut)
    document.removeEventListener("click", this.onClick)
    document.removeEventListener("scroll", this.onScroll, { capture: true })
  },

  show(anchor, { immediate }) {
    const label = anchor.dataset.tip
    if (!shouldShow({ label })) return
    clearTimeout(this.showTimer)
    const delay = immediate
      ? 0
      : showDelay({ visible: this.visible, hiddenAt: this.hiddenAt, now: Date.now() })
    if (delay === 0) {
      this.reveal(anchor, label)
    } else {
      this.showTimer = setTimeout(() => this.reveal(anchor, label), delay)
    }
  },

  reveal(anchor, label) {
    const scale = parseUiScale(
      getComputedStyle(document.documentElement).getPropertyValue("--ui-scale")
    )
    // The label sets the tip's size, so it goes in before measuring. Every
    // rect is viewport (zoomed) units; the fit works in local units.
    this.tip.textContent = label
    const rect = anchor.getBoundingClientRect()
    const box = this.tip.getBoundingClientRect()
    const fit = fitToViewport({
      position: tooltipPosition(rect, scale, placementFor(anchor)),
      placement: placementFor(anchor),
      size: { width: box.width / scale, height: box.height / scale },
      viewport: { width: window.innerWidth / scale, height: window.innerHeight / scale },
      anchorTop: rect.top / scale,
    })
    const { resting, entrance } = tooltipTransforms(fit, fit.placement)
    if (this.visible) {
      // Already open: transform transition carries it to the new anchor.
      this.tip.style.transform = resting
    } else {
      // Closed: jump (transition suppressed) to the entrance pose, then
      // release the transition and settle — a 6px slide-in with the fade.
      this.tip.style.transition = "none"
      this.tip.style.transform = entrance
      this.tip.getBoundingClientRect() // flush so the jump isn't transitioned
      this.tip.style.transition = ""
      this.tip.dataset.state = "open"
      this.tip.style.transform = resting
    }
    this.visible = true
  },

  hide() {
    clearTimeout(this.showTimer)
    this.currentAnchor = null
    if (!this.visible) return
    this.visible = false
    this.hiddenAt = Date.now()
    this.tip.dataset.state = "closed"
  },
}
