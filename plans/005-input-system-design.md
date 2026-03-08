# Library View Redesign: Input System

**Status:** planned
**Area:** frontend input / navigation
**Related plans:**
- Continue Watching mode: `003-continue-watching-design.md`
- Library Browse mode: `004-library-browse-design.md`
- Unified detail system: `006-unified-detail-system.md`

---

## Context

The library page is being redesigned with two zones (Continue Watching + Library browse), a detail modal, and a detail drawer. The UI will run full-screen on a 4K OLED TV and must be equally usable with mouse, keyboard, and Xbox Series gamepad. This plan defines the unified input system that makes all three input methods first-class.

---

## Navigation Contexts

The UI has five navigation contexts, each with its own spatial rules:

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
- **A / Enter / Click** on card → opens detail modal (DetailPanel in ModalShell)
- **Start / P / Double-click** on card → smart play (`LibraryBrowser.play/1`)

### 3. Page Content — Library Zone

- **Arrow keys / D-pad:** Spatial navigation through the poster card grid
- **Up from top grid row:** Moves focus into the **toolbar** (see Toolbar Navigation below)
- **Up from toolbar:** Crosses back into Continue Watching zone (see Zone Transition below)
- **Left from leftmost column:** Enters sidebar
- **A / Enter / Click** on card → opens detail drawer (DetailPanel in DrawerShell), or swaps content if already open
- **Start / P / Double-click** on card → smart play of **focused card** (not drawer entity)
- **Right from any grid card (drawer open):** Enters drawer, focus on play button. Drawer content unchanged.
- **Right from grid card (drawer closed):** Normal spatial navigation (no special behavior)

### 4. Detail Modal (overlay) — Continue Watching

- **Opens with focus on Resume/Play button** at top
- **Focus trap** — only elements inside the modal are focusable, grid is inert behind backdrop
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

**Note:** Also used as the responsive fallback for Library Browse on screens below `lg` breakpoint. Behavior is identical — focus trap, B/Escape closes.

### 5. Detail Drawer (sidebar) — Library Browse

- **Enter:** Click / Enter / A on a Library card, or Right arrow from any grid card (when drawer is open)
- **Split focus** — grid and drawer are two independent nav zones (no focus trap)
- **Up/Down:** Navigates vertical list inside drawer (Play button → seasons → episodes)
- **Enter / A** on Play button → plays
- **Enter / A** on season header → expand/collapse
- **Enter / A** on episode row → plays that specific episode
- **Start / P** → smart play of **focused element** (the episode/button focused in drawer)
- **Left:** Exit drawer, focus returns to the grid card that was last focused (the "associated" card)
- **B / Escape / Close button** → closes drawer entirely, grid returns to full width
- **Clicking a different grid card (while drawer is open):** Swaps drawer content with ~150ms cross-fade, focus moves into drawer

**Key difference from modal:** Drawer uses selection mode — arrow keys in the grid do NOT change drawer content. Only explicit Enter/A/click on a card swaps the drawer entity.

---

## Focus Management Modes

Two distinct focus management strategies, selected by `data-detail-mode` attribute:

### Modal Mode (`data-detail-mode="modal"`)
- Focus trap — Tab/Shift+Tab cycle within the modal only
- Grid elements have `inert` attribute
- Escape releases trap and returns focus to originating card

### Drawer Mode (`data-detail-mode="drawer"`)
- Split focus — spatial nav treats grid and drawer as two adjacent zones
- Right from ANY grid card → enters drawer (focus on play button), drawer content unchanged
- Left from drawer → back to grid (focus on associated card)
- Enter/A on grid card → selects entity into drawer + moves focus into drawer
- Drawer is a persistent zone, not tied to a specific grid position

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

### Zone Transition with Drawer

- Navigating **UP** from Library toolbar into Continue Watching → **drawer auto-closes**
- Navigating **DOWN** from CW into Library → drawer does **NOT** auto-reopen (start fresh)

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

## Smart Play Rule (Global)

**P / Start always plays the focused element**, regardless of what the drawer is showing.

