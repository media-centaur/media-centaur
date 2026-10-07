/**
 * Profile picker page behavior ("Who's watching?", UIDR-053): a sidebar-less
 * page with one `grid` zone holding the profile tiles and the add form. There
 * is deliberately NO `activateOnFocus` — a tile submits the form that switches
 * the profile, so it must fire only on an explicit SELECT, never because the
 * cursor passed over it. BACK is a no-op (there is no sidebar to exit to).
 *
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createProfilesBehavior() {
  return {
    onAttach() {},
    onDetach() {},
  }
}
