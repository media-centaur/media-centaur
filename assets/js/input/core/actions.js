/**
 * Semantic input actions.
 *
 * Maps raw input events (keyboard keys, gamepad buttons) to semantic
 * actions that the state machine understands. This decouples input
 * hardware from navigation behavior.
 */

export const Action = Object.freeze({
  NAVIGATE_UP: "NAVIGATE_UP",
  NAVIGATE_DOWN: "NAVIGATE_DOWN",
  NAVIGATE_LEFT: "NAVIGATE_LEFT",
  NAVIGATE_RIGHT: "NAVIGATE_RIGHT",
  SELECT: "SELECT",
  BACK: "BACK",
  PLAY: "PLAY",
  CLEAR: "CLEAR",
  ZONE_NEXT: "ZONE_NEXT",
  ZONE_PREV: "ZONE_PREV",
})

const ZONE_KEY_MAP = Object.freeze({
  "]": Action.ZONE_NEXT,
  "[": Action.ZONE_PREV,
})

export const DEFAULT_KEY_MAP = Object.freeze({
  ArrowUp: Action.NAVIGATE_UP,
  ArrowDown: Action.NAVIGATE_DOWN,
  ArrowLeft: Action.NAVIGATE_LEFT,
  ArrowRight: Action.NAVIGATE_RIGHT,
  Enter: Action.SELECT,
  Escape: Action.BACK,
  Backspace: Action.CLEAR,
  p: Action.PLAY,
  P: Action.PLAY,
})

export const DEFAULT_BUTTON_MAP = Object.freeze({
  0: Action.SELECT,
  1: Action.BACK,
  3: Action.CLEAR,
  4: Action.ZONE_PREV,
  5: Action.ZONE_NEXT,
  9: Action.PLAY,
  12: Action.NAVIGATE_UP,
  13: Action.NAVIGATE_DOWN,
  14: Action.NAVIGATE_LEFT,
  15: Action.NAVIGATE_RIGHT,
})

/**
 * Map a keyboard key to a semantic action.
 * @param {string} key - KeyboardEvent.key
 * @param {Object} [opts] - Options
 * @param {boolean} [opts.targetIsInput] - True if event target is a text input
 * @param {Object} [keyMap] - Custom key map (defaults to DEFAULT_KEY_MAP)
 * @returns {string|null} Action or null
 */
export function keyToAction(key, opts = {}, keyMap = DEFAULT_KEY_MAP) {
  if (opts.targetIsInput) return null
  return keyMap[key] ?? ZONE_KEY_MAP[key] ?? null
}

/**
 * Map a gamepad button index to a semantic action.
 * @param {number} button - Gamepad button index
 * @param {Object} [buttonMap] - Custom button map (defaults to DEFAULT_BUTTON_MAP)
 * @returns {string|null} Action or null
 */
export function buttonToAction(button, buttonMap = DEFAULT_BUTTON_MAP) {
  return buttonMap[button] ?? null
}
