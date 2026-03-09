# Unified Library Redesign — Implementation Plan

## Context

The library page is being redesigned from a flat alphabetical grid with a narrow side drawer into a two-zone vertical layout: **Continue Watching** (top, default landing) and **Library Browse** (below), with a shared detail system that renders as a centered modal or right-docked drawer depending on context. A unified input system makes mouse, keyboard, and gamepad first-class.

This plan sequences the work from plans 003–006 into a single implementation order with dependency awareness.

**Source plans:** `003-continue-watching-design.md`, `004-library-browse-design.md`, `005-input-system-design.md`, `006-unified-detail-system.md`

---

## What Exists Today

- `library_live.ex` (1025 lines): monolithic LiveView with inline `defp` components
- 360px sticky right drawer with entity details, episode/movie lists
- Poster grid: `repeat(auto-fill, minmax(135px, 1fr))`, constrained by `max-w-7xl`
- Tabs: All / Movies / TV (no counts, no Collections)
- Text filter with debounce
- URL params: `?tab=`, `?selected=`, `?filter=`
- Stream-based rendering (`phx-update="stream"`)
- PubSub: `"library:updates"` and `"playback:events"` subscriptions
- `ResumeTarget` computed on progress updates but **discarded** (line ~186)
- No keyboard/gamepad spatial navigation
- No backdrop cards, no modal, no zone transitions

**Data layer (unchanged, reused as-is):**
- `LibraryBrowser.fetch_entities/0`, `fetch_entries_by_ids/1`, `play/1`
- `ProgressSummary.compute/2`, `Resume.resolve/2`, `ResumeTarget.compute/2`
- `WatchProgress`, `Entity`, `Season`, `Episode`, `Movie`, `Image` resources
- `EpisodeList`, `MovieList`, `Resolver` helpers

---

## Legacy Removal Strategy

The current drawer and card rendering in `library_live.ex` lines ~306–822 will be **replaced, not extended**. These are all private `defp` functions with no external callers:

| Current Code | Replacement |
|-------------|-------------|
| `defp entity_card/1` (306–362) | Two new card types: backdrop card (CW) + poster card (Library) |
| `defp card_progress/1` (364–403) | Progress bar on cards + ProgressSummary in DetailPanel |
| `defp render_drawer/1` (405–722) | DetailPanel component in DrawerShell/ModalShell |
| `defp episode_row/1` (725–773) | Episode rows inside DetailPanel |
| `defp movie_row/1` (775–822) | Movie rows inside DetailPanel |

**Safe removal approach:**
1. Build new components alongside old ones (new files, not inline `defp`)
2. Switch the `render/1` function to use new components
3. Delete old `defp` functions only after new render is working
4. Run `mix precommit` at each phase boundary

**URL params:** `?selected=` stays (maps to `@selected_entity_id`). Add `?zone=cw|library` if needed for deep linking. `?tab=` and `?filter=` stay, extended with `?sort=`.

---

## Implementation Phases

> **Progress:** Phases 1–4 complete. Phase 5a (keyboard spatial nav) complete.
> Phase 5b (gamepad) pending. See `docs/input-system.md` for Phase 5 architecture.

### Phase 1: DetailPanel Component (shared foundation)

**Why first:** Both zones depend on this. It's a pure function component with no shell dependency — testable in isolation.

**Files:**
- Create `lib/media_centaur_web/components/detail_panel.ex`

**Work:**
- Extract entity detail rendering from current drawer `defp` functions into a standalone function component
- Three variants based on entity type:
  - **TV Series:** Hero (21:9 backdrop, logo, gradient) → progress summary + resume button → metadata row → collapsible season/episode list with watched/current/unwatched styling
  - **Movie Series:** Hero → metadata → movie list with poster thumbnails and individual play buttons
  - **Standalone Movie:** Hero → metadata → description only
- Accepts assigns: `entity`, `progress`, `resume`, `on_play`, `on_close`
- Episode list: auto-expand current season, auto-scroll to ~2 episodes above current
- All event handling via configurable event names (so modal and drawer can use different handlers)

**Test approach:**
- Render tests for each variant with factory-built entities (no DB needed for component rendering)
- Verify correct variant selection by entity type
- Verify season expand/collapse logic
- Verify progress display formatting

**Data reuse:**
- `ProgressSummary.compute/2` → progress assign
- `ResumeTarget.compute/2` → resume assign
- Entity with associations → entity assign (already loaded by `LibraryBrowser`)

---

### Phase 2: Shell Components (ModalShell + DrawerShell)

**Why second:** These are the presentation wrappers. DetailPanel content is ready; now wrap it.

**Files:**
- Create `lib/media_centaur_web/components/modal_shell.ex`
- Create `lib/media_centaur_web/components/drawer_shell.ex`
- Add CSS to `assets/css/app.css`

