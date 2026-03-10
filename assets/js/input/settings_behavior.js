/**
 * Settings page behavior.
 *
 * Activates section links on focus so up/down navigation
 * switches between settings sub-pages.
 *
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createSettingsBehavior() {
  return {
    activateOnFocus: ["sections"],
    onAttach() {},
    onDetach() {},
  }
}
