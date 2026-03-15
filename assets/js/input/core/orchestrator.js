/**
 * Orchestrator — wires all framework modules together.
 *
 * Creates instances, manages input sources, routes actions through
 * the state machine, and executes directives via the DOM adapter.
 *
 * Input sources (keyboard, gamepad) are decoupled peers that produce
 * semantic actions. The orchestrator is source-agnostic — it never
 * knows which source produced an action.
 *
 * All external dependencies (reader, writer, globals) and app-specific
 * configuration are injected via a config object, making the orchestrator
 * fully testable with mocks and free of app-specific imports.
 */

import { Action } from "./actions"
import { gridNavigate } from "./spatial"
import { FocusContextMachine, Context, contextType } from "./focus_context"
import { InputMethodDetector } from "./input_method"
import { buildNavGraph, resolveCursorStart } from "./nav_graph"
import { debug } from "./debug"

// Minimum mouse movement (px) to switch to mouse input method.
// Layout shifts fire mousemove at the same coordinates — real mouse
// movement always changes position. This eliminates race conditions
// that plagued the old time-based cooldown approach.
const MOUSE_MOVE_THRESHOLD = 1

export class Orchestrator {
  /**
   * @param {Object} config
   * @param {Object} config.reader - DomReader interface
   * @param {Object} config.writer - DomWriter interface
   * @param {Object} config.globals - { document, sessionStorage, requestAnimationFrame, ... }
   * @param {Array} [config.sources] - Source factory functions: (callbacks, globals) => source
   * @param {Object} config.contextSelectors - Maps context keys to CSS selectors
   * @param {Object} [config.instanceTypes] - Maps instance names to context types
   * @param {string} [config.primaryMenu] - Instance name with enter/exit behavior
   * @param {Object} [config.layouts] - Spatial layouts per zone
   * @param {Object} [config.cursorStartPriority] - Cursor start priority per zone
   * @param {string[]} [config.alwaysPopulated] - Contexts that skip item count check
   * @param {function} [config.createBehavior] - Factory: (name) => PageBehavior|null
   */
  constructor(config = {}) {
    this._config = config
    this.focusMachine = new FocusContextMachine({
      instanceTypes: config.instanceTypes,
      primaryMenu: config.primaryMenu,
      onContextChanged: (context) => this.writer?.setNavContext?.(context),
    })
    this.inputDetector = new InputMethodDetector()
    this.reader = config.reader
    this.writer = config.writer
    this._globals = config.globals ?? {}
    this._hookEl = null
    // Last known mouse position — synthetic mousemove from layout shifts
    // has the same coordinates, so we only switch to mouse on real movement.
    // Starts null: the first mousemove only records the baseline position
    // (we can't know the delta without a prior reading).
    this._lastMouseX = null
    this._lastMouseY = null
    // Track the entity ID of the card that opened a modal/drawer,
    // so we can restore focus on dismiss.
    this._originEntityId = null
    // Per-context focus memory: remembers the last focused index in each
    // context so returning to it restores position instead of jumping to first.
    this._contextMemory = {}
    // Which context the user was in before entering the sidebar,
    // so exiting restores to zone tabs / toolbar / grid as appropriate.
    this._preSidebarContext = null
    // Grid uses entity ID for memory (indices shift on stream updates).
    this._lastGridEntityId = null
    // Cached item counts per context, rebuilt in _syncState
    this._counts = {}
    // Active page behavior (detected from data-page-behavior attribute)
    this._behavior = null
    this._behaviorName = null
    // Input sources (created in start())
    this._sources = []
    this._sourceFactories = config.sources ?? []
    // Expected presentation state after an orchestrator-initiated transition.
    // undefined = no expectation (trust DOM), null = expect no presentation.
    // Prevents _syncState() from re-entering an overlay context during the
    // LiveView round-trip after _executeDismiss().
    this._expectedPresentation = undefined
    this._onMouseMove = this._onMouseMove.bind(this)
  }

