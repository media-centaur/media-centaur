# Library View Redesign: Input System

**Status:** planned
**Area:** frontend input / navigation
**Related plans:**
- Continue Watching mode: `continue-watching-design.md`
- Library Browse mode: `library-browse-design.md`

**Mockup reference:** `/tmp/media-centaur-mockups/input-design.html` (tab C: Full Interactive)

---

## Context

The library page is being redesigned with two zones (Continue Watching + Library browse) and a detail modal. The UI will run full-screen on a 4K OLED TV and must be equally usable with mouse, keyboard, and Xbox Series gamepad. This plan defines the unified input system that makes all three input methods first-class.

---

## Navigation Contexts

The UI has four navigation contexts, each with its own spatial rules:

### 1. Sidebar

- **Enter:** Left arrow from the **leftmost column** of page content (not from any arbitrary position)
- **On enter:** Sidebar expands from 52px to 200px, current page's nav item is focused
- **Up/Down:** Moves between nav items. **Each item activates immediately on focus** — page content updates as you move (no Enter needed to select)
- **Right:** Exits sidebar, sidebar collapses, focus returns to page content
- **Left (at wall):** Nothing

### 2. Page Content — Continue Watching Zone

- **Default zone** on page load. Focus starts on first Continue Watching card.
- **Arrow keys / D-pad:** Spatial navigation through the backdrop card grid (left/right/up/down)
- **Down from bottom row:** Crosses into Library zone (see Zone Transition below)
- **Left from leftmost column:** Enters sidebar
- **A / Enter / Click** on card → opens detail modal
- **Start / P / Double-click** on card → smart play (`LibraryBrowser.play/1`)

### 3. Page Content — Library Zone

- **Arrow keys / D-pad:** Spatial navigation through the poster card grid
- **Up from top grid row:** Moves focus into the **toolbar** (see Toolbar Navigation below)
- **Up from toolbar:** Crosses back into Continue Watching zone (see Zone Transition below)
- **Left from leftmost column:** Enters sidebar
- **A / Enter / Click** on card → opens detail modal
- **Start / P / Double-click** on card → smart play

### 4. Detail Modal (overlay)

- **Opens with focus on Resume/Play button** at top
- **Up/Down:** Navigates a vertical list:
  1. Play/Resume button
  2. Season headers (when TV series or movie series)
  3. Episode/movie rows (when season is expanded)
- **Enter / A** on Play button → plays
- **Enter / A** on season header → expand/collapse that season
- **Enter / A** on episode row → plays that specific episode
- **Start / P** → smart play (equivalent to hitting Play button, works from any focus position in modal)
- **Bottom of list wraps to top:** After the last item, Down returns focus to the Play/Resume button (as if modal just opened)
- **B / Escape / Click-outside / Close button** → closes modal, focus returns to the card that opened it
- **Left/Right:** No effect (single-column vertical list)

---

## Zone Transition: Edge Hint

Continue Watching and Library are one continuous vertical space. Only one zone is visible at a time, but navigating down from the bottom of Continue Watching scrolls into Library, and vice versa.

**Visual indicator: Edge Hint** — a subtle line at the bottom of Continue Watching:

```
──────── ↓ Library · 63 titles ────────
```

- Appears at the bottom of the Continue Watching zone
- Disappears once you've scrolled into the Library
- When in Library, an equivalent hint at the very top: `↑ Continue Watching`
- Minimal and unobtrusive — the transition itself (scrolling/focus movement) is the primary feedback

---

## Toolbar Navigation (Library Zone)

The Library toolbar (type tabs, sort dropdown, filter input) is a single horizontal focus row above the poster grid.

**Focus flow:**
1. **Up from top grid row** → focus lands on the **currently active type tab**
2. **Left/Right** → moves between toolbar items: `[All] [Movies] [TV] [Collections] [Sort] [Filter]`
3. **Down** → returns to the poster grid
4. **Enter / A** on a type tab → activates it (filters the grid)
5. **Enter / A** on sort dropdown → opens it, Up/Down selects option, Enter confirms
6. **Enter / A** on filter input → enters text entry mode (keyboard types normally, Escape/B exits back to spatial nav)

**Note:** Filter input is primarily a mouse/keyboard affordance. On gamepad, the OS on-screen keyboard handles text entry if needed — but filtering a 50-item library with a gamepad is an edge case, not a primary flow.

---

## Input Equivalence Table

