# Library View Redesign: Continue Watching + Detail Modal

## Context

The library view currently treats all entities as one flat alphabetical grid, which serves none of the user's primary tasks well. This plan covers the **Continue Watching** mode and its **detail modal** — the first of two modes in the redesigned library page. The second mode (Library browse grid) is planned in `004-library-browse-design.md`.

**Companion plans:**
- Library Browse mode: `004-library-browse-design.md`
- Input system: `005-input-system-design.md`
- Unified detail system: `006-unified-detail-system.md`

**Design decision:** Continue Watching and Library Browse share a **DetailPanel** component — the same content rendered in two different shells. Continue Watching uses ModalShell (centered overlay). Library Browse uses DrawerShell (right-docked sidebar). See `006-unified-detail-system.md` for the unified architecture.

**Future constraint (design-compatible, not implemented yet):** Full-screen 4K OLED TV with mouse, keyboard, and gamepad input. No hover-dependent interactions, generous focus states, spatial-navigation-friendly layouts.

---

## Component Architecture

### DetailPanel (shared content component)

A standalone LiveView function component that renders identically in both shells:
- Hero (21:9, backdrop, logo, gradient)
- Progress + Resume/Play button
- Metadata (type badge, year, counts)
- Description
- Content list (episodes / movies / —)
- Event handling (play, toggle, etc.)

Accepts: `entity`, `progress`, `resume`, `on_play` / `on_close` event names.

### ModalShell (used by Continue Watching)

- Fixed centered overlay
- Backdrop: `oklch(0% 0 0 / 0.7)` + `backdrop-filter: blur(4px)`
- Panel: `width: min(600px, 92vw)`, `max-height: 90vh`, `border-radius: 0.75rem`
- Focus trap — grid is inert, all nav confined to modal
- Entrance: `scale(0.96) translateY(8px)` → identity, 200ms
- Dismiss: Escape / B / click-outside / close button (top-right circle, 32px)

---

## Design: Continue Watching Mode

### Page Structure

Continue Watching and Library are two zones in one continuous vertical space (see input system plan for zone transition design). Continue Watching is at the top — the default, comfortable landing spot.

- Type-agnostic — shows all in-progress entities regardless of type
- Type tabs (Movies, TV, Collections) belong to the Library zone only

### Continue Watching Cards

Large horizontal 16:9 backdrop cards displayed in an auto-fill grid:
- Grid: `grid-template-columns: repeat(auto-fill, minmax(480px, 1fr))`, `gap: 1rem`
- Each card uses the entity's **backdrop image** as full-bleed background
- **Logo** overlaid bottom-left (when available), with drop-shadow
- If no logo: entity name as text in the overlay
- Bottom gradient overlay (black 88% -> transparent) contains:
  - Episode info: `S1 E7 — 1:00 P.M.` (season, episode number, episode name)
  - Resume label: `Resume at 26:24` (primary color)
- **Progress bar** at the very bottom edge (4px, primary color fill)
- `border-radius: 0.5rem`, hover: `scale(1.02)` with elevated shadow
- Focus: `outline: 2px solid var(--primary)` with offset (for keyboard/gamepad)

### Interaction Paths on Cards

1. **Click / Enter / A** → opens the **detail modal** (DetailPanel in ModalShell) for that entity
2. **Double-click / P / Start** → triggers **smart play** immediately (calls `LibraryBrowser.play/1`), visual feedback via brief green outline flash on the card

### Empty State

When no entities have active progress: brief message prompting to browse the library.

---

## Design: Detail Modal

A centered overlay modal (ModalShell) containing the shared DetailPanel component. Provides full entity detail and episode navigation.

### Hero Section
- Aspect ratio: `21 / 9` (ultrawide, cinematic)
- Entity **backdrop image** full-bleed
- Gradient fade from bottom (`var(--base-200)` -> transparent, 60% height)
- **Logo** bottom-left (or text title fallback), with drop-shadow
- **Right side of hero** (bottom-right, opposite logo):
  - Series progress: `6/15 episodes` with a small 140px green progress bar
  - **Resume button** directly below: `btn-soft btn-soft-success`, labeled `▶ Resume S1E7`

### Modal Body (scrollable)
- Padding: `1rem 1.5rem 1.5rem`
- **Header row:** type badge + year + season/episode counts
- **Description** text (dim color, 1.6 line height)
- Divider
- **Season/episode list** (see below)

### Modal Navigation (keyboard/gamepad)
- Opens with focus on **Play/Resume button**
- Up/Down navigates vertical list: Play button → season headers → episode rows
- Enter/A on season header → expand/collapse
- Enter/A on episode row → play that episode
- Start/P → smart play from any position in modal
- Bottom of list wraps to top (Play button)
- See input system plan for full details

