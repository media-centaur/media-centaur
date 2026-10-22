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
import { createEpisodeMappingBehavior } from "./episode_mapping_behavior"
import { createSettingsBehavior } from "./settings_behavior"
import { createIncomingBehavior, incomingDom } from "./incoming_behavior"
import { createWatchHistoryBehavior } from "./watch_history_behavior"
import { createSocialBehavior } from "./social_behavior"
import { createAppsBehavior } from "./apps_behavior"
import { createSetupBehavior } from "./setup_behavior"
import { createProfilesBehavior } from "./profiles_behavior"
import { createGuideBehavior } from "./guide_behavior"
import { withWipNotice } from "./wip_notice"
import { withViewing } from "./viewing_behavior"

// Pages still mid-redesign carry the "UI overhaul in progress" notice via
// withWipNotice (see wip_notice.js). The set of wrapped entries below is the
// single source of truth for which pages show it; unwrap an entry once its
// in-page navigation is finished.
const BEHAVIOR_REGISTRY = {
  status: () => createStatusBehavior(),
  library: () => createLibraryBehavior(libraryDom),
  review: () => createReviewBehavior(),
  "episode-mapping": () => createEpisodeMappingBehavior(),
  settings: () => createSettingsBehavior(),
  incoming: () => createIncomingBehavior(incomingDom),
  "watch-history": () => withWipNotice(createWatchHistoryBehavior()),
  social: () => createSocialBehavior(),
  apps: () => createAppsBehavior(),
  setup: () => createSetupBehavior(),
  profiles: () => createProfilesBehavior(),
  guide: () => createGuideBehavior(),
}

/**
 * Look up and instantiate a page behavior by name. While the viewing layer
 * is on the page (`options.viewing`) the behavior is wrapped by
 * `withViewing`, which needs the hook's `pushEvent` and the menu switch.
 * @param {string|null} name - The data-page-behavior value
 * @param {{viewing?: boolean, pushEvent?: function, isMenuOpen?: function}} [options]
 * @returns {PageBehavior|null}
 */
export function createPageBehavior(name, options = {}) {
  const factory = BEHAVIOR_REGISTRY[name]
  const behavior = factory ? factory() : null
  if (!options.viewing) return behavior
  return withViewing(behavior ?? {}, { pushEvent: options.pushEvent, isMenuOpen: options.isMenuOpen })
}
