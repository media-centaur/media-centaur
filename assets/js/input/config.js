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
    // Home page shelves (horizontal media rows stacked vertically)
    hero: "[data-nav-zone='hero'] [data-nav-item]",
    continue: "[data-nav-zone='continue'] [data-nav-item]",
    recently: "[data-nav-zone='recently'] [data-nav-item]",
    coming_up: "[data-nav-zone='coming_up'] [data-nav-item]",
    // Download page (single column: omnibox → drafts → pursuits → history)
    omnibox: "[data-nav-zone='omnibox'] [data-nav-item]",
    drafts: "[data-nav-zone='drafts'] [data-nav-item]",
    pursuits: "[data-nav-zone='pursuits'] [data-nav-item]",
    history: "[data-nav-zone='history'] [data-nav-item]",
    other_downloads: "[data-nav-zone='other_downloads'] [data-nav-item]",
  },

  // Instance → context type mapping
  instanceTypes: {
    sidebar: Context.MENU,
    sections: Context.MENU,
    upcoming: Context.MENU,
    "review-list": Context.MENU,
    "review-detail": Context.MENU,
    // Home shelves behave as horizontal lists with a vertical nav graph
    hero: Context.SHELF,
    continue: Context.SHELF,
    recently: Context.SHELF,
    coming_up: Context.SHELF,
    // Download zones are vertical item lists.
    omnibox: Context.MENU,
    drafts: Context.MENU,
    pursuits: Context.MENU,
    history: Context.MENU,
    other_downloads: Context.MENU,
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
      toolbar:   { down: ["grid"],             left: ["sidebar"] },
      grid:      { up: ["toolbar"],            left: ["sidebar"], right: ["drawer"] },
      sidebar:   { right: ["grid", "toolbar"] },
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
    // Download: single column, top to bottom — omnibox → release-search
    // results ("grid") → drafts → pursuits → history → other_downloads.
    // Conditional zones (grid, drafts, other_downloads) are skipped via
    // candidate lists, same convention as home. History collapsed still
    // carries its disclosure toggle as a nav item, so the zone is always
    // reachable.
    download: {
      omnibox:         { down: ["grid", "drafts", "pursuits", "history"], left: ["sidebar"] },
      grid:            { up: ["omnibox"], down: ["drafts", "pursuits", "history"], left: ["sidebar"] },
      drafts:          { up: ["grid", "omnibox"], down: ["pursuits", "history"], left: ["sidebar"] },
      pursuits:        { up: ["drafts", "grid", "omnibox"], down: ["history", "other_downloads"], left: ["sidebar"] },
      history:         { up: ["pursuits", "drafts", "grid", "omnibox"], down: ["other_downloads"], left: ["sidebar"] },
      other_downloads: { up: ["history", "pursuits"], left: ["sidebar"] },
      sidebar:         { right: ["pursuits", "omnibox", "history"] },
    },
    watch_history: {
      toolbar:   { down: ["grid"], left: ["sidebar"] },
      grid:      { up: ["toolbar"], left: ["sidebar"] },
      sidebar:   { right: ["toolbar", "grid"] },
    },
    // Home: vertical stack of horizontal shelves. Up/down crosses between
    // shelves (candidate lists skip shelves the page didn't render); left
    // always returns to the sidebar.
    home: {
      hero:      { down: ["continue", "recently", "coming_up"], left: ["sidebar"] },
      continue:  { up: ["hero"], down: ["recently", "coming_up"], left: ["sidebar"] },
      recently:  { up: ["continue", "hero"], down: ["coming_up"], left: ["sidebar"] },
      coming_up: { up: ["recently", "continue", "hero"], left: ["sidebar"] },
      sidebar:   { right: ["hero", "continue", "recently", "coming_up"] },
    },
  },

  // Cursor start priority per zone
  cursorStartPriority: {
    watching:  ["grid", "zone_tabs", "sidebar"],
    library:   ["grid", "toolbar", "sidebar"],
    upcoming:  ["upcoming", "grid", "zone_tabs", "sidebar"],
    settings:  ["sections", "grid", "sidebar"],
    status:    ["sections", "sidebar"],
    review:    ["review-list", "review-detail", "sidebar"],
    download:  ["pursuits", "omnibox", "sidebar"],
    watch_history: ["toolbar", "grid", "sidebar"],
    home:      ["hero", "continue", "recently", "coming_up", "sidebar"],
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
