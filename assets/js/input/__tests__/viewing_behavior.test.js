import { describe, expect, test } from "bun:test"
import { Action } from "../core/index.js"
import { withViewing } from "../viewing_behavior"

/**
 * The viewing layer's deps: a recording pushEvent, a switch for the track
 * menu, and a way to say whether the focused item is the prompt.
 */
function deps({ menuOpen = false, prompt = false, tracks = false, onTracks = false } = {}) {
  const pushed = []
  const focus = []
  return {
    pushEvent: (event, payload) => pushed.push([event, payload]),
    isMenuOpen: () => menuOpen,
    hasPrompt: () => prompt,
    hasTracksButton: () => tracks,
    isTracksFocused: () => onTracks,
    focusTracksButton: () => focus.push("focus"),
    leaveTracksButton: () => focus.push("leave"),
    pushed,
    focus,
  }
}

const nothing = null

describe("withViewing — the bar state (no menu open)", () => {
  test("arrows seek: left and right by 10 s, up and down by 60 s", () => {
    const d = deps()
    const behavior = withViewing({}, d)

    expect(behavior.onAction(Action.NAVIGATE_LEFT, "modal", nothing)).toBe(true)
    expect(behavior.onAction(Action.NAVIGATE_RIGHT, "modal", nothing)).toBe(true)
    expect(behavior.onAction(Action.NAVIGATE_UP, "modal", nothing)).toBe(true)
    expect(behavior.onAction(Action.NAVIGATE_DOWN, "modal", nothing)).toBe(true)

    expect(d.pushed).toEqual([
      ["viewing_command", { command: "seek", seconds: -10 }],
      ["viewing_command", { command: "seek", seconds: 10 }],
      ["viewing_command", { command: "seek", seconds: 60 }],
      ["viewing_command", { command: "seek", seconds: -60 }],
    ])
  })

  test("select toggles pause, or acts on the prompt while one shows, focused or not", () => {
    const d = deps()
    expect(withViewing({}, d).onAction(Action.SELECT, "modal", nothing)).toBe(true)
    expect(d.pushed).toEqual([["viewing_command", { command: "toggle_pause" }]])

    const withPrompt = deps({ prompt: true })
    expect(withViewing({}, withPrompt).onAction(Action.SELECT, "modal", nothing)).toBe(true)
    expect(withPrompt.pushed).toEqual([["viewing_prompt", {}]])
  })

  test("the remote's media keys: play/pause toggles, forward and rewind seek 30 s, menu opens the track menu", () => {
    const d = deps()
    const behavior = withViewing({}, d)

    expect(behavior.onAction(Action.PLAY_PAUSE, "modal", nothing)).toBe(true)
    expect(behavior.onAction(Action.SEEK_FORWARD, "modal", nothing)).toBe(true)
    expect(behavior.onAction(Action.SEEK_BACK, "modal", nothing)).toBe(true)
    expect(behavior.onAction(Action.MENU, "modal", nothing)).toBe(true)

    expect(d.pushed).toEqual([
      ["viewing_command", { command: "toggle_pause" }],
      ["viewing_command", { command: "seek", seconds: 30 }],
      ["viewing_command", { command: "seek", seconds: -30 }],
      ["viewing_menu_open", {}],
    ])
  })

  test("back is containment, not a command: it passes through so the overlay's dismiss event stops the viewing", () => {
    const d = deps()
    const behavior = withViewing({}, d)
    expect(behavior.onAction(Action.BACK, "modal", nothing)).toBe(false)
    expect(d.pushed).toEqual([])
  })

  test("zone cycling and clear do nothing during a viewing", () => {
    const d = deps()
    const behavior = withViewing({}, d)
    expect(behavior.onAction(Action.ZONE_NEXT, "modal", nothing)).toBe(true)
    expect(behavior.onAction(Action.ZONE_PREV, "modal", nothing)).toBe(true)
    expect(behavior.onAction(Action.CLEAR, "modal", nothing)).toBe(true)
    expect(d.pushed).toEqual([])
  })
})

