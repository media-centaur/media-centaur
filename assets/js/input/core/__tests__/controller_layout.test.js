import { describe, expect, test } from "bun:test"
import {
  controllerLayout,
  detectControllerType,
  normalizeButtons,
  STANDARD_BUTTON_COUNT,
} from "../controller_layout"

function gamepad({ id = "pad", mapping = "standard", buttons = 17, axes = 4 } = {}) {
  return {
    id,
    mapping,
    buttons: Array.from({ length: buttons }, () => ({ pressed: false })),
    axes: Array.from({ length: axes }, () => 0),
  }
}

function emptyState() {
  return new Array(STANDARD_BUTTON_COUNT).fill(false)
}

/** Standard indices reported as pressed, for readable assertions. */
function pressedIndices(state) {
  return state.flatMap((down, index) => (down ? [index] : []))
}

describe("layout selection", () => {
  test("a browser-remapped pad is standard whatever its shape", () => {
    // The browser's own word is authoritative — never second-guess it by shape.
    expect(controllerLayout(gamepad({ mapping: "standard" })).name).toBe("standard")
    expect(controllerLayout(gamepad({ mapping: "standard", buttons: 11, axes: 8 })).name).toBe("standard")
  })

  test("a non-standard pad with no D-pad buttons but a hat pair is evdev", () => {
    expect(controllerLayout(gamepad({ mapping: "", buttons: 11, axes: 8 })).name).toBe("linux-evdev")
  })

  test("a non-standard pad that still has D-pad buttons falls back to standard", () => {
    expect(controllerLayout(gamepad({ mapping: "", buttons: 17, axes: 4 })).name).toBe("standard")
  })

  test("a non-standard pad with too few axes to carry a hat falls back to standard", () => {
    const layout = controllerLayout(gamepad({ mapping: "", buttons: 11, axes: 4 }))
    expect(layout.name).toBe("standard")
    expect(layout.hatAxes).toBeNull()
  })

  test("layout carries the label family", () => {
    expect(controllerLayout(gamepad({ id: "045e-028e-Microsoft X-Box 360 pad" })).labels).toBe("xbox")
  })
})

describe("detectControllerType", () => {
  test("matches across id spellings from different browsers", () => {
    // Chromium writes its own name; Firefox on Linux writes the kernel one.
    expect(detectControllerType("Xbox Wireless Controller")).toBe("xbox")
    expect(detectControllerType("045e-028e-Microsoft X-Box 360 pad")).toBe("xbox")
    expect(detectControllerType("054c-0ce6-Sony Interactive Entertainment Wireless Controller")).toBe("playstation")
  })

  test("a missing id is generic rather than a crash", () => {
    expect(detectControllerType(undefined)).toBe("generic")
    expect(detectControllerType(null)).toBe("generic")
  })
})

describe("normalizeButtons", () => {
  test("standard indices pass through unchanged", () => {
    const pad = gamepad({ mapping: "standard" })
    pad.buttons[9] = { pressed: true }
    pad.buttons[13] = { pressed: true }

    const state = normalizeButtons(pad, controllerLayout(pad), 0.3, emptyState())
    expect(pressedIndices(state)).toEqual([9, 13])
  })

  test("evdev indices are translated to standard ones", () => {
    const pad = gamepad({ mapping: "", buttons: 11, axes: 8 })
    const layout = controllerLayout(pad)

    // Start sits at raw 7, where standard puts it at 9.
    pad.buttons[7] = { pressed: true }
    expect(pressedIndices(normalizeButtons(pad, layout, 0.3, emptyState()))).toEqual([9])

    // Raw 9 is left-stick click, standard 10 — not Start.
    pad.buttons[7] = { pressed: false }
    pad.buttons[9] = { pressed: true }
    expect(pressedIndices(normalizeButtons(pad, layout, 0.3, emptyState()))).toEqual([10])

    // Guide sits at raw 8, standard 16.
    pad.buttons[9] = { pressed: false }
    pad.buttons[8] = { pressed: true }
    expect(pressedIndices(normalizeButtons(pad, layout, 0.3, emptyState()))).toEqual([16])
  })

  test("hat axes become D-pad presses", () => {
    const pad = gamepad({ mapping: "", buttons: 11, axes: 8 })
    const layout = controllerLayout(pad)

    pad.axes[7] = -1
    expect(pressedIndices(normalizeButtons(pad, layout, 0.3, emptyState()))).toEqual([12])

    pad.axes[7] = 1
    expect(pressedIndices(normalizeButtons(pad, layout, 0.3, emptyState()))).toEqual([13])

    pad.axes[7] = 0
    pad.axes[6] = -1
    expect(pressedIndices(normalizeButtons(pad, layout, 0.3, emptyState()))).toEqual([14])

    pad.axes[6] = 1
    expect(pressedIndices(normalizeButtons(pad, layout, 0.3, emptyState()))).toEqual([15])
  })

  test("a diagonal hat presses both axes' D-pad buttons", () => {
    const pad = gamepad({ mapping: "", buttons: 11, axes: 8 })
    pad.axes[6] = 1
    pad.axes[7] = -1

    const state = normalizeButtons(pad, controllerLayout(pad), 0.3, emptyState())
    expect(pressedIndices(state)).toEqual([12, 15])
  })

  test("a hat resting inside the threshold presses nothing", () => {
    const pad = gamepad({ mapping: "", buttons: 11, axes: 8 })
    pad.axes[6] = 0.2

    const state = normalizeButtons(pad, controllerLayout(pad), 0.3, emptyState())
    expect(pressedIndices(state)).toEqual([])
  })

  test("the destination is cleared, so last frame's presses do not linger", () => {
    const pad = gamepad({ mapping: "standard" })
    const layout = controllerLayout(pad)
    const state = emptyState()

    pad.buttons[0] = { pressed: true }
    normalizeButtons(pad, layout, 0.3, state)
    pad.buttons[0] = { pressed: false }
    normalizeButtons(pad, layout, 0.3, state)

    expect(pressedIndices(state)).toEqual([])
  })

  test("a device reporting more buttons than the standard layout is truncated", () => {
    // Some pads expose extra paddles past index 16; they have no standard
    // meaning, and must not write past the end of the state array.
    const pad = gamepad({ mapping: "standard", buttons: 20 })
    pad.buttons[19] = { pressed: true }

    const state = normalizeButtons(pad, controllerLayout(pad), 0.3, emptyState())
    expect(state.length).toBe(STANDARD_BUTTON_COUNT)
    expect(pressedIndices(state)).toEqual([])
  })
})
