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
 * Focus and visibility are how a windowed surface proves it deserves the
 * controller. An automation surface fakes both — a headless instance reports
 * `hasFocus:true` and `visibilityState:"visible"` — so it cannot prove it that
 * way. It **declares** instead, via `automationDrivesInput`. That declaration
 * is the E2E suite's way of saying "this run is the intended driver"; without
 * it an automation context is still denied, so mc-debug-browser and any other
 * unattended launch behave exactly as before.
 *
 * A declaration only ever answers the automation question. It cannot stand in
 * for focus or visibility, so it opens no hole in cases 1 and 2.
 *
 * Pure and fail-closed: any missing/falsey signal denies input.
 *
 * @param {Object} env
 * @param {boolean} env.hasFocus                - document.hasFocus()
 * @param {string}  env.visibilityState         - document.visibilityState
 * @param {boolean} env.automation              - navigator.webdriver
 * @param {boolean} [env.automationDrivesInput] - This automation context
 *   declares itself the intended driver of gamepad input
 * @returns {boolean} true only when the surface may accept gamepad input
 */
export function gamepadInputAllowed({
  hasFocus,
  visibilityState,
  automation,
  automationDrivesInput,
} = {}) {
  if (!hasFocus || visibilityState !== "visible") return false
  if (!automation) return true
  return Boolean(automationDrivesInput)
}
