/**
 * Focus context state machine.
 *
 * Manages which navigation zone is active and what rules apply.
 * Returns FocusDirective data objects — never touches DOM.
 *
 * Parameterized by config: instanceTypes maps instance names to context
 * behavior types, primaryMenu identifies the menu with enter/exit behavior.
 */

import { Action } from "./actions"

export const Context = Object.freeze({
  GRID: "grid",
  DRAWER: "drawer",
  MODAL: "modal",
  TOOLBAR: "toolbar",
  MENU: "menu",
  ZONE_TABS: "zone_tabs",
})

/**
 * Resolve an instance name to its context behavior type.
 * @param {string} instance - The context instance name
 * @param {Object} [instanceTypes={}] - Map of instance names to context types
 * @returns {string} The context type for transition logic
 */
export function contextType(instance, instanceTypes = {}) {
  return instanceTypes[instance] ?? instance
}

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
  /**
   * @param {Object} [config={}]
   * @param {Object} [config.instanceTypes={}] - Map instance names to context types
   * @param {string} [config.primaryMenu] - Instance name with enter/exit behavior
   * @param {string} [config.initialContext] - Starting context (default: GRID)
   */
  constructor(config = {}) {
    this._config = {
      instanceTypes: config.instanceTypes ?? {},
      primaryMenu: config.primaryMenu ?? null,
    }
    this._context = config.initialContext ?? Context.GRID
    this._drawerOpen = false
    this._zone = "watching"
    this._navGraph = null
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
    const type = contextType(this._context, this._config.instanceTypes)
    switch (type) {
      case Context.MODAL:    return this._modalTransition(action)
      case Context.DRAWER:   return this._drawerTransition(action)
      case Context.GRID:     return this._gridTransition(action)
      case Context.TOOLBAR:  return this._toolbarTransition(action)
      case Context.MENU:     return this._menuTransition(action)
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
   * Force the machine into a specific context.
   * Used by the orchestrator for sidebar resume, exit restore,
   * and stay-in-sidebar fallback — replaces direct _context mutation.
   * @param {string} context - One of the Context values
   */
  forceContext(context) {
    this._context = context
  }

  /**
   * Sync the drawer-open flag from the DOM.
   * Replaces direct _drawerOpen mutation from the orchestrator.
   * @param {boolean} isOpen
   */
  syncDrawerState(isOpen) {
    this._drawerOpen = isOpen
  }

  /**
   * Set the navigation graph for cross-context transitions.
   * Built by the orchestrator from live DOM state.
   * @param {Object} graph - Adjacency map from buildNavGraph()
   */
  setNavGraph(graph) {
    this._navGraph = graph
  }

  /**
   * Enter primary menu from a left-wall transition in zone tabs or toolbar.
   * Sets context to primaryMenu and returns the enter_sidebar directive.
   * @returns {FocusDirective}
   */
  enterSidebarFromWall() {
    this._context = this._config.primaryMenu
    return { type: "enter_sidebar" }
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
      case Action.NAVIGATE_LEFT: {
        const target = this._navGraph?.drawer?.left
        if (!target) return NONE
        this._context = Context.GRID
        return { type: "grid_row_edge", side: "right" }
      }
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

  /** Toolbar: left/right between controls. Down/Up consult nav graph. */
  _toolbarTransition(action) {
    switch (action) {
      case Action.NAVIGATE_LEFT:  return navigate("left")
      case Action.NAVIGATE_RIGHT: return navigate("right")
      case Action.NAVIGATE_DOWN: {
        const target = this._navGraph?.toolbar?.down
        if (!target) return NONE
        this._context = target
        return focusFirst(target)
      }
      case Action.NAVIGATE_UP: {
        const target = this._navGraph?.toolbar?.up
        if (!target) return NONE
        this._context = target
        return focusFirst(target)
      }
      case Action.SELECT:         return ACTIVATE
      case Action.BACK:           return NONE
      case Action.ZONE_NEXT:      return { type: "zone_cycle", direction: "next" }
      case Action.ZONE_PREV:      return { type: "zone_cycle", direction: "prev" }
      default: return NONE
    }
  }

  /** Menu: up/down between items. Right/Back exits. Generalizes sidebar and section nav. */
  _menuTransition(action) {
    const isPrimaryMenu = this._context === this._config.primaryMenu

    switch (action) {
      case Action.NAVIGATE_UP:    return navigate("up")
      case Action.NAVIGATE_DOWN:  return navigate("down")
      case Action.NAVIGATE_RIGHT: {
        if (isPrimaryMenu) return { type: "exit_sidebar" }
        const target = this._navGraph?.[this._context]?.right
        if (!target) return NONE
        this._context = target
        return focusFirst(target)
      }
      case Action.NAVIGATE_LEFT: {
        if (isPrimaryMenu) return NONE
        const target = this._navGraph?.[this._context]?.left
        if (!target) return NONE
        if (target === this._config.primaryMenu) {
          this._context = this._config.primaryMenu
          return { type: "enter_sidebar" }
        }
        this._context = target
        return focusFirst(target)
      }
      case Action.SELECT:         return ACTIVATE
      case Action.BACK: {
        if (isPrimaryMenu) return { type: "exit_sidebar" }
        const target = this._navGraph?.[this._context]?.left
        if (!target) return NONE
        if (target === this._config.primaryMenu) {
          this._context = this._config.primaryMenu
          return { type: "enter_sidebar" }
        }
        this._context = target
        return focusFirst(target)
      }
      default: return NONE
    }
  }

  /** Zone tabs: left/right between tabs. Enter activates. Down consults nav graph. */
  _zoneTabsTransition(action) {
    switch (action) {
      case Action.NAVIGATE_LEFT:  return navigate("left")
      case Action.NAVIGATE_RIGHT: return navigate("right")
      case Action.NAVIGATE_DOWN: {
        const target = this._navGraph?.zone_tabs?.down
        if (!target) return NONE
        this._context = target
        return focusFirst(target)
      }
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
      case "up": {
        const target = this._navGraph?.grid?.up
        if (!target) return NONE
        this._context = target
        return focusFirst(target)
      }

      case "left": {
        const target = this._navGraph?.grid?.left
        if (!target) return NONE
        if (target === this._config.primaryMenu) {
          this._context = this._config.primaryMenu
          return { type: "enter_sidebar" }
        }
        this._context = target
        return focusFirst(target)
      }

      case "right": {
        const target = this._navGraph?.grid?.right
        if (!target) return NONE
        this._context = Context.DRAWER
        return focusContext(Context.DRAWER)
      }

      default:
        return NONE
    }
  }
}
