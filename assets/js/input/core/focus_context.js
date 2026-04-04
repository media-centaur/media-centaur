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
import { debug } from "./debug"

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

function enterSubFocus() {
  return { type: "enter_sub_focus" }
}

function exitSubFocus() {
  return { type: "exit_sub_focus" }
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
    this._onContextChanged = config.onContextChanged ?? null
    this._drawerOpen = false
    this._subFocus = false
    this._zone = "watching"
    this._navGraph = null
  }

  /**
   * Set context with change notification. All internal context mutations
   * go through this method so the onContextChanged callback fires exactly
   * once per actual state change.
   */
  _setContext(value) {
    if (value === this._context) return
    const prev = this._context
    this._context = value
    debug(() => ["_setContext:", prev, "→", value, new Error().stack.split("\n")[2]?.trim()])
    this._onContextChanged?.(value)
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
      this._setContext(Context.GRID)
    }
  }

  /**
   * Force the machine into a specific context.
   * Used by the orchestrator for sidebar resume, exit restore,
   * and stay-in-sidebar fallback — replaces direct _context mutation.
   * @param {string} context - One of the Context values
   */
  forceContext(context) {
    this._setContext(context)
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
   * Whether the machine is in sub-focus mode (e.g. checkmark within a row).
   */
  get subFocus() {
    return this._subFocus
  }

  /**
   * Clear sub-focus without emitting a directive.
   * Called by the orchestrator when the focused item has no sub-item.
   */
  clearSubFocus() {
    this._subFocus = false
  }

  /**
   * Enter primary menu from a left-wall transition in zone tabs or toolbar.
   * Sets context to primaryMenu and returns the enter_sidebar directive.
   * @returns {FocusDirective}
   */
  enterSidebarFromWall() {
    this._setContext(this._config.primaryMenu)
    return { type: "enter_sidebar" }
  }

  /**
   * Notify that a modal/drawer has opened or closed.
   * @param {"modal"|"drawer"|null} presentation
   */
  presentationChanged(presentation) {
    this._subFocus = false
    if (presentation === "modal") {
      this._setContext(Context.MODAL)
    } else if (presentation === "drawer") {
      this._drawerOpen = true
      this._setContext(Context.DRAWER)
    } else {
      this._drawerOpen = false
      if (this._context === Context.MODAL || this._context === Context.DRAWER) {
        this._setContext(Context.GRID)
      }
    }
  }

  // --- Context-specific transition rules ---

  /** Modal: focus trapped. Navigate vertically. Escape dismisses.
   *  Sub-focus: RIGHT enters sub-item, LEFT/BACK exits, UP/DOWN exit then navigate. */
  _modalTransition(action) {
    if (this._subFocus) {
      switch (action) {
        case Action.NAVIGATE_LEFT:  this._subFocus = false; return exitSubFocus()
        case Action.NAVIGATE_RIGHT: return NONE
        case Action.SELECT:         return ACTIVATE
        case Action.NAVIGATE_UP:    this._subFocus = false; return navigate("up")
        case Action.NAVIGATE_DOWN:  this._subFocus = false; return navigate("down")
        case Action.BACK:           this._subFocus = false; return exitSubFocus()
        case Action.PLAY:           return { type: "play" }
        default: return NONE
      }
    }

    switch (action) {
      case Action.NAVIGATE_UP:    return navigate("up")
      case Action.NAVIGATE_DOWN:  return navigate("down")
      case Action.NAVIGATE_LEFT:  return navigate("left")
      case Action.NAVIGATE_RIGHT: this._subFocus = true; return enterSubFocus()
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
        this._setContext(Context.GRID)
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
        this._setContext(target)
        return focusFirst(target)
      }
      case Action.NAVIGATE_UP: {
        const target = this._navGraph?.toolbar?.up
        if (!target) return NONE
        this._setContext(target)
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
        this._setContext(target)
        return focusFirst(target)
      }
      case Action.NAVIGATE_LEFT: {
        if (isPrimaryMenu) return NONE
        const target = this._navGraph?.[this._context]?.left
        if (!target) return NONE
        if (target === this._config.primaryMenu) {
          this._setContext(this._config.primaryMenu)
          return { type: "enter_sidebar" }
        }
        this._setContext(target)
        return focusFirst(target)
      }
      case Action.SELECT:         return ACTIVATE
      case Action.BACK: {
        if (isPrimaryMenu) return { type: "exit_sidebar" }
        const target = this._navGraph?.[this._context]?.left
        if (!target) return NONE
        if (target === this._config.primaryMenu) {
          this._setContext(this._config.primaryMenu)
          return { type: "enter_sidebar" }
        }
        this._setContext(target)
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
        this._setContext(target)
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
   * Look up the nav graph neighbor for a context in a given direction.
   * @param {string} context - The source context
   * @param {"up"|"down"|"left"|"right"} direction
   * @returns {string|undefined} The target context name, or undefined if no edge.
   */
  getGraphTarget(context, direction) {
    return this._navGraph?.[context]?.[direction]
  }

  /**
   * General wall handler: look up a nav graph edge for any context and direction.
   * Handles sidebar entry when the target is the primary menu.
   * @param {string} context - The source context
   * @param {"up"|"down"|"left"|"right"} direction
   * @returns {FocusDirective}
   */
  contextWall(context, direction) {
    const target = this.getGraphTarget(context, direction)
    if (!target) return NONE
    if (target === this._config.primaryMenu) {
      this._setContext(this._config.primaryMenu)
      return { type: "enter_sidebar" }
    }
    this._setContext(target)
    return focusFirst(target)
  }

  /**
   * Called by the orchestrator when grid navigation hits a wall.
   * Delegates to contextWall for up/left; handles right → drawer specially.
   * @param {"up"|"down"|"left"|"right"} direction
   * @returns {FocusDirective}
   */
  gridWall(direction) {
    if (direction === "right") {
      const target = this.getGraphTarget(Context.GRID, "right")
      if (!target) return NONE
      this._setContext(Context.DRAWER)
      return focusContext(Context.DRAWER)
    }
    return this.contextWall(Context.GRID, direction)
  }
}
