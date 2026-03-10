/**
 * App entry point — imports the framework core and app config,
 * creates the LiveView hook for the input system.
 */

import { Orchestrator, createDomReader, createDomWriter } from "./core/index.js"
import { inputConfig } from "./config.js"

const BROWSER_GLOBALS = {
  get document() { return document },
  get sessionStorage() { return sessionStorage },
  get requestAnimationFrame() { return requestAnimationFrame.bind(window) },
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
        ...inputConfig,
      })
      orchestrator.start(this.el)
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
