import { describe, expect, test } from "bun:test"
import { Action, DEFAULT_KEY_MAP, DEFAULT_BUTTON_MAP, keyToAction, buttonToAction } from "../actions"

describe("Action enum", () => {
  test("is frozen", () => {
    expect(Object.isFrozen(Action)).toBe(true)
  })

  test("contains all expected actions", () => {
    const expected = [
      "NAVIGATE_UP", "NAVIGATE_DOWN", "NAVIGATE_LEFT", "NAVIGATE_RIGHT",
      "SELECT", "BACK", "PLAY", "ZONE_NEXT", "ZONE_PREV",
    ]
    for (const name of expected) {
      expect(Action[name]).toBeDefined()
    }
  })
})

describe("keyToAction", () => {
  test("maps arrow keys to navigation", () => {
    expect(keyToAction("ArrowUp")).toBe(Action.NAVIGATE_UP)
    expect(keyToAction("ArrowDown")).toBe(Action.NAVIGATE_DOWN)
    expect(keyToAction("ArrowLeft")).toBe(Action.NAVIGATE_LEFT)
    expect(keyToAction("ArrowRight")).toBe(Action.NAVIGATE_RIGHT)
  })

  test("maps Enter to select", () => {
    expect(keyToAction("Enter")).toBe(Action.SELECT)
  })

  test("maps Escape to back", () => {
    expect(keyToAction("Escape")).toBe(Action.BACK)
  })

  test("maps p/P to play", () => {
    expect(keyToAction("p")).toBe(Action.PLAY)
    expect(keyToAction("P")).toBe(Action.PLAY)
  })

  test("maps bracket keys to zone cycling", () => {
    expect(keyToAction("]")).toBe(Action.ZONE_NEXT)
    expect(keyToAction("[")).toBe(Action.ZONE_PREV)
  })

  test("returns null for unmapped keys", () => {
    expect(keyToAction("a")).toBe(null)
    expect(keyToAction("Tab")).toBe(null)
    expect(keyToAction("F1")).toBe(null)
  })

  test("returns null when target is an input element", () => {
    expect(keyToAction("ArrowUp", { targetIsInput: true })).toBe(null)
    expect(keyToAction("Enter", { targetIsInput: true })).toBe(null)
    expect(keyToAction("Escape", { targetIsInput: true })).toBe(null)
  })

  test("accepts custom key map", () => {
    const custom = { w: Action.NAVIGATE_UP, s: Action.NAVIGATE_DOWN }
    expect(keyToAction("w", {}, custom)).toBe(Action.NAVIGATE_UP)
    expect(keyToAction("s", {}, custom)).toBe(Action.NAVIGATE_DOWN)
    // Zone keys still work with custom map
    expect(keyToAction("]", {}, custom)).toBe(Action.ZONE_NEXT)
  })
})

describe("buttonToAction", () => {
  test("maps standard gamepad buttons", () => {
    expect(buttonToAction(0)).toBe(Action.SELECT)
    expect(buttonToAction(1)).toBe(Action.BACK)
    expect(buttonToAction(9)).toBe(Action.PLAY)
  })

  test("maps D-pad to navigation", () => {
    expect(buttonToAction(12)).toBe(Action.NAVIGATE_UP)
    expect(buttonToAction(13)).toBe(Action.NAVIGATE_DOWN)
    expect(buttonToAction(14)).toBe(Action.NAVIGATE_LEFT)
    expect(buttonToAction(15)).toBe(Action.NAVIGATE_RIGHT)
  })

  test("maps bumpers to zone cycling", () => {
    expect(buttonToAction(4)).toBe(Action.ZONE_PREV)
    expect(buttonToAction(5)).toBe(Action.ZONE_NEXT)
  })

  test("returns null for unmapped buttons", () => {
    expect(buttonToAction(2)).toBe(null)
    expect(buttonToAction(3)).toBe(null)
    expect(buttonToAction(99)).toBe(null)
  })

  test("accepts custom button map", () => {
    const custom = { 0: Action.PLAY, 1: Action.SELECT }
    expect(buttonToAction(0, custom)).toBe(Action.PLAY)
    expect(buttonToAction(1, custom)).toBe(Action.SELECT)
  })
})

describe("DEFAULT_KEY_MAP", () => {
  test("is frozen", () => {
    expect(Object.isFrozen(DEFAULT_KEY_MAP)).toBe(true)
  })
})

describe("DEFAULT_BUTTON_MAP", () => {
  test("is frozen", () => {
    expect(Object.isFrozen(DEFAULT_BUTTON_MAP)).toBe(true)
  })
})
