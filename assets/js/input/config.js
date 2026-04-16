/**
 * App-specific input system configuration.
 *
 * All app-specific knowledge lives here: CSS selectors, zone layouts,
 * instance type mappings, and behavior factories. The framework core
 * is parameterized by this config and has no app-specific imports.
 */

import { Context } from "./core/index.js"
import { createPageBehavior } from "./page_behavior.js"

export const inputConfig = {
  // Context selectors — maps context keys to CSS selectors
  contextSelectors: {
    [Context.GRID]: "[data-nav-zone='grid'] [data-nav-item]",
    [Context.DRAWER]: "[data-detail-mode='drawer'] [data-nav-item]",
    [Context.MODAL]: "[data-detail-mode='modal'] [data-nav-item]",
    [Context.TOOLBAR]: "[data-nav-zone='toolbar'] [data-nav-item]",
    sidebar: "[data-nav-zone='sidebar'] [data-nav-item]",
    sections: "[data-nav-zone='sections'] [data-nav-item]",
    upcoming: "[data-nav-zone='upcoming'] > [data-nav-item]",
    [Context.ZONE_TABS]: "[data-nav-zone='zone-tabs'] [data-nav-item]",
    "review-list": "[data-nav-zone='review-list'] [data-nav-item]",
    "review-detail": "[data-nav-zone='review-detail'] [data-nav-item]",
  },

  // Instance → context type mapping
  instanceTypes: {
    sidebar: Context.MENU,
    sections: Context.MENU,
    upcoming: Context.MENU,
    "review-list": Context.MENU,
    "review-detail": Context.MENU,
  },

  // Zone layouts for nav graph
  layouts: {
    watching: {
      zone_tabs: { down: ["grid"],             left: ["sidebar"] },
      grid:      { up: ["zone_tabs"],          left: ["sidebar"], right: ["drawer"] },
      sidebar:   { right: ["grid", "zone_tabs"] },
      drawer:    { left: ["grid"] },
    },
    library: {
      zone_tabs: { down: ["toolbar", "grid"],  left: ["sidebar"] },
      toolbar:   { up: ["zone_tabs"],          down: ["grid"],   left: ["sidebar"] },
      grid:      { up: ["toolbar", "zone_tabs"], left: ["sidebar"], right: ["drawer"] },
      sidebar:   { right: ["grid", "toolbar", "zone_tabs"] },
      drawer:    { left: ["grid", "toolbar"] },
    },
    upcoming: {
      zone_tabs: { down: ["upcoming"],           left: ["sidebar"] },
      upcoming:  { up: ["zone_tabs"],            left: ["sidebar"] },
      grid:      { up: ["upcoming", "zone_tabs"], left: ["upcoming", "sidebar"] },
      sidebar:   { right: ["upcoming", "grid", "zone_tabs"] },
    },
    settings: {
      sections:  { right: ["grid"],            left: ["sidebar"] },
      grid:      { left: ["sections"] },
      sidebar:   { right: ["sections", "grid"] },
    },
    status: {
      sections:  { left: ["sidebar"] },
      sidebar:   { right: ["sections"] },
    },
    review: {
      "review-list":   { right: ["review-detail"], left: ["sidebar"] },
      "review-detail": { left: ["review-list"] },
      sidebar:         { right: ["review-list", "review-detail"] },
    },
    download: {
      sections:  { down: ["grid"], left: ["sidebar"] },
      grid:      { up: ["sections"], left: ["sidebar"] },
      sidebar:   { right: ["sections", "grid"] },
    },
  },

  // Cursor start priority per zone
  cursorStartPriority: {
    watching:  ["grid", "zone_tabs", "sidebar"],
    library:   ["grid", "toolbar", "zone_tabs", "sidebar"],
    upcoming:  ["upcoming", "grid", "zone_tabs", "sidebar"],
    settings:  ["sections", "grid", "sidebar"],
    status:    ["sections", "sidebar"],
    review:    ["review-list", "review-detail", "sidebar"],
    download:  ["sections", "grid", "sidebar"],
  },

  // Always-populated contexts (skip item count check)
  alwaysPopulated: ["sidebar", "sections"],

  // Active item class names for focus restoration
  activeClassNames: [
    "sidebar-link-active", "tab-active",
    "zone-tab-active", "menu-item-active",
  ],

  // Primary menu instance (has special enter/exit behavior)
  primaryMenu: "sidebar",

  // Page behavior factory
  createBehavior: createPageBehavior,
}
