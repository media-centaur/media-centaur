/**
 * Guide page behavior.
 *
 * The guide is two link lists (chapter sidebar + on-this-page outline) flanking
 * a prose reading pane that is deliberately NOT a nav zone — there is no scroll
 * primitive, so gamepad/keyboard users navigate the guide by *structure*: pick a
 * chapter, jump to a section. Activating chapters on focus mirrors Settings'
 * sections (up/down loads each chapter). Outline links activate on SELECT only,
 * so moving through the outline doesn't yank the page to each anchor.
 *
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createGuideBehavior() {
  return {
    activateOnFocus: ["guide_chapters"],
    onAttach() {},
    onDetach() {},
  }
}