  /**
   * Start the input system. Called from the LiveView hook's mounted().
   * @param {HTMLElement} hookEl - The hook element for pushing events
   */
  start(hookEl) {
    this._hookEl = hookEl

    // Restore input method from previous mount (survives cross-LiveView navigation)
    const savedMethod = this._globals.sessionStorage.getItem("inputSystem:inputMethod")
    if (savedMethod) {
      this._globals.sessionStorage.removeItem("inputSystem:inputMethod")
      this.inputDetector = new InputMethodDetector(savedMethod)
      this.writer.setInputMethod(savedMethod)
    }

    // Create and start input sources
    const callbacks = {
      onAction: (action) => this._onSourceAction(action),
      onInputDetected: (type) => this._onInputDetected(type),
    }
    this._sources = this._sourceFactories.map(factory => {
      const source = factory(callbacks, this._globals)
      source.start()
      return source
    })

    this._globals.document.addEventListener("mousemove", this._onMouseMove)

    // Sync initial state (also detects and attaches page behavior)
    this._syncState()

    // Project initial nav context to DOM (the callback only fires on changes,
    // so the constructor's initial value needs an explicit write)
    this.writer.setNavContext?.(this.focusMachine.context)

    // Let the page behavior restore its state on attach
    this._behavior?.onAttach()

    // Resume sidebar context after navigation (sessionStorage bridge)
    const primaryMenu = this._config.primaryMenu
    if (primaryMenu && this._globals.sessionStorage.getItem("inputSystem:resumeSidebar") === "true") {
      this._globals.sessionStorage.removeItem("inputSystem:resumeSidebar")
      this.focusMachine.forceContext(primaryMenu)
      const activeIndex = this.reader.getActiveItemIndex(primaryMenu)
      if (activeIndex >= 0) {
        this.writer.focusByIndex(primaryMenu, activeIndex)
      } else {
        this.writer.focusFirst(primaryMenu)
      }
    }

    // If the initial context (GRID) is empty, fall back to a non-empty context
    this._ensureCursorStart()
  }

  /**
   * If the current context has no focusable items, resolve the first
   * viable context from the cursor start priority list.
   */
  _ensureCursorStart() {
    // Don't override context while the orchestrator owns a presentation transition.
    // The DOM may transiently show zero items during morphdom patching.
    if (this._expectedPresentation !== undefined) return

    const context = this.focusMachine.context
    const count = this.reader.getItemCount(context)
    if (count > 0) return

    const target = resolveCursorStart(this.reader.getZone(), this._counts, {
      cursorStartPriority: this._config.cursorStartPriority,
      alwaysPopulated: this._config.alwaysPopulated,
    })
    if (target) {
      this.focusMachine.forceContext(target)
      this._restoreContextFocus(target)
    }
  }

  /**
   * Stop the input system. Called from the LiveView hook's destroyed().
   */
  destroy() {
    // If we're in the sidebar, persist so the new page resumes there
    const primaryMenu = this._config.primaryMenu
    if (primaryMenu && this.focusMachine.context === primaryMenu) {
      this._globals.sessionStorage.setItem("inputSystem:resumeSidebar", "true")
    }

    // Persist input method so the next mount starts with the correct mode
    this._globals.sessionStorage.setItem(
      "inputSystem:inputMethod",
      this.inputDetector.current
    )

    // Stop all input sources
    for (const source of this._sources) {
      source.stop()
    }
    this._sources = []

    this._globals.document.removeEventListener("mousemove", this._onMouseMove)
    this._detachBehavior()
    this._hookEl = null
  }

  /**
   * Called by the LiveView hook when the view updates.
   * Syncs focus machine state with current DOM state.
   */
  onViewChanged() {
    debug("onViewChanged")
    this._syncState()
    this._ensureCursorStart()
  }

  // --- Source callbacks ---

  /**
   * Shared callback from any input source when a semantic action is produced.
   * Handles behavior onEscape for BACK action, then delegates to _handleAction.
   */
  _onSourceAction(action) {
    debug("action:", action, "context:", this.focusMachine.context, "method:", this.inputDetector.current)
    // CLEAR action: delegate to page behavior's onClear hook.
    // Behaviors use this for resetting page-specific state (e.g. clearing a filter).
    if (action === Action.CLEAR && this._behavior?.onClear) {
      this._behavior.onClear()
      return
    }

    // BACK action: let page behavior try onEscape first (e.g. navigate to subnav),
    // but only in content contexts. Overlays (modal/drawer) and menus
    // (sidebar/sections) have their own BACK semantics that must not be intercepted.
    if (action === Action.BACK && this._behavior?.onEscape) {
      const context = this.focusMachine.context
      const isOverlay = context === Context.MODAL || context === Context.DRAWER
      const isMenu = contextType(context, this._config.instanceTypes) === Context.MENU
      if (!isOverlay && !isMenu) {
        const result = this._behavior.onEscape()
        if (typeof result === "string") {
          this._saveContextMemory()
          if (result === this._config.primaryMenu) {
            this._preSidebarContext = context
            this.focusMachine.forceContext(result)
            this._executeEnterSidebar()
          } else {
            this.focusMachine.forceContext(result)
            this._restoreContextFocus(result)
          }
          return
        }
        if (result) {
          return // consumed by behavior
        }
      }
    }

    this._handleAction(action)
  }

