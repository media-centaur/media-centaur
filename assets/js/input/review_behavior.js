/**
 * Review page behavior.
 *
 * Navigation (list, detail, the decision row, the search panel) is the
 * framework's, via the `review` zone layout. One hook: SELECT on Search TMDB
 * opens the panel and moves the cursor into it, so the query field — the
 * panel's first item — is where the next key lands. The panel arrives with
 * the patch; the button lets go of focus so the post-patch reconcile, which
 * only re-asserts focus nothing holds, focuses the panel in the new context.
 *
 * @returns {import("./page_behavior").PageBehavior}
 */
import { Action } from "./core/index"

export function createReviewBehavior() {
  return {
    onAttach() {},
    onDetach() {},

    onAction(action, _context, focused) {
      if (action !== Action.SELECT || !focused?.hasAttribute("data-review-open-search")) return false
      focused.click()
      focused.blur()
      return { transitionTo: "review-search" }
    },
  }
}
