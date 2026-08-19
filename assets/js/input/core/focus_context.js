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
  SHELF: "shelf",
  TREE: "tree",
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
 * @property {"navigate"|"focus_context"|"enter_context"|"dismiss"|"activate"|"none"} type
 * @property {string} [direction] - For navigate and enter_context directives
 * @property {string} [target] - For focus_context directives
 * @property {string} [context] - For enter_context directives
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

/**
 * Cross into `context`, having travelled in `direction` to get there. The
 * direction matters because entering a zone should land you on something
 * adjacent to the edge you crossed — see the orchestrator's `_enterContext`.
 * Omitted when the crossing is not spatial (exiting the sidebar).
 */
function enterContext(context, direction) {
  return { type: "enter_context", context, direction }
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
    // Whether an overlay currently contains the cursor. Tracked separately from
    // the context because an overlay may hold several regions (the detail
    // modal's action row and episode list), so "am I in an overlay" can no
    // longer be answered by comparing the context to MODAL.
    this._overlay = false
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
    // BACK is answered before the context type, because what it does is not a
    // property of the region you are in — it is a property of what contains
    // that region. See `_backTransition`.
    if (action === Action.BACK) return this._backTransition()

    const type = contextType(this._context, this._config.instanceTypes)
    switch (type) {
      case Context.MODAL:    return this._modalTransition(action)
      case Context.DRAWER:   return this._drawerTransition(action)
      case Context.GRID:     return this._gridTransition(action)
      case Context.TOOLBAR:  return this._toolbarTransition(action)
      case Context.MENU:     return this._menuTransition(action)
      case Context.SHELF:    return this._shelfTransition(action)
      case Context.TREE:     return this._treeTransition(action)
      case Context.ZONE_TABS: return this._zoneTabsTransition(action)
      default: return NONE
    }
  }

  /**
   * BACK leaves the region you are in, whatever depth you reached inside it:
   *
   * 1. **A region within an overlay** — declared as a `back` edge in the nav
   *    graph. The detail modal's episode list leaves for its action row from
   *    anywhere: a season header, an episode, or an episode's own controls.
   *    Stepping back out one level at a time is what LEFT is for.
   * 2. **Sub-focus**, where the region itself has nowhere to go — the flat
   *    overlays, whose items have controls but no region above them.
   * 3. **The overlay itself** — dismiss.
   * 4. **The primary menu** — back to whatever the sidebar was opened over.
   * 5. **Content** — enter the primary menu. The main nav is what contains
   *    every content region, so BACK from a grid, shelf, toolbar, zone-tab
   *    strip or non-primary menu goes there. LEFT stays lateral movement
   *    within the page and never leaves it. A page whose layout declares no
   *    sidebar node (the setup tour) has no menu to enter, so BACK stays a
   *    no-op there — the node's presence in the graph is the capability check.
   *
   * Ordering is the whole design: an overlay region leaves for its sibling
   * before the overlay dismisses itself, which is what makes "BACK anywhere in
   * the episode list goes to Play, BACK from Play closes the modal" one rule
   * instead of two special cases. Each of these used to be a `case Action.BACK`
   * in a different transition function, where the ordering was implicit.
   */
  _backTransition() {
    const target = this._navGraph?.[this._context]?.back
    if (target) {
      this._subFocus = false
      this._setContext(target)
      return enterContext(target, "back")
    }

    if (this._subFocus) {
      this._subFocus = false
      return exitSubFocus()
    }

    if (this._overlay) return DISMISS
    const primaryMenu = this._config.primaryMenu
    if (this._context === primaryMenu) return { type: "exit_sidebar" }
    if (primaryMenu && this._navGraph?.[primaryMenu]) {
      this._setContext(primaryMenu)
      return { type: "enter_sidebar" }
    }
    return NONE
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
   * Whether an overlay currently contains the cursor.
   */
  get inOverlay() {
    return this._overlay
  }

  /**
   * Enter sub-focus without emitting a directive. The counterpart to
   * `clearSubFocus`, for the paths where the orchestrator has already confirmed
   * against the DOM that the focused item has a sub-item to enter — a TREE's
   * RIGHT means "expand" or "go deeper" depending on what is under the cursor,
   * so only the orchestrator can say which happened.
   */
  beginSubFocus() {
    this._subFocus = true
  }

  /**
   * Clear sub-focus without emitting a directive.
   * Called by the orchestrator when the focused item has no sub-item.
   */
  clearSubFocus() {
    this._subFocus = false
  }

  /**
   * Notify that a modal/drawer has opened or closed.
   *
   * @param {"modal"|"drawer"|null} presentation
   * @param {string} [entryContext] - Which region of the overlay takes the
   *   cursor. Overlays that are a single flat list omit it and get MODAL; the
   *   detail modal names its action row, because "the first item in the
   *   overlay" and "the region you should land in" stopped being the same thing
   *   once the overlay had more than one region.
   */
  presentationChanged(presentation, entryContext = null) {
    this._subFocus = false
    if (presentation === "modal") {
      this._overlay = true
      this._setContext(entryContext ?? Context.MODAL)
    } else if (presentation === "drawer") {
      this._overlay = true
      this._drawerOpen = true
      this._setContext(Context.DRAWER)
    } else {
      const wasOverlay = this._overlay
      this._overlay = false
      this._drawerOpen = false
      if (wasOverlay) this._setContext(Context.GRID)
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
      case Action.PLAY:           return { type: "play" }
      case Action.ZONE_NEXT:      return { type: "zone_cycle", direction: "next" }
      case Action.ZONE_PREV:      return { type: "zone_cycle", direction: "prev" }
      default: return NONE
    }
  }

  /** Toolbar: left/right between controls. Down/Up consult the nav graph for
   *  THIS instance (keyed by `_context`, not the literal "toolbar"), so a
   *  toolbar-typed companion like the upcoming mini-month follows its own
   *  up/down edges. */
  _toolbarTransition(action) {
    switch (action) {
      case Action.NAVIGATE_LEFT:  return navigate("left")
      case Action.NAVIGATE_RIGHT: return navigate("right")
      case Action.NAVIGATE_DOWN: {
        const target = this._navGraph?.[this._context]?.down
        if (!target) return NONE
        this._setContext(target)
        return enterContext(target, "down")
      }
      case Action.NAVIGATE_UP: {
        const target = this._navGraph?.[this._context]?.up
        if (!target) return NONE
        this._setContext(target)
        return enterContext(target, "up")
      }
      case Action.SELECT:         return ACTIVATE
      case Action.ZONE_NEXT:      return { type: "zone_cycle", direction: "next" }
      case Action.ZONE_PREV:      return { type: "zone_cycle", direction: "prev" }
      default: return NONE
    }
  }

  /** Menu: up/down between items. Right exits toward content (primary menu)
   *  or follows the nav graph (non-primary). BACK is handled before dispatch
   *  by `_backTransition`: it exits the primary menu and enters it from
   *  everywhere else — LEFT is lateral movement within the page and never
   *  reaches the sidebar. Generalizes sidebar and section nav. */
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
        return enterContext(target, "right")
      }
      case Action.NAVIGATE_LEFT: {
        if (isPrimaryMenu) return NONE
        const target = this._navGraph?.[this._context]?.left
        if (!target) return NONE
        this._setContext(target)
        return enterContext(target, "left")
      }
      case Action.SELECT:         return ACTIVATE
      default: return NONE
    }
  }

  /**
   * Shelf: a sequence of media tiles that happens to be laid out spatially —
   * the home page's hero CTAs, Continue Watching, Recently Added, and the
   * Coming Up marquee. Most shelves are a single row; the marquee is a mosaic
   * (one large tile beside a stacked column). Both are the same thing, so
   * there is one context type and one navigation path.
   *
   * All four directions return `navigate` and are resolved by the
   * orchestrator's `_shelfNavigate`, which asks in order: the layout
   * (geometry), then the nav graph (cross into a neighbouring zone), then the
   * sequence. Keeping the walls out of here is what lets a mosaic and a row
   * share one rule set — the state machine never has to know which it is.
   *
   * Select activates the focused card; BACK enters the sidebar via
   * `_backTransition` before this dispatch is reached.
   */
  _shelfTransition(action) {
    switch (action) {
      case Action.NAVIGATE_LEFT:  return navigate("left")
      case Action.NAVIGATE_RIGHT: return navigate("right")
      case Action.NAVIGATE_UP:    return navigate("up")
      case Action.NAVIGATE_DOWN:  return navigate("down")
      case Action.SELECT:         return ACTIVATE
      case Action.PLAY:           return { type: "play" }
      default: return NONE
    }
  }

  /**
   * Tree: a vertical list whose items nest — the detail modal's body, where
   * seasons contain episodes and an episode contains its own controls (the
   * synopsis disclosure, the watched toggle).
   *
   * The dual of SHELF's insight, one axis over. UP and DOWN walk the list as
   * rendered, so a collapsed season is one line and an expanded one is many;
   * LEFT and RIGHT are *depth* rather than lateral movement. That is the one
   * idiom the surface needs: RIGHT goes in (expand a collapsed season, or step
   * into an episode's controls), LEFT comes back out (leave the controls, then
   * collapse the season you are inside, landing on its header).
   *
   * Which of those RIGHT and LEFT mean depends on what the cursor is actually
   * on, which is a DOM question — so the machine says only the direction of
   * travel and the orchestrator's `_executeTreeIn` / `_executeTreeOut` resolve
   * it. Keeping the DOM out of here is what lets the same context serve a
   * season list, a movie-series list, and a bare extras list without knowing
   * which it has.
   *
   * BACK is not handled here: it leaves the region entirely, which is
   * `_backTransition`'s job.
   */
  _treeTransition(action) {
    if (this._subFocus) {
      switch (action) {
        // Still depth, one level further in: an episode carries more than one
        // control, so RIGHT walks along them and LEFT walks back and then out.
        case Action.NAVIGATE_RIGHT: return { type: "tree_in" }
        case Action.NAVIGATE_LEFT:  return { type: "tree_out" }
        case Action.NAVIGATE_UP:    this._subFocus = false; return navigate("up")
        case Action.NAVIGATE_DOWN:  this._subFocus = false; return navigate("down")
        case Action.SELECT:         return ACTIVATE
        case Action.PLAY:           return { type: "play" }
        default: return NONE
      }
    }

    switch (action) {
      case Action.NAVIGATE_UP:    return navigate("up")
      case Action.NAVIGATE_DOWN:  return navigate("down")
      case Action.NAVIGATE_RIGHT: return { type: "tree_in" }
      case Action.NAVIGATE_LEFT:  return { type: "tree_out" }
      case Action.SELECT:         return ACTIVATE
      case Action.PLAY:           return { type: "play" }
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
        return enterContext(target, "down")
      }
      case Action.NAVIGATE_UP:    return NONE
      case Action.SELECT:         return ACTIVATE
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
   * @param {string} context - The source context
   * @param {"up"|"down"|"left"|"right"} direction
   * @returns {FocusDirective}
   */
  contextWall(context, direction) {
    const target = this.getGraphTarget(context, direction)
    if (!target) return NONE
    this._setContext(target)
    return enterContext(target, direction)
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
