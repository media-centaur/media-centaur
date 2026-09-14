# Nav overlay inventory (subagent report, 2026-09-14)

## 1a. Overlays (config.js:159)
| Overlay | entry | Zone | up | down | back | Line |
|---|---|---|---|---|---|---|
| detail | [detail_actions, detail_rail, manage_tools, manage_list, detail_list, detail_cast, detail_tracking] (161) | detail_actions | — | [detail_rail, manage_tools, manage_list, detail_list, detail_cast, detail_tracking] | — | 176-178 |
| | | detail_rail | [detail_actions] | [manage_tools, manage_list, detail_list, detail_cast, detail_tracking] | [detail_actions] | 179-183 |
| | | manage_tools | [detail_rail, detail_actions] | [manage_list] | [detail_actions] | 184 |
| | | manage_list | [manage_tools] | — | [detail_actions] | 185 |
| | | detail_list | [detail_rail, detail_actions] | [detail_tracking] | [detail_actions] | 186 |
| | | detail_cast | [detail_rail, detail_actions] | — | [detail_actions] | 187 |
| | | detail_tracking | [detail_list, detail_rail, detail_actions] | — | [detail_actions] | 190 |
| title_detail | [title_detail_body, title_detail_menu, title_detail_tracking] (212) | title_detail_body | — | [title_detail_menu, title_detail_tracking] | — | 214 |
| | | title_detail_menu | [title_detail_body] | [title_detail_tracking] | [title_detail_body] | 218 |
| | | title_detail_tracking | [title_detail_menu, title_detail_body] | — | — | 219 |

No left/right edges in either. detail_actions and title_detail_body have no back edge → BACK falls to DISMISS (focus_context.js:177).

## 1b. Per zone
| Zone | instanceTypes | contextSelectors | alwaysPopulated | entryDefaults |
|---|---|---|---|---|
| detail_actions | TOOLBAR (112) | [data-nav-zone='detail_actions'] [data-nav-item] (21) | no | none |
| detail_rail | TOOLBAR (113) | (22) | no | [data-selected] |
| manage_tools | TOOLBAR (114) | (23) | no | none |
| manage_list | TREE (115) | (24) | no | none |
| detail_list | TREE (116) | (25) | no | [data-resume-target] |
| detail_cast | SHELF (117) | (26) | no | none |
| detail_tracking | TREE (120) | (27) | no | none |
| title_detail_body | TOOLBAR (130) | (36) | no | none |
| title_detail_menu | TREE (133) | (37) | no | none |
| title_detail_tracking | TREE (137) | (38) | no | none |

alwaysPopulated = [sidebar, sections, guide_chapters] (372); entryAnchors {hero: 0} (380); cursorStartPriority (355-369) page zones only — overlay regions resolved by `entry`. Context.MODAL selector `[data-detail-mode='modal'] [data-nav-item]` (17); dom_adapter overrides MODAL item queries to activeModalElement().querySelectorAll("[data-nav-item]") (dom_adapter.js:74-77). config.js:18-20: closed modal is visibility:hidden so items count zero. No behavior references any of the ten zones.

