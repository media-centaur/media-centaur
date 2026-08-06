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
    [Context.ZONE_TABS]: "[data-nav-zone='zone-tabs'] [data-nav-item]",
    "review-list": "[data-nav-zone='review-list'] [data-nav-item]",
    "review-detail": "[data-nav-zone='review-detail'] [data-nav-item]",
    // Episode mapping (/reconcile) — the same master/detail shape as review
    "reconcile-list": "[data-nav-zone='reconcile-list'] [data-nav-item]",
    "reconcile-detail": "[data-nav-zone='reconcile-detail'] [data-nav-item]",
    // Status page subsystem drill-in (vertical rail: close, incidents, logs)
    "drill-in": "[data-nav-zone='drill-in'] [data-nav-item]",
    // Home page shelves (horizontal media rows stacked vertically)
    hero: "[data-nav-zone='hero'] [data-nav-item]",
    continue: "[data-nav-zone='continue'] [data-nav-item]",
    recently: "[data-nav-zone='recently'] [data-nav-item]",
    coming_up: "[data-nav-zone='coming_up'] [data-nav-item]",
    // Incoming page (single column: omnibox → shelf → drafts → pursuits →
    // ledger). `coming_up_list` is the incoming page's own vertical take on
    // the forecast (the home pages keep the horizontal `coming_up` shelf
    // above); the ledger hosts both the glimpse rows and the expanded
    // archive (chips + search).
    coming_up_list: "[data-nav-zone='coming_up_list'] [data-nav-item]",
    omnibox: "[data-nav-zone='omnibox'] [data-nav-item]",
    drafts: "[data-nav-zone='drafts'] [data-nav-item]",
    pursuits: "[data-nav-zone='pursuits'] [data-nav-item]",
    ledger: "[data-nav-zone='ledger'] [data-nav-item]",
    other_downloads: "[data-nav-zone='other_downloads'] [data-nav-item]",
    // Guide: chapter sidebar + on-this-page outline (both vertical link lists).
    guide_chapters: "[data-nav-zone='guide_chapters'] [data-nav-item]",
    guide_outline: "[data-nav-zone='guide_outline'] [data-nav-item]",
  },

  // Instance → context type mapping
  instanceTypes: {
    sidebar: Context.MENU,
    sections: Context.MENU,
    "review-list": Context.MENU,
    "review-detail": Context.MENU,
    "reconcile-list": Context.MENU,
    "reconcile-detail": Context.MENU,
    "drill-in": Context.MENU,
    // Home shelves behave as horizontal lists with a vertical nav graph
    hero: Context.SHELF,
    continue: Context.SHELF,
    recently: Context.SHELF,
    coming_up: Context.SHELF,
    // Incoming zones are vertical item lists — including the forecast,
    // which is an agenda list here (the home pages keep their horizontal
    // `coming_up` SHELF instance above).
    coming_up_list: Context.MENU,
    omnibox: Context.MENU,
    drafts: Context.MENU,
    pursuits: Context.MENU,
    ledger: Context.MENU,
    other_downloads: Context.MENU,
    guide_chapters: Context.MENU,
    guide_outline: Context.MENU,
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
    settings: {
      sections:  { right: ["grid"],            left: ["sidebar"] },
      grid:      { left: ["sections"] },
      sidebar:   { right: ["sections", "grid"] },
    },
    // Guide: chapter list (left) → reading pane (not navigable — prose) →
    // on-this-page outline (right). RIGHT from chapters skips the prose
    // straight to the outline; the outline is conditional (long chapters,
    // xl+ only), so the candidate fallback handles its absence.
    guide: {
      guide_chapters: { right: ["guide_outline"], left: ["sidebar"] },
      guide_outline:  { left: ["guide_chapters"] },
      sidebar:        { right: ["guide_chapters"] },
    },
    // Status: toolbar (Report a problem) over the subsystem tile grid
    // (spatial GRID nav), with the conditional drill-in panel below —
    // skipped via candidate lists while no subsystem is selected.
    status: {
      toolbar:    { down: ["grid"], left: ["sidebar"] },
      grid:       { up: ["toolbar"], down: ["drill-in"], left: ["sidebar"] },
      "drill-in": { up: ["grid"], left: ["sidebar"] },
      sidebar:    { right: ["grid", "toolbar"] },
    },
    // The two review surfaces — identity (/review) and episode mapping
    // (/reconcile) — share the ReviewTabs strip and the same master/detail
    // shape, so their layouts are deliberately identical apart from the zone
    // names. Up from either pane reaches the tab strip (MENU walls route
    // through the graph); the strip's own down edge returns to whichever pane
    // has items, so the empty state still navigates.
    review: {
      zone_tabs:       { down: ["review-list", "review-detail"], left: ["sidebar"] },
      "review-list":   { up: ["zone_tabs"], right: ["review-detail"], left: ["sidebar"] },
      "review-detail": { up: ["zone_tabs"], left: ["review-list"] },
      sidebar:         { right: ["review-list", "review-detail", "zone_tabs"] },
    },
    reconcile: {
      zone_tabs:          { down: ["reconcile-list", "reconcile-detail"], left: ["sidebar"] },
      "reconcile-list":   { up: ["zone_tabs"], right: ["reconcile-detail"], left: ["sidebar"] },
      "reconcile-detail": { up: ["zone_tabs"], left: ["reconcile-list"] },
      sidebar:            { right: ["reconcile-list", "reconcile-detail", "zone_tabs"] },
    },
    // Incoming: omnibox on top, then the zone tabs (Coming up | Activity |
    // History) — one tab's content renders at a time, so the candidate
    // lists do the routing: Coming up shows coming_up_list; Activity shows
    // drafts → pursuits → other_downloads; History shows the ledger
    // (glimpse AND expanded archive, one zone). While a search owns the
    // page only "grid" (the flat results) exists below the omnibox and the
    // tabs recede. The ledger always carries its "View all" toggle as a
    // nav item once any history exists, so the archive stays reachable.
    incoming: {
      omnibox:         { down: ["grid", "zone_tabs", "coming_up_list", "drafts", "pursuits", "ledger"], left: ["sidebar"] },
      grid:            { up: ["omnibox"], left: ["sidebar"] },
      zone_tabs:       { up: ["omnibox"], down: ["coming_up_list", "drafts", "pursuits", "ledger", "other_downloads"], left: ["sidebar"] },
      coming_up_list:  { up: ["zone_tabs", "omnibox"], left: ["sidebar"] },
      drafts:          { up: ["zone_tabs", "omnibox"], down: ["pursuits", "other_downloads"], left: ["sidebar"] },
      pursuits:        { up: ["drafts", "zone_tabs", "omnibox"], down: ["other_downloads"], left: ["sidebar"] },
      ledger:          { up: ["zone_tabs", "omnibox"], left: ["sidebar"] },
      other_downloads: { up: ["pursuits", "drafts", "zone_tabs"], left: ["sidebar"] },
      sidebar:         { right: ["coming_up_list", "pursuits", "ledger", "zone_tabs", "omnibox"] },
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
    // Setup tour: a sidebar-less first-run wizard. A single `grid` context
    // holds the whole step card (form fields + footer buttons); there is
    // nowhere else to navigate, so the context has no edges. Up/down walks the
    // card linearly; SELECT activates a button or edits a field.
    setup: {
      grid: {},
    },
  },

  // Cursor start priority per zone
  cursorStartPriority: {
    watching:  ["grid", "zone_tabs", "sidebar"],
    library:   ["grid", "toolbar", "sidebar"],
    settings:  ["sections", "grid", "sidebar"],
    guide:     ["guide_chapters", "guide_outline", "sidebar"],
    status:    ["grid", "toolbar", "sidebar"],
    review:    ["review-list", "review-detail", "zone_tabs", "sidebar"],
    reconcile: ["reconcile-list", "reconcile-detail", "zone_tabs", "sidebar"],
    incoming:  ["coming_up_list", "pursuits", "ledger", "zone_tabs", "omnibox", "sidebar"],
    watch_history: ["toolbar", "grid", "sidebar"],
    home:      ["hero", "continue", "recently", "coming_up", "sidebar"],
    setup:     ["grid"],
  },

  // Always-populated contexts (skip item count check)
  alwaysPopulated: ["sidebar", "sections", "guide_chapters"],

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
