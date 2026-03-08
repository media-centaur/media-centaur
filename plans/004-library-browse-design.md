# Library View Redesign: Library Browse Mode

## Context

This is the second of two zones in the redesigned library page. The first zone (Continue Watching) is documented in `continue-watching-design.md`. The input system is documented in `giggly-beaming-valley.md`.

**Mockup reference:** `/tmp/media-centaur-mockups/library-browse.html` (served at `http://localhost:8090/library-browse.html`, requires the app running at localhost:4000 for images).

**Companion plans:**
- Continue Watching: `continue-watching-design.md`
- Input system: `giggly-beaming-valley.md`

---

## Design Decision: No Side Drawer

The current library view uses a 360px side drawer for entity details on selection. The redesign **removes the drawer entirely** in favor of the detail modal for both modes. Rationale:

- The modal provides a richer, more focused detail view than the cramped drawer
- Having both a drawer and a modal is redundant — one interaction path is simpler
- The modal is already designed and shared with Continue Watching mode
- Removing the drawer lets the poster grid use the full viewport width at all times

**Interaction model:** Single click (or Enter on focused card) opens the detail modal. No intermediate selection state.

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

Full-width poster card grid with no max-width cap:
- Grid: `grid-template-columns: repeat(auto-fill, minmax(155px, 1fr))`, `gap: 0.75rem`
- Padding: `1rem` (reduced from current `1.5rem`)
- No `max-w-7xl` constraint — grid fills available viewport width
- At 4K (3840px minus 52px sidebar), this yields ~22 columns

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

- **Click / Enter / A** → opens the **detail modal** for that entity
- **Double-click / P / Start** → triggers **smart play** immediately (same as Continue Watching)

---

## Design: Detail Modal (Library Mode)

The modal is structurally identical to the Continue Watching modal (shared component) but adapts its content based on entity type. Three variants:

### Shared Modal Chrome (same as Continue Watching)
- **Backdrop:** fixed overlay, `oklch(0% 0 0 / 0.7)` with `backdrop-filter: blur(4px)`
- **Panel:** `width: min(600px, 92vw)`, `max-height: 90vh`, `border-radius: 0.75rem`
- Background: `var(--base-200)`, border and shadow matching glass system
- Entrance animation: `scale(0.96) translateY(8px)` -> `scale(1) translateY(0)`, 200ms
- **Dismiss:** Escape key, click on backdrop, or close button (top-right circle, 32px)

### Shared Hero Section
- Aspect ratio: `21 / 9` (ultrawide, cinematic)
- Entity **backdrop image** full-bleed
- Gradient fade from bottom (`var(--base-200)` -> transparent, 60% height)
- **Logo** bottom-left (or text title fallback), with drop-shadow
- **Right side of hero** (bottom-right): summary info varies by type (see below)

### Shared Modal Body
- Padding: `1rem 1.5rem 1.5rem`
- **Header row:** type badge + metadata on left, Play button on right (`btn-soft btn-soft-success`)
- **Description** text (dim color, 1.6 line height)
- Divider (when content follows below)
- Type-specific content (see below)

---

### Variant 1: TV Series Modal

**Hero right:** `5 Seasons · 110 Episodes`
- When in-progress: also shows series progress (`6/15 episodes` with green mini progress bar) and Resume button

**Header row meta:** type badge "TV Series" + year + season/episode counts

**Body content:** Collapsible season/episode list (identical to Continue Watching modal):
- Season headers with chevron, "Season N", episode count
- Click toggles expand/collapse
- First season auto-expands on open (or current season if in-progress)
- Episode rows: 3-column grid (number | name | duration/status)
- Watched rows: subtly darker background (`oklch(0% 0 0 / 0.15)`), green checkmark
- Current episode: blue-tinted background, partial progress bar, position/duration in monospace
- Unwatched: default background, muted duration text
- Auto-scroll to show ~2 watched episodes above current (when applicable)

### Variant 2: Movie Series (Collection) Modal

**Hero right:** `2 Movies`

**Header row meta:** type badge "Collection" + movie count

**Body content:** Movie list with individual posters:
- Each row: 48x72px poster thumbnail | movie name + year/duration | Play button
- Rows: `border-radius: 0.375rem`, hover highlight, cursor pointer
- Each movie is independently playable

### Variant 3: Standalone Movie Modal

**Hero right:** duration (e.g. `3h 1m`)

**Header row meta:** type badge "Movie" + year + duration

**Body content:** Description only, no list section. No divider needed.

---

## Data Sources (existing, reusable)

Same data sources as Continue Watching mode (see `continue-watching-design.md`):

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

### 1. Remove the drawer
- Delete the 360px drawer panel from `library_live.ex`
- Remove `selected_entity` assign and drawer-related event handlers
- Grid now occupies the full main area

### 2. Library mode grid + toolbar
- Render poster grid when `active_mode == :library`
- Type tabs with counts, sort dropdown (default: recently added), text filter
- Wire `handle_event` for type switch, sort change, filter input
- Grid uses `repeat(auto-fill, minmax(155px, 1fr))` with no max-width cap

### 3. Shared detail modal component
- Extract the modal from Continue Watching into a shared LiveView component
- Accept entity + progress data as assigns
- Render appropriate variant (TV/movie series/movie) based on entity type
- Wire `handle_event("open_modal", %{"id" => id})` and `handle_event("close_modal")`

### 4. Smart play on P key (shared with Continue Watching)
- JS hook on all focusable cards in both modes
- Push event to server on "p" keydown
- Brief visual feedback

### 5. Remove `max-w-7xl` from library page
- The library page should not be constrained by the root layout's max-width
- Either override it for the library route or restructure the layout

---

## Files to Modify

- `lib/media_centaur_web/live/library_live.ex` — remove drawer, add library mode rendering, shared modal component
- `lib/media_centaur_web/components/layouts.ex` — remove or override `max-w-7xl` for library route
- `assets/css/app.css` — poster grid styles, remove drawer styles, modal variant styles

---

## Implementation Order (Both Zones Together)

Since both zones share the modal component, page structure, and input system, implement them together:

1. **Page structure:** Continuous vertical layout with both zones, edge hint transition
2. **Shared modal component:** All three variants (TV, movie series, movie), dismiss behavior
3. **Continue Watching zone:** Backdrop card grid, in-progress filter, resume display
4. **Library zone:** Poster grid, type tabs, sort, filter, no drawer
5. **Input system:** Spatial navigation, gamepad support, focus management (see `giggly-beaming-valley.md`)
6. **Layout fix:** Remove max-width cap for library page
7. **PubSub integration:** Real-time progress updates refresh both zones

---

## Verification

1. Navigate to Library, switch to Library mode
2. Poster grid fills full viewport width with no max-width constraint
3. Type tabs filter correctly, counts are accurate
4. Sort: Recently Added (default) shows newest first, A-Z and Year work
5. Text filter narrows results live as you type
6. Click any poster → detail modal opens (no drawer)
7. TV series modal: collapsible seasons, episode rows with correct styling
8. Movie series modal: movie rows with individual posters and play buttons
9. Standalone movie modal: simple view with description, play button
10. Escape / click-outside / close button all dismiss the modal
11. Focus a card with Tab, press P → smart play triggers
12. No drawer visible anywhere — fully replaced by modal
13. `mix precommit` passes