  /**
   * Shared callback from any input source when raw input is detected.
   * Updates input method.
   */
  _onInputDetected(type) {
    const methodChange = this.inputDetector.observe(type)
    if (methodChange) {
      this.writer.setInputMethod(methodChange)
    }
  }

  // --- Internal ---

  _syncState() {
    debug(() => ["_syncState called, context:", this.focusMachine.context, new Error().stack.split("\n")[2]?.trim()])
    const zone = this.reader.getZone()
    const presentation = this.reader.getPresentation()
    const drawerOpen = this.reader.isDrawerOpen()

    // Detect and attach page behavior from data-page-behavior attribute
    this._detectBehavior()

    // Let page behavior check for state changes (e.g. sort order)
    if (this._behavior?.onSyncState) {
      const result = this._behavior.onSyncState(this.reader)
      if (result?.clearGridMemory) {
        delete this._contextMemory[Context.GRID]
        this._lastGridEntityId = null
      }
    }

    if (zone !== this.focusMachine._zone) {
      this.focusMachine.zoneChanged(zone)
      // Zone content changes — clear grid and toolbar memory (stale items)
      delete this._contextMemory[Context.GRID]
      delete this._contextMemory[Context.TOOLBAR]
      this._lastGridEntityId = null
    }

    // Always sync drawer open state, regardless of current context.
    // The user may have navigated to GRID while drawer was open, then
    // the drawer closed via LiveView — we need to clear _drawerOpen.
    this.focusMachine.syncDrawerState(drawerOpen)

    // When the orchestrator has initiated a presentation transition (e.g. dismiss),
    // skip DOM-based detection until the DOM confirms the expected state.
    if (this._expectedPresentation !== undefined) {
      if (presentation === this._expectedPresentation) {
        this._expectedPresentation = undefined
      }
    } else if (presentation === "modal" && this.focusMachine.context !== Context.MODAL) {
      this.focusMachine.presentationChanged("modal")
      this._globals.requestAnimationFrame(() => this.writer.focusFirst(Context.MODAL))
    } else if (presentation === "drawer" && this.focusMachine.context !== Context.DRAWER) {
      this.focusMachine.presentationChanged("drawer")
      this._globals.requestAnimationFrame(() => this.writer.focusFirst(Context.DRAWER))
    } else if (!presentation && (this.focusMachine.context === Context.MODAL || this.focusMachine.context === Context.DRAWER)) {
      this.focusMachine.presentationChanged(null)
      // Restore focus to the originating card after modal/drawer closes
      this._restoreOriginFocus()
    }

    // Build navigation graph from current DOM state
    this._counts = this._buildCounts()
    const navGraph = buildNavGraph(this.reader.getZone(), this._counts, {
      drawerOpen: this.reader.isDrawerOpen(),
      layouts: this._config.layouts,
      alwaysPopulated: this._config.alwaysPopulated,
    })
    this.focusMachine.setNavGraph(navGraph)

    // After a modal sub-view transition (e.g. info → main), the previously
    // focused element was removed by morphdom. Refocus into the modal now
    // that the DOM has been patched and the nav graph rebuilt.
    if (this._pendingModalRefocus && this.focusMachine.context === Context.MODAL) {
      this._pendingModalRefocus = false
      this.writer.focusFirst(Context.MODAL)
    }
  }

  _buildCounts() {
    const counts = {}
    const contextSelectors = this._config.contextSelectors ?? {}
    for (const context of Object.keys(contextSelectors)) {
      counts[context] = this.reader.getItemCount(context)
    }
    return counts
  }

  /**
   * Detect data-page-behavior on the page and attach/detach as needed.
   */
  _detectBehavior() {
    const behaviorName = this.reader.getPageBehavior?.() ?? null
    if (behaviorName === this._behaviorName) return

    this._detachBehavior()
    this._behaviorName = behaviorName

    if (behaviorName && this._config.createBehavior) {
      this._behavior = this._config.createBehavior(behaviorName)
      this._behavior?.onAttach?.()
    }
  }

