/**
 * Episode-mapping page behavior.
 *
 * No page-specific hooks — the master/detail navigation is handled by the
 * framework via the `episode-mapping-list` / `episode-mapping-detail` zone layout.
 *
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createEpisodeMappingBehavior() {
  return {
    onAttach() {},
    onDetach() {},
  }
}
