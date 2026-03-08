# Library View Redesign: Library Browse Mode

## Context

This is the second of two zones in the redesigned library page. The first zone (Continue Watching) is documented in `003-continue-watching-design.md`. The input system is documented in `005-input-system-design.md`.

**Companion plans:**
- Continue Watching: `003-continue-watching-design.md`
- Input system: `005-input-system-design.md`
- Unified detail system: `006-unified-detail-system.md`

---

## Design Decision: Detail Drawer (Selection Mode)

Library Browse uses a **480px right-docked drawer** for entity details, not the centered modal used by Continue Watching. The drawer enables exploration-mode previewing without losing grid context.

| Property | Value |
|----------|-------|
| Width | 480px |
| Position | `sticky; top: 0; right: 0; max-height: 100vh; overflow-y: auto` |
| Border radius | `0` (flush with viewport edge) |
| Backdrop | None — grid remains visible and interactive |
| Focus | Split with grid — grid and drawer are independent nav zones |
| Entrance | `translateX(100%)` → `translateX(0)`, 200ms |
| Content swap | ~150ms cross-fade when switching entities |
| Dismiss | Escape / B / close button, auto-closes on zone transition (nav up into CW) |
| Mode | **Selection** — drawer content only changes on explicit Enter/A/click, not on arrow-key movement |

The drawer contains the same **DetailPanel** component used by the modal (see `006-unified-detail-system.md`), wrapped in a **DrawerShell** instead of a ModalShell.

**Responsive fallback:** On screens below `lg` breakpoint, the drawer becomes a modal (same DetailPanel, ModalShell). Same content, different shell.

### Grid Behavior with Drawer

- When drawer is open: grid occupies `calc(100% - 480px)`, drawer takes the remaining 480px
- When drawer is closed: grid returns to full viewport width
- Grid reflows naturally — `auto-fill` handles the narrower container

### Inactive Drawer (Focus in Grid)

When focus leaves the drawer and returns to the grid:
- Drawer remains open at full brightness
- No element inside the drawer has a focus outline
- Drawer content does NOT change — it stays on the originally-selected entity (selection mode)

---

## Design: Library Browse Mode

### Page Structure

Continue Watching and Library are two zones in one continuous vertical space. Library is the lower zone. Navigating down from the bottom of Continue Watching crosses into Library (see input system plan for zone transition and edge hint design).

- Type tabs live in the Library zone only
- Default sort: **Recently Added** (not alphabetical)

### Toolbar

Below the mode toggle, a horizontal toolbar:
- **Type tabs** (boxed-tab style): All | Movies | TV | Collections
  - Each tab shows a count badge (e.g. `Movies 24`)
  - "All" shows total entity count
- **Sort select** (dropdown): Recently Added / A-Z / Year
  - Default: Recently Added (reverse chronological by `inserted_at`)
- **Text filter** (input, right-aligned): filters by entity name substring, live as-you-type

### Poster Grid

Full-width poster card grid (shrinks when drawer is open):
- Grid: `grid-template-columns: repeat(auto-fill, minmax(155px, 1fr))`, `gap: 0.75rem`
- Padding: `1rem` (reduced from current `1.5rem`)
- No `max-w-7xl` constraint — grid fills available width
- At 4K (3840px minus 52px sidebar), this yields ~22 columns (full width) or ~20 columns (with drawer)

**Poster cards:**
- Glass surface background with backdrop blur
- **Poster image**: 2:3 aspect ratio, full-bleed, `object-fit: cover`
- **Progress bar** at bottom of poster (3px) when entity has watch progress — primary color fill, dark track
- **Card footer**: entity name (2-line clamp) + subtitle line
  - TV: `5 Seasons · 110 Episodes`
  - Movie series: `2 Movies`
  - Movie: year
- Hover: `translateY(-2px)` with elevated shadow
- Focus: `outline: 2px solid var(--primary)` with offset (keyboard/gamepad)
- `border-radius: 0.5rem`, cursor pointer

