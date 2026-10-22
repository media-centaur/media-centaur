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
  // The viewing's actions (Controls' "During playback on a TV"): the viewing
  // behaviour answers them while a viewing is on (viewing_behavior.js);
  // otherwise the machine answers PLAY_PAUSE as PLAY and ignores the rest.
  PLAY_PAUSE: "PLAY_PAUSE",
  SEEK_FORWARD: "SEEK_FORWARD",
  SEEK_BACK: "SEEK_BACK",
  MENU: "MENU",
})

/**
 * Actions that claim the focus cursor. Producing one is the signal that the
 * user has started cursor-driving, so it switches the input method (mouse →
 * keyboard). Commands (BACK, CLEAR, PLAY) and text entry run in whatever
 * method is current — a mouse user pressing Escape is still a mouse user.
 */
const CURSOR_DRIVING_ACTIONS = new Set([
  Action.NAVIGATE_UP,
  Action.NAVIGATE_DOWN,
  Action.NAVIGATE_LEFT,
  Action.NAVIGATE_RIGHT,
  Action.SELECT,
  Action.ZONE_NEXT,
  Action.ZONE_PREV,
])

/**
 * Whether producing this action should switch the input method.
 * @param {string} action - Action value
 * @returns {boolean}
 */
export function isCursorDriving(action) {
  return CURSOR_DRIVING_ACTIONS.has(action)
}

// The catalog's default keys (Settings.Controls.Catalog), copied here for the
// test fixtures: the app always builds its map from the bindings the layout
// embeds, so this copy is never consulted at runtime. Every key the app
// answers to is a catalog binding, the zone keys and the viewing's keys
// included; there is no fallback map behind the user's.
export const DEFAULT_KEY_MAP = Object.freeze({
  ArrowUp: Action.NAVIGATE_UP,
  ArrowDown: Action.NAVIGATE_DOWN,
  ArrowLeft: Action.NAVIGATE_LEFT,
  ArrowRight: Action.NAVIGATE_RIGHT,
  Enter: Action.SELECT,
  Escape: Action.BACK,
  Backspace: Action.CLEAR,
  "]": Action.ZONE_NEXT,
  "[": Action.ZONE_PREV,
  p: Action.PLAY,
  P: Action.PLAY,
  MediaPlayPause: Action.PLAY_PAUSE,
  MediaFastForward: Action.SEEK_FORWARD,
  MediaRewind: Action.SEEK_BACK,
  ContextMenu: Action.MENU,
})

// The catalog's default buttons, a fixture copy like DEFAULT_KEY_MAP.
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
  return keyMap[key] ?? null
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
