import { describe, expect, test } from "bun:test"
import { Action } from "../core/index"
import { createProfilesBehavior } from "../profiles_behavior"

/** A focused element, inside the open add form or not, with the form's Cancel. */
function focusedField({ inAddForm }) {
  const cancel = {
    clicked: 0,
    click() {
      this.clicked += 1
    },
  }
  const form = {
    querySelector: (selector) => (selector === "[data-profile-add-cancel]" ? cancel : null),
  }
  return {
    cancel,
    closest: (selector) => (inAddForm && selector === "#add-profile-form" ? form : null),
  }
}

describe("profiles behavior", () => {
  test("does not activate items on focus — a tile switches the profile only on an explicit SELECT", () => {
    const behavior = createProfilesBehavior()
    expect(behavior.activateOnFocus ?? []).toEqual([])
  })

  test("defines no onEscape — BACK is the state machine's (the sidebar, when the shell is present)", () => {
    const behavior = createProfilesBehavior()
    expect(behavior.onEscape).toBeUndefined()
  })

  test("BACK inside the open add form cancels it and goes no further (not into the sidebar)", () => {
    const behavior = createProfilesBehavior()
    const focused = focusedField({ inAddForm: true })

    expect(behavior.onAction(Action.BACK, "profile_picker", focused)).toBe(true)
    expect(focused.cancel.clicked).toBe(1)
  })

  test("BACK anywhere else is the state machine's", () => {
    const behavior = createProfilesBehavior()
    const focused = focusedField({ inAddForm: false })

    expect(behavior.onAction(Action.BACK, "profile_picker", focused)).toBe(false)
    expect(focused.cancel.clicked).toBe(0)
  })

  test("other actions in the add form pass through", () => {
    const behavior = createProfilesBehavior()
    const focused = focusedField({ inAddForm: true })

    expect(behavior.onAction(Action.SELECT, "profile_picker", focused)).toBe(false)
    expect(focused.cancel.clicked).toBe(0)
  })
})
