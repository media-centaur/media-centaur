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

const BROWSER_GLOBALS = {
  get document() { return document },
  get sessionStorage() { return sessionStorage },
  get requestAnimationFrame() { return requestAnimationFrame.bind(window) },
  get cancelAnimationFrame() { return cancelAnimationFrame.bind(window) },
  get getGamepads() { return navigator.getGamepads?.bind(navigator) ?? (() => []) },
}

function actionForId(idStr) {
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

      orchestrator = new Orchestrator({
        reader,
        writer,
        globals: BROWSER_GLOBALS,
        sources: [
          (callbacks, globals) => {
            keyboardSource = new KeyboardSource({
              document: globals.document,
              keyMap,
              ...callbacks,
            })
            return keyboardSource
          },
          (callbacks, globals) => {
            gamepadSource = new GamepadSource({
              getGamepads: globals.getGamepads,
              requestAnimationFrame: globals.requestAnimationFrame,
              cancelAnimationFrame: globals.cancelAnimationFrame,
              addEventListener: window.addEventListener.bind(window),
              removeEventListener: window.removeEventListener.bind(window),
              onControllerChanged: (type) => writer.setControllerType(type),
              buttonMap,
              ...callbacks,
            })
            return gamepadSource
          },
        ],
        ...inputConfig,
      })
      orchestrator.start(this)

      this.bridge = new ControlsBridge({
        window,
        pushEvent: (ev, payload) => this.pushEvent(ev, payload),
      })

      this.handleEvent("controls:listen", ({ kind, id }) => {
        if (kind === "keyboard") this.bridge.listenKeyboard({ id })
        if (kind === "gamepad") this.bridge.listenGamepad({ id })
      })

      this.handleEvent("controls:updated", (maps) => this.bridge.updateMaps(maps))

      window.addEventListener("input:rebindMaps", handleRebind)
    },

    updated() {
      orchestrator?.onViewChanged()
    },

    destroyed() {
      window.removeEventListener("input:rebindMaps", handleRebind)
      orchestrator?.destroy()
      orchestrator = null
      keyboardSource = null
      gamepadSource = null
    },
  }
}
