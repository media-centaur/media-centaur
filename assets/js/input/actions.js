/**
 * Semantic action vocabulary and input-to-action mapping.
 *
 * Pure data + pure functions. No DOM, no side effects.
 */

export const Action = Object.freeze({
  NAVIGATE_UP: "navigate_up",
  NAVIGATE_DOWN: "navigate_down",
  NAVIGATE_LEFT: "navigate_left",
  NAVIGATE_RIGHT: "navigate_right",
  SELECT: "select",
  BACK: "back",
  PLAY: "play",
  ZONE_NEXT: "zone_next",
  ZONE_PREV: "zone_prev",
})

export const DEFAULT_KEY_MAP = Object.freeze({
  ArrowUp: Action.NAVIGATE_UP,
  ArrowDown: Action.NAVIGATE_DOWN,
  ArrowLeft: Action.NAVIGATE_LEFT,
  ArrowRight: Action.NAVIGATE_RIGHT,
  Enter: Action.SELECT,
  Escape: Action.BACK,
  p: Action.PLAY,
  P: Action.PLAY,
})

/** Shift+arrow shortcuts for zone tab cycling. */
const ZONE_KEY_MAP = Object.freeze({
  "]": Action.ZONE_NEXT,
  "[": Action.ZONE_PREV,
})

export const DEFAULT_BUTTON_MAP = Object.freeze({
  0: Action.SELECT,     // A
  1: Action.BACK,       // B
  4: Action.ZONE_PREV,  // LB
  5: Action.ZONE_NEXT,  // RB
  9: Action.PLAY,       // Start
  12: Action.NAVIGATE_UP,
  13: Action.NAVIGATE_DOWN,
  14: Action.NAVIGATE_LEFT,
  15: Action.NAVIGATE_RIGHT,
})

/**
 * Map a keyboard event key (+ modifiers) to a semantic action.
 * Returns null if the key has no mapping.
 */
export function keyToAction(key, modifiers = {}, keyMap = DEFAULT_KEY_MAP) {
  // Don't intercept when user is typing in an input/textarea/select
  if (modifiers.targetIsInput) return null

  // Zone shortcuts (bracket keys)
  const zoneAction = ZONE_KEY_MAP[key]
  if (zoneAction) return zoneAction

  return keyMap[key] ?? null
}

/**
 * Map a gamepad button index to a semantic action.
 * Returns null if the button has no mapping.
 */
export function buttonToAction(buttonIndex, buttonMap = DEFAULT_BUTTON_MAP) {
  return buttonMap[buttonIndex] ?? null
}
