/**
 * Episode-mapping (reconcile) page behavior.
 *
 * No page-specific hooks — the master/detail navigation is handled by the
 * framework via the `reconcile-list` / `reconcile-detail` zone layout.
 *
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createReconcileBehavior() {
  return {
    onAttach() {},
    onDetach() {},
  }
}