## 2. Template side (selected)
- detail_panel.ex:325-327: data-detail-mode, data-detail-nested (DL.nested_view?/2 logic.ex:445-446), data-nav-overlay="detail"; :318 → cinematic_shell.ex:114 → modal.ex:75 data-dismiss-event={@on_close} ("close_detail", entity_modal.ex:1049).
- detail_panel.ex:482 div data-nav-zone="detail_cast" (@detail_view == :cast); :508 data-nav-zone="detail_list" (default view); :659 #detail-tracking data-nav-zone="detail_tracking".
- detail_panel.ex:412-425 member watched toggle on Play line → PlayableRow.watched_toggle nav_item (playable_row.ex:135) in detail_actions.
- play_card.ex:40 data-nav-zone="detail_actions" + :41 data-nav-enter-scroll-top; :49 Play button data-nav-item data-entity-id={@target_id}; :53-63 Offline button no data-nav-item; :64 render_slot(@controls) inside zone.
- view_controls.ex:157 Review (#detail-review, :if review? && tmdb_id && type in [movie, tv_series]) data-nav-item; :172 Manage toggle (no :if) data-nav-item aria-pressed; :195 view_button data-nav-item; bookmark watchlist_toggle.ex:60 data-nav-item aria-pressed.
- collection_rail.ex:59 .row-scroll data-nav-zone="detail_rail"; :99 tile data-selected; :100 data-nav-item.
- manage_panel.ex:154 data-nav-zone="manage_tools"; :163 Delete all; :184 Cancel; :196 Rematch (:if tmdb_ready); :208 Refresh artwork; :514 external-id <a> data-nav-item; :231 ledger data-nav-zone="manage_list"; :234 → lower_quality_note.ex:58 Reset; :312 file-group data-nav-group; :318 head aria-expanded; :319 data-nav-item; :349 folder delete data-nav-sub-item; :453 per-file delete data-nav-item; :274 → subtitles_row.ex:68; :278 → track_override_badge.ex:45.
- season_list.ex:115 "Download more of this show" link data-nav-item (:if series_tmdb_id && acquisition?); :167 season section data-nav-group; :171 head aria-expanded; :173 data-nav-item; :312 episode row data-resume-target; :315 data-nav-item; :336 details toggle data-nav-sub-item; :338 aria-expanded; :407 missing row data-nav-item={@actionable}; :446/:480 in-flight/upcoming rows deliberately no nav item.
- extras_section.ex:82 extra row data-nav-item; :87 → playable_row.ex:134 watched toggle data-nav-sub-item.
- cast_panel.ex:268-269 Show more data-nav-item data-nav-return-focus; :306-307 linked person <a> data-nav-item data-nav-focus-target; :310 photo data-nav-focus-ring; :325-326 unlinked card; :329.
- detail_panel.ex:668 → tracking_controls.ex:143 switch row (role=switch, aria-checked, aria-disabled) data-nav-item in detail_tracking.
- title/detail_modal.ex:110 → modal.ex:75 data-dismiss-event="close_title"; :115 data-nav-overlay="title_detail"; :116 explicit data-dismiss-event="close_title" (duplicate); no data-detail-nested anywhere.
- title/detail_modal.ex:153 action strip data-nav-zone="title_detail_body"; :160 #title-watchlist (no :if) data-nav-item; :174 #title-review (:if review?); :265 #title-in-library; :279 #title-needs-review; :301-319 → glass_menu.ex:112 split main #title-download data-nav-item; :128,130 chevron #title-download-toggle aria-expanded data-nav-item; glass_menu.ex:53 <ul> #title-download-menu (:if open) data-nav-zone="title_detail_menu"; :54 data-nav-dismiss-event="title_menu_close"; :64 <li role=menuitem> data-nav-item; :320-339 → glass_menu.ex:189,191 scope trigger #title-scope (:if scoped?); #title-scope-menu same zone/dismiss.
- title/detail_modal.ex:210 tracking card data-nav-zone="title_detail_tracking" (:if tracking_block?); :217 switch rows; :229 Reset; :360 #title-activity-delete (:if own?) data-nav-item.
- cinematic_shell.ex:95,119 attr :rest global spread onto .modal; :205-207 #-content data-scroll-key/data-view/data-scroll-to-resume (DetailBodyScroll).
- modal.ex:74 data-detail-mode={@open && @on_close && "modal"}; :75 data-dismiss-event; :76-78 phx-window-keydown Escape — never fires under input system (keyboard.js:162-165 preventDefault+stopPropagation).
Absent everywhere: data-nav-reveal, data-nav-reveal-block, data-nav-action, data-nav-defer-activate.

## 3. Skip-absent-zone
- Counts: orchestrator.js:359 _buildCounts; 506-513 every contextSelectors key → getItemCount. Item query dom_adapter.js:74-82 (isNavigable = not disabled && checkVisibility(); ownedByScope 58-62). Absent zone counts 0.
- Overlay open orchestrator.js:366-376: entry = _overlayEntry(overlay); region memory wiped; presentationChanged("modal", entry); rAF focusFirst(entry).
- _overlayEntry 502-505: `entry.find(region => counts[region] > 0) ?? Context.MODAL` — YES, absent/empty zones skipped; fallback flat MODAL. Does not consult alwaysPopulated.
- Re-resolution 377-387: if presentation modal && overlay && !_inOverlayRegion → re-resolve entry on every patch until a region populates; once in a region, no re-entry (test :3303).
- Directional: nav_graph.js:35 layout = {...layouts[zone], ...overlayLayout}; 40-52 resolveFirst per edge; isPopulated 73-76 — YES graph skips empty zones; rebuilt every _syncState (393-399).
- Absent layout zone gets a graph node (nav_graph.js:44) but unreachable; harmless.
- GAP (code reading): if region holding cursor empties by a patch (title_detail_menu closed by phx-click-away glass_menu.ex:104/181; manage_list emptied by Delete all), _ensureCursorStart (195-217) resolves the PAGE priority and focuses behind the modal for one patch; healed next patch by 377-387. Comment 380-382 acknowledges.
- Entry tails unreachable at first open: detail_actions (Manage toggle no :if) and title_detail_body (bookmark no :if) always ≥1 item.
Tests: orchestrator.test.js:3277, 3287, 3303, 3715; index.test.js:353, 403.

## 4. Dismiss / BACK
- keyboard.js:158-166 preventDefault/stopPropagation; actions.js:58 Escape → BACK. focus_context.js:124 BACK → _backTransition; 164-181: back edge → enter_context(back); sub-focus exit; overlay → DISMISS; primary-menu rungs.
- orchestrator.js:698-705 back edge pushes zone's data-nav-dismiss-event (dom_adapter.js:396-401, FIRST [data-nav-zone='X'] element). No detail zone declares one (test :3427).
- _executeDismiss 1230-1253: 1236 isDetailNested → pushEvent("close_detail") HARD-CODED, _pendingModalRefocus = true; 1244 else pushEvent(getDismissEvent() ?? "close_detail"); 1248 presentationChanged(null); 1249 _restoreOriginFocus.
- dom_adapter.js:24-26 activeModalElement = first [data-detail-mode='modal']; 370-372 isDetailNested; 379-381 getOverlayName; 387-389 getDismissEvent.
- _pendingModalRefocus consumed 471-476 in _reconcileFocus → focusFirst(_overlayEntry(...)).
- _expectedPresentation guard 362-365, 199.
- Server: entity_modal.ex:128-132 close_detail → close_detail_target 1338-1346 (server decides close vs return; client flag only selects side effects). title_detail_host.ex:483 close_title → push_close 638; title_menu_close → open_menu nil.
- Backdrop click modal.ex:76 phx-click bypasses orchestrator; _syncState 388-391 handles.

## 5. Tests
- orchestrator.test.js: 288, 581, 1220, 1559, 1583, 1611, 3277, 3287, 3303, 3362, 3375, 3388, 3403, 3427, 3472, 3486, 3507, 3522, 3573-3640, 3715, 3726-3756, 3772, 3804, 3828, 3859, 3887, 3983, 3995, 4014, 4026.
- focus_context.test.js: 752, 757, 767, 777, 828-840, 844, 856-870.
- dom_adapter.test.js: 755, 768, 780, 874, 898, 911, 919.
- index.test.js (real config): 228 (detail_tracking TREE; name says toolbar), 238, 244, 253, 258, 324, 335, 341, 347, 353, 360, 383, 389, 397, 403, 409.
- discovery_behavior.test.js:30 — toEqual the whole overlays.title_detail object + three selectors.
- test/e2e/library.spec.js: 199, 208, 226 (data-nav-context detail_actions; BACK → grid; DOWN → /^detail_/).
- library_live_test.exs: 714-719, 750, 762-763, 774, 799, 991-999, 1084-1102, 1161-1182, 1283-1290 (markup contract).
- entity_modal_tracking_test.exs:64 #detail-tracking[data-nav-zone='detail_tracking']; discovery_live_test.exs:794 no title_detail_tracking items when not listed.

## 6. Hint bar / other consumers
- dom_adapter.js:650-651 setNavContext writes instance name. root.html.heex:137-176 hint bar groups (grid, modal, drawer, sidebar, menu, shelf); app.css:2472-2521 mapping — NONE of the ten overlay zones appear → no legend while in overlay regions; only flat MODAL shows Close/Play.
- glass_menu.ex:10-20 moduledoc documents nested-zone + dismiss contract. docs/input-system.md:308, 351-360, 385, 452.
- Other data-nav-overlay: acquisition/plan_modal.ex:189-191 (plan). Other data-detail-mode: modal.ex:74, pursuit_modal.ex:97-98, issue_view.ex:30.

## Discrepancies
- title_detail_tracking documented TOOLBAR (docs/input-system.md:308) but configured TREE (config.js:137); index.test.js:228 name says toolbar, asserts TREE.
- Duplicate attrs on both roots (data-detail-mode detail_panel.ex:325 + modal.ex:74; data-dismiss-event detail_modal.ex:116 + modal.ex:75).
- Cursor can leak to the page for one patch when the region holding it empties (not runtime-verified).
- Hint bar has no legend for any overlay region.
- Entry tails unreachable at first open.
- Offline Play placeholder not focusable (play_card.ex:53-63).
