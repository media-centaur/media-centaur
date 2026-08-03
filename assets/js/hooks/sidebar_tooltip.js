// SidebarTooltip — glass label tooltip for the collapsed sidebar rail.
//
// Expected shape:
//   <aside id="sidebar" phx-hook="SidebarTooltip"> ...links with data-tip... </aside>
//
// daisyUI tooltips can't work here: they are ::before/::after pseudo-elements
// of the link, and both the rail (overflow-y: auto) and each link
// (overflow: hidden) clip anything that pokes past the 52px collapsed width.
// This hook instead keeps ONE tooltip element in <body> (position: fixed,
// so nothing clips it) and moves it next to whichever link is hovered or
// focused, reading the label from that link's data-tip.
//
// Feel: the first hover waits a beat (COLD_DELAY_MS); while the tooltip is
// warm — visible, or hidden less than WARM_WINDOW_MS ago — the next link's
// label shows instantly, and because position lives entirely in `transform`
// (transitioned), the open tooltip glides down the rail between icons.
// Keyboard/gamepad focus shows immediately: focus is deliberate, not a
// pass-through, so there is nothing to debounce.
//
// Tooltips only apply while <html data-sidebar="collapsed"> — expanded mode
// renders the label text on the link itself.

export const COLD_DELAY_MS = 300
export const WARM_WINDOW_MS = 250

const TOOLTIP_ID = "sidebar-tooltip"
const GAP_PX = 10

/**
 * Should a tooltip show at all, given the sidebar state and the link label?
 * @param {string|undefined} sidebarState - value of <html data-sidebar>
 * @param {string|undefined} label - the link's data-tip
 * @returns {boolean}
 */
export function shouldShow(sidebarState, label) {
  return sidebarState === "collapsed" && !!label
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
 * Anchor point: right of the link with a gap, vertically centered.
 * The rect comes from getBoundingClientRect — viewport coordinates, already
 * multiplied by the root `zoom` UI scale — while the tooltip's transform
 * lengths are multiplied by that zoom again at render. Dividing by the scale
 * keeps (X/S)×S = X physical (the modal-clamp idiom); the gap stays in local
 * units so it scales with the UI like every other length.
 * @param {{right: number, top: number, height: number}} rect - link bounding rect
 * @param {number} scale - effective root UI scale (1 when unscaled)
 * @returns {{x: number, y: number}}
 */
export function tooltipPosition(rect, scale) {
  return { x: rect.right / scale + GAP_PX, y: (rect.top + rect.height / 2) / scale }
}

/**
 * Parse the raw `--ui-scale` custom-property string from computed style.
 * @param {string|undefined} raw
 * @returns {number} the scale, or 1 for anything absent or malformed
 */
export function parseUiScale(raw) {
  const scale = Number.parseFloat(raw)
  return Number.isFinite(scale) && scale > 0 ? scale : 1
}

/**
 * Transform strings for the two visual states. Position lives entirely in
 * `transform` (never top/left) so movement stays compositor-only and the
 * open tooltip can glide; `entrance` starts slightly left for the slide-in.
 * @param {{x: number, y: number}} position
 * @returns {{resting: string, entrance: string}}
 */
export function tooltipTransforms({ x, y }) {
  const resting = `translate3d(${x}px, ${y}px, 0) translateY(-50%)`
  return { resting, entrance: `${resting} translateX(-6px)` }
}

function ensureTooltipEl() {
  let el = document.getElementById(TOOLTIP_ID)
  if (!el) {
    el = document.createElement("div")
    el.id = TOOLTIP_ID
    el.className = "sidebar-tooltip"
    el.dataset.state = "closed"
    el.setAttribute("aria-hidden", "true")
    document.body.appendChild(el)
  }
  return el
}

export const SidebarTooltip = {
  mounted() {
    this.tip = ensureTooltipEl()
    this.currentLink = null
    this.showTimer = null
    this.visible = false
    this.hiddenAt = null

    this.onMouseOver = (event) => {
      const link = event.target.closest("[data-tip]")
      if (!link || link === this.currentLink) return
      this.currentLink = link
      this.show(link, { immediate: false })
    }
    this.onMouseOut = (event) => {
      const link = event.target.closest("[data-tip]")
      if (!link || link.contains(event.relatedTarget)) return
      this.hide()
    }
    // Focus is deliberate (keyboard/gamepad nav) — reveal without delay.
    this.onFocusIn = (event) => {
      const link = event.target.closest("[data-tip]")
      if (!link) return
      this.currentLink = link
      this.show(link, { immediate: true })
    }
    this.onFocusOut = () => this.hide()
    // Click navigates or toggles the rail — either way the anchor is gone.
    this.onClick = () => this.hide()
    this.onScroll = () => this.hide()

    this.el.addEventListener("mouseover", this.onMouseOver)
    this.el.addEventListener("mouseout", this.onMouseOut)
    this.el.addEventListener("focusin", this.onFocusIn)
    this.el.addEventListener("focusout", this.onFocusOut)
    this.el.addEventListener("click", this.onClick)
    this.el.addEventListener("scroll", this.onScroll, { passive: true })
  },

  destroyed() {
    this.hide()
    this.el.removeEventListener("mouseover", this.onMouseOver)
    this.el.removeEventListener("mouseout", this.onMouseOut)
    this.el.removeEventListener("focusin", this.onFocusIn)
    this.el.removeEventListener("focusout", this.onFocusOut)
    this.el.removeEventListener("click", this.onClick)
    this.el.removeEventListener("scroll", this.onScroll)
  },

  show(link, { immediate }) {
    const label = link.dataset.tip
    if (!shouldShow(document.documentElement.dataset.sidebar, label)) return
    clearTimeout(this.showTimer)
    const delay = immediate
      ? 0
      : showDelay({ visible: this.visible, hiddenAt: this.hiddenAt, now: Date.now() })
    if (delay === 0) {
      this.reveal(link, label)
    } else {
      this.showTimer = setTimeout(() => this.reveal(link, label), delay)
    }
  },

  reveal(link, label) {
    const scale = parseUiScale(
      getComputedStyle(document.documentElement).getPropertyValue("--ui-scale")
    )
    const { resting, entrance } = tooltipTransforms(
      tooltipPosition(link.getBoundingClientRect(), scale)
    )
    this.tip.textContent = label
    if (this.visible) {
      // Already open: transform transition carries it to the new link.
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
    this.currentLink = null
    if (!this.visible) return
    this.visible = false
    this.hiddenAt = Date.now()
    this.tip.dataset.state = "closed"
  },
}
