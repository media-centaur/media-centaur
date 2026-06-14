/**
 * Setup Tour page behavior.
 *
 * The first-run tour is a sidebar-less wizard: a single `grid` zone holds the
 * whole step card (form fields + footer buttons). There is deliberately NO
 * `activateOnFocus` — Begin / Next / Finish must fire only on an explicit
 * SELECT, never just because navigation landed on them, or arrowing through
 * the card would advance the tour. BACK is a no-op (there is no sidebar to
 * exit to, and the on-screen Back button is the way back).
 *
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createSetupBehavior() {
  return {
    onAttach() {},
    onDetach() {},
  }
}