describe("withViewing — with the track menu open", () => {
  test("steps aside: every action reaches the page's behaviour and the state machine", () => {
    const d = deps({ menuOpen: true })
    const seen = []
    const behavior = withViewing({ onAction: (action) => (seen.push(action), false) }, d)

    expect(behavior.onAction(Action.NAVIGATE_DOWN, "viewing_subtitles", nothing)).toBe(false)
    expect(behavior.onAction(Action.SELECT, "viewing_subtitles", nothing)).toBe(false)
    expect(behavior.onAction(Action.BACK, "viewing_subtitles", nothing)).toBe(false)
    expect(seen).toEqual([Action.NAVIGATE_DOWN, Action.SELECT, Action.BACK])
    expect(d.pushed).toEqual([])
  })

  test("the menu key closes the menu", () => {
    const d = deps({ menuOpen: true })
    const behavior = withViewing({}, d)
    expect(behavior.onAction(Action.MENU, "viewing_subtitles", nothing)).toBe(true)
    expect(d.pushed).toEqual([["viewing_menu_close", {}]])
  })
})

describe("withViewing — the wrapped behaviour", () => {
  test("keeps the page behaviour's other hooks", () => {
    const base = { onClear: () => "cleared", activateOnFocus: ["sections"] }
    const behavior = withViewing(base, deps())
    expect(behavior.onClear()).toBe("cleared")
    expect(behavior.activateOnFocus).toEqual(["sections"])
  })
})

// Paused, the bar shows an "Audio & subtitles" button: the track menu without
// a Menu key, which most Google TV remotes lack (Play's TV-DM criterion).
describe("withViewing — the paused bar's tracks button", () => {
  test("down focuses the button instead of seeking back", () => {
    const d = deps({ tracks: true })
    expect(withViewing({}, d).onAction(Action.NAVIGATE_DOWN, "modal", nothing)).toBe(true)
    expect(d.focus).toEqual(["focus"])
    expect(d.pushed).toEqual([])
  })

  test("select on the focused button opens the track menu", () => {
    const d = deps({ tracks: true, onTracks: true })
    expect(withViewing({}, d).onAction(Action.SELECT, "modal", nothing)).toBe(true)
    expect(d.pushed).toEqual([["viewing_menu_open", {}]])
  })

  test("select off the button still resumes", () => {
    const d = deps({ tracks: true })
    expect(withViewing({}, d).onAction(Action.SELECT, "modal", nothing)).toBe(true)
    expect(d.pushed).toEqual([["viewing_command", { command: "toggle_pause" }]])
  })

  test("up leaves the button without seeking; OK pauses and resumes again", () => {
    const d = deps({ tracks: true, onTracks: true })
    const behavior = withViewing({}, d)
    expect(behavior.onAction(Action.NAVIGATE_UP, "modal", nothing)).toBe(true)
    expect(d.focus).toEqual(["leave"])
    expect(d.pushed).toEqual([])
  })

  test("down on the focused button stays put", () => {
    const d = deps({ tracks: true, onTracks: true })
    expect(withViewing({}, d).onAction(Action.NAVIGATE_DOWN, "modal", nothing)).toBe(true)
    expect(d.focus).toEqual([])
    expect(d.pushed).toEqual([])
  })

  test("left and right still seek while the button is focused", () => {
    const d = deps({ tracks: true, onTracks: true })
    expect(withViewing({}, d).onAction(Action.NAVIGATE_RIGHT, "modal", nothing)).toBe(true)
    expect(d.pushed).toEqual([["viewing_command", { command: "seek", seconds: 10 }]])
  })

  test("without the button (playing) down still seeks back 60 s", () => {
    const d = deps()
    expect(withViewing({}, d).onAction(Action.NAVIGATE_DOWN, "modal", nothing)).toBe(true)
    expect(d.pushed).toEqual([["viewing_command", { command: "seek", seconds: -60 }]])
  })
})
