/**
 * Review page behavior.
 *
 * Navigation (list, detail, the decision row, the search panel) is the
 * framework's, via the `review` zone layout. The search panel is a nested
 * region of the decision row (a `back` edge to it and a
 * `data-nav-dismiss-event`): it takes the cursor when Search TMDB opens it
 * and closes when the cursor leaves it, like any nested menu.
 *
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createReviewBehavior() {
  return {
    onAttach() {},
    onDetach() {},
  }
}
