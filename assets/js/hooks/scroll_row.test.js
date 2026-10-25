import { afterEach, describe, expect, test } from "bun:test"
import { edges, step } from "./scroll_row"
import { restoreGlobals } from "../test_support/dom_stubs"

afterEach(restoreGlobals)

describe("edges", () => {
  test("a track at scroll 0 is at its start", () => {
    expect(edges({ scrollLeft: 0, scrollWidth: 3000, clientWidth: 1000 })).toEqual({
      atStart: true,
      atEnd: false,
    })
  })

  test("a track mid-row is at neither end", () => {
    expect(edges({ scrollLeft: 800, scrollWidth: 3000, clientWidth: 1000 })).toEqual({
      atStart: false,
      atEnd: false,
    })
  })

  // Browsers report fractional scroll offsets under a root zoom; a track
  // 0.6px short of its maximum is at its end.
  test("a track within a pixel of its maximum is at its end", () => {
    expect(edges({ scrollLeft: 1999.4, scrollWidth: 3000, clientWidth: 1000 })).toEqual({
      atStart: false,
      atEnd: true,
    })
  })

  test("a track that fits is at both ends", () => {
    expect(edges({ scrollLeft: 0, scrollWidth: 900, clientWidth: 1000 })).toEqual({
      atStart: true,
      atEnd: true,
    })
  })
})

describe("step", () => {
  // One screenful less one card and its gap: the last visible card stays
  // as the reader's anchor, the rule the track's scroll padding states for
  // the cursor.
  test("is the scrollport less one card and its gap", () => {
    expect(step({ clientWidth: 1000, cardWidth: 200, gap: 8 })).toBe(792)
  })

  // A scrollport narrower than two cards (UI scale 2× on a small window)
  // still moves a whole card, never a sliver.
  test("is never less than one card", () => {
    expect(step({ clientWidth: 300, cardWidth: 200, gap: 8 })).toBe(200)
  })
})
