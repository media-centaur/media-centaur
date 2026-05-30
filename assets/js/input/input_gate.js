/**
 * input_gate — pure policy for whether a connected gamepad may drive the UI.
 *
 * Keyboard input is naturally scoped by the OS to the focused window. The
 * Gamepad API is not: `navigator.getGamepads()` reports controller state
 * globally, so any surface running the input hook keeps seeing button presses
 * even when it is not the surface the user is looking at. That lets three kinds
 * of "invisible" surface hijack a physical controller:
 *
 *   1. Unfocused   — another app (e.g. a fullscreen game) holds OS focus.
 *   2. Hidden      — a backgrounded tab or occluded window still polling rAF.
 *   3. Automation  — a headless debug browser (mc-debug-browser launches with
 *                    `--enable-automation`, so `navigator.webdriver === true`).
 *
 * The automation case is the load-bearing one: a headless instance reports
 * `hasFocus:true` and `visibilityState:"visible"`, so focus + visibility alone
 * do not catch it. The webdriver flag is a deterministic marker we set on every
 * agent-spawned browser, making this a trustworthy signal rather than fragile
 * UA fingerprinting.
 *
 * Pure and fail-closed: any missing/falsey signal denies input.
 *
 * @param {Object} env
 * @param {boolean} env.hasFocus          - document.hasFocus()
 * @param {string}  env.visibilityState   - document.visibilityState
 * @param {boolean} env.webdriver         - navigator.webdriver
 * @returns {boolean} true only when the surface may accept gamepad input
 */
export function gamepadInputAllowed({ hasFocus, visibilityState, webdriver } = {}) {
  return Boolean(hasFocus) && visibilityState === "visible" && !webdriver
}