  _detachBehavior() {
    if (this._behavior) {
      this._behavior.onDetach?.()
      this._behavior = null
      this._behaviorName = null
    }
  }

  /**
   * After modal/drawer dismissal, restore focus to the card that opened it.
   */
  _restoreOriginFocus() {
    const entityId = this._originEntityId
    this._originEntityId = null
    this._globals.requestAnimationFrame(() => {
      if (entityId && this.writer.focusByEntityId(Context.GRID, entityId)) return
      this._restoreContextFocus(Context.GRID)
    })
  }

  _onMouseMove(event) {
    const x = event.clientX
    const y = event.clientY

    // First mousemove: record baseline position only. We can't compute
    // a delta without a prior reading, so we never switch on the first event.
    // This prevents full-page navigations from triggering a false switch
    // (initial position is unknown → any coordinate looks like movement).
    if (this._lastMouseX === null) {
      this._lastMouseX = x
      this._lastMouseY = y
      return
    }

    // Layout shifts fire mousemove at the same coordinates.
    // Only switch to mouse when the pointer has actually moved.
    const dx = Math.abs(x - this._lastMouseX)
    const dy = Math.abs(y - this._lastMouseY)
    this._lastMouseX = x
    this._lastMouseY = y

    if (dx < MOUSE_MOVE_THRESHOLD && dy < MOUSE_MOVE_THRESHOLD) return

    debug("mousemove delta:", dx, dy, "method:", this.inputDetector.current)
    const methodChange = this.inputDetector.observe("mousemove")
    if (methodChange) {
      this.writer.setInputMethod(methodChange)
    }
  }

  _handleAction(action) {
    // SELECT on a MENU = confirm selection + exit the menu.
    // Primary menu: activate-on-focus already clicked the item during up/down
    // navigation, so just exit (no redundant click that would trigger remount).
    // Non-primary menus: click after the transition to avoid race conditions.
    let pendingMenuClick = null
    if (action === Action.SELECT) {
      const type = contextType(this.focusMachine.context, this._config.instanceTypes)
      if (type === Context.MENU) {
        const isPrimary = this.focusMachine.context === this._config.primaryMenu
        const focused = this.reader.getCurrentFocusedItem()
        if (isPrimary && focused?.hasAttribute("data-nav-defer-activate")) {
          // Deferred items weren't activated on focus — explicit SELECT activates them
          this._executeActivate()
          return
        }
        if (!isPrimary) {
          pendingMenuClick = focused
        }
        action = Action.NAVIGATE_RIGHT
      }
    }

    // Save focus position in current context before any transition
    this._saveContextMemory()

    // Remember which context we're in before the state machine transitions,
    // so exiting sidebar can restore to zone tabs / toolbar / grid.
    const contextBefore = this.focusMachine.context

    const directive = this.focusMachine.transition(action)

    // If we just entered the sidebar, record where we came from
    if (directive.type === "enter_sidebar" && contextBefore !== this._config.primaryMenu) {
      this._preSidebarContext = contextBefore
    }

    this._executeDirective(directive)

    // Click non-primary menu item after transition completes
    if (pendingMenuClick) pendingMenuClick.click()
  }

  /**
   * Save the current focus position for the active context.
   * Grid uses entity ID (stable across stream updates); others use index.
   */
  _saveContextMemory() {
    const context = this.focusMachine.context
    if (context === Context.GRID) {
      const focused = this.reader.getCurrentFocusedItem()
      if (focused?.dataset?.entityId) {
        this._lastGridEntityId = focused.dataset.entityId
      }
    } else {
      const index = this.reader.getFocusedIndex(context)
      if (index >= 0) {
        this._contextMemory[context] = index
      }
    }
  }

  /**
   * Restore focus to the appropriate item in a context.
   * Grid: restore by entity ID memory.
   * All others: active item (DOM marker) → index memory → first item.
   */
  _restoreContextFocus(context) {
    if (context === Context.GRID) {
      if (this._lastGridEntityId) {
        if (this.writer.focusByEntityId(Context.GRID, this._lastGridEntityId)) return
      }
      this.writer.focusFirst(Context.GRID)
    } else {
      // Try DOM-marked active item first (tab-active, menu-item-active, etc.)
      const activeIndex = this.reader.getActiveItemIndex(context)
      if (activeIndex >= 0) {
        this.writer.focusByIndex(context, activeIndex)
        return
      }
      // Fall back to saved memory position
      const savedIndex = this._contextMemory[context]
      if (savedIndex != null && savedIndex < this.reader.getItemCount(context)) {
        this.writer.focusByIndex(context, savedIndex)
      } else {
        this.writer.focusFirst(context)
      }
    }
  }