### Card Interaction

- **Click / Enter / A** → opens the **detail drawer** (or swaps content if already open), focus moves into drawer
- **Double-click / P / Start** → triggers **smart play** of the **focused card** immediately (not the drawer entity)

---

## Design: Detail Drawer (Library Mode)

The drawer wraps the shared DetailPanel component (see `006-unified-detail-system.md`) in a DrawerShell. The DetailPanel adapts its content based on entity type — three variants:

### Shared Hero Section (same as modal, narrower at 480px)
- Aspect ratio: `21 / 9` (206px tall at 480px width — compact but works)
- Entity **backdrop image** full-bleed
- Gradient fade from bottom (`var(--base-200)` -> transparent, 60% height)
- **Logo** bottom-left (or text title fallback), with drop-shadow
- **Right side of hero** (bottom-right): summary info varies by type (see below)

### Shared Body
- Padding: `1rem 1.5rem 1.5rem`
- **Header row:** type badge + metadata on left, Play button on right (`btn-soft btn-soft-success`)
- **Description** text (dim color, 1.6 line height)
- Divider (when content follows below)
- Type-specific content (see below)

---

### Variant 1: TV Series

**Hero right:** `5 Seasons · 110 Episodes`
- When in-progress: also shows series progress (`6/15 episodes` with green mini progress bar) and Resume button

**Header row meta:** type badge "TV Series" + year + season/episode counts

**Body content:** Collapsible season/episode list:
- Season headers with chevron, "Season N", episode count
- Click toggles expand/collapse
- First season auto-expands on open (or current season if in-progress)
- Episode rows: 3-column grid (number | name | duration/status)
- Watched rows: subtly darker background (`oklch(0% 0 0 / 0.15)`), green checkmark
- Current episode: blue-tinted background, partial progress bar, position/duration in monospace
- Unwatched: default background, muted duration text
- Auto-scroll to show ~2 watched episodes above current (when applicable)

### Variant 2: Movie Series (Collection)

**Hero right:** `2 Movies`

**Header row meta:** type badge "Collection" + movie count

**Body content:** Movie list with individual posters:
- Each row: 48x72px poster thumbnail | movie name + year/duration | Play button
- Rows: `border-radius: 0.375rem`, hover highlight, cursor pointer
- Each movie is independently playable

### Variant 3: Standalone Movie

**Hero right:** duration (e.g. `3h 1m`)

**Header row meta:** type badge "Movie" + year + duration

**Body content:** Description only, no list section. No divider needed.

---

## Data Sources (existing, reusable)

Same data sources as Continue Watching mode (see `003-continue-watching-design.md`):

| Need | Source | File |
|------|--------|------|
| Entities with associations | `LibraryBrowser.fetch_entities/0` | `lib/media_centaur/library_browser.ex` |
| Progress summary per entity | `ProgressSummary.compute/2` | `lib/media_centaur/playback/progress_summary.ex` |
| Resume action resolution | `Resume.resolve/2` | `lib/media_centaur/playback/resume.ex` |
| Smart play | `LibraryBrowser.play/1` | `lib/media_centaur/library_browser.ex` |
| Entity images | `/media-images/#{content_url}` | `ImageServer` plug |
| Watch progress records | `WatchProgress` resource | `lib/media_centaur/library/watch_progress.ex` |

### New data needed
- **Sort by `inserted_at`:** Entities need their `inserted_at` timestamp available for "Recently Added" sort (already on the resource, just needs to be passed through)
- **Type counts:** Computed client-side from the entity list for tab badges

---

## Implementation Steps

### 1. DrawerShell component
- Right-docked sticky shell wrapping DetailPanel
- 480px width, slide-in animation, cross-fade on content swap
- No backdrop overlay — grid remains interactive
- Split focus with grid (not a focus trap)
- Close button, auto-close on zone transition

