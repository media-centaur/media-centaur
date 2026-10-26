/**
 * App entry point — imports the framework core and app config,
 * creates the LiveView hook for the input system.
 *
 * Reads `data-input-bindings` from the hook element at mount, builds
 * key and button maps, and listens for `input:rebindMaps` events to
 * hot-swap maps without a full remount.
 */

import { Orchestrator, createDomReader, createDomWriter, KeyboardSource, GamepadSource } from "./core/index.js"
import { Action } from "./core/actions.js"
import { inputConfig } from "./config.js"
import { ControlsBridge } from "./controls_bridge.js"
import { gamepadInputAllowed } from "./input_gate.js"

const BROWSER_GLOBALS = {
  get document() { return document },
  get sessionStorage() { return sessionStorage },
  get requestAnimationFrame() { return requestAnimationFrame.bind(window) },
  get cancelAnimationFrame() { return cancelAnimationFrame.bind(window) },
  get getGamepads() { return navigator.getGamepads?.bind(navigator) ?? (() => []) },
  // Read live each call (polled per frame): a connected gamepad may only drive
  // the UI when this surface is focused, visible, and either not an automation
  // context or one that has declared itself the intended driver. The E2E suite
  // sets the flag via addInitScript; nothing in the app ever sets it.
  get acceptsGamepadInput() {
    return () => gamepadInputAllowed({
      hasFocus: document.hasFocus(),
      visibilityState: document.visibilityState,
      automation: navigator.webdriver,
      automationDrivesInput: window.__inputAutomationDrivesGamepad === true,
    })
  },
}

/**
 * Leaving the app, when the page runs inside a shell that can: the TV app
 * registers `MediaCentaurTV` (a WebView JavaScript interface) whose `leave()`
 * finishes its activity. A browser has no such shell, so BACK keeps its
 * in-page meaning there.
 */
export function shellLeave(win) {
  const shell = win.MediaCentaurTV
  return typeof shell?.leave === "function" ? () => shell.leave() : undefined
}

/**
 * Whether the page is served to a remote player (the TV app): the root
 * layout marks `<html data-player="remote">` from the request's player, and
 * the host's page carries no player.
 */
export function remotePlayer(documentElement) {
  return documentElement.dataset.player === "remote"
}

/**
 * The input source factories a page starts, from the device it is served
 * to. A remote player has no gamepad (the TV app is driven by the remote), so
 * its page starts no gamepad source: it then holds no `gamepadconnected`
 * listener, and Chromium's gamepad polling thread, which runs while a page
 * does, never starts beside the glide (`docs/tv-performance.md`).
 */
export function inputSources(remote, { keyboard, gamepad }) {
  return remote ? [keyboard] : [keyboard, gamepad]
}

/** The catalog's binding id → the input system's action; null for an id it does not know. */
export function actionForId(idStr) {
  switch (idStr) {
    case "navigate_up": return Action.NAVIGATE_UP
    case "navigate_down": return Action.NAVIGATE_DOWN
    case "navigate_left": return Action.NAVIGATE_LEFT
    case "navigate_right": return Action.NAVIGATE_RIGHT
    case "select": return Action.SELECT
    case "back": return Action.BACK
    case "clear": return Action.CLEAR
    case "play": return Action.PLAY
    case "zone_next": return Action.ZONE_NEXT
    case "zone_prev": return Action.ZONE_PREV
    case "play_pause": return Action.PLAY_PAUSE
    case "seek_forward": return Action.SEEK_FORWARD
    case "seek_back": return Action.SEEK_BACK
    case "track_menu": return Action.MENU
    default: return null
  }
}

function buildKeyMap(keyboardBindings) {
  const keyMap = {}
  for (const [key, idStr] of Object.entries(keyboardBindings ?? {})) {
    const action = actionForId(idStr)
    if (action) keyMap[key] = action
  }
  return keyMap
}

function buildButtonMap(gamepadBindings) {
  const buttonMap = {}
  for (const [btnStr, idStr] of Object.entries(gamepadBindings ?? {})) {
    const action = actionForId(idStr)
    if (action) buttonMap[Number(btnStr)] = action
  }
  return buttonMap
}

function readBindings(el) {
  try {
    return JSON.parse(el.dataset.inputBindings ?? "{}")
  } catch {
    return {}
  }
}

export function createInputHook() {
  let orchestrator = null
  let keyboardSource = null
  let gamepadSource = null

  const rebind = (maps) => {
    if (keyboardSource) keyboardSource._keyMap = buildKeyMap(maps.keyboard)
    if (gamepadSource) gamepadSource._buttonMap = buildButtonMap(maps.gamepad)
  }

  const handleRebind = (event) => rebind(event.detail)

  return {
    mounted() {
      const bindings = readBindings(this.el)
      const keyMap = buildKeyMap(bindings.keyboard)
      const buttonMap = buildButtonMap(bindings.gamepad)

      const reader = createDomReader(inputConfig)
      const writer = createDomWriter(inputConfig)

      const keyboard = (callbacks, globals) => {
        keyboardSource = new KeyboardSource({
          document: globals.document,
          keyMap,
          onEditingChanged: (editing) => writer.setTextEditing(editing),
          ...callbacks,
        })
        return keyboardSource
      }

      const gamepad = (callbacks, globals) => {
        gamepadSource = new GamepadSource({
          getGamepads: globals.getGamepads,
          requestAnimationFrame: globals.requestAnimationFrame,
          cancelAnimationFrame: globals.cancelAnimationFrame,
          addEventListener: window.addEventListener.bind(window),
          removeEventListener: window.removeEventListener.bind(window),
          acceptsInput: globals.acceptsGamepadInput,
          onControllerChanged: (type) => writer.setControllerType(type),
          buttonMap,
          ...callbacks,
        })
        return gamepadSource
      }

      orchestrator = new Orchestrator({
        reader,
        writer,
        globals: BROWSER_GLOBALS,
        sources: inputSources(remotePlayer(document.documentElement), { keyboard, gamepad }),
        ...inputConfig,
        leaveApp: shellLeave(window),
      })
      orchestrator.start(this)

      // The bridge captures a gamepad button only where a gamepad source
      // exists; a remote player's Controls page offers no Pad slot to ask.
      this.bridge = new ControlsBridge({
        window,
        pushEvent: (ev, payload) => this.pushEvent(ev, payload),
        captureGamepadButton: gamepadSource ? (fn) => gamepadSource.captureNext(fn) : undefined,
      })

      this.handleEvent("controls:listen", ({ kind, id }) => {
        if (kind === "keyboard") this.bridge.listenKeyboard({ id })
        if (kind === "gamepad") this.bridge.listenGamepad({ id })
      })

      this.handleEvent("controls:updated", (maps) => this.bridge.updateMaps(maps))

      window.addEventListener("input:rebindMaps", handleRebind)
    },

    beforeUpdate() {
      orchestrator?.onBeforeViewChange()
    },

    updated() {
      orchestrator?.onViewChanged()
    },

    destroyed() {
      this.bridge?.cancel()
      window.removeEventListener("input:rebindMaps", handleRebind)
      orchestrator?.destroy()
      orchestrator = null
      keyboardSource = null
      gamepadSource = null
    },
  }
}