  _executeDirective(directive) {
    switch (directive.type) {
      case "navigate":
        this._executeNavigate(directive.direction)
        break

      case "focus_context":
        this._executeFocusContext(directive.target)
        break

      case "focus_first":
        this._restoreContextFocus(directive.context)
        break

      case "activate":
        this._executeActivate()
        break

      case "dismiss":
        this._executeDismiss()
        break

      case "play":
        this._executePlay()
        break

      case "zone_cycle":
        this._executeZoneCycle(directive.direction)
        break

      case "grid_row_edge":
        this._executeGridRowEdge(directive.side)
        break

      case "enter_sidebar":
        this._executeEnterSidebar()
        break

      case "exit_sidebar":
        this._executeExitSidebar()
        break

      case "none":
        break
    }
  }

  _executeNavigate(direction) {
    const context = this.focusMachine.context

    // For grid contexts, try fast-path grid arithmetic first
    if (context === Context.GRID) {
      const result = this._gridNavigate(direction)
      if (result === "wall") {
        const wallDirective = this.focusMachine.gridWall(direction)
        this._executeDirective(wallDirective)
      }
      return
    }

    // For all other contexts, use linear index arithmetic
    this._linearNavigate(context, direction)
  }

  /**
   * Navigate within a grid. Returns "wall" if at edge, "moved" if successful.
   */
  _gridNavigate(direction) {
    const currentIndex = this.reader.getFocusedIndex(Context.GRID)
    const totalCount = this.reader.getItemCount(Context.GRID)
    const columnCount = this.reader.getGridColumnCount(Context.GRID)
    debug("_gridNavigate:", direction, "idx:", currentIndex, "cols:", columnCount, "total:", totalCount)

    if (currentIndex < 0) {
      // Nothing focused in grid — focus first
      this.writer.focusFirst(Context.GRID)
      return "moved"
    }

    const nextIndex = gridNavigate(currentIndex, columnCount, totalCount, direction)
    if (nextIndex === null) return "wall"

    this.writer.focusByIndex(Context.GRID, nextIndex)
    return "moved"
  }

  /**
   * Navigate within a linear list (toolbar, zone tabs, sidebar, modal, drawer).
   */
  _linearNavigate(context, direction) {
    const currentIndex = this.reader.getFocusedIndex(context)
    const totalCount = this.reader.getItemCount(context)

    if (currentIndex < 0) {
      this.writer.focusFirst(context)
      return
    }

    // Map direction to index change
    let nextIndex
    if (direction === "left" || direction === "up") {
      nextIndex = currentIndex - 1
    } else if (direction === "right" || direction === "down") {
      nextIndex = currentIndex + 1
    } else {
      return
    }

    // Wrap in modal (bottom wraps to top)
    if (context === Context.MODAL) {
      if (nextIndex < 0) nextIndex = totalCount - 1
      else if (nextIndex >= totalCount) nextIndex = 0
    } else if (nextIndex < 0 || nextIndex >= totalCount) {
      // Left wall on horizontal rows → enter primary menu
      if (nextIndex < 0 && direction === "left" &&
          (context === Context.ZONE_TABS || context === Context.TOOLBAR)) {
        this._saveContextMemory()
        this._preSidebarContext = context
        this.focusMachine.enterSidebarFromWall()
        this._executeEnterSidebar()
      }
      return
    }

    this.writer.focusByIndex(context, nextIndex)

    // Activate on focus: click item when navigating up/down
    const isPrimaryMenu = this._config.primaryMenu && context === this._config.primaryMenu
    const behaviorActivate = this._behavior?.activateOnFocus
    const isBehaviorActivate = behaviorActivate && behaviorActivate.includes(context)
    if (isPrimaryMenu || isBehaviorActivate) {
      this._globals.requestAnimationFrame(() => {
        const focused = this.reader.getCurrentFocusedItem()
        if (focused && !focused.hasAttribute("data-nav-defer-activate")) focused.click()
      })
    }
  }

  _executeFocusContext(target) {
    this._restoreContextFocus(target)
  }

