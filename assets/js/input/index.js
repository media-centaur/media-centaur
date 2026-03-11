/**
 * App entry point — imports the framework core and app config,
 * creates the LiveView hook for the input system.
 */

import { Orchestrator, createDomReader, createDomWriter, KeyboardSource, GamepadSource } from "./core/index.js"
import { inputConfig } from "./config.js"

const BROWSER_GLOBALS = {
  get document() { return document },
  get sessionStorage() { return sessionStorage },
  get requestAnimationFrame() { return requestAnimationFrame.bind(window) },
  get cancelAnimationFrame() { return cancelAnimationFrame.bind(window) },
  get getGamepads() { return navigator.getGamepads?.bind(navigator) ?? (() => []) },
}

/**
 * Create the LiveView hook for the input system.
 * This is the bridge between LiveView lifecycle and the Orchestrator.
 */
export function createInputHook() {
  let orchestrator = null

  return {
    mounted() {
      const reader = createDomReader(inputConfig)
      const writer = createDomWriter(inputConfig)
      orchestrator = new Orchestrator({
        reader,
        writer,
        globals: BROWSER_GLOBALS,
        sources: [
          (callbacks, globals) => new KeyboardSource({
            document: globals.document,
            ...callbacks,
          }),
          (callbacks, globals) => new GamepadSource({
            getGamepads: globals.getGamepads,
            requestAnimationFrame: globals.requestAnimationFrame,
            cancelAnimationFrame: globals.cancelAnimationFrame,
            addEventListener: window.addEventListener.bind(window),
            removeEventListener: window.removeEventListener.bind(window),
            onControllerChanged: (type) => writer.setControllerType(type),
            ...callbacks,
          }),
        ],
        ...inputConfig,
      })
      orchestrator.start(this)
    },

    updated() {
      orchestrator?.onViewChanged()
    },

    destroyed() {
      orchestrator?.destroy()
      orchestrator = null
    },
  }
}
