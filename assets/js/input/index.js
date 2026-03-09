/**
 * InputSystem orchestrator — wires all modules together.
 *
 * Creates instances, attaches event listeners, routes actions through
 * the state machine, and executes directives via the DOM adapter.
 */

import { keyToAction } from "./actions"
import { gridNavigate } from "./spatial"
import { FocusContextMachine, Context } from "./focus_context"
import { InputMethodDetector } from "./input_method"
import { DomReader, DomWriter } from "./dom_adapter"

const TEXT_INPUT_ELEMENTS = new Set(["INPUT", "TEXTAREA"])
const SELECT_ELEMENT = "SELECT"

// After keyboard input, ignore mousemove for this many ms.
// Prevents scroll-triggered synthetic mouse events from stealing focus rings.
const KEYBOARD_COOLDOWN_MS = 400

export class InputSystem {
  constructor(reader = DomReader, writer = DomWriter) {
    this.focusMachine = new FocusContextMachine()
    this.inputDetector = new InputMethodDetector()
    this.reader = reader
    this.writer = writer
    this._hookEl = null
    this._lastKeyboardTime = 0
    // Track the entity ID of the card that opened a modal/drawer,
    // so we can restore focus on dismiss.
    this._originEntityId = null
    // Per-context focus memory: remembers the last focused index in each
    // context so returning to it restores position instead of jumping to first.
    this._contextMemory = {}
    // Grid uses entity ID for memory (indices shift on stream updates).
    this._lastGridEntityId = null
    // When true, a text input has been activated for typing.
    // Arrow keys pass through; only Escape exits back to nav.
    this._inputEditing = false
    this._onKeyDown = this._onKeyDown.bind(this)
    this._onMouseMove = this._onMouseMove.bind(this)
  }

  /**
   * Start the input system. Called from the LiveView hook's mounted().
   * @param {HTMLElement} hookEl - The hook element for pushing events
   */
  start(hookEl) {
    this._hookEl = hookEl
    document.addEventListener("keydown", this._onKeyDown)
    document.addEventListener("mousemove", this._onMouseMove)

    // Sync initial state
    this._syncState()

    // Resume sidebar context after navigation (sessionStorage bridge)
    if (sessionStorage.getItem("inputSystem:resumeSidebar") === "true") {
      sessionStorage.removeItem("inputSystem:resumeSidebar")
      this.focusMachine._context = Context.SIDEBAR
      const activeIndex = this.reader.getActiveSidebarIndex()
      if (activeIndex >= 0) {
        this.writer.focusByIndex(Context.SIDEBAR, activeIndex)
      } else {
        this.writer.focusFirst(Context.SIDEBAR)
      }
    }
  }

  /**
   * Stop the input system. Called from the LiveView hook's destroyed().
   */
  destroy() {
    // If we're in the sidebar, persist so the new page resumes there
    if (this.focusMachine.context === Context.SIDEBAR) {
      sessionStorage.setItem("inputSystem:resumeSidebar", "true")
    }
    document.removeEventListener("keydown", this._onKeyDown)
    document.removeEventListener("mousemove", this._onMouseMove)
    this._hookEl = null
  }

  /**
   * Called by the LiveView hook when the view updates.
   * Syncs focus machine state with current DOM state.
   */
  onViewChanged() {
    this._syncState()
  }

  // --- Internal ---

  _syncState() {
    const zone = this.reader.getZone()
    const presentation = this.reader.getPresentation()
    const drawerOpen = this.reader.isDrawerOpen()

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
    this.focusMachine._drawerOpen = drawerOpen

    if (presentation === "modal" && this.focusMachine.context !== Context.MODAL) {
      this.focusMachine.presentationChanged("modal")
      requestAnimationFrame(() => this.writer.focusFirst(Context.MODAL))
    } else if (presentation === "drawer" && this.focusMachine.context !== Context.DRAWER) {
      this.focusMachine.presentationChanged("drawer")
      requestAnimationFrame(() => this.writer.focusFirst(Context.DRAWER))
    } else if (!presentation && (this.focusMachine.context === Context.MODAL || this.focusMachine.context === Context.DRAWER)) {
      this.focusMachine.presentationChanged(null)
      // Restore focus to the originating card after modal/drawer closes
      this._restoreOriginFocus()
    }
  }

  /**
   * After modal/drawer dismissal, restore focus to the card that opened it.
   */
  _restoreOriginFocus() {
    if (this._originEntityId) {
      const entityId = this._originEntityId
      this._originEntityId = null
      requestAnimationFrame(() => {
        if (!this.writer.focusByEntityId(Context.GRID, entityId)) {
          this.writer.focusFirst(Context.GRID)
        }
      })
    }
  }

