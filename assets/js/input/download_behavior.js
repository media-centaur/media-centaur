/**
 * Download page behavior.
 *
 * BACK navigates to the sidebar from the download page.
 *
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createDownloadBehavior() {
  return {
    onAttach() {},
    onDetach() {},
    onEscape() {
      return "sidebar"
    },
  }
}
