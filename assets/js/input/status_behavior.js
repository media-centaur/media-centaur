/**
 * Status page behavior.
 *
 * BACK navigates to the sidebar from content contexts.
 *
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createStatusBehavior() {
  return {
    onAttach() {},
    onDetach() {},
    onEscape() {
      return "sidebar"
    },
  }
}
