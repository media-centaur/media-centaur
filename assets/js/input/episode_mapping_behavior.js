/**
 * Episode-mapping page behavior.
 *
 * No page-specific hooks — the master/detail navigation is handled by the
 * framework via the `episode-mapping` zone layout (list, the decision toolbar,
 * the detail).
 *
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createEpisodeMappingBehavior() {
  return {
    onAttach() {},
    onDetach() {},
  }
}
