/**
 * Page behavior registry.
 *
 * Maps `data-page-behavior` attribute values to behavior factories.
 * Each factory receives injected dependencies and returns a behavior instance.
 *
 * @typedef {Object} PageBehavior
 * @property {function(): void} [onAttach]          — behavior activates
 * @property {function(): void} [onDetach]          — behavior deactivates
 * @property {function(): boolean} [onEscape]       — return true to consume
 * @property {function(string): void} [onZoneChanged] — zone switched
 * @property {function(Object): {clearGridMemory: boolean}} [onSyncState] — state sync
 */

import { createLibraryBehavior, libraryDom } from "./library_behavior"
import { createSettingsBehavior } from "./settings_behavior"

const BEHAVIOR_REGISTRY = {
  library: () => createLibraryBehavior(libraryDom),
  settings: () => createSettingsBehavior(),
}

/**
 * Look up and instantiate a page behavior by name.
 * @param {string} name - The data-page-behavior value
 * @returns {PageBehavior|null}
 */
export function createPageBehavior(name) {
  const factory = BEHAVIOR_REGISTRY[name]
  return factory ? factory() : null
}
