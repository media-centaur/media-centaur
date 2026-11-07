import { describe, expect, test } from "bun:test"
import { seekSeconds, tapAction } from "./viewing_touch"

describe("seekSeconds — a tap on the seek bar as a position in the file", () => {
  test("the tap's share of the bar's width, in whole seconds", () => {
    expect(seekSeconds(150, { left: 100, width: 400 }, 2000)).toBe(250)
    expect(seekSeconds(300, { left: 100, width: 400 }, 2000)).toBe(1000)
  })

  test("a tap past either end lands on that end", () => {
    expect(seekSeconds(50, { left: 100, width: 400 }, 2000)).toBe(0)
    expect(seekSeconds(900, { left: 100, width: 400 }, 2000)).toBe(2000)
  })

  test("no duration or no width is no seek", () => {
    expect(seekSeconds(150, { left: 100, width: 400 }, 0)).toBe(null)
    expect(seekSeconds(150, { left: 100, width: 0 }, 2000)).toBe(null)
  })
})

describe("tapAction — what a tap on the OSD does", () => {
  const target = (matches) => ({ closest: (selector) => (matches.includes(selector) ? {} : null) })

  test("the seek bar seeks", () => {
    expect(tapAction(target(["[data-viewing-seek]"]))).toBe("seek")
  })

  test("a control answers for itself", () => {
    expect(tapAction(target(["button"]))).toBe(null)
  })

  test("the picture shows or hides the bar", () => {
    expect(tapAction(target([]))).toBe("tap")
  })
})