**ModalShell:**
- Fixed centered overlay
- Backdrop: `oklch(0% 0 0 / 0.7)` + `backdrop-filter: blur(4px)`
- Panel: `width: min(600px, 92vw)`, `max-height: 90vh`, rounded
- Focus trap (grid inert behind backdrop)
- Entrance animation: `scale(0.96) translateY(8px)` → identity, 200ms
- Dismiss: Escape / click-outside / close button
- Renders DetailPanel inside

**DrawerShell:**
- `position: sticky; top: 0; right: 0; max-height: 100vh; overflow-y: auto`
- Width: 480px, flush with viewport edge (no border-radius)
- No backdrop — grid remains visible and interactive
- Split focus with grid (not a focus trap)
- Entrance: `translateX(100%)` → `translateX(0)`, 200ms
- Content swap: ~150ms cross-fade when switching entities
- Dismiss: Escape / close button
- Renders DetailPanel inside

**Test approach:**
- Render tests verifying shell markup, dismiss behavior
- Verify focus trap attribute (`inert`) on ModalShell
- Verify drawer width and positioning classes

---

### Phase 3: Two-Zone Page Structure + Continue Watching

**Why third:** With detail components ready, build the first zone. This is the default landing spot.

**Files:**
- Modify `lib/media_centaur_web/live/library_live.ex` — new render structure, new assigns
- Modify `lib/media_centaur_web/components/layouts.ex` — remove `max-w-7xl` for library route
- Add CSS to `assets/css/app.css`

**Work:**

3a. **Page structure:**
- Replace single-zone render with two-zone vertical layout
- Continue Watching zone at top (default landing)
- Library zone below
- Edge hint divider: `── ↓ Library · N titles ──`
- New assigns: `@selected_entity_id`, `@detail_presentation` (`:modal` | `:drawer`)
- Keep `ResumeTarget` from PubSub updates (currently discarded at line ~186)

3b. **In-progress entity filter:**
- Filter entities where `Resume.resolve/2` returns `:resume` or `:play_next` (not `:restart`, not `nil`)
- Store as separate assign for the CW zone
- If empty: brief empty state message prompting to browse library

3c. **Continue Watching cards:**
- Large horizontal 16:9 backdrop cards in auto-fill grid (`minmax(480px, 1fr)`)
- Backdrop image full-bleed, logo overlay bottom-left (text fallback)
- Bottom gradient with episode info (`S1 E7 — Episode Name`) and resume label (`Resume at 26:24`)
- Progress bar at bottom edge (4px, primary color)
- Click → opens detail modal (DetailPanel in ModalShell)
- Double-click → smart play via `LibraryBrowser.play/1`

3d. **Remove `max-w-7xl` for library page:**
- Grid fills full available width

**Test approach:**
- Test in-progress entity filtering logic (pure function, factory entities)
- Test CW assign computation from entity list
- Test `handle_event` for `"select_entity"` setting `@detail_presentation` to `:modal` when from CW zone
- LiveView integration: verify CW cards render for entities with active progress

**Legacy removal (Phase 3):**
- Old `defp entity_card/1` still used by Library zone — don't remove yet
- Old drawer `defp` functions — don't remove yet (Library zone still needs them temporarily)

---

### Phase 4: Library Browse Zone

**Why fourth:** CW zone is done. Now replace the existing library grid with the redesigned version.

**Files:**
- Modify `lib/media_centaur_web/live/library_live.ex` — library zone render, toolbar, drawer layout
- Add CSS to `assets/css/app.css`

**Work:**

4a. **Toolbar:**
- Type tabs (boxed-tab style): All | Movies | TV | Collections — each with count badge
- Sort dropdown: Recently Added (default, by `inserted_at`) / A-Z / Year
- Text filter (existing, repositioned right-aligned)

4b. **Poster grid:**
- `repeat(auto-fill, minmax(155px, 1fr))`, no max-width cap
- Poster cards: 2:3 aspect ratio, progress bar (3px), footer (name + subtitle)
- Grid shrinks to `calc(100% - 480px)` when drawer is open

4c. **Card → drawer interaction:**
- Click / Enter → opens DrawerShell (or swaps content with cross-fade if already open)
- Focus moves into drawer on open/swap
- Double-click → smart play of focused card (not drawer entity)

4d. **Responsive fallback:**
- Below `lg` breakpoint: drawer becomes ModalShell instead

**Test approach:**
- Test sort logic (recently added, A-Z, year) as pure functions
- Test type filtering with counts
- Test `handle_event` for sort change, tab switch
- Test `@detail_presentation` set to `:drawer` for library zone, `:modal` below lg

**Legacy removal (Phase 4) — now safe:**
- Delete old `defp entity_card/1`, `defp card_progress/1`
- Delete old `defp render_drawer/1` and all sub-functions (episode_row, movie_row, etc.)
- Delete old drawer CSS
- Run `mix precommit` — zero warnings, zero dead code

