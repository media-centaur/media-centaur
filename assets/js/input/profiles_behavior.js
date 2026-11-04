/**
 * Profile picker page behavior ("Who's watching?", UIDR-053): one
 * `profile_picker` zone (SHELF, resolved by geometry) holding the profile
 * tiles and the add form. There is deliberately NO `activateOnFocus` — a tile
 * submits the form that switches the profile, so it must fire only on an
 * explicit SELECT, never because the cursor passed over it. BACK is the state
 * machine's: it enters the sidebar when the picker is inside the shell (a
 * switch) and is a no-op at the door, where there is no sidebar — except
 * inside the open add form, where BACK is its Cancel: the form closes, the
 * add tile returns in its place and keeps the cursor.
 *
 * @returns {import("./page_behavior").PageBehavior}
 */
import { Action } from "./core/index"

export function createProfilesBehavior() {
  return {
    onAttach() {},
    onDetach() {},

    onAction(action, _context, focused) {
      if (action !== Action.BACK) return false
      const form = focused?.closest?.("#add-profile-form")
      if (!form) return false
      form.querySelector("[data-profile-add-cancel]")?.click()
      return true
    },
  }
}
