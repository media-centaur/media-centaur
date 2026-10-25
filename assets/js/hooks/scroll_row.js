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
// The hook attaches only where a pointer is (`(hover: hover)`), the same
// truth the CSS reveal rests on: the TV's glide frames carry no scroll
// listener for chrome it can never show.
//
// Layout pixels throughout (`offsetWidth`, `clientWidth`, `scrollLeft`),
// never `getBoundingClientRect`: the UI runs under a root zoom, and rects
// come back in visual pixels.

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
