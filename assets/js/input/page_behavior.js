/**
 * Page behavior registry.
 *
 * Maps `data-page-behavior` attribute values to behavior factories.
 * Each factory receives injected dependencies and returns a behavior instance.
 *
 * @typedef {Object} PageBehavior
 * @property {function(): void} [onAttach]          — behavior activates
 * @property {function(): void} [onDetach]          — behavior deactivates
 * @property {function(): boolean|string} [onEscape] — true to consume, string to navigate
 * @property {function(): void} [onClear]            — CLEAR action (Y / Backspace)
 * @property {function(string): void} [onZoneChanged] — context changed
 * @property {function(Object): {clearGridMemory: boolean}} [onSyncState] — state sync
 * @property {function(string, string, Element): boolean|{transitionTo: string}} [onAction]
 *   — intercept action before framework processing (action, context, focusedItem).
 *     Return true to consume, { transitionTo } to transition, false to pass through.
 */

import { createStatusBehavior } from "./status_behavior"
import { createLibraryBehavior, libraryDom } from "./library_behavior"
import { createReviewBehavior } from "./review_behavior"
import { createSettingsBehavior } from "./settings_behavior"
import { createDownloadBehavior } from "./download_behavior"

const BEHAVIOR_REGISTRY = {
  status: () => createStatusBehavior(),
  library: () => createLibraryBehavior(libraryDom),
  review: () => createReviewBehavior(),
  settings: () => createSettingsBehavior(),
  download: () => createDownloadBehavior(),
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
