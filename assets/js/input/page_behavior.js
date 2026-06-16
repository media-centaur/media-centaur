/**
 * Page behavior registry.
 *
 * Maps `data-page-behavior` attribute values to behavior factories.
 * Each factory receives injected dependencies and returns a behavior instance.
 *
 * @typedef {Object} PageBehavior
 * @property {function(): void} [onAttach]          — behavior activates
 * @property {function(): void} [onDetach]          — behavior deactivates
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
import { createDownloadBehavior, downloadDom } from "./download_behavior"
import { createWatchHistoryBehavior } from "./watch_history_behavior"
import { createUpcomingBehavior } from "./upcoming_behavior"
import { createHomeBehavior, homeDom } from "./home_behavior"
import { createSetupBehavior } from "./setup_behavior"
import { createGuideBehavior } from "./guide_behavior"
import { withWipNotice } from "./wip_notice"

// Pages still mid-redesign carry the "UI overhaul in progress" notice via
// withWipNotice (see wip_notice.js). The set of wrapped entries below is the
// single source of truth for which pages show it; unwrap an entry once its
// in-page navigation is finished.
const BEHAVIOR_REGISTRY = {
  home: () => createHomeBehavior(homeDom),
  status: () => createStatusBehavior(),
  library: () => createLibraryBehavior(libraryDom),
  review: () => createReviewBehavior(),
  settings: () => createSettingsBehavior(),
  download: () => createDownloadBehavior(downloadDom),
  "watch-history": () => withWipNotice(createWatchHistoryBehavior()),
  upcoming: () => createUpcomingBehavior(),
  setup: () => createSetupBehavior(),
  guide: () => createGuideBehavior(),
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