| Context | Focused Element | P/Start Result |
|---------|----------------|----------------|
| CW grid | CW card | Smart play that entity |
| Library grid (drawer open) | Grid card | Smart play the **focused card** (not drawer entity) |
| Detail modal | Play button / episode row | Smart play (equivalent to hitting Play button) |
| Detail drawer | Episode row | Play that specific episode |
| Detail drawer | Play button | Smart play the drawer entity |

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

### Drawer Focus Rendering

**Focus inside drawer** (user is navigating episodes/seasons):
- Active element (play button, episode row, season header) has the primary focus ring
- Grid cards have NO focus ring — the grid is not the active zone

**Focus leaves drawer → grid:**
- Focus ring appears on the card that originally opened the drawer (the "associated" card)
- Drawer remains open at full brightness
- No element inside the drawer has a focus outline (internal focus ring disappears)
- Drawer content does NOT change — selection mode

**Enter/A on a new grid card (while drawer is open):**
- Drawer content swaps to the new entity with ~150ms cross-fade
- Focus moves INTO the drawer (play button gets focus)
- The new card becomes the "associated" card

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
  - In drawer: `[D] Navigate  [A] Select  [≡] Play  [B] Close`
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
- Grid ↔ drawer transitions (Right from grid → drawer, Left from drawer → grid)

**Implementation note:** The browser Gamepad API provides button/axis state. A JS hook polls gamepad state on `requestAnimationFrame`, translates to navigation events, and moves focus accordingly. Keyboard arrow keys use the same spatial algorithm via `keydown` listeners.

---

## Files to Create/Modify

- `assets/js/spatial_nav.js` — Spatial navigation engine (nearest-neighbor algorithm, focus management, input-method detection, split-focus support)
- `assets/js/gamepad.js` — Gamepad API polling, button mapping, hint bar visibility
- `assets/js/hooks/spatial_nav_hook.js` — LiveView hook that initializes spatial nav on mount, reads `data-detail-mode` for focus strategy
- `lib/media_centaur_web/live/library_live.ex` — `data-nav-zone` attributes on containers, `data-detail-mode` on detail containers, gamepad hint bar component
- `assets/css/app.css` — Focus ring styles, gamepad hint bar styles, input-method-dependent visibility, drawer focus states

---

## Verification

1. **Keyboard:** Arrow keys navigate through Continue Watching cards spatially
2. **Keyboard:** Down from last CW row → focus crosses into Library grid, edge hint disappears
3. **Keyboard:** Up from top Library row → focus enters toolbar on active tab
4. **Keyboard:** Left/Right in toolbar moves between tabs/sort/filter, Enter activates
5. **Keyboard:** Down from toolbar → back to grid
6. **Keyboard:** Left from leftmost column → sidebar expands, nav items focusable
7. **Keyboard:** Up/Down in sidebar switches pages immediately, Right collapses and returns
8. **Keyboard:** Enter on Library card → drawer opens, focus on Play button
9. **Keyboard:** Up/Down in drawer navigates vertical list, Enter on season toggles
10. **Keyboard:** Left from drawer → focus returns to grid card, drawer stays open
11. **Keyboard:** Arrow keys in grid (drawer open) do NOT change drawer content
12. **Keyboard:** Enter on different grid card → drawer content swaps, focus moves into drawer
13. **Keyboard:** Right from grid card (drawer open) → enters drawer, content unchanged
14. **Keyboard:** Escape in drawer → drawer closes, grid returns to full width
15. **Keyboard:** Navigate up from Library toolbar into CW → drawer auto-closes
16. **Keyboard:** Enter on CW card → modal opens (not drawer), focus trapped
17. **Keyboard:** Escape closes modal, focus returns to originating card
18. **Keyboard:** P on any card → smart play of **focused** element with visual feedback
19. **Gamepad:** All above works with A/B/Start/D-pad equivalents
20. **Gamepad:** Hint bar appears on gamepad input, hides on mouse/keyboard
21. **Gamepad:** Hint bar updates contextually (grid vs modal vs drawer vs sidebar)
22. **Mouse:** Click opens modal/drawer, double-click smart plays, focus ring hidden during mouse use
23. **Mouse:** Moving mouse after keyboard nav hides focus ring; pressing arrow key restores it
24. **Responsive:** Below `lg` breakpoint, Library card click opens modal instead of drawer
25. `mix precommit` passes
