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
    // The detail modal's two regions. A closed modal is `visibility: hidden`
    // and its items fail `checkVisibility()`, so these count zero until it
    // opens — no modal scoping needed on the selectors.
    detail_actions: "[data-nav-zone='detail_actions'] [data-nav-item]",
    detail_rail: "[data-nav-zone='detail_rail'] [data-nav-item]",
    manage_tools: "[data-nav-zone='manage_tools'] [data-nav-item]",
    manage_list: "[data-nav-zone='manage_list'] [data-nav-item]",
    detail_list: "[data-nav-zone='detail_list'] [data-nav-item]",
    detail_cast: "[data-nav-zone='detail_cast'] [data-nav-item]",
    // The plan modal's regions (UIDR-029): head (status, verdict, their
    // controls) over the episode grid over the body (release rows,
    // decisions, footer). Each stage before the board puts everything in
    // `plan_body`.
    plan_head: "[data-nav-zone='plan_head'] [data-nav-item]",
    plan_grid: "[data-nav-zone='plan_grid'] [data-nav-item]",
    plan_body: "[data-nav-zone='plan_body'] [data-nav-item]",
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
    // The detail modal: a horizontal command row over a nesting list. The
    // Cast sub-view swaps the list for a photo grid, whose arrangement
    // carries the meaning — SHELF resolves it by geometry, which is what
    // walks the two grid sections and the Show more button without an
    // adjacency table.
    detail_actions: Context.TOOLBAR,
    detail_rail: Context.TOOLBAR,
    manage_tools: Context.TOOLBAR,
    manage_list: Context.TREE,
    detail_list: Context.TREE,
    detail_cast: Context.SHELF,
    // The plan modal: two vertical lists around the episode grid. The grid's
    // arrangement carries its meaning (season rows, capsules for packs), so
    // it is a SHELF — geometry answers adjacency across wrapped rows and
    // capsule groups without an adjacency table.
    plan_head: Context.TREE,
    plan_grid: Context.SHELF,
    plan_body: Context.TREE,
  },

  // Overlays that navigate as several regions rather than one flat list.
  // Named by `data-nav-overlay` on the overlay element; anything without one
  // stays a flat MODAL, which is right for a confirm or a small form.
  //
  // The detail modal is Play / More info / Manage above the body of the title —
  // seasons and episodes for a series, the film list for a collection, extras
  // for anything. `entry` lands the cursor on Play; `back` is what makes BACK
  // climb from the body to the buttons before it closes the modal.
  // Only one body zone is in the DOM at a time (the sub-views swap it), so
  // the candidate list on `down` routes to whichever body is populated.
  //
  // Every region climbs on UP at its top — stopping dead under whatever sits
  // above read as a dead end each time it was tried (UIDR-019, twice
  // amended). The tree's `up` candidates route through the Manage toolbar
  // card when it exists; a spatial region (the cast grid) has a geometric
  // "above", and stopping dead under the action row reads as
  // a dead end.
  overlays: {
    detail: {
      entry: ["detail_actions", "detail_rail", "manage_tools", "manage_list", "detail_list", "detail_cast"],
      layout: {
        // manage_tools is the Manage sub-view's toolbar card — a horizontal
        // strip (Delete all, Rematch, Refresh artwork, ID links) that is its
        // own TOOLBAR region so DOWN drops past it instead of walking it.
        // manage_list is the folder ledger below it — a tree like the
        // episode list but deliberately NOT the same context: per-context
        // cursor memory is keyed by name, and sharing `detail_list` let
        // ledger activity overwrite the episode list's remembered position.
        // Both are empty in the other sub-views, where the candidate lists
        // fall through to whichever body is populated.
        // detail_rail is the collection modal's poster-rail picker
        // (UIDR-023) — a TOOLBAR strip between the action row and the
        // body. Present only for collections; everywhere else the
        // candidate lists fall through past it.
        detail_actions: { down: ["detail_rail", "manage_tools", "manage_list", "detail_list", "detail_cast"] },
        detail_rail: {
          up: ["detail_actions"],
          down: ["manage_tools", "manage_list", "detail_list", "detail_cast"],
          back: ["detail_actions"],
        },
        manage_tools: { up: ["detail_rail", "detail_actions"], down: ["manage_list"], back: ["detail_actions"] },
        manage_list: { up: ["manage_tools"], back: ["detail_actions"] },
        detail_list: { up: ["detail_rail", "detail_actions"], back: ["detail_actions"] },
        detail_cast: { up: ["detail_rail", "detail_actions"], back: ["detail_actions"] },
      },
    },
    // The plan modal (UIDR-029). Regions stack vertically; a movie board has
    // no grid and the candidate lists fall through head ↔ body. No `back`
    // edges: BACK dismisses from anywhere, as it did when the modal was one
    // flat list — the regions exist so the grid can be walked spatially, not
    // to add depth. The modal opens on a loading stage with no controls;
    // the orchestrator enters the first region that populates.
    plan: {
      entry: ["plan_head", "plan_body", "plan_grid"],
      layout: {
        plan_head: { down: ["plan_grid", "plan_body"] },
        plan_grid: { up: ["plan_head"], down: ["plan_body"] },
        plan_body: { up: ["plan_grid", "plan_head"] },
      },
    },
  },

  // Contexts entered at a declared item when there is no position to return to.
  // The detail body opens on the episode Play would play — the same row the
  // panel scrolls to and marks as next up, so the cursor agrees with both.
  // The rail enters at the selected member's tile — the cursor agrees
  // with the panel's subject.
  entryDefaults: { detail_list: "[data-resume-target]", detail_rail: "[data-selected]" },

  // Zone layouts for nav graph. No content context carries a left edge to the
  // sidebar: reaching the main menu is BACK's job (see `_backTransition`), and
  // LEFT stays lateral movement within the page. Each layout still declares a
  // sidebar node with its `right` candidates — its presence is what tells BACK
  // the page has a main menu, and the candidates are where exiting it lands.
  layouts: {
    watching: {
      zone_tabs: { down: ["grid"] },
      grid:      { up: ["zone_tabs"], right: ["drawer"] },
      sidebar:   { right: ["grid", "zone_tabs"] },
      drawer:    { left: ["grid"] },
    },
    library: {
      toolbar:   { down: ["grid"] },
      grid:      { up: ["toolbar"], right: ["drawer"] },
      sidebar:   { right: ["grid", "toolbar"] },
      drawer:    { left: ["grid", "toolbar"] },
    },
    settings: {
      sections:  { right: ["grid"] },
      grid:      { left: ["sections"] },
      sidebar:   { right: ["sections", "grid"] },
    },
    // Guide: chapter list (left) → reading pane (not navigable — prose) →
    // on-this-page outline (right). RIGHT from chapters skips the prose
    // straight to the outline; the outline is conditional (long chapters,
    // xl+ only), so the candidate fallback handles its absence.
    guide: {
      guide_chapters: { right: ["guide_outline"] },
      guide_outline:  { left: ["guide_chapters"] },
      sidebar:        { right: ["guide_chapters"] },
    },
    // Status: toolbar (Report a problem) over the subsystem tile grid
    // (spatial GRID nav), with the conditional drill-in panel below —
    // skipped via candidate lists while no subsystem is selected.
    status: {
      toolbar:    { down: ["grid"] },
      grid:       { up: ["toolbar"], down: ["drill-in"] },
      "drill-in": { up: ["grid"] },
      sidebar:    { right: ["grid", "toolbar"] },
    },
    // The two review surfaces — identity (/review) and episode mapping
    // (/reconcile) — share the ReviewTabs strip and the same master/detail
    // shape, so their layouts are deliberately identical apart from the zone
    // names. Up from either pane reaches the tab strip (MENU walls route
    // through the graph); the strip's own down edge returns to whichever pane
    // has items, so the empty state still navigates.
    review: {
      zone_tabs:       { down: ["review-list", "review-detail"] },
      "review-list":   { up: ["zone_tabs"], right: ["review-detail"] },
      "review-detail": { up: ["zone_tabs"], left: ["review-list"] },
      sidebar:         { right: ["review-list", "review-detail", "zone_tabs"] },
    },
    reconcile: {
      zone_tabs:          { down: ["reconcile-list", "reconcile-detail"] },
      "reconcile-list":   { up: ["zone_tabs"], right: ["reconcile-detail"] },
      "reconcile-detail": { up: ["zone_tabs"], left: ["reconcile-list"] },
      sidebar:            { right: ["reconcile-list", "reconcile-detail", "zone_tabs"] },
    },
    // Incoming: omnibox on top, then the zone tabs (Coming up | Activity |
    // History) — one tab's content renders at a time, so the candidate
    // lists do the routing: Coming up shows coming_up_list; Activity shows
    // drafts → pursuits → other_downloads; History shows the ledger
    // (glimpse AND expanded archive, one zone). While a search owns the
    // page the tabs recede: media search renders "toolbar" (scope chips +
    // Clear) over "grid" (the result rows, a 2-column pick/bookmark grid
    // via the row-level data-nav-grid); release search renders only "grid"
    // (its linear group list carries its own Clear). The ledger always
    // carries its "View all" toggle as a nav item once any history exists,
    // so the archive stays reachable.
    incoming: {
      omnibox:         { down: ["toolbar", "grid", "zone_tabs", "coming_up_list", "drafts", "pursuits", "ledger"] },
      toolbar:         { up: ["omnibox"], down: ["grid"] },
      grid:            { up: ["toolbar", "omnibox"] },
      zone_tabs:       { up: ["omnibox"], down: ["coming_up_list", "drafts", "pursuits", "ledger", "other_downloads"] },
      coming_up_list:  { up: ["zone_tabs", "omnibox"] },
      drafts:          { up: ["zone_tabs", "omnibox"], down: ["pursuits", "other_downloads"] },
      pursuits:        { up: ["drafts", "zone_tabs", "omnibox"], down: ["other_downloads"] },
      ledger:          { up: ["zone_tabs", "omnibox"] },
      other_downloads: { up: ["pursuits", "drafts", "zone_tabs"] },
      sidebar:         { right: ["coming_up_list", "pursuits", "ledger", "zone_tabs", "omnibox"] },
    },
    watch_history: {
      toolbar:   { down: ["grid"] },
      grid:      { up: ["toolbar"] },
      sidebar:   { right: ["toolbar", "grid"] },
    },
    // Discovery: the zone-tabs strip above the watchlist grid (feed and
    // friends tabs join the strip later). Same shape as review/reconcile.
    discovery: {
      zone_tabs: { down: ["grid"] },
      grid:      { up: ["zone_tabs"] },
      sidebar:   { right: ["grid", "zone_tabs"] },
    },
    apps: {
      toolbar: { down: ["grid"] },
      grid:    { up: ["toolbar"] },
      sidebar: { right: ["grid", "toolbar"] },
    },
    // Home: vertical stack of horizontal shelves. Up/down crosses between
    // shelves (candidate lists skip shelves the page didn't render).
    home: {
      hero:      { down: ["continue", "recently", "coming_up"] },
      continue:  { up: ["hero"], down: ["recently", "coming_up"] },
      recently:  { up: ["continue", "hero"], down: ["coming_up"] },
      coming_up: { up: ["recently", "continue", "hero"] },
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
    watch_history: ["grid", "toolbar", "sidebar"],
    discovery: ["grid", "zone_tabs", "sidebar"],
    apps: ["grid", "toolbar", "sidebar"],
    home:      ["hero", "continue", "recently", "coming_up", "sidebar"],
    setup:     ["grid"],
  },

  // Always-populated contexts (skip item count check)
  alwaysPopulated: ["sidebar", "sections", "guide_chapters"],

  // Contexts that are always entered at one specific item, whatever the user
  // last touched there. Reserved for zones that exist to be entered at a
  // single action — the home hero is "press play", so arriving from any
  // direction lands on Play rather than on whichever CTA was focused last.
  // Applies on entry only; a post-patch focus reconcile leaves the cursor
  // where it is.
  entryAnchors: { hero: 0 },

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
