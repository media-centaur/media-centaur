/**
 * Controller layout — what one physical device's snapshot means.
 *
 * Above this module every button is a **standard-layout index**. The catalog
 * (`MediaCentaur.Settings.Controls.Catalog`), the user's saved overrides,
 * `DEFAULT_BUTTON_MAP` and the wiki cheat-sheet all speak that one vocabulary.
 * A layout's only job is to translate whatever the browser actually reported
 * into it — so a binding captured in one browser keeps working in another.
 *
 * Chromium remaps known pads itself and reports `mapping: "standard"`. Firefox
 * on Linux does not always: it passes the raw evdev shape through, where an
 * Xbox pad is 11 buttons and 8 axes, Start sits at 7 rather than 9, and the
 * D-pad arrives on a hat axis pair instead of buttons 12–15 (Mozilla bug
 * 1643358). Reading `gamepad.mapping` is what tells the two apart.
 *
 * Note the two meanings of "mapping" kept apart here: `gamepad.mapping` is the
 * browser's own string, never ours. A *layout* is the value type below.
 */

/** Standard-layout button count, including the Guide button at 16. */
export const STANDARD_BUTTON_COUNT = 17

/** Standard-layout D-pad indices, in hat order: up, down, left, right. */
const DPAD_UP = 12
const DPAD_DOWN = 13
const DPAD_LEFT = 14
const DPAD_RIGHT = 15

/**
 * @typedef {Object} ControllerLayout
 * @property {string} name - Layout identifier, for debug output
 * @property {number[]|null} buttons - Raw index → standard index. Null means
 *   the raw indices are already standard (identity).
 * @property {{x: number, y: number}} stickAxes - Axis indices of the left stick
 * @property {{x: number, y: number}|null} hatAxes - Axis indices carrying the
 *   D-pad as discrete −1/0/+1 values, or null when the D-pad is on buttons
 * @property {"xbox"|"playstation"|"generic"} labels - Hint-bar label family
 */

const STANDARD_LAYOUT = Object.freeze({
  name: "standard",
  buttons: null,
  stickAxes: Object.freeze({ x: 0, y: 1 }),
  hatAxes: null,
})

/**
 * Raw evdev order for an xpad-style controller:
 *   A B X Y LB RB Back Start Guide LSB RSB
 * Axes: leftX leftY leftTrigger rightX rightY rightTrigger hatX hatY
 */
const LINUX_EVDEV_LAYOUT = Object.freeze({
  name: "linux-evdev",
  buttons: Object.freeze([0, 1, 2, 3, 4, 5, 8, 9, 16, 10, 11]),
  stickAxes: Object.freeze({ x: 0, y: 1 }),
  hatAxes: Object.freeze({ x: 6, y: 7 }),
})

/**
 * Detect the hint-bar label family from a gamepad's id string.
 *
 * Ids are not standardised. Chromium writes its own name ("Xbox 360 Controller
 * (XInput STANDARD GAMEPAD)"); Firefox on Linux writes the kernel device name
 * prefixed with vendor/product ("045e-028e-Microsoft X-Box 360 pad"). Stripping
 * everything but letters and digits before matching is what lets one rule cover
 * both spellings — "X-Box" and "Xbox" normalise to the same thing.
 *
 * @param {string} id - Gamepad.id
 * @returns {"xbox"|"playstation"|"generic"}
 */
export function detectControllerType(id) {
  const normalized = (id ?? "").toLowerCase().replace(/[^a-z0-9]/g, "")
  if (normalized.includes("xbox") || normalized.includes("xinput")) return "xbox"
  if (
    normalized.includes("playstation") ||
    normalized.includes("dualshock") ||
    normalized.includes("dualsense") ||
    normalized.includes("sony")
  ) {
    return "playstation"
  }
  return "generic"
}

/**
 * Derive the layout for a connected gamepad.
 *
 * @param {Gamepad} gamepad
 * @returns {ControllerLayout}
 */
export function controllerLayout(gamepad) {
  const layout = gamepad?.mapping === "standard" ? STANDARD_LAYOUT : nonStandardLayout(gamepad)
  return { ...layout, labels: detectControllerType(gamepad?.id) }
}

/**
 * Pick a layout for a device the browser did not remap.
 *
 * Only one non-standard shape is known well enough to translate: the evdev
 * xpad, recognised by having no D-pad buttons but a hat pair past the sticks
 * and triggers. Anything else falls back to standard indices, which is the best
 * available guess and degrades to "some buttons do nothing" rather than to
 * wrong actions.
 */
function nonStandardLayout(gamepad) {
  const buttonCount = gamepad?.buttons?.length ?? 0
  const axisCount = gamepad?.axes?.length ?? 0
  if (buttonCount <= 11 && axisCount >= 8) return LINUX_EVDEV_LAYOUT
  return STANDARD_LAYOUT
}

/**
 * Project a raw gamepad snapshot onto standard-layout button state.
 *
 * Writes into a caller-owned array so the polling loop allocates nothing per
 * frame. A hat pair becomes D-pad presses, which is what makes the hat travel
 * the same binding and key-repeat path as a real D-pad button.
 *
 * @param {Gamepad} gamepad
 * @param {ControllerLayout} layout
 * @param {number} threshold - Magnitude past which a hat axis counts as pressed
 * @param {boolean[]} out - Destination, length STANDARD_BUTTON_COUNT
 */
export function normalizeButtons(gamepad, layout, threshold, out) {
  out.fill(false)

  const buttons = gamepad.buttons
  for (let raw = 0; raw < buttons.length; raw++) {
    const standard = layout.buttons ? layout.buttons[raw] : raw
    if (standard === undefined || standard >= out.length) continue
    out[standard] = buttons[raw].pressed
  }

  if (layout.hatAxes) {
    const hatX = gamepad.axes[layout.hatAxes.x] ?? 0
    const hatY = gamepad.axes[layout.hatAxes.y] ?? 0
    if (hatY <= -threshold) out[DPAD_UP] = true
    if (hatY >= threshold) out[DPAD_DOWN] = true
    if (hatX <= -threshold) out[DPAD_LEFT] = true
    if (hatX >= threshold) out[DPAD_RIGHT] = true
  }

  return out
}
