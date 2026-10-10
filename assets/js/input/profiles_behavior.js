/**
 * Profile picker page behavior ("Who's watching?", UIDR-053): one
 * `profile_picker` zone (SHELF, resolved by geometry) holding the profile
 * tiles and the add form. There is deliberately NO `activateOnFocus` — a tile
 * submits the form that switches the profile, so it must fire only on an
 * explicit SELECT, never because the cursor passed over it. BACK is the state
 * machine's: it enters the sidebar when the picker is inside the shell (a
 * switch) and is a no-op at the door, where there is no sidebar.
 *
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createProfilesBehavior() {
  return {
    onAttach() {},
    onDetach() {},
  }
}