  /**
   * Focus the edge item (leftmost or rightmost) in the same grid row
   * as the last focused grid item. Used when crossing from drawer to grid.
   */
  _executeGridRowEdge(side) {
    const columnCount = this.reader.getGridColumnCount(Context.GRID)
    const totalCount = this.reader.getItemCount(Context.GRID)

    // Find the row of the last focused grid item
    let anchorIndex = -1
    if (this._lastGridEntityId) {
      anchorIndex = this.reader.getEntityIndex(Context.GRID, this._lastGridEntityId)
    }

    if (anchorIndex < 0) {
      this.writer.focusFirst(Context.GRID)
      return
    }

    const row = Math.floor(anchorIndex / columnCount)

    if (side === "right") {
      // Rightmost item in this row: min of (row end, last item)
      const rowEnd = (row + 1) * columnCount - 1
      const targetIndex = Math.min(rowEnd, totalCount - 1)
      this.writer.focusByIndex(Context.GRID, targetIndex)
    } else {
      // Leftmost item in this row
      this.writer.focusByIndex(Context.GRID, row * columnCount)
    }
  }

  _executeActivate() {
    const focused = this.reader.getCurrentFocusedItem()
    if (!focused) return

    // Custom action: dispatch a named event instead of clicking
    const action = focused.dataset.navAction
    if (action) {
      focused.dispatchEvent(new Event(action, { bubbles: true }))
      return
    }

    // Remember which card opened the modal/drawer for focus restoration
    if (this.focusMachine.context === Context.GRID && focused.dataset.entityId) {
      this._originEntityId = focused.dataset.entityId
    }

    focused.click()
  }

  _executeDismiss() {
    if (!this._hookEl) return

    // If the modal has a sub-view (e.g. info), BACK returns to the main view
    // without dismissing. Push the event and let LiveView handle it — keep
    // focus context in the modal so the user stays in the overlay.
    const detailView = this.reader.getDetailView?.()
    if (detailView && detailView !== "main") {
      this._hookEl.pushEvent("close_detail", {})
      // The LiveView patch (info → main) will remove the focused element.
      // Flag _syncState to refocus the modal after the DOM updates.
      this._pendingModalRefocus = true
      return
    }

    this._hookEl.pushEvent("close_detail", {})
    // Proactively restore — don't wait for onViewChanged() which may not
    // fire if the hook element isn't directly patched by morphdom.
    this.focusMachine.presentationChanged(null)
    this._restoreOriginFocus()
    // Declare expected presentation state — _syncState() will skip DOM-based
    // detection until the DOM confirms no overlay is present.
    this._expectedPresentation = null
  }

  _executePlay() {
    const focused = this.reader.getCurrentFocusedItem()
    const entityId = focused?.dataset?.entityId
    if (entityId && this._hookEl) {
      this._hookEl.pushEvent("play", { id: entityId })
      this.writer.flashElement(focused, "nav-play-flash")
    }
  }

  _executeZoneCycle(direction) {
    const tabCount = this.reader.getZoneTabCount()
    if (tabCount < 2) return

    const activeIndex = this.reader.getActiveZoneTabIndex()

    let nextIndex
    if (direction === "next") {
      nextIndex = (activeIndex + 1) % tabCount
    } else {
      nextIndex = (activeIndex - 1 + tabCount) % tabCount
    }

    this.writer.clickZoneTab(nextIndex)
  }

  _executeEnterSidebar() {
    const primaryMenu = this._config.primaryMenu
    this.writer.setSidebarState(false)
    const activeIndex = this.reader.getActiveItemIndex(primaryMenu)
    if (activeIndex >= 0) {
      this.writer.focusByIndex(primaryMenu, activeIndex)
    } else {
      this.writer.focusFirst(primaryMenu)
    }
  }

  _executeExitSidebar() {
    const preferred = this._preSidebarContext
    this._preSidebarContext = null

    const primaryMenu = this._config.primaryMenu

    // Use pre-sidebar context if still populated, otherwise consult graph
    const graphTarget = this.focusMachine._navGraph?.[primaryMenu]?.right
    const restoreTo =
      (preferred && this.reader.getItemCount(preferred) > 0) ? preferred :
      graphTarget ?? null

    if (!restoreTo) {
      // No content on this page — stay in sidebar
      this.focusMachine.forceContext(primaryMenu)
      return
    }

    const wasCollapsed = this.reader.getSidebarCollapsed()
    this.writer.setSidebarState(wasCollapsed)

    this.focusMachine.forceContext(restoreTo)
    this._restoreContextFocus(restoreTo)
  }
}
