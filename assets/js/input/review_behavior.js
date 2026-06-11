/**
 * Review page behavior.
 *
 * No page-specific hooks — navigation (including left from the review
 * list into the sidebar) is handled by the framework via the `review`
 * zone layout.
 *
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createReviewBehavior() {
  return {
    onAttach() {},
    onDetach() {},
  }
}