### Season/Episode List

Collapsible season sections with smart scroll behavior:

**Season headers:**
- Chevron + "Season N" + "X/Y watched" + status ("In progress" / "Complete")
- Click/Enter toggles expand/collapse
- The season containing the current episode **auto-expands** on modal open
- If no current episode, Season 1 auto-expands

**Episode rows** (3-column grid: number | name+progress | status):
- **Watched episodes:** subtly darker background (`oklch(0% 0 0 / 0.15)`), green checkmark status
- **Current episode:** blue-tinted background (`oklch(62% 0.16 250 / 0.08)`), partial progress bar (2px, primary color), position/duration in monospace
- **Unwatched episodes:** default background, muted duration text
- All rows: `border-radius: 0.375rem`, hover highlight, cursor pointer
- Episode name truncates with ellipsis

**Auto-scroll behavior:** On modal open, the episode list scrolls so that ~2 previously completed episodes are visible above the current/next episode. This gives context ("where was I?") without drowning in history.

---

## Data Sources (existing, reusable)

| Need | Source | File |
|------|--------|------|
| Entities with associations | `LibraryBrowser.fetch_entities/0` | `lib/media_centaur/library_browser.ex` |
| Progress summary per entity | `ProgressSummary.compute/2` | `lib/media_centaur/playback/progress_summary.ex` |
| Resume action resolution | `Resume.resolve/2` | `lib/media_centaur/playback/resume.ex` |
| Smart play | `LibraryBrowser.play/1` | `lib/media_centaur/library_browser.ex` |
| Resume target (display hints) | `ResumeTarget` | `lib/media_centaur/playback/resume_target.ex` |
| Progress PubSub updates | `{:entity_progress_updated, ...}` | Already received in `library_live.ex:185-192` |
| Entity images | `/media-images/#{content_url}` | `ImageServer` plug |
| Watch progress records | `WatchProgress` resource | `lib/media_centaur/library/watch_progress.ex` |

Key finding: `ResumeTarget` is already computed on progress updates but **discarded** in the LiveView (line 186). It should be kept in assigns for the Continue Watching display.

### New data needed
- **In-progress entity filter:** Query/filter for entities where resume action is `:resume` or `:play_next` (not `:restart`, not nil)
- **Per-episode progress for modal:** The `progress_records` are already loaded by `fetch_entities` — they just need to be passed through to the modal view

---

## Implementation Steps

### 1. DetailPanel component (shared)
- Extract a standalone function component for entity detail content
- Accepts entity, progress, resume, event names as assigns
- Renders hero, metadata, description, season/episode list
- Three variants based on entity type (TV series, movie series, standalone movie)

### 2. ModalShell component
- Centered overlay shell that wraps DetailPanel
- Focus trap, backdrop blur, dismiss behavior
- Entrance animation

### 3. Continue Watching zone + data
- Filter entities with active progress into a separate assign
- Keep `ResumeTarget` from PubSub updates instead of discarding it

### 4. Continue Watching card grid
- New render function for the backdrop card layout
- Cards show backdrop image, logo, episode info, resume label, progress bar
- Click/Enter opens detail modal, double-click/P/Start triggers smart play

### 5. Zone transition
- Edge hint at bottom of Continue Watching: "↓ Library · N titles"
- Scrolling/navigating down crosses into Library zone

---

## LiveView State

```elixir
@selected_entity_id   # which entity is shown in modal (nil = closed)
@detail_presentation  # :modal (always, for CW zone)
```

---

## Files to Modify

- `lib/media_centaur_web/live/library_live.ex` — continue watching rendering, event handlers
- `lib/media_centaur_web/components/detail_panel.ex` — shared DetailPanel function component (new)
- `lib/media_centaur_web/components/modal_shell.ex` — modal wrapper component (new)
- `lib/media_centaur/library_browser.ex` — possibly add a filtered fetch for in-progress entities
- `assets/css/app.css` — continue watching card styles, modal styles, episode row styles, edge hint styles

---

## Verification

1. Start the app, navigate to Library — Continue Watching zone is the default landing
2. In-progress entities appear as backdrop cards with correct episode info and progress
3. Click a card — modal opens with hero, series progress, episode list
4. Episode list auto-scrolls to show ~2 watched episodes above current
5. Season headers collapse/expand, correct watched/in-progress/unwatched styling
6. Escape or click-outside closes modal
7. Focus a card, press P — playback starts (smart play)
8. Navigate down past Continue Watching → crosses into Library zone
9. Edge hint visible at bottom of Continue Watching zone
10. Progress PubSub updates refresh Continue Watching cards in real time
11. `mix precommit` passes
