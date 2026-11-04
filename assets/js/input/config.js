/**
 * App-specific input system configuration.
 *
 * All app-specific knowledge lives here: CSS selectors, zone layouts,
 * instance type mappings, and behavior factories. The framework core
 * is parameterized by this config and has no app-specific imports.
 */

import { Context } from "./core/index.js"
import { createPageBehavior } from "./page_behavior.js"
import { scrollGlider } from "../scroll_glider.js"

export const inputConfig = {
  // The page's one scroll animator (assets/js/scroll_glider.js); the DOM
  // writer glides with it, and so does the scroll row hook.
  glider: scrollGlider,

  // Context selectors — maps context keys to CSS selectors
  contextSelectors: {
    [Context.GRID]: "[data-nav-zone='grid'] [data-nav-item]",
    [Context.MODAL]: "[data-detail-mode='modal'] [data-nav-item]",
    // The detail modal's two regions. A closed modal is `visibility: hidden`
    // and its items fail `checkVisibility()`, so these count zero until it
    // opens — no modal scoping needed on the selectors.
    detail_social: "[data-nav-zone='detail_social'] [data-nav-item]",
    detail_finish: "[data-nav-zone='detail_finish'] [data-nav-item]",
    detail_actions: "[data-nav-zone='detail_actions'] [data-nav-item]",
    detail_menu: "[data-nav-zone='detail_menu'] [data-nav-item]",
    detail_rail: "[data-nav-zone='detail_rail'] [data-nav-item]",
    manage_tools: "[data-nav-zone='manage_tools'] [data-nav-item]",
    manage_list: "[data-nav-zone='manage_list'] [data-nav-item]",
    detail_list: "[data-nav-zone='detail_list'] [data-nav-item]",
    detail_cast: "[data-nav-zone='detail_cast'] [data-nav-item]",
    detail_cast_filter: "[data-nav-zone='detail_cast_filter'] [data-nav-item]",
    detail_tracking: "[data-nav-zone='detail_tracking'] [data-nav-item]",
    detail_tracking_menu: "[data-nav-zone='detail_tracking_menu'] [data-nav-item]",
    // The plan modal's regions (UIDR-029): head (status, verdict, their
    // controls) over the episode grid over the body (release rows,
    // decisions, footer). Each stage before the board puts everything in
    // `plan_body`.
    plan_head: "[data-nav-zone='plan_head'] [data-nav-item]",
    plan_grid: "[data-nav-zone='plan_grid'] [data-nav-item]",
    plan_body: "[data-nav-zone='plan_body'] [data-nav-item]",
    // The picker's Download split menu — a GlassMenu list nested in `plan_body`, present only while open.
    plan_menu: "[data-nav-zone='plan_menu'] [data-nav-item]",
    // A page's toolbar (Library, Watchlist, Status, Apps, …).
    [Context.TOOLBAR]: "[data-nav-zone='toolbar'] [data-nav-item]",
    // The library toolbar's sort menu — a GlassMenu.menu_select list nested in the toolbar zone.
    library_sort_menu: "[data-nav-zone='library_sort_menu'] [data-nav-item]",
    // The Watchlist page's rows across its rung groups; a row's rung select
    // is its `[data-nav-sub-item]`, and the open list its own nested zone.
    watchlist_rows: "[data-nav-zone='watchlist_rows'] [data-nav-item]",
    watchlist_rung_menu: "[data-nav-zone='watchlist_rung_menu'] [data-nav-item]",
    // Watch history's rows, a row's Remove its `[data-nav-sub-item]`; the
    // pager and the empty states' buttons are items of the same tree.
    history_rows: "[data-nav-zone='history_rows'] [data-nav-item]",
    // The Apps add/edit modal: its controls, and the Steam picker's grid.
    apps_controls: "[data-nav-zone='apps_controls'] [data-nav-item]",
    apps_steam: "[data-nav-zone='apps_steam'] [data-nav-item]",
    sidebar: "[data-nav-zone='sidebar'] [data-nav-item]",
    sections: "[data-nav-zone='sections'] [data-nav-item]",
    // Settings → Controls: the binding table. A row is the item; its keycaps
    // and unbind buttons are its `[data-nav-sub-item]` controls, so RIGHT
    // steps into a row and UP/DOWN walk rows, not every control in turn.
    bindings: "[data-nav-zone='bindings'] [data-nav-item]",
    [Context.ZONE_TABS]: "[data-nav-zone='zone-tabs'] [data-nav-item]",
    // Social's Friends tab: person cards, each a poster strip over text
    // rows over a footer — arrangement carries the meaning, so geometry
    // answers adjacency (UIDR-038).
    people: "[data-nav-zone='people'] [data-nav-item]",
    // Friends under the cards: the hidden group's Show buttons, the add
    // form (key, name, Add friend), and the pointer to Settings → Social.
    hidden_people: "[data-nav-zone='hidden_people'] [data-nav-item]",
    add_friend: "[data-nav-zone='add_friend'] [data-nav-item]",
    friends_pointer: "[data-nav-zone='friends_pointer'] [data-nav-item]",
    feed: "[data-nav-zone='feed'] [data-nav-item]",
    person_rows: "[data-nav-zone='person_rows'] [data-nav-item]",
    person_view: "[data-nav-zone='person_view'] [data-nav-item]",
    // The Undo toast after an Ignore (`ActionToast`): its one action.
    undo_toast: "[data-nav-zone='undo_toast'] [data-nav-item]",
    // The Review modal's regions: the sentiment row, the words, the footer.
    review_choice: "[data-nav-zone='review_choice'] [data-nav-item]",
    review_text: "[data-nav-zone='review_text'] [data-nav-item]",
    review_footer: "[data-nav-zone='review_footer'] [data-nav-item]",
    profile_picker: "[data-nav-zone='profile_picker'] [data-nav-item]",
    // The viewing layer's track menu (a remote player's OSD): two columns,
    // each a GlassMenu list, walked as MENUs with left/right between them.
    viewing_audio: "[data-nav-zone='viewing_audio'] [data-nav-item]",
    viewing_subtitles: "[data-nav-zone='viewing_subtitles'] [data-nav-item]",
    "review-list": "[data-nav-zone='review-list'] [data-nav-item]",
    "review-detail": "[data-nav-zone='review-detail'] [data-nav-item]",
    // Episode mapping (/episode-mapping) — the same master/detail shape as review
    "episode-mapping-list": "[data-nav-zone='episode-mapping-list'] [data-nav-item]",
    "episode-mapping-detail": "[data-nav-zone='episode-mapping-detail'] [data-nav-item]",
    // Status page subsystem drill-in (vertical rail: close, incidents, logs)
    "drill-in": "[data-nav-zone='drill-in'] [data-nav-item]",
    // Home page shelves (horizontal media rows stacked vertically)
    hero: "[data-nav-zone='hero'] [data-nav-item]",
    continue: "[data-nav-zone='continue'] [data-nav-item]",
    recently: "[data-nav-zone='recently'] [data-nav-item]",
    coming_up: "[data-nav-zone='coming_up'] [data-nav-item]",
    // Discovery page shelves (campaign discovery.md): one SHELF per shelf,
    // stacked like Home's.
    out_now: "[data-nav-zone='out_now'] [data-nav-item]",
    new_releases: "[data-nav-zone='new_releases'] [data-nav-item]",
    friends: "[data-nav-zone='friends'] [data-nav-item]",
    watchlist: "[data-nav-zone='watchlist'] [data-nav-item]",
    // The search box at the top of Discovery and of Downloads (one page
    // renders one), then Downloads' single column: drafts → pursuits →
    // ledger; the ledger hosts the archive (chips + search).
    omnibox: "[data-nav-zone='omnibox'] [data-nav-item]",
    drafts: "[data-nav-zone='drafts'] [data-nav-item]",
    pursuits: "[data-nav-zone='pursuits'] [data-nav-item]",
    ledger: "[data-nav-zone='ledger'] [data-nav-item]",
    other_downloads: "[data-nav-zone='other_downloads'] [data-nav-item]",
    // Guide: chapter sidebar + on-this-page outline (both vertical link lists).
    guide_chapters: "[data-nav-zone='guide_chapters'] [data-nav-item]",
    guide_outline: "[data-nav-zone='guide_outline'] [data-nav-item]",
    // The console's footer actions (clear, copy, download, rescan).
    console_footer: "[data-nav-zone='console_footer'] [data-nav-item]",
  },

  // Instance → context type mapping
  instanceTypes: {
    sidebar: Context.MENU,
    sections: Context.MENU,
    viewing_audio: Context.MENU,
    viewing_subtitles: Context.MENU,
    bindings: Context.TREE,
    "review-list": Context.MENU,
    "review-detail": Context.MENU,
    "episode-mapping-list": Context.MENU,
    "episode-mapping-detail": Context.MENU,
    "drill-in": Context.MENU,
    // Home shelves behave as horizontal lists with a vertical nav graph
    hero: Context.SHELF,
    continue: Context.SHELF,
    recently: Context.SHELF,
    coming_up: Context.SHELF,
    out_now: Context.SHELF,
    new_releases: Context.SHELF,
    friends: Context.SHELF,
    watchlist: Context.SHELF,
    // Downloads' zones are vertical item lists (the home pages keep their
    // horizontal `coming_up` SHELF instance above).
    omnibox: Context.MENU,
    drafts: Context.MENU,
    pursuits: Context.MENU,
    ledger: Context.MENU,
    other_downloads: Context.MENU,
    guide_chapters: Context.MENU,
    guide_outline: Context.MENU,
    console_footer: Context.TOOLBAR,
    people: Context.SHELF,
    hidden_people: Context.TREE,
    add_friend: Context.TOOLBAR,
    friends_pointer: Context.TOOLBAR,
    undo_toast: Context.TOOLBAR,
    review_choice: Context.TOOLBAR,
    review_text: Context.TOOLBAR,
    review_footer: Context.TOOLBAR,
    // The Feed: a vertical list of rows, each with its verbs (List,
    // Download, Ignore) as sub-items — the bindings table's shape.
    feed: Context.TREE,
    // The person page: the back row and the rows as a tree (a row's verbs
    // are its sub-items), the reader's view a vertical walk of its rows
    // (the colour swatches one row, walked by RIGHT as its sub-items).
    person_rows: Context.TREE,
    person_view: Context.TREE,
    // The profile picker: tiles in a wrapping row plus the Add input over its button, so geometry answers adjacency.
    profile_picker: Context.SHELF,
    // The detail modal: a horizontal command row over a nesting list. The
    // Cast sub-view swaps the list for a photo grid, whose arrangement
    // carries the meaning — SHELF resolves it by geometry, which is what
    // walks the two grid sections and the Show more button without an
    // adjacency table.
    detail_actions: Context.TOOLBAR,
    // The social capsule in the hero's upper right (`Title.Social`): one
    // button above the action row; its panel holds no controls.
    detail_social: Context.TOOLBAR,
    // The finish prompt above the action row (UIDR-052): Review, Delete, Done.
    detail_finish: Context.TOOLBAR,
    // Whichever Download menu is open — the other planning mode, or the
    // scope — a short vertical list nested inside the action row.
    detail_menu: Context.TREE,
    detail_rail: Context.TOOLBAR,
    manage_tools: Context.TOOLBAR,
    manage_list: Context.TREE,
    detail_list: Context.TREE,
    detail_cast: Context.SHELF,
    // The Cast view's filter input, between the action row and the grid.
    detail_cast_filter: Context.TOOLBAR,
    // The tracking block under the detail list (UIDR-035, UIDR-042): the
    // two switch rows and the acceptance Reset stack vertically — UP/DOWN.
    detail_tracking: Context.TREE,
    detail_tracking_menu: Context.TREE,
    // The plan modal: two vertical lists around the episode grid. The grid's
    // arrangement carries its meaning (season rows, capsules for packs), so
    // it is a SHELF — geometry answers adjacency across wrapped rows and
    // capsule groups without an adjacency table.
    plan_head: Context.TREE,
    plan_grid: Context.SHELF,
    plan_body: Context.TREE,
    // The picker's open Download menu: the other planning mode, a short list nested in the body.
    plan_menu: Context.TREE,
    // The library sort menu, present only while open: a short list under the toolbar's Sort trigger.
    library_sort_menu: Context.TREE,
    // The Watchlist page: rows with their rung select as the sub-item (the
    // Feed's shape), and the open rung menu nested in a row.
    watchlist_rows: Context.TREE,
    watchlist_rung_menu: Context.TREE,
    // Watch history: rows with their Remove as the sub-item.
    history_rows: Context.TREE,
    // The Apps modal: a vertical walk of its controls around the Steam
    // picker, a three-column grid of banners resolved by geometry.
    apps_controls: Context.TREE,
    apps_steam: Context.SHELF,
  },

  // Overlays that navigate as several regions rather than one flat list.
  // Named by `data-nav-overlay` on the overlay element; anything without one
  // stays a flat MODAL, which is right for a confirm or a small form.
  //
  // The detail modal is its action row above the body of the title — seasons
  // and episodes for a series, the film list for a collection, extras for
  // anything. `entry` lands the cursor on the row (the finish prompt first
  // while shown); `back` is what makes BACK climb from the body to the row
  // before it closes the modal.
  // Only one body zone is in the DOM at a time (the sub-views swap it), so
  // the candidate list on `down` routes to whichever body is populated.
  //
  // Every region climbs on UP at its top — stopping dead under whatever sits
  // above read as a dead end each time it was tried (UIDR-019, twice
  // amended). The folder ledger's `up` climbs to the Manage toolbar card; a
  // spatial region (the cast grid) has a geometric
  // "above", and stopping dead under the action row reads as
  // a dead end.
  overlays: {
    detail: {
      entry: ["detail_finish", "detail_actions", "detail_menu", "detail_cast_filter", "detail_rail", "manage_tools", "manage_list", "detail_list", "detail_cast", "detail_tracking"],
      layout: {
        // detail_menu is whichever glass menu the action row has open —
        // an unowned title's Download mode or scope list — present only
        // while open. DOWN from the row enters it; BACK leaves it for the
        // row and, through the list's `data-nav-dismiss-event`, closes it.
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
        // detail_social is the social capsule in the hero's upper right,
        // above the row; its zone carries the panel's dismiss event while
        // the panel is open, so BACK closes the panel on the way down.
        detail_social: { down: ["detail_finish", "detail_actions"], back: ["detail_actions"] },
        // detail_finish is the finish prompt between the hero and the row,
        // present only after a finished movie; the entry region while shown.
        detail_finish: { up: ["detail_social"], down: ["detail_actions"] },
        detail_actions: {
          up: ["detail_finish", "detail_social"],
          down: ["detail_menu", "detail_cast_filter", "detail_rail", "manage_tools", "manage_list", "detail_list", "detail_cast", "detail_tracking"],
        },
        detail_menu: {
          up: ["detail_actions"],
          down: ["detail_rail", "manage_tools", "manage_list", "detail_list", "detail_cast", "detail_tracking"],
          back: ["detail_actions"],
        },
        // detail_cast_filter is the Cast view's filter input, under the
        // synopsis (or, with no synopsis column, inline above the grid):
        // the grid climbs to it, it climbs to the action row.
        detail_cast_filter: {
          up: ["detail_actions"],
          down: ["detail_rail", "detail_cast"],
          back: ["detail_actions"],
        },
        detail_rail: {
          up: ["detail_cast_filter", "detail_actions"],
          down: ["manage_tools", "manage_list", "detail_list", "detail_cast", "detail_tracking"],
          back: ["detail_actions"],
        },
        manage_tools: { up: ["detail_rail", "detail_actions"], down: ["manage_list"], back: ["detail_actions"] },
        manage_list: { up: ["manage_tools"], back: ["detail_actions"] },
        detail_list: { up: ["detail_rail", "detail_actions"], down: ["detail_tracking"], back: ["detail_actions"] },
        detail_cast: { up: ["detail_rail", "detail_cast_filter", "detail_actions"], back: ["detail_actions"] },
        // The tracking block follows the list (or stands alone in a
        // collection without extras); UP climbs back through the list.
        // detail_tracking_menu is the Caught up row's open season or
        // episode list (M16), nested in the card and present only while
        // open: DOWN from the card enters it, BACK returns to the card and,
        // through the list's `data-nav-dismiss-event`, closes it.
        detail_tracking: {
          up: ["detail_list", "detail_rail", "detail_actions"],
          down: ["detail_tracking_menu"],
          back: ["detail_actions"],
        },
        detail_tracking_menu: { up: ["detail_tracking"], back: ["detail_tracking"] },
      },
    },
    // The plan modal (UIDR-029). Regions stack vertically; a movie board has
    // no grid and the candidate lists fall through head ↔ body. The regions
    // declare no `back` edges: BACK dismisses from anywhere, as it did when
    // the modal was one flat list — they exist so the grid can be walked
    // spatially, not to add depth. The one exception is `plan_menu`, the
    // picker's open Download menu, a glass list nested in the body and
    // present only while open: DOWN from the body enters it, BACK returns to
    // the body and, through the list's `data-nav-dismiss-event`, closes it.
    // The modal opens on a loading stage with no controls; the orchestrator
    // enters the first region that populates.
    plan: {
      entry: ["plan_head", "plan_body", "plan_grid"],
      layout: {
        plan_head: { down: ["plan_grid", "plan_body"] },
        plan_grid: { up: ["plan_head"], down: ["plan_body"] },
        plan_body: { up: ["plan_grid", "plan_head"], down: ["plan_menu"] },
        plan_menu: { up: ["plan_body"], back: ["plan_body"] },
      },
    },
    // The Review modal: the sentiment row (LEFT/RIGHT along Dislike, Like,
    // Love) over the words over the footer (Remove review, Cancel, Share).
    // No `back` edges, so BACK is Cancel from any region, as it was when the
    // modal was one flat list.
    review: {
      entry: ["review_choice", "review_text", "review_footer"],
      layout: {
        review_choice: { down: ["review_text"] },
        review_text: { up: ["review_choice"], down: ["review_footer"] },
        review_footer: { up: ["review_text"] },
      },
    },
    // The Apps add/edit modal: the Steam picker grid is its own region,
    // walked by geometry, between the controls above it (close, the
    // Steam/Manual tabs) and nothing below; the manual form and the edit
    // form are the controls region alone. The cursor opens on the picker
    // when it shows. No back edges: BACK closes the modal from anywhere.
    apps_modal: {
      entry: ["apps_steam", "apps_controls"],
      layout: {
        apps_controls: { down: ["apps_steam"] },
        apps_steam:    { up: ["apps_controls"] },
      },
    },
    // The viewing layer's track menu: Audio beside Subtitles, LEFT/RIGHT
    // between them, no back edges so BACK closes the menu from either.
    // The cursor opens on Subtitles, the desktop menu's rule.
    viewing_menu: {
      entry: ["viewing_subtitles", "viewing_audio"],
      layout: {
        viewing_audio: { right: ["viewing_subtitles"] },
        viewing_subtitles: { left: ["viewing_audio"] },
      },
    },
  },

  // Contexts entered at a declared item when there is no position to return to.
  // The detail body opens on the episode Play would play — the same row the
  // panel scrolls to and marks as next up, so the cursor agrees with both.
  // The rail enters at the selected member's tile — the cursor agrees
  // with the panel's subject.
  // The action row of a title you do not own enters on the Download split's
  // menu toggle, beside Download: a stray SELECT opens a menu instead of
  // starting a whole-title download. An owned title has no such toggle and
  // enters on Play.
  // Manage's toolbar card leads with Delete all (the card's layout); it
  // enters on Refresh from TMDB, the first tool that changes nothing you
  // keep.
  entryDefaults: {
    detail_list: "[data-resume-target]",
    detail_rail: "[data-selected]",
    detail_actions: "#detail-download-toggle",
    manage_tools: "#manage-refresh-from-tmdb",
  },

  // Zone layouts for nav graph. No content context carries a left edge to the
  // sidebar: reaching the main menu is BACK's job (see `_backTransition`), and
  // LEFT stays lateral movement within the page. Each layout still declares a
  // sidebar node with its `right` candidates — its presence is what tells BACK
  // the page has a main menu, and the candidates are where exiting it lands.
  layouts: {
    library: {
      toolbar:           { down: ["library_sort_menu", "grid"] },
      // The open sort menu, nested in the toolbar: BACK leaves it for the
      // toolbar and, through its `data-nav-dismiss-event`, closes it.
      library_sort_menu: { up: ["toolbar"], back: ["toolbar"] },
      grid:              { up: ["toolbar"] },
      sidebar:           { right: ["grid", "toolbar"] },
    },
    settings: {
      sections:  { right: ["grid"] },
      // The Controls section nests a bindings tree under the grid's last
      // control (the glyph choice); every other section leaves it empty, so
      // the candidate list makes DOWN a wall there. No left edge: LEFT in a
      // tree is depth (back out of a row's controls), never lateral.
      grid:      { left: ["sections"], down: ["bindings"] },
      bindings:  { up: ["grid"] },
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
    // (/episode-mapping) — share the ReviewTabs strip and the same master/detail
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
    "episode-mapping": {
      zone_tabs:          { down: ["episode-mapping-list", "episode-mapping-detail"] },
      "episode-mapping-list":   { up: ["zone_tabs"], right: ["episode-mapping-detail"] },
      "episode-mapping-detail": { up: ["zone_tabs"], left: ["episode-mapping-list"] },
      sidebar:            { right: ["episode-mapping-list", "episode-mapping-detail", "zone_tabs"] },
    },
    // Downloads: the release search box on top, then the zone tabs
    // (Activity | History) — one tab's content renders at a time, so the
    // candidate lists do the routing: Activity shows drafts → pursuits →
    // other_downloads; History shows its toolbar (chips + search) over the
    // ledger's rows.
    // While a search owns the page the tabs recede and only "grid" (the
    // result groups, carrying their own Clear) sits below the box. The
    // History toolbar renders with the tab, so the archive stays reachable
    // when a filter empties the ledger.
    downloads: {
      omnibox:         { down: ["grid", "zone_tabs", "drafts", "pursuits", "toolbar", "ledger"] },
      grid:            { up: ["omnibox"] },
      zone_tabs:       { up: ["omnibox"], down: ["drafts", "pursuits", "toolbar", "ledger", "other_downloads"] },
      drafts:          { up: ["zone_tabs", "omnibox"], down: ["pursuits", "other_downloads"] },
      pursuits:        { up: ["drafts", "zone_tabs", "omnibox"], down: ["other_downloads"] },
      // History: the filter chips and the search, one horizontal row, over
      // the ledger's rows.
      toolbar:         { up: ["zone_tabs", "omnibox"], down: ["ledger"] },
      ledger:          { up: ["toolbar", "zone_tabs", "omnibox"] },
      other_downloads: { up: ["pursuits", "drafts", "zone_tabs"] },
      sidebar:         { right: ["pursuits", "ledger", "toolbar", "zone_tabs", "omnibox"] },
    },
    // Watch history: the filters over the rows tree (pager and empty
    // states included). The heatmap is not a nav zone.
    watch_history: {
      toolbar:      { down: ["history_rows"] },
      history_rows: { up: ["toolbar"] },
      sidebar:      { right: ["history_rows", "toolbar"] },
    },
    // Watchlist: the filter and search over the rows (one TREE across the
    // rung groups); a row's open rung menu is nested in it, BACK closing
    // it through its `data-nav-dismiss-event`. The empty states carry the
    // rows' zone so their button is reachable.
    watchlist: {
      toolbar:             { down: ["watchlist_rows"] },
      watchlist_rows:      { up: ["toolbar"], down: ["watchlist_rung_menu"], right: ["undo_toast"] },
      watchlist_rung_menu: { up: ["watchlist_rows"], back: ["watchlist_rows"] },
      // The Undo toast after an Ignore: RIGHT from the rows reaches it while
      // it shows; LEFT, DOWN or BACK return to the rows.
      undo_toast:          { left: ["watchlist_rows"], down: ["watchlist_rows"], back: ["watchlist_rows"] },
      sidebar:             { right: ["watchlist_rows", "toolbar"] },
    },
    // Social: the zone-tabs strip, with the Feed's scope control (a
    // `toolbar`) to its right, above one body — the Feed's rows on Feed; on
    // Friends the person cards over the hidden group, the add form and the
    // Settings pointer; on a person page the rows beside the reader's view.
    // The Feed's rail of people is not a nav zone. The Undo toast after an
    // Ignore is reached by RIGHT from the rows.
    social: {
      zone_tabs:       { right: ["toolbar"], down: ["feed", "people", "hidden_people", "add_friend", "person_rows", "person_view"] },
      toolbar:         { left: ["zone_tabs"], down: ["feed"] },
      feed:            { up: ["zone_tabs"], right: ["undo_toast"] },
      people:          { up: ["zone_tabs"], down: ["hidden_people", "add_friend"] },
      hidden_people:   { up: ["people", "zone_tabs"], down: ["add_friend"] },
      add_friend:      { up: ["hidden_people", "people", "zone_tabs"], down: ["friends_pointer"] },
      friends_pointer: { up: ["add_friend"] },
      person_rows:     { up: ["zone_tabs"], down: ["person_view"], right: ["undo_toast", "person_view"] },
      person_view:     { up: ["person_rows", "zone_tabs"], left: ["person_rows"] },
      undo_toast:      { left: ["feed", "person_rows"], down: ["feed", "person_rows"], back: ["feed", "person_rows"] },
      sidebar:         { right: ["feed", "people", "hidden_people", "add_friend", "person_rows", "person_view", "zone_tabs"] },
    },
    apps: {
      toolbar: { down: ["grid"] },
      grid:    { up: ["toolbar"] },
      sidebar: { right: ["grid", "toolbar"] },
    },
    // Console: the header (scope links, component chips, level, search) over
    // the log view — not navigable; it follows its live edge, and End holds
    // or resumes it — over the footer actions.
    console: {
      toolbar:        { down: ["console_footer"] },
      console_footer: { up: ["toolbar"] },
      sidebar:        { right: ["toolbar", "console_footer"] },
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
    // Discovery: Home's construction over the titles you do not own yet —
    // the omnibox over the hero over a vertical stack of horizontal shelves:
    // Out Now, New Releases, Reviewed by Friends, the Watchlist grouped row
    // (campaign discovery.md). Candidate lists skip shelves the page did
    // not render; while a query owns the page only the omnibox and the
    // results' toolbar and grid exist.
    discovery: {
      omnibox:      { down: ["hero", "out_now", "new_releases", "friends", "watchlist", "toolbar", "grid"] },
      hero:         { up: ["omnibox"], down: ["out_now", "new_releases", "friends", "watchlist"] },
      out_now:      { up: ["hero", "omnibox"], down: ["new_releases", "friends", "watchlist"] },
      new_releases: { up: ["out_now", "hero", "omnibox"], down: ["friends", "watchlist"] },
      friends:      { up: ["new_releases", "out_now", "hero", "omnibox"], down: ["watchlist"] },
      watchlist:    { up: ["friends", "new_releases", "out_now", "hero", "omnibox"] },
      // While a query owns the page: the results' chips and rows.
      toolbar:      { up: ["omnibox"], down: ["grid"] },
      grid:         { up: ["toolbar", "omnibox"] },
      sidebar:      { right: ["hero", "out_now", "new_releases", "friends", "watchlist", "grid", "toolbar", "omnibox"] },
    },
    // Setup tour: a sidebar-less first-run wizard. The `grid` context holds
    // the whole step card (form fields + footer buttons); up/down walks it
    // linearly, SELECT activates a button or edits a field. Above it, the
    // `toolbar` holds Skip the tour — the wizard's exit, absent on the summary.
    setup: {
      toolbar: { down: ["grid"] },
      grid:    { up: ["toolbar"] },
    },
    // Profile picker: one geometry-resolved zone of tiles and the add
    // form. The sidebar is on the page only on a switch (the picker inside
    // the shell); at the door it is absent, so its node is too, and BACK
    // does nothing — or leaves the app on the TV.
    profiles: {
      profile_picker: {},
      sidebar:        { right: ["profile_picker"] },
    },
  },

  // Cursor start priority per zone
  cursorStartPriority: {
    library:   ["grid", "toolbar", "sidebar"],
    settings:  ["sections", "grid", "bindings", "sidebar"],
    guide:     ["guide_chapters", "guide_outline", "sidebar"],
    status:    ["grid", "toolbar", "sidebar"],
    review:    ["review-list", "review-detail", "zone_tabs", "sidebar"],
    "episode-mapping": ["episode-mapping-list", "episode-mapping-detail", "zone_tabs", "sidebar"],
    downloads:  ["pursuits", "ledger", "toolbar", "zone_tabs", "omnibox", "sidebar"],
    watch_history: ["history_rows", "toolbar", "sidebar"],
    watchlist: ["watchlist_rows", "toolbar", "sidebar"],
    social: ["feed", "people", "hidden_people", "add_friend", "person_rows", "person_view", "toolbar", "zone_tabs", "sidebar"],
    apps: ["grid", "toolbar", "sidebar"],
    console: ["toolbar", "console_footer", "sidebar"],
    home:      ["hero", "continue", "recently", "coming_up", "sidebar"],
    discovery: ["hero", "out_now", "new_releases", "friends", "watchlist", "grid", "toolbar", "omnibox", "sidebar"],
    setup:     ["grid", "toolbar"],
    profiles:  ["profile_picker", "sidebar"],
  },

  // Always-populated contexts (skip item count check). Not the sidebar: the
  // shell renders it on every page but the profile door and the setup tour,
  // and its count is what tells BACK whether the page has a main menu.
  alwaysPopulated: ["sections", "guide_chapters"],

  // Contexts that are always entered at one specific item, whatever the user
  // last touched there. Reserved for zones that exist to be entered at a
  // single action — the home hero is "press play", so arriving from any
  // direction lands on Play rather than on whichever CTA was focused last.
  // Applies on entry only; a post-patch focus reconcile leaves the cursor
  // where it is.
  entryAnchors: { hero: 0 },

  // Markers of a context's current selection, for focus restoration on
  // entry: the current page, tab or section, and the chosen option of a
  // segmented control — the only pick-one group the input system restores
  // to its chosen option on entry. The marker is scoped to it because
  // `aria-pressed` on other nav items also marks independent toggles (the
  // title modal's List, a plan-grid cell), which must never be an entry
  // target.
  activeMarkers: [
    ".sidebar-link-active", ".zone-tab-active", ".menu-item-active", ".glass-menu-item-active",
    ".segmented-control [aria-pressed='true']",
  ],

  // Primary menu instance (has special enter/exit behavior)
  primaryMenu: "sidebar",

  // Page behavior factory
  createBehavior: createPageBehavior,
}