  _onKeyDown(event) {
    // Track input method
    const methodChange = this.inputDetector.observe("keydown")
    if (methodChange) {
      this.writer.setInputMethod(methodChange)
    }
    this._lastKeyboardTime = Date.now()

    const isTextInput = TEXT_INPUT_ELEMENTS.has(event.target?.tagName)

    // SELECT elements: let browser handle up/down for option cycling,
    // but intercept left/right/escape to exit back to toolbar navigation.
    // We must keep focus on the element (not blur) so that linear nav can
    // find its index and move to the correct neighbor.
    if (event.target?.tagName === SELECT_ELEMENT) {
      if (event.key === "ArrowLeft" || event.key === "ArrowRight" || event.key === "Escape") {
        event.preventDefault()
        const action = keyToAction(event.key, { targetIsInput: false })
        if (action) this._handleAction(action)
      }
      return
    }

    // Text inputs have two modes:
    // 1. Focused (not editing): arrow keys navigate, Enter activates edit mode,
    //    printable characters activate edit mode and pass through to the input.
    // 2. Editing: all keys pass through to the input, Escape exits edit mode.
    if (isTextInput) {
      // Escape on a text input: clear value, exit edit mode
      if (event.key === "Escape") {
        if (event.target.value) {
          event.target.value = ""
          event.target.dispatchEvent(new Event("input", { bubbles: true }))
        }
        this._inputEditing = false
        event.preventDefault()
        return
      }

      if (this._inputEditing) {
        // Enter exits edit mode back to navigation
        if (event.key === "Enter") {
          this._inputEditing = false
          event.preventDefault()
        }
        // All other keys pass through to the input
        return
      }

      // Focused but not editing — nav keys still work
      if (event.key === "Enter") {
        this._inputEditing = true
        event.preventDefault()
        return
      }

      // Printable character → activate edit mode and let it type
      if (event.key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey) {
        this._inputEditing = true
        return
      }

      // Arrow keys / Escape / other nav keys — handle as normal navigation
      const action = keyToAction(event.key, { targetIsInput: false })
      if (!action) return
      event.preventDefault()
      this._handleAction(action)
      return
    }

    const action = keyToAction(event.key, { targetIsInput: false })
    if (!action) return

    event.preventDefault()
    this._handleAction(action)
  }

  _onMouseMove() {
    // Ignore mouse events shortly after keyboard input — focus changes
    // can trigger scroll, which fires synthetic mousemove in some browsers
    if (Date.now() - this._lastKeyboardTime < KEYBOARD_COOLDOWN_MS) return

    const methodChange = this.inputDetector.observe("mousemove")
    if (methodChange) {
      this.writer.setInputMethod(methodChange)
    }
  }

  _handleAction(action) {
    // Navigating away from a text input exits edit mode
    this._inputEditing = false

    // Save focus position in current context before any transition
    this._saveContextMemory()

    const directive = this.focusMachine.transition(action)
    this._executeDirective(directive)
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
   * Zone tabs and toolbar: focus the active/selected item (not memory).
   * Grid: restore by entity ID memory.
   * Other contexts: restore by index memory.
   */
  _restoreContextFocus(context) {
    if (context === Context.GRID) {
      // Grid: restore by entity ID
      if (this._lastGridEntityId) {
        if (this.writer.focusByEntityId(Context.GRID, this._lastGridEntityId)) return
      }
      this.writer.focusFirst(Context.GRID)
    } else if (context === Context.ZONE_TABS) {
      // Zone tabs: focus the active tab
      const activeIndex = this.reader.getActiveZoneTabIndex()
      if (activeIndex >= 0) {
        this.writer.focusByIndex(Context.ZONE_TABS, activeIndex)
      } else {
        this.writer.focusFirst(Context.ZONE_TABS)
      }
    } else if (context === Context.TOOLBAR) {
      // Toolbar: focus the active type tab
      const activeIndex = this.reader.getActiveToolbarTabIndex()
      if (activeIndex >= 0) {
        this.writer.focusByIndex(Context.TOOLBAR, activeIndex)
      } else {
        this.writer.focusFirst(Context.TOOLBAR)
      }
    } else {
      // Other contexts: restore by index
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
    } else {
      // Clamp for other contexts
      if (nextIndex < 0 || nextIndex >= totalCount) return
    }

    this.writer.focusByIndex(context, nextIndex)

    // Sidebar: activate on focus
    if (context === Context.SIDEBAR) {
      requestAnimationFrame(() => {
        const focused = this.reader.getCurrentFocusedItem()
        if (focused) focused.click()
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

    // Remember which card opened the modal/drawer for focus restoration
    if (this.focusMachine.context === Context.GRID && focused.dataset.entityId) {
      this._originEntityId = focused.dataset.entityId
    }

    focused.click()
  }

  _executeDismiss() {
    if (!this._hookEl) return
    this._hookEl.pushEvent("close_detail", {})
    // Focus restoration happens in _syncState when the presentation closes
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
    this.writer.setSidebarState(false)
    const activeIndex = this.reader.getActiveSidebarIndex()
    if (activeIndex >= 0) {
      this.writer.focusByIndex(Context.SIDEBAR, activeIndex)
    } else {
      this.writer.focusFirst(Context.SIDEBAR)
    }
  }

  _executeExitSidebar() {
    const gridCount = this.reader.getItemCount(Context.GRID)
    if (gridCount === 0) {
      // No grid content on this page — stay in sidebar
      this.focusMachine._context = Context.SIDEBAR
      return
    }
    const wasCollapsed = this.reader.getSidebarCollapsed()
    this.writer.setSidebarState(wasCollapsed)
    this.writer.focusFirst(Context.GRID)
  }
}

/**
 * Create the LiveView hook for the input system.
 * This is the bridge between LiveView lifecycle and the InputSystem.
 */
export function createInputHook() {
  let inputSystem = null

  return {
    mounted() {
      inputSystem = new InputSystem()
      inputSystem.start(this.el)
    },

    updated() {
      inputSystem?.onViewChanged()
    },

    destroyed() {
      inputSystem?.destroy()
      inputSystem = null
    },
  }
}