### 2. Library mode grid + toolbar
- Render poster grid when `active_mode == :library`
- Type tabs with counts, sort dropdown (default: recently added), text filter
- Wire `handle_event` for type switch, sort change, filter input
- Grid uses `repeat(auto-fill, minmax(155px, 1fr))` with no max-width cap

### 3. Grid + drawer layout
- Flex or grid layout that accommodates 480px drawer when open
- Grid shrinks to `calc(100% - 480px)`, drawer slides in from right
- Grid returns to full width when drawer is closed

### 4. Card → drawer interaction
- Click / Enter / A → opens drawer (or swaps content with cross-fade if already open)
- Focus moves into drawer on open/swap
- Smart play (P/Start/double-click) always plays the **focused card**, not the drawer entity

### 5. Responsive fallback
- Below `lg` breakpoint: drawer becomes a modal (ModalShell wrapping DetailPanel)
- Same content, different shell

### 6. Remove `max-w-7xl` from library page
- The library page should not be constrained by the root layout's max-width
- Either override it for the library route or restructure the layout

---

## LiveView State

```elixir
@selected_entity_id   # which entity is shown in drawer (nil = closed)
@detail_presentation  # :drawer (default for library zone, or :modal below lg breakpoint)
```

The presentation is determined by which zone triggered the open:
- CW card click → `:modal`
- Library card click → `:drawer` (or `:modal` if below lg breakpoint)

---

## Files to Modify

- `lib/media_centaur_web/live/library_live.ex` — library mode rendering, drawer event handlers
- `lib/media_centaur_web/components/detail_panel.ex` — shared DetailPanel (from plan 003)
- `lib/media_centaur_web/components/drawer_shell.ex` — drawer wrapper component (new)
- `lib/media_centaur_web/components/layouts.ex` — remove or override `max-w-7xl` for library route
- `assets/css/app.css` — poster grid styles, drawer styles, grid-with-drawer layout

---

## Implementation Order (Both Zones Together)

Since both zones share the DetailPanel component, page structure, and input system, implement them together:

1. **DetailPanel component:** Shared content — all three variants (TV, movie series, movie)
2. **ModalShell + DrawerShell:** Two presentation wrappers for DetailPanel
3. **Page structure:** Continuous vertical layout with both zones, edge hint transition
4. **Continue Watching zone:** Backdrop card grid, in-progress filter, resume display
5. **Library zone:** Poster grid, type tabs, sort, filter, drawer layout
6. **Input system:** Spatial navigation, gamepad support, focus management (see `005-input-system-design.md`)
7. **Layout fix:** Remove max-width cap for library page
8. **PubSub integration:** Real-time progress updates refresh both zones

---

## Verification

1. Navigate to Library, switch to Library mode
2. Poster grid fills full viewport width with no max-width constraint
3. Type tabs filter correctly, counts are accurate
4. Sort: Recently Added (default) shows newest first, A-Z and Year work
5. Text filter narrows results live as you type
6. Click any poster → detail drawer opens on right, grid shrinks to accommodate
7. Drawer shows DetailPanel with correct variant (TV/movie series/movie)
8. TV series drawer: collapsible seasons, episode rows with correct styling
9. Movie series drawer: movie rows with individual posters and play buttons
10. Standalone movie drawer: simple view with description, play button
11. Click a different card while drawer is open → content swaps with cross-fade
12. Arrow-key movement in grid does NOT change drawer content (selection mode)
13. Enter/A on a different card swaps drawer content and moves focus into drawer
14. Left arrow from drawer → focus returns to grid, drawer stays open
15. Escape / close button closes drawer, grid returns to full width
16. Navigate up from Library into CW → drawer auto-closes
17. Focus a card with keyboard, press P → smart play triggers on **focused card** (not drawer entity)
18. Below `lg` breakpoint: drawer becomes a centered modal instead
19. `mix precommit` passes