| Action | Mouse | Keyboard | Gamepad (Xbox) |
|--------|-------|----------|----------------|
| Navigate | Pointer movement | Arrow keys | D-pad / Left stick |
| Select / Open | Single click | Enter | A |
| Smart Play | Double click | P | Start (≡) |
| Back / Dismiss | Click outside | Escape | B |
| Sidebar | Click directly | Left arrow (from leftmost col) | Left on D-pad (from leftmost col) |

---

## Focus Visibility

- **Keyboard/Gamepad active:** Prominent focus ring (`outline: 2px solid var(--primary)`, offset) always visible on the current element
- **Mouse active:** Focus ring hidden while mouse is moving. Reappears instantly on any key or gamepad input.
- **Transition between input methods is seamless** — no dead states, no "press Tab to start keyboard nav" requirement. First arrow key press focuses the nearest logical element.

---

## Gamepad Hint Bar

A persistent floating bar at the bottom center of the screen showing context-sensitive button mappings:

```
[D] Navigate    [A] Select    [≡] Play    [B] Back
```

- Background: glass-nav style, pill shape (`border-radius: 2rem`)
- Only visible when gamepad input is detected (hides for mouse/keyboard)
- Updates contextually:
  - In grid: `[D] Navigate  [A] Open  [≡] Play  [B] —`
  - In modal: `[D] Navigate  [A] Select  [≡] Play  [B] Close`
  - In sidebar: `[D] Navigate  [A] —  [≡] —  [B] —` (or hidden)

---

## Gamepad Configuration

- **Default:** Auto-detect controller type (Xbox, PlayStation, etc.) and show matching button icons
- **Settings:** Configurable override — user can select controller type manually
- Button mapping itself is fixed (A=select, B=back, Start=play, D-pad=navigate) — no remapping in v1

---

## Spatial Navigation Algorithm

Arrow key / D-pad navigation through grids uses **nearest-neighbor in the pressed direction:**

1. From the currently focused element, project a ray in the pressed direction
2. Find all focusable elements whose center is in that direction (within ~45° cone)
3. Select the nearest one by distance
4. If none found in the cone: no movement (wall)

This handles:
- Grids with varying row lengths (auto-fill wrapping)
- Moving between zones (Continue Watching → Library) when the nearest element downward is in the next zone
- Toolbar ↔ grid transitions

**Implementation note:** The browser Gamepad API provides button/axis state. A JS hook polls gamepad state on `requestAnimationFrame`, translates to navigation events, and moves focus accordingly. Keyboard arrow keys use the same spatial algorithm via `keydown` listeners.

---

## Files to Create/Modify

- `assets/js/spatial_nav.js` — Spatial navigation engine (nearest-neighbor algorithm, focus management, input-method detection)
- `assets/js/gamepad.js` — Gamepad API polling, button mapping, hint bar visibility
- `assets/js/hooks/spatial_nav_hook.js` — LiveView hook that initializes spatial nav on mount
- `lib/media_centaur_web/live/library_live.ex` — `data-nav-zone` attributes on containers, gamepad hint bar component
- `assets/css/app.css` — Focus ring styles, gamepad hint bar styles, input-method-dependent visibility

---

## Verification

1. **Keyboard:** Arrow keys navigate through Continue Watching cards spatially
2. **Keyboard:** Down from last CW row → focus crosses into Library grid, edge hint disappears
3. **Keyboard:** Up from top Library row → focus enters toolbar on active tab
4. **Keyboard:** Left/Right in toolbar moves between tabs/sort/filter, Enter activates
5. **Keyboard:** Down from toolbar → back to grid
6. **Keyboard:** Left from leftmost column → sidebar expands, nav items focusable
7. **Keyboard:** Up/Down in sidebar switches pages immediately, Right collapses and returns
8. **Keyboard:** Enter on card → modal opens, focus on Play button
9. **Keyboard:** Up/Down in modal navigates vertical list, Enter on season toggles, bottom wraps to top
10. **Keyboard:** Escape closes modal, focus returns to originating card
11. **Keyboard:** P on any card → smart play with visual feedback
12. **Gamepad:** All above works with A/B/Start/D-pad equivalents
13. **Gamepad:** Hint bar appears on gamepad input, hides on mouse/keyboard
14. **Gamepad:** Hint bar updates contextually (grid vs modal vs sidebar)
15. **Mouse:** Click opens modal, double-click smart plays, focus ring hidden during mouse use
16. **Mouse:** Moving mouse after keyboard nav hides focus ring; pressing arrow key restores it
17. `mix precommit` passes
