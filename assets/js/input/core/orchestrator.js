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
import { findNearest, gridNavigate } from "./spatial"
import { FocusContextMachine, Context, contextType } from "./focus_context"
import { InputMethod, InputMethodDetector } from "./input_method"
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
      onContextChanged: (context) => {
        this.writer?.setNavContext?.(context)
        this._behavior?.onZoneChanged?.(context)
      },
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
    // Track the entity ID and context of the card that opened a modal/drawer,
    // so we can restore focus on dismiss. The context matters because cards
    // live in different content contexts on different pages (the grid on
    // library/watching, a shelf on home) — restoring always to GRID would
    // lose focus on pages that have no grid.
    this._originEntityId = null
    this._originContext = null
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
    // Sub-focus: the index of the parent nav-item when focus is on a child
    // sub-item. Stored as an index (not a DOM ref) so morphdom patches don't
    // create stale references — every DOM access re-queries from the index.
    this._subFocusIndex = null
    // One-slot memory of the item the cursor last moved OFF, per move within
    // a context. A data-nav-return-focus activation stashes it as the pending
    // return target; _reconcileFocus applies it after the patch lands.
    this._departedItem = null
    this._pendingReturnFocus = null
    // Which of the focused item's controls the cursor is on, when in sub-focus.
    this._subItemIndex = null
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
    // True while start() seeds focus — mount-time focus writes are
    // scroll-neutral because the navigation's scroll hasn't settled yet.
    this._mounting = false
    this._onMouseMove = this._onMouseMove.bind(this)
    this._onWheel = this._onWheel.bind(this)
    this._onClick = this._onClick.bind(this)
    this._onVisibilityChange = this._onVisibilityChange.bind(this)
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
    this._globals.document.addEventListener("wheel", this._onWheel, { passive: true })
    this._globals.document.addEventListener("click", this._onClick)
    this._globals.document.addEventListener("visibilitychange", this._onVisibilityChange)

    // Mount-time focus seeding is scroll-neutral. The window still carries
    // the previous page's scroll offset here: LiveView writes the
    // navigation's own scroll (reset to top on redirect, restore on
    // back/forward, the browser's on a fresh load) one frame after this hook
    // mounts. A reveal issued now would be measured against that doomed
    // offset, and its glide would keep chasing the stale absolute target
    // *after* LiveView's write — parking the new page wherever the old one
    // was scrolled. So every focus write below passes { reveal: false } via
    // _restoreOpts(); scroll authority returns to the cursor with the first
    // user action, which reveals as always.
    this._mounting = true

    // Sync initial state (also detects and attaches page behavior)
    this._syncState()

    // Project initial nav context to DOM (the callback only fires on changes,
    // so the constructor's initial value needs an explicit write)
    this.writer.setNavContext?.(this.focusMachine.context)

    // Let the page behavior restore its state on attach. The method is
    // optional — guard it (not just the behavior) so behaviors without an
    // onAttach hook (home, watch-history) don't abort start() with a
    // TypeError before _ensureCursorStart runs. Mirrors _detectBehavior.
    this._behavior?.onAttach?.()

    // Resume sidebar context after navigation (sessionStorage bridge)
    const primaryMenu = this._config.primaryMenu
    if (primaryMenu && this._globals.sessionStorage.getItem("inputSystem:resumeSidebar") === "true") {
      this._globals.sessionStorage.removeItem("inputSystem:resumeSidebar")
      this.focusMachine.forceContext(primaryMenu)
      const activeIndex = this.reader.getActiveItemIndex(primaryMenu)
      if (activeIndex >= 0) {
        this.writer.focusByIndex(primaryMenu, activeIndex, this._restoreOpts())
      } else {
        this.writer.focusFirst(primaryMenu, this._restoreOpts())
      }
    }

    // If the initial context (GRID) is empty, fall back to a non-empty context
    this._ensureCursorStart()

    this._mounting = false
  }

  /**
   * If the current context has no focusable items, resolve the first
   * viable context from the cursor start priority list.
   */
  _ensureCursorStart() {
    // Don't override context while the orchestrator owns a presentation transition.
    // The DOM may transiently show zero items during morphdom patching.
    if (this._expectedPresentation !== undefined) return

    // Yield to foreign focus for the same reason as _reconcileFocus: seeding
    // cursor-start focus here would steal the cursor from an unmanaged overlay
    // the user is interacting with over an empty page context.
    if (this.reader.hasForeignFocus?.()) return

    const context = this.focusMachine.context
    const count = this.reader.getItemCount(context)
    if (count > 0) return

    const target = resolveCursorStart(this.reader.getZone(), this._counts, {
      cursorStartPriority: this._config.cursorStartPriority,
      alwaysPopulated: this._config.alwaysPopulated,
    })
    if (target) {
      this.focusMachine.forceContext(target)
      this._restoreContextFocus(target, this._restoreOpts())
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

    // Stop all in-flight scroll glides. The scroll containers outlive this
    // orchestrator — documentElement is the same element on the next page
    // after a live navigation — so a surviving glide would keep writing their
    // offsets forever (its target can lie beyond the next page's scroll
    // range, so it never arrives) and fight the next page's own scrolling.
    this.writer.cancelScrollMotion?.()

    // Stop all input sources
    for (const source of this._sources) {
      source.stop()
    }
    this._sources = []

    this._globals.document.removeEventListener("mousemove", this._onMouseMove)
    this._globals.document.removeEventListener("wheel", this._onWheel)
    this._globals.document.removeEventListener("click", this._onClick)
    this._globals.document.removeEventListener("visibilitychange", this._onVisibilityChange)
    this._detachBehavior()
    this._hookEl = null
  }

  /**
   * Called by the LiveView hook's beforeUpdate(), before morphdom patches the
   * DOM. A patch (notably `stream(:grid, …, reset: true)`) can re-render the
   * focused element and drop focus to <body>, so we snapshot the focused
   * position here — while it still exists — so `_reconcileFocus()` can re-grab
   * it after the patch. This covers the idle case (no navigation since landing
   * on the item, so the move-time memory would otherwise lag by one).
   * `_saveContextMemory` records the right identity per context (entity ID for
   * the grid, index for the rest).
   */
  onBeforeViewChange() {
    this._saveContextMemory()
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
   * Handles behavior onClear for CLEAR, then delegates to _handleAction.
   */
  _onSourceAction(action) {
    debug("action:", action, "context:", this.focusMachine.context, "method:", this.inputDetector.current)
    // CLEAR action: delegate to page behavior's onClear hook. Behaviors use
    // this for resetting page-specific state (e.g. clearing a filter). A
    // behavior MAY return a string naming a target context — when the clear
    // naturally ends one task (the filter) the user's next move is usually in
    // another zone (the now-unfiltered grid), so we follow focus there.
    if (action === Action.CLEAR && this._behavior?.onClear) {
      const result = this._behavior.onClear()
      if (typeof result === "string") {
        this._saveContextMemory()
        this.focusMachine.forceContext(result)
        this._restoreContextFocus(result, this._restoreOpts())
      }
      return
    }

    // BACK peels containment layers: overlays (modal/drawer) dismiss, the
    // primary menu exits back to content, and content enters the primary
    // menu — the main nav is what contains every content region. See
    // `_backTransition`.
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
    // Counts are needed before the presentation block: which region of an
    // overlay takes the cursor is resolved against them, the same way a page's
    // cursor start is.
    this._counts = this._buildCounts()
    const overlay = this._config.overlays?.[this.reader.getOverlayName?.()] ?? null

    if (this._expectedPresentation !== undefined) {
      if (presentation === this._expectedPresentation) {
        this._expectedPresentation = undefined
      }
    } else if (presentation === "modal" && !this.focusMachine.inOverlay) {
      const entry = this._overlayEntry(overlay)
      // An overlay is entered fresh every time. Its regions' position memory is
      // scoped to one opening, so reopening a title re-seeds the episode list
      // from the resume target rather than restoring wherever the last title
      // was browsed to.
      for (const region of Object.keys(overlay?.layout ?? {})) {
        delete this._contextMemory[region]
      }
      this.focusMachine.presentationChanged("modal", entry)
      this._globals.requestAnimationFrame(() => this.writer.focusFirst(entry))
    } else if (presentation === "modal" && overlay && !this._inOverlayRegion(overlay)) {
      // An overlay whose regions populate after it opened: the plan modal opens
      // on a loading stage with no controls and grows its regions when the
      // stage lands. Entry was resolved against empty counts at open and fell
      // back to the flat MODAL context (or the cursor start leaked to a page
      // context beneath); re-resolve until a region exists to step into.
      const entry = this._overlayEntry(overlay)
      if (entry !== Context.MODAL) {
        this.focusMachine.forceContext(entry)
        this.writer.focusFirst(entry, this._restoreOpts())
      }
    } else if (presentation === "drawer" && this.focusMachine.context !== Context.DRAWER) {
      this.focusMachine.presentationChanged("drawer")
      this._globals.requestAnimationFrame(() => this.writer.focusFirst(Context.DRAWER))
    } else if (!presentation && this.focusMachine.inOverlay) {
      this.focusMachine.presentationChanged(null)
      // Restore focus to the originating card after modal/drawer closes
      this._restoreOriginFocus()
    }

    // Build navigation graph from current DOM state. An open overlay merges its
    // own fixed topology over the page's — the regions inside a modal relate to
    // each other the same way whatever page it was opened from.
    const navGraph = buildNavGraph(this.reader.getZone(), this._counts, {
      drawerOpen: this.reader.isDrawerOpen(),
      layouts: this._config.layouts,
      alwaysPopulated: this._config.alwaysPopulated,
      overlayLayout: presentation === "modal" ? overlay?.layout : null,
    })
    this.focusMachine.setNavGraph(navGraph)

    // The DOM has been patched and the nav graph rebuilt — re-assert the
    // focus the orchestrator owns onto the fresh DOM.
    this._reconcileFocus()
  }

  /**
   * Single post-patch focus reconciler. A LiveView patch can move, replace, or
   * destroy the element the user was on; this re-asserts the owned focus onto
   * the fresh DOM. It is the one place that answers "where should focus be now"
   * after every `updated()`, so a new content surface that loses focus on a
   * patch is covered without adding another bespoke guard.
   *
   * Identity by context:
   * - sub-focus: the `[data-nav-sub-item]` within the saved parent index
   * - modal: first item after a sub-view transition (overlay-scoped semantics)
   * - everything else (grid, shelf, menu, toolbar, zone tabs): the context's
   *   own memory via `_restoreContextFocus` — entity ID for the grid, active
   *   marker / saved index for the rest
   *
   * Drawer focus on open and origin-card restore on overlay close are
   * transition-driven and handled in the presentation block above; empty
   * contexts are left to `_ensureCursorStart`.
   */
  _reconcileFocus() {
    // Only reconcile focus the system owns. When focus lives on an element
    // outside every managed nav region (an unmanaged overlay's input, button,
    // or card), the system does not own it — re-asserting nav focus here would
    // yank the cursor onto a page row mid-interaction. The reader treats
    // foreign focus the same as focus-fell-to-body (both report no nav item),
    // so without this guard the restore below steals focus on every patch. See
    // ADR-053 and the Track-new-release modal focus-steal regression.
    if (this.reader.hasForeignFocus?.()) return

    // Sub-focus is layered: reconcile the sub-item within its parent, which
    // morphdom may have replaced (e.g. a watched-state class toggle).
    if (this.focusMachine.subFocus && this._subFocusIndex != null) {
      const parent = this.reader.getItemAt?.(this.focusMachine.context, this._subFocusIndex)
      const subItem = this._subItemsOf(parent)[this._subItemIndex ?? 0]
      if (subItem) {
        subItem.focus({ preventScroll: true })
      } else {
        this.focusMachine.clearSubFocus()
        this._subFocusIndex = null
        if (parent) parent.focus({ preventScroll: true })
      }
      return
    }

    // A data-nav-return-focus control was activated: the patch has landed, so
    // put the cursor back on the item it came from. Item indices before the
    // control are stable across the patch (new items pop in after them).
    if (this._pendingReturnFocus) {
      const { context, index } = this._pendingReturnFocus
      this._pendingReturnFocus = null
      if (context === this.focusMachine.context && index < this.reader.getItemCount(context)) {
        this.writer.focusByIndex(context, index, this._restoreOpts())
        return
      }
    }

    // Modal sub-view transition (info → main): the focused element was removed.
    // Refocus the first modal item — overlay focus has its own semantics and is
    // not routed through the generic content/menu restore below.
    if (this._pendingModalRefocus && this.focusMachine.inOverlay) {
      this._pendingModalRefocus = false
      const entry = this._overlayEntry(this._config.overlays?.[this.reader.getOverlayName?.()])
      this.focusMachine.forceContext(entry)
      this.writer.focusFirst(entry, this._restoreOpts())
      return
    }

    // Content/menu contexts: a patch — notably `stream(:grid, …, reset: true)`,
    // which LibraryLive fires on any library mutation — can destroy the focused
    // element and drop focus to <body>. Re-grab it by the context's identity so
    // the cursor stays put instead of falling back to the first item (and then
    // out to the sidebar) on the next keypress. Overlays are handled above and
    // in the presentation block; empty contexts are left to _ensureCursorStart.
    const context = this.focusMachine.context
    if (context === Context.MODAL || context === Context.DRAWER) return
    if (this.reader.getItemCount(context) > 0 && !this.reader.getCurrentFocusedItem()) {
      this._restoreContextFocus(context, this._restoreOpts())
    }
  }

  /**
   * The region of an overlay that takes the cursor when it opens — the first
   * populated entry in its priority list, exactly as a page resolves its cursor
   * start. An overlay that declares no regions is a flat list and gets MODAL.
   */
  /** Whether the cursor is in one of the open overlay's declared regions. */
  _inOverlayRegion(overlay) {
    return Object.prototype.hasOwnProperty.call(overlay?.layout ?? {}, this.focusMachine.context)
  }

  _overlayEntry(overlay) {
    const entry = overlay?.entry ?? []
    return entry.find(region => (this._counts[region] ?? 0) > 0) ?? Context.MODAL
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
   * Returns to the originating context (grid, or a home shelf) — not just
   * GRID — so pages without a grid don't lose focus. Falls back to GRID when
   * the overlay had no recorded origin (e.g. opened via a deep link).
   */
  _restoreOriginFocus() {
    const entityId = this._originEntityId
    const context = this._originContext ?? Context.GRID
    this._originEntityId = null
    this._originContext = null
    this._globals.requestAnimationFrame(() => {
      // An overlay may have opened again in the meantime — closing one detail
      // modal and opening another lands both transitions before this frame
      // runs. Restoring the origin card would then yank the cursor out of the
      // overlay the user is now in.
      if (this.focusMachine.inOverlay) return
      this.focusMachine.forceContext(context)
      // Reveal is method-gated: a key-driven dismissal glides back to the
      // origin card, while a mouse dismissal (backdrop click) re-asserts
      // focus without moving the viewport the pointer owns.
      if (entityId && this.writer.focusByEntityId(context, entityId, this._restoreOpts())) return
      this._restoreContextFocus(context, this._restoreOpts())
    })
  }

  /**
   * A mouse click that lands on an entity card records the overlay-restore
   * origin, exactly as SELECT does in _executeActivate. Without this, a
   * modal opened by pointer has no origin: Escape's dismissal would fall
   * back to cursor-start seeding instead of re-asserting the card the user
   * came from. Clicks inside an open overlay never overwrite the origin that
   * opened it (a rail or cast card is not where the user came from).
   */
  _onClick(event) {
    if (this.focusMachine.inOverlay) return
    const origin = this.reader.originOf?.(event.target)
    if (origin) this._recordOrigin(origin.entityId, origin.context)
  }

  /**
   * Remember which card opened the modal/drawer for focus restoration.
   * Content-card contexts (the grid, or a home shelf) carry a stable entity
   * ID; menu/overlay contexts don't, and must not seed a bogus origin.
   */
  _recordOrigin(entityId, context) {
    const type = contextType(context, this._config.instanceTypes)
    if (!entityId || (type !== Context.GRID && type !== Context.SHELF)) return
    this._originEntityId = entityId
    this._originContext = context
  }

  _onVisibilityChange() {
    if (this._globals.document.hidden) {
      for (const source of this._sources) {
        source.pause?.()
      }
    } else {
      for (const source of this._sources) {
        source.resume?.()
      }
    }
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

  /**
   * A wheel scroll is the pointer claiming scroll authority. Stop every glide
   * where it stands — otherwise an in-flight reveal (e.g. the mount-time glide
   * back to the parked cursor after the browser restores a previous scroll
   * position) overrides the user's scrolling every frame until it arrives —
   * and switch to mouse mode, which also suppresses reveal on patch-driven
   * focus restores (see `_reconcileFocus`).
   */
  _onWheel() {
    debug("wheel, method:", this.inputDetector.current)
    this.writer.cancelScrollMotion?.()
    const methodChange = this.inputDetector.observe("wheel")
    if (methodChange) {
      this.writer.setInputMethod(methodChange)
    }
  }

  _handleAction(action) {
    // Let page behavior intercept actions before framework processing.
    // Returns: false/undefined = passthrough, true = consumed,
    // { transitionTo: string } = save memory + transition to context.
    if (this._behavior?.onAction) {
      const focused = this.reader.getCurrentFocusedItem()
      const result = this._behavior.onAction(action, this.focusMachine.context, focused)
      if (result === true) return
      if (result?.transitionTo) {
        this._saveContextMemory()
        this.focusMachine.forceContext(result.transitionTo)
        this._restoreContextFocus(result.transitionTo)
        return
      }
    }

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
   * Cross INTO a context, having travelled `direction` to get there.
   *
   * Distinct from `_restoreContextFocus`, which re-asserts focus the system
   * already holds after a DOM patch. Entering is a user-driven move and obeys
   * two rules the restore path must not:
   *
   * - **A declared anchor wins.** Some zones exist to be entered at one
   *   specific item — the hero's whole job is "press play". That is a product
   *   rule, not a nav accident, so it is declared in config rather than
   *   emerging from geometry (which would pick More info when you arrive from
   *   a right-ward card, and plain memory would pick whichever CTA you touched
   *   last). It deliberately does NOT apply on reconcile: yanking More info
   *   back to Play on every LiveView patch would make the second CTA unusable.
   * - **Memory is constrained to the edge you crossed.** You should land on
   *   something adjacent to where you came from, so a remembered tile that
   *   doesn't touch that edge is not a candidate. This is the whole of "coming
   *   down into Coming Up never lands on the bottom tile" — that tile doesn't
   *   touch the mosaic's top edge. In a single-row shelf every tile touches
   *   the top and bottom edges, so memory always survives and the rule is
   *   invisible, which is exactly right.
   *
   * Scoped to SHELF contexts for now. The rule is not shelf-specific — a
   * vertical MENU entered from above should land on its first item by the same
   * logic — but the remaining pages get it as they are reviewed, one at a
   * time. See `campaigns/input-system-1.0-pass.md`.
   */
  _enterContext(context, direction) {
    this._subFocusIndex = null
    this._subItemIndex = null

    // Travelling into a zone (a spatial crossing) lets it declare a resting
    // scroll — the detail action row glides its modal back to the top. BACK
    // ("back") and post-patch restores (null) are not travel: the user is
    // escaping or the DOM is settling, and the viewport stays put. Whether a
    // zone declares anything is the writer's business.
    if (direction && direction !== "back") this.writer.scrollZoneToTop(context)

    // Cursor-driven crossings have flipped the method before the action ran,
    // so _restoreOpts() reveals for them as before. The exception is BACK's
    // containment peeling (region back edges, sidebar exit), which runs in
    // whatever method is current — in mouse mode these writes must not move
    // the viewport the pointer owns.
    const opts = this._restoreOpts()

    const anchor = this._config.entryAnchors?.[context]
    if (anchor != null && this.reader.getItemCount(context) > anchor) {
      this.writer.focusByIndex(context, anchor, opts)
      return
    }

    const band = this._entryBand(context, direction)
    if (!band) {
      this._restoreContextFocus(context, opts)
      return
    }

    const savedIndex = this._contextMemory[context]
    if (savedIndex != null && band.includes(savedIndex)) {
      this.writer.focusByIndex(context, savedIndex, opts)
      return
    }
    this.writer.focusByIndex(context, band[0], opts)
  }

  /**
   * The indices of the items lying along the edge crossed to enter `context`
   * travelling `direction` — the only items you may land on.
   *
   * Returns null when the constraint doesn't apply (no direction, not a shelf,
   * no geometry), leaving the caller to fall back to plain restore.
   */
  _entryBand(context, direction) {
    if (!direction) return null
    if (contextType(context, this._config.instanceTypes) !== Context.SHELF) return null

    const rects = this.reader.getItemRects?.(context) ?? []
    if (rects.length === 0) return null

    // Travelling down means entering through the top edge, and so on.
    const edgeOf = {
      down: r => r.y,
      up: r => -(r.y + r.height),
      right: r => r.x,
      left: r => -(r.x + r.width),
    }[direction]
    if (!edgeOf) return null

    // Sub-pixel layout rounding puts nominally flush tiles a hair apart.
    const EDGE_TOLERANCE = 4
    const nearest = Math.min(...rects.map(edgeOf))
    const band = []
    for (let i = 0; i < rects.length; i++) {
      if (edgeOf(rects[i]) <= nearest + EDGE_TOLERANCE) band.push(i)
    }
    return band.length > 0 ? band : null
  }

  /**
   * Restore focus to the appropriate item in a context.
   * Grid: restore by entity ID memory.
   * All others: active item (DOM marker) → index memory → declared default → first item.
   *
   * `opts` is threaded to the writer's focus calls, in practice always
   * `_restoreOpts()`: cursor-driving actions flip the method before they run,
   * so their restores reveal, while patch-driven reconciles and command
   * actions (BACK, CLEAR) executed in mouse mode never move the viewport the
   * pointer owns.
   */
  _restoreContextFocus(context, opts = { reveal: true }) {
    if (context === Context.GRID) {
      if (this._lastGridEntityId) {
        if (this.writer.focusByEntityId(Context.GRID, this._lastGridEntityId, opts)) return
      }
      this.writer.focusFirst(Context.GRID, opts)
    } else {
      // Try DOM-marked active item first (tab-active, menu-item-active, etc.)
      const activeIndex = this.reader.getActiveItemIndex(context)
      if (activeIndex >= 0) {
        this.writer.focusByIndex(context, activeIndex, opts)
        return
      }
      // Fall back to saved memory position
      const savedIndex = this._contextMemory[context]
      if (savedIndex != null && savedIndex < this.reader.getItemCount(context)) {
        this.writer.focusByIndex(context, savedIndex, opts)
        return
      }
      // Nothing remembered — some contexts open somewhere other than the top.
      // The detail body opens on the episode Play would play, so arriving there
      // for the first time and pressing Play do the same thing.
      const seed = this._config.entryDefaults?.[context]
      if (seed && this.reader.getMatchingIndex?.(context, seed) >= 0) {
        this.writer.focusByIndex(context, this.reader.getMatchingIndex(context, seed), opts)
        return
      }
      this.writer.focusFirst(context, opts)
    }
  }

  /**
   * Writer focus opts for restores the user didn't ask for (post-patch
   * reconciles, cursor-start seeding). While the pointer owns the scroll,
   * re-assert focus without revealing it — moving the viewport would fight
   * the mouse. Cursor-driven methods keep the reveal: their focus must stay
   * visible across patches. During start() the scroll state itself is
   * unsettled (see the _mounting comment there), so no method reveals.
   */
  _restoreOpts() {
    return { reveal: !this._mounting && this.inputDetector.current !== InputMethod.MOUSE }
  }

  _executeDirective(directive) {
    switch (directive.type) {
      case "navigate":
        this._executeNavigate(directive.direction)
        break

      case "focus_context":
        this._executeFocusContext(directive.target)
        break

      case "enter_context":
        this._enterContext(directive.context, directive.direction)
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

      case "enter_sub_focus":
        this._executeEnterSubFocus()
        break

      case "exit_sub_focus":
        this._executeExitSubFocus()
        break

      case "tree_in":
        this._executeTreeIn()
        break

      case "tree_out":
        this._executeTreeOut()
        break

      case "none":
        break
    }
  }

  _executeNavigate(direction) {
    // If in sub-focus, restore parent focus before navigating
    // so _linearNavigate starts from the correct index.
    if (this._subFocusIndex != null) {
      this.writer.focusByIndex(this.focusMachine.context, this._subFocusIndex)
      this._subFocusIndex = null
    }

    const context = this.focusMachine.context

    // Shelves are laid out, not listed — resolve them against their geometry.
    if (contextType(context, this._config.instanceTypes) === Context.SHELF) {
      this._shelfNavigate(context, direction)
      return
    }

    // For grid contexts, try fast-path grid arithmetic first
    if (context === Context.GRID) {
      const result = this._gridNavigate(direction)
      if (result === "wall") {
        this._executeDirective(this.focusMachine.gridWall(direction))
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

    this._recordDeparture(Context.GRID, currentIndex)
    this.writer.focusByIndex(Context.GRID, nextIndex)
    return "moved"
  }

  /**
   * Navigate within a shelf — a sequence of tiles laid out spatially.
   *
   * Three questions, asked in order, each answering what the one before it
   * couldn't:
   *
   * 1. **The layout.** `findNearest` against the live rects. This is the whole
   *    answer for anything the arrangement makes unambiguous, and it is why
   *    the Coming Up mosaic needs no adjacency table of its own — a table
   *    would be wrong the moment the marquee renders a fourth tile.
   * 2. **The nav graph.** Nothing in this direction means we're at the shelf's
   *    edge, so try crossing into a neighbouring zone (the shelf above, the
   *    sidebar to the left).
   * 3. **The sequence, on the inline axis only.** A shelf is still an ordered
   *    set of tiles, and that order reads left to right — so when the layout
   *    offers nothing and there is nowhere to cross to, "right" means the next
   *    tile, which is what carries you from the marquee's top secondary to the
   *    one below it. UP and DOWN never reach here: their answer is geometry's
   *    or the graph's, and "the next tile" on a vertical press would move the
   *    cursor sideways. In a single row the fallback only fires at the ends,
   *    where the sequence has nothing to offer either, so it is inert
   *    everywhere except a mosaic.
   */
  _shelfNavigate(context, direction) {
    const currentIndex = this.reader.getFocusedIndex(context)
    if (currentIndex < 0) {
      this.writer.focusFirst(context)
      return
    }

    const rects = this.reader.getItemRects(context)
    const from = rects[currentIndex]

    // 1. The layout. Candidates keep their document order so that tiles which
    // tie on score — a stack facing a tall neighbour — resolve to "the next
    // one" rather than an arbitrary pick.
    if (from) {
      const candidates = []
      const indices = []
      for (let i = 0; i < rects.length; i++) {
        if (i === currentIndex) continue
        candidates.push(rects[i])
        indices.push(i)
      }
      const nearest = findNearest(from, direction, candidates)
      if (nearest != null) {
        this._recordDeparture(context, currentIndex)
        this.writer.focusByIndex(context, indices[nearest])
        return
      }
    }

    // 2. The nav graph.
    this._saveContextMemory()
    const wallDirective = this.focusMachine.contextWall(context, direction)
    if (wallDirective.type !== "none") {
      this._executeDirective(wallDirective)
      return
    }

    // 3. The sequence — inline axis only.
    //
    // A shelf is an ordered set of tiles, and that order is a *reading* order:
    // it runs left to right. So it can answer LEFT and RIGHT when the layout
    // and the graph both come up empty, but it must never answer UP or DOWN —
    // "the next tile" in a mosaic is the one beside you, and moving sideways on
    // a vertical press is precisely what adjacency-by-geometry exists to stop.
    //
    // Measured on the home page: DOWN on the Coming Up marquee's large tile
    // landed on the top secondary, which sits to its right. Nothing is below
    // that tile — it spans the mosaic's full height — so the honest answer is
    // that nothing happens, and if a shelf is ever added underneath, step 2
    // will find it.
    if (direction !== "left" && direction !== "right") return

    const nextIndex = currentIndex + (direction === "right" ? 1 : -1)
    if (nextIndex >= 0 && nextIndex < rects.length) {
      this._recordDeparture(context, currentIndex)
      this.writer.focusByIndex(context, nextIndex)
    }
  }

  /** Record the item a within-context move departs from (see constructor). */
  _recordDeparture(context, index) {
    this._departedItem = { context, index }
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
      const type = contextType(context, this._config.instanceTypes)
      // Left wall on a horizontal row (zone tabs or toolbar) → follow the nav
      // graph's left edge, where the layout declares one (the upcoming
      // mini-month's edge to the rail). Keyed by TYPE so non-"toolbar" toolbar
      // instances are included. No content context has a left edge to the
      // sidebar — reaching the main menu is BACK's job. Shelves never reach
      // here: they resolve every direction, walls included, in _shelfNavigate.
      if (nextIndex < 0 && direction === "left" &&
          (type === Context.ZONE_TABS || type === Context.TOOLBAR)) {
        this._saveContextMemory()
        this._executeDirective(this.focusMachine.contextWall(context, "left"))
      }
      // Up/down wall on MENU or TREE → try nav graph neighbor. For a TREE the
      // edge exists only where the layout declares one (the Manage toolbar
      // card above the folder ledger — UIDR-019 amended); with no edge,
      // contextWall returns NONE and the wall stays a wall.
      else if ((direction === "up" || direction === "down") &&
               (contextType(context, this._config.instanceTypes) === Context.MENU ||
                contextType(context, this._config.instanceTypes) === Context.TREE)) {
        this._saveContextMemory()
        this._executeDirective(this.focusMachine.contextWall(context, direction))
      }
      return
    }

    this._recordDeparture(context, currentIndex)
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
    this._restoreContextFocus(target, this._restoreOpts())
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
      ?? this.reader.getCurrentFocusedSubItem?.()
    if (!focused) return

    // Custom action: dispatch a named event instead of clicking
    const action = focused.dataset.navAction
    if (action) {
      focused.dispatchEvent(new Event(action, { bubbles: true }))
      return
    }

    this._recordOrigin(focused.dataset.entityId, this.focusMachine.context)

    // A control that grows its own list (Show more): after its patch lands,
    // return the cursor to the item it came from — grounding the user on a
    // familiar item before the viewport moves and the new items get walked.
    if (focused.hasAttribute?.("data-nav-return-focus") &&
        this._departedItem?.context === this.focusMachine.context) {
      this._pendingReturnFocus = this._departedItem
    }

    focused.click()
  }

  _executeDismiss() {
    if (!this._hookEl) return

    // Below the modal's root view, BACK returns to that root rather than
    // dismissing. Push the event and let LiveView handle it — keep focus
    // context in the modal so the user stays in the overlay.
    if (this.reader.isDetailNested?.()) {
      this._hookEl.pushEvent("close_detail", {})
      // The LiveView patch back to the root view will remove the focused
      // element. Flag _syncState to refocus the modal after the DOM updates.
      this._pendingModalRefocus = true
      return
    }

    const dismissEvent = this.reader.getDismissEvent?.() ?? "close_detail"
    this._hookEl.pushEvent(dismissEvent, {})
    // Proactively restore — don't wait for onViewChanged() which may not
    // fire if the hook element isn't directly patched by morphdom.
    this.focusMachine.presentationChanged(null)
    this._restoreOriginFocus()
    // Declare expected presentation state — _syncState() will skip DOM-based
    // detection until the DOM confirms no overlay is present.
    this._expectedPresentation = null
  }

  _executeEnterSubFocus() {
    const context = this.focusMachine.context
    const parent = this.reader.getCurrentFocusedItem()
    if (!parent) return

    if (!this._enterSubItem(parent)) {
      // No sub-item — fall back to linear navigation (e.g. horizontal button row)
      this.focusMachine.clearSubFocus()
      this._linearNavigate(context, "right")
    }
  }

  /**
   * Move focus into the controls carried by a nav item, remembering the item's
   * index so exiting can come back to it. Returns false when the item has none.
   */
  _enterSubItem(parent) {
    const subItems = this._subItemsOf(parent)
    if (subItems.length === 0) return false
    this._subFocusIndex = this.reader.getFocusedIndex(this.focusMachine.context)
    this._subItemIndex = 0
    subItems[0].focus({ preventScroll: true })
    return true
  }

  /**
   * The controls carried by a nav item, in DOM order. An episode row has two —
   * the synopsis disclosure and the watched toggle — so "the item's controls"
   * is a list, not a single element.
   */
  _subItemsOf(parent) {
    return Array.from(parent?.querySelectorAll?.("[data-nav-sub-item]") ?? [])
  }

  /** Focus the nth control of the item at the saved parent index. */
  _focusSubItemAt(index) {
    const parent = this.reader.getItemAt?.(this.focusMachine.context, this._subFocusIndex)
    const subItems = this._subItemsOf(parent)
    if (!subItems[index]) return false
    this._subItemIndex = index
    subItems[index].focus({ preventScroll: true })
    return true
  }

  /**
   * RIGHT in a TREE: go one level deeper into whatever the cursor is on.
   *
   * A collapsed branch opens — that IS going deeper, and there is nothing
   * further in until it has. Anything else steps into the item's own controls
   * (an episode's synopsis disclosure and watched toggle), and where there are
   * none, RIGHT does nothing: a leaf has no inside. Unlike a flat overlay list,
   * it deliberately does not fall through to "move to the next item" — in a
   * vertical list that would be lateral movement dressed up as depth.
   *
   * `aria-expanded` is the disclosure signal because it is already the correct
   * markup for one; no parallel `data-` attribute states the same fact twice.
   */
  _executeTreeIn() {
    // Already among an item's controls — go along to the next one, and stop at
    // the last rather than wrapping or falling out sideways.
    if (this.focusMachine.subFocus) {
      this._focusSubItemAt(this._subItemIndex + 1)
      return
    }

    const focused = this.reader.getCurrentFocusedItem()
    if (!focused) return

    if (focused.getAttribute?.("aria-expanded") === "false") {
      focused.click()
      return
    }

    if (this._enterSubItem(focused)) this.focusMachine.beginSubFocus()
  }

  /**
   * LEFT in a TREE: come back out one level.
   *
   * On an open branch that means closing it. On anything inside an open branch
   * it means closing the branch you are in — so LEFT from episode 7 collapses
   * its season and lands you on the season header, which is both where the
   * content you were looking at went and where you would want to continue from.
   * Focus moves to the header *before* the click, because collapsing destroys
   * the row the cursor is standing on.
   *
   * Sub-focus is peeled by the state machine before this runs, so the cursor is
   * always on a nav item here.
   */
  _executeTreeOut() {
    // Among an item's controls: back along them, then out to the item itself.
    if (this.focusMachine.subFocus) {
      if (this._subItemIndex > 0 && this._focusSubItemAt(this._subItemIndex - 1)) return
      this.focusMachine.clearSubFocus()
      this._executeExitSubFocus()
      return
    }

    const focused = this.reader.getCurrentFocusedItem()
    if (!focused) return

    if (focused.getAttribute?.("aria-expanded") === "true") {
      focused.click()
      return
    }

    const head = focused.closest?.("[data-nav-group]")?.querySelector?.("[aria-expanded='true']")
    if (!head || head === focused) return
    this.writer.focusElement(head)
    head.click()
  }

  _executeExitSubFocus() {
    if (this._subFocusIndex != null) {
      this.writer.focusByIndex(this.focusMachine.context, this._subFocusIndex, this._restoreOpts())
      this._subFocusIndex = null
    }
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
    // The rail keeps the user's chosen width — a collapsed rail labels the
    // focused icon via the SidebarTooltip hook (focusin), no auto-expand.
    const primaryMenu = this._config.primaryMenu
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
    const graphTarget = this.focusMachine.getGraphTarget(primaryMenu, "right")
    const restoreTo =
      (preferred && this.reader.getItemCount(preferred) > 0) ? preferred :
      graphTarget ?? null

    if (!restoreTo) {
      // No content on this page — stay in sidebar
      this.focusMachine.forceContext(primaryMenu)
      return
    }

    this.focusMachine.forceContext(restoreTo)
    // An entry, so a declared anchor applies — but the crossing is a mode
    // change (leave the nav rail, return to content), not a spatial move, so
    // there is no edge to constrain memory against.
    this._enterContext(restoreTo, null)
  }
}
