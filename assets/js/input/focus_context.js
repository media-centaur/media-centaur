/**
 * Focus context state machine.
 *
 * Manages which navigation zone is active and what rules apply.
 * Returns FocusDirective data objects — never touches DOM.
 */

import { Action } from "./actions"

export const Context = Object.freeze({
  GRID: "grid",
  DRAWER: "drawer",
  MODAL: "modal",
  TOOLBAR: "toolbar",
  SIDEBAR: "sidebar",
  ZONE_TABS: "zone_tabs",
})

/**
 * @typedef {Object} FocusDirective
 * @property {"navigate"|"focus_context"|"focus_first"|"dismiss"|"activate"|"none"} type
 * @property {string} [direction] - For navigate directives
 * @property {string} [target] - For focus_context directives
 * @property {string} [context] - For focus_first directives
 */

const NONE = Object.freeze({ type: "none" })
const DISMISS = Object.freeze({ type: "dismiss" })
const ACTIVATE = Object.freeze({ type: "activate" })

function navigate(direction) {
  return { type: "navigate", direction }
}

function focusContext(target) {
  return { type: "focus_context", target }
}

function focusFirst(context) {
  return { type: "focus_first", context }
}

export class FocusContextMachine {
  constructor(initialContext = Context.GRID) {
    this._context = initialContext
    this._drawerOpen = false
    this._zone = "watching"
  }

  get context() {
    return this._context
  }

  /**
   * Process an action in the current context and return a directive.
   * @param {string} action - Action from actions.js
   * @returns {FocusDirective}
   */
  transition(action) {
    switch (this._context) {
      case Context.MODAL:    return this._modalTransition(action)
      case Context.DRAWER:   return this._drawerTransition(action)
      case Context.GRID:     return this._gridTransition(action)
      case Context.TOOLBAR:  return this._toolbarTransition(action)
      case Context.SIDEBAR:  return this._sidebarTransition(action)
      case Context.ZONE_TABS: return this._zoneTabsTransition(action)
      default: return NONE
    }
  }

  /**
   * Notify that the zone has changed (CW <-> Library).
   * Resets context to GRID and clears drawer state.
   */
  zoneChanged(zone) {
    this._zone = zone
    this._drawerOpen = false
    // Preserve ZONE_TABS context — user is still navigating tabs
    if (this._context !== Context.ZONE_TABS) {
      this._context = Context.GRID
    }
  }

  /**
   * Notify that a modal/drawer has opened or closed.
   * @param {"modal"|"drawer"|null} presentation
   */
  presentationChanged(presentation) {
    if (presentation === "modal") {
      this._context = Context.MODAL
    } else if (presentation === "drawer") {
      this._drawerOpen = true
      this._context = Context.DRAWER
    } else {
      this._drawerOpen = false
      if (this._context === Context.MODAL || this._context === Context.DRAWER) {
        this._context = Context.GRID
      }
    }
  }

  // --- Context-specific transition rules ---

  /** Modal: focus trapped. Navigate vertically. Escape dismisses. */
  _modalTransition(action) {
    switch (action) {
      case Action.NAVIGATE_UP:    return navigate("up")
      case Action.NAVIGATE_DOWN:  return navigate("down")
      case Action.NAVIGATE_LEFT:  return NONE
      case Action.NAVIGATE_RIGHT: return NONE
      case Action.SELECT:         return ACTIVATE
      case Action.BACK:           return DISMISS
      case Action.PLAY:           return { type: "play" }
      case Action.ZONE_NEXT:      return NONE
      case Action.ZONE_PREV:      return NONE
      default: return NONE
    }
  }

  /** Drawer: split focus. Left → grid (rightmost col, same row). Escape → dismiss. */
  _drawerTransition(action) {
    switch (action) {
      case Action.NAVIGATE_UP:    return navigate("up")
      case Action.NAVIGATE_DOWN:  return navigate("down")
      case Action.NAVIGATE_LEFT:
        this._context = Context.GRID
        return { type: "grid_row_edge", side: "right" }
      case Action.NAVIGATE_RIGHT: return NONE
      case Action.SELECT:         return ACTIVATE
      case Action.BACK:           return DISMISS
      case Action.PLAY:           return { type: "play" }
      case Action.ZONE_NEXT:      return { type: "zone_cycle", direction: "next" }
      case Action.ZONE_PREV:      return { type: "zone_cycle", direction: "prev" }
      default: return NONE
    }
  }

