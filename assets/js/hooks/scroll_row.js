// assets/js/hooks/scroll_row.js
//
// A scroll row's pointer chrome: two edge arrows over a `.row-scroll`
// track, each gliding the track one step toward its end. The arrows are a
// pointer affordance in the play overlay's sense (UIDR-027): revealed on
// hover by CSS, outside the input system, never seen by keyboard, gamepad
// or the TV.
//
// The hook owns two things. The track's EDGE STATE — at its start, at its
// end — is the track's own geometry, projected as `data-at-start` and
// `data-at-end` on the track so CSS can drop the arrow that points at an
// end already reached (a track that fits carries both and shows none). And
// the PRESS: one step is a scrollport less one card and its gap, so the
// last visible card stays as the reader's anchor; the glide is the page's
// one glider (assets/js/scroll_glider.js), so the orchestrator's wheel rule
// cancels it like any other and a cursor key mid-glide retargets it.
//
// The hook attaches its chrome only where a pointer is (`(hover: hover)`),
// the same truth the CSS reveal rests on: the TV's glide frames carry no
// scroll listener for chrome it can never show.
//
// One thing it does everywhere: DECODE AHEAD. The row's images carry
// `decoding="sync"` (UIDR-012), so the frame that first paints them waits
// on their decode. A row on the first screen pays that at load; a row
// below the fold pays it inside the glide that brings it into view — on
// the TV, where the page is drawn at 1080p and Discovery's New Releases
// sits below the hero and Out Now, 17 posters decoding at once held the
// first vertical glide for 200 ms (2026-11-02, mc-tv-smooth runs
// 20261102-121100 and 20261102-121641, mc-tv-trace 20261102T120910: the
// glide's scroll write blocked in LayerTreeHost::WaitForCommitCompletion).
// So the hook decodes the images inside the track's scrollport once the
// page is idle, with `HTMLImageElement.decode()`, and again for the images
// a patch adds; the same run measured the glide clean under that decode.
// Only the scrollport: a tile hidden to the right enters one at a time
// with a sideways glide, which the TV presented at 60 fps before any of
// this, and decoding every tile ahead held 50 MB of pixels the screen was
// not showing (run 20261102-123105). Decoded pixels are dropped with the
// page.
//
// Layout pixels throughout (`offsetWidth`, `clientWidth`, `scrollLeft`),
// never `getBoundingClientRect`: the UI runs under a root zoom, and rects
// come back in visual pixels.

import { scrollGlider } from "../scroll_glider.js"
import { whenIdle } from "../when_idle.js"

/** Within this many px of an end counts as at it (fractional offsets under zoom). */
const EDGE_TOLERANCE = 1

/**
 * Which ends of a track are reached.
 * @param {{scrollLeft: number, scrollWidth: number, clientWidth: number}} track
 * @returns {{atStart: boolean, atEnd: boolean}}
 */
export function edges({ scrollLeft, scrollWidth, clientWidth }) {
  const max = Math.max(0, scrollWidth - clientWidth)
  return {
    atStart: scrollLeft <= EDGE_TOLERANCE,
    atEnd: scrollLeft >= max - EDGE_TOLERANCE,
  }
}

/**
 * How far one press moves the track: the scrollport less one card and its
 * gap, and never less than a card.
 * @param {{clientWidth: number, cardWidth: number, gap: number}} geometry
 * @returns {number}
 */
export function step({ clientWidth, cardWidth, gap }) {
  return Math.max(cardWidth, clientWidth - (cardWidth + gap))
}

/**
 * Decode the images not yet decoded, remembering them in `decoded`. A
 * decode rejects for an image that failed to load; the row has nothing to
 * do about that.
 * @param {Iterable<HTMLImageElement>} images
 * @param {WeakSet<HTMLImageElement>} decoded
 * @returns {Promise<void>}
 */
export function decodeImages(images, decoded) {
  const pending = []
  for (const img of images) {
    if (decoded.has(img) || typeof img.decode !== "function") continue
    decoded.add(img)
    pending.push(img.decode().catch(() => {}))
  }
  return Promise.all(pending).then(() => undefined)
}

/**
 * The images whose box overlaps the track's scrollport sideways: what a
 * vertical reveal of the row would paint. Visual pixels on both sides.
 * @param {{getBoundingClientRect(): {left: number, right: number}}} track
 * @param {Iterable<HTMLImageElement>} images
 * @returns {HTMLImageElement[]}
 */
export function inScrollport(track, images) {
  const port = track.getBoundingClientRect()
  return Array.from(images).filter((img) => {
    const box = img.getBoundingClientRect()
    return box.right > port.left && box.left < port.right
  })
}

export const ScrollRow = {
  mounted() {
    this.track = this.el.querySelector(":scope > .row-scroll")
    if (!this.track) return
    this.decoded = new WeakSet()
    this.whenIdle = this.whenIdle ?? whenIdle
    this.decodeAhead()
    if (!globalThis.matchMedia?.("(hover: hover)").matches) return
    this.glider = this.glider ?? scrollGlider

    this.onScroll = () => this.project()
    this.track.addEventListener("scroll", this.onScroll, { passive: true })

    this.observer = new ResizeObserver(() => this.project())
    this.observer.observe(this.track)

    this.onClick = (event) => {
      const arrow = event.target.closest?.("[data-scroll-row-arrow]")
      if (arrow) this.press(arrow.dataset.scrollRowArrow)
    }
    this.el.addEventListener("click", this.onClick)

    // Pointer chrome never takes the cursor. Chromium focuses a clicked
    // `tabindex="-1"` button; in the collection rail the arrows sit outside
    // every nav zone, and the input system's reconciler would read that
    // focus as foreign (`hasForeignFocus`) and cede the cursor to it.
    this.onMouseDown = (event) => {
      if (event.target.closest?.("[data-scroll-row-arrow]")) event.preventDefault()
    }
    this.el.addEventListener("mousedown", this.onMouseDown)

    this.project()
  },

  updated() {
    if (!this.track) return
    this.decodeAhead()
    if (this.observer) this.project()
  },

  destroyed() {
    if (!this.observer) return
    this.track.removeEventListener("scroll", this.onScroll)
    this.el.removeEventListener("click", this.onClick)
    this.el.removeEventListener("mousedown", this.onMouseDown)
    this.observer.disconnect()
  },

  /** Decode the scrollport's images once the page is idle (see the header). */
  decodeAhead() {
    this.whenIdle(() => decodeImages(inScrollport(this.track, this.el.querySelectorAll("img")), this.decoded))
  },

  /** Write the track's edge state onto it. */
  project() {
    const { atStart, atEnd } = edges(this.track)
    this.track.toggleAttribute("data-at-start", atStart)
    this.track.toggleAttribute("data-at-end", atEnd)
  },

  /** Glide the track one step toward `direction` ("left" | "right"). */
  press(direction) {
    const track = this.track
    const cardWidth = track.firstElementChild?.offsetWidth ?? 0
    const gap = parseFloat(globalThis.getComputedStyle(track).columnGap) || 0
    const distance = step({ clientWidth: track.clientWidth, cardWidth, gap })
    const max = Math.max(0, track.scrollWidth - track.clientWidth)
    const wanted = direction === "left" ? track.scrollLeft - distance : track.scrollLeft + distance
    this.glider.glide(track, { left: Math.min(Math.max(wanted, 0), max) })
  },
}