---

### Phase 5: Input System

**Why last:** All visual components exist. Now layer on the navigation system.

**Files:**
- Create `assets/js/spatial_nav.js` — nearest-neighbor algorithm, focus management, input-method detection
- Create `assets/js/gamepad.js` — Gamepad API polling, button mapping, hint bar visibility
- Create `assets/js/hooks/spatial_nav_hook.js` — LiveView hook, reads `data-detail-mode`
- Modify `lib/media_centaur_web/live/library_live.ex` — `data-nav-zone` attributes, gamepad hint bar
- Add CSS to `assets/css/app.css` — focus ring, hint bar, input-method visibility

**Work:**

5a. **Spatial navigation engine:**
- Arrow key / D-pad: nearest-neighbor in pressed direction (45° cone projection)
- Handles auto-fill grids with varying row lengths
- Zone transitions: CW ↔ toolbar ↔ Library grid
- Grid ↔ drawer transitions (Right → drawer, Left → grid)

5b. **Focus management modes:**
- `data-detail-mode="modal"` → focus trap (Tab cycles within modal, grid inert)
- `data-detail-mode="drawer"` → split focus (grid and drawer are independent zones)

5c. **Sidebar navigation:**
- Left from leftmost grid column → sidebar expands, nav items focusable
- Up/Down in sidebar activates immediately (page switches on focus)
- Right → collapse sidebar, return to page content

5d. **Gamepad support:**
- Gamepad API polling on `requestAnimationFrame`
- Button mapping: A=select, B=back, Start=play, D-pad=navigate
- Context-sensitive hint bar (floating pill, glass-nav style)
- Auto-detect controller type, show matching icons
- Hint bar visible only during gamepad input

5e. **Focus visibility:**
- Keyboard/gamepad: prominent focus ring (`outline: 2px solid var(--primary)`)
- Mouse: focus ring hidden during mouse movement, reappears on key/gamepad input
- Seamless input method transitions

5f. **Smart play rule (global):**
- P / Start always plays the **focused element**, regardless of drawer content
- Visual feedback: brief green outline flash on card

**Test approach:**
- Unit test spatial navigation algorithm (nearest-neighbor in direction, cone filtering)
- Test focus mode switching (modal trap vs drawer split)
- Test input equivalence (keyboard events map to same actions as gamepad)
- Manual verification with Xbox controller required

---

## Cross-Cutting Concerns

### PubSub Integration (all phases)
- `:entities_changed` → refresh both CW and Library zones
- `:entity_progress_updated` → update CW cards in real time, keep `ResumeTarget` in assigns
- `:playback_state_changed` → update playing indicator on cards

### URL State
- `?tab=` — library type tab (existing, add `collections`)
- `?selected=` — selected entity ID (existing, maps to `@selected_entity_id`)
- `?filter=` — text filter (existing)
- `?sort=` — sort order (new, default: `recent`)

### LiveView Assigns (final state)
```elixir
# Zone & detail
@selected_entity_id    # UUID or nil
@detail_presentation   # :modal | :drawer

# Continue Watching
@continue_watching     # filtered in-progress entries
@resume_targets        # %{entity_id => ResumeTarget}

# Library Browse
@active_tab            # :all | :movies | :tv | :collections
@sort_order            # :recent | :alpha | :year
@filter_text           # string
@counts                # %{all: N, movies: N, tv: N, collections: N}

# Existing (kept)
@entries               # stream of all entity entries
@playback              # current playback state
```

---

## Verification (end-to-end, after all phases)

1. App starts, library page loads — CW zone is default landing
2. In-progress entities show as backdrop cards with episode info and progress bars
3. Click CW card → modal opens with DetailPanel (correct variant)
4. Modal: season expand/collapse, episode styling, auto-scroll to current
5. Escape closes modal, focus returns to originating card
6. Scroll/navigate down → edge hint → Library zone
7. Library: poster grid fills full width, type tabs with counts, sort dropdown, filter
8. Click library card → drawer opens (480px right), grid shrinks
9. Drawer: DetailPanel with correct variant, cross-fade on entity swap
10. Arrow keys in grid don't change drawer content (selection mode)
11. Enter on different card → drawer swaps, focus moves into drawer
12. Left from drawer → focus to grid, drawer stays open
13. Navigate up from library → drawer auto-closes → CW zone
14. P/Start on any focused element → smart play with visual feedback
15. Gamepad: A/B/Start/D-pad work as equivalents, hint bar appears
16. Mouse: focus ring hidden, click opens modal/drawer, double-click plays
17. Below `lg` breakpoint: library drawer becomes modal
18. PubSub updates refresh both zones in real time
19. `mix precommit` passes — zero warnings, zero dead code