  /** Grid: arrows navigate spatially. Wall transitions handled by gridWall(). */
  _gridTransition(action) {
    switch (action) {
      case Action.NAVIGATE_UP:    return navigate("up")
      case Action.NAVIGATE_DOWN:  return navigate("down")
      case Action.NAVIGATE_LEFT:  return navigate("left")
      case Action.NAVIGATE_RIGHT: return navigate("right")
      case Action.SELECT:         return ACTIVATE
      case Action.BACK:           return NONE
      case Action.PLAY:           return { type: "play" }
      case Action.ZONE_NEXT:      return { type: "zone_cycle", direction: "next" }
      case Action.ZONE_PREV:      return { type: "zone_cycle", direction: "prev" }
      default: return NONE
    }
  }

  /** Toolbar: left/right between controls. Down → grid. Up → zone tabs. */
  _toolbarTransition(action) {
    switch (action) {
      case Action.NAVIGATE_LEFT:  return navigate("left")
      case Action.NAVIGATE_RIGHT: return navigate("right")
      case Action.NAVIGATE_DOWN:
        this._context = Context.GRID
        return focusFirst(Context.GRID)
      case Action.NAVIGATE_UP:
        this._context = Context.ZONE_TABS
        return focusFirst(Context.ZONE_TABS)
      case Action.SELECT:         return ACTIVATE
      case Action.BACK:           return NONE
      case Action.ZONE_NEXT:      return { type: "zone_cycle", direction: "next" }
      case Action.ZONE_PREV:      return { type: "zone_cycle", direction: "prev" }
      default: return NONE
    }
  }

  /** Sidebar: up/down between items, activate on focus. Right → exit sidebar. */
  _sidebarTransition(action) {
    switch (action) {
      case Action.NAVIGATE_UP:    return navigate("up")
      case Action.NAVIGATE_DOWN:  return navigate("down")
      case Action.NAVIGATE_RIGHT:
        this._context = Context.GRID
        return { type: "exit_sidebar" }
      case Action.NAVIGATE_LEFT:  return NONE
      case Action.SELECT:         return ACTIVATE
      case Action.BACK:
        this._context = Context.GRID
        return { type: "exit_sidebar" }
      default: return NONE
    }
  }

  /** Zone tabs: left/right between tabs. Enter activates. Down → zone content. Up → wall. */
  _zoneTabsTransition(action) {
    switch (action) {
      case Action.NAVIGATE_LEFT:  return navigate("left")
      case Action.NAVIGATE_RIGHT: return navigate("right")
      case Action.NAVIGATE_DOWN:
        this._context = this._zone === "library" ? Context.TOOLBAR : Context.GRID
        return focusFirst(this._context)
      case Action.NAVIGATE_UP:    return NONE
      case Action.SELECT:         return ACTIVATE
      case Action.BACK:           return NONE
      case Action.ZONE_NEXT:      return { type: "zone_cycle", direction: "next" }
      case Action.ZONE_PREV:      return { type: "zone_cycle", direction: "prev" }
      default: return NONE
    }
  }

  /**
   * Called by the orchestrator when grid navigation hits a wall.
   * Returns a directive for cross-context navigation (e.g., up from top row → toolbar).
   * @param {"up"|"down"|"left"|"right"} direction
   * @returns {FocusDirective}
   */
  gridWall(direction) {
    switch (direction) {
      case "up":
        if (this._zone === "library") {
          this._context = Context.TOOLBAR
          return focusFirst(Context.TOOLBAR)
        }
        this._context = Context.ZONE_TABS
        return focusFirst(Context.ZONE_TABS)

      case "left":
        this._context = Context.SIDEBAR
        return { type: "enter_sidebar" }

      case "right":
        if (this._drawerOpen) {
          this._context = Context.DRAWER
          return focusContext(Context.DRAWER)
        }
        return NONE

      default:
        return NONE
    }
  }
}
