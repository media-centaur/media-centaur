# Library Redesign: Unified Detail System (Modal + Drawer)

## Context

The library redesign has three companion plans: Continue Watching (003), Library Browse (004), and Input System (005). The original design removed the sidebar drawer entirely in favor of a centered modal. After review, the drawer UX for Library Browse is too good to lose — it enables exploration-mode previewing without losing grid context. This plan unifies modal and drawer as two presentations of one component system.

---

## Design Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Drawer width: **480px** | Good balance. 4K: ~20 grid columns. 1080p: ~8 columns. |
| 2 | Hero: **same 21:9** in both presentations | Consistency over optimal sizing. 206px tall at 480px is compact but works. |
| 3 | Zone exit: **drawer auto-closes** on nav up into CW | Drawer belongs to Library zone. Clean separation. |
| 4 | Smart play target: **always the focused element** | Drawer is a preview, not the active selection. Consistent with modal. |
| 5 | Drawer swap: **brief cross-fade** (~150ms) | Signals content changed without slowing rapid browsing. |
| 6 | Responsive: drawer → modal fallback on small screens | Same content, different shell. Deferred to implementation. |
| 7 | Drawer mode: **selection** (not preview pane) | Drawer content only changes on explicit Enter/A/click. Arrow keys just move focus ring through grid. Stable, predictable. |
| 8 | Inactive zone indicator: **remove internal focus ring only** | When focus leaves drawer → grid, drawer stays full brightness. Only change: no element inside the drawer has a focus outline. Minimal, clean. |

---

## Unified Architecture

### Two Interaction Modes

| Zone | Presentation | Mode | Why |
|------|-------------|------|-----|
| Continue Watching | Centered modal | **Decision** — focused, choose, dismiss | You're about to play something |
| Library Browse | Right-docked drawer | **Exploration** — preview while browsing | You're looking through your collection |

### Component Layers

```
┌─────────────────────────────────────────┐
│ DetailPanel (shared content component)  │
│  - Hero (21:9, backdrop, logo, gradient) │
│  - Progress + Resume/Play button        │
│  - Metadata (type badge, year, counts)  │
│  - Description                          │
│  - Content list (episodes / movies / —) │
│  - Event handling (play, toggle, etc.)  │
└──────────────┬──────────────────────────┘
               │ rendered inside
       ┌───────┴───────┐
       ▼               ▼
  ModalShell      DrawerShell
  (overlay)       (sidebar)
```

**DetailPanel** is a LiveView function component that accepts:
- `entity` — the entity to display
- `progress` — progress summary
- `resume` — resume target
- `on_play` / `on_close` — event names

It renders identically in both shells. The shell controls:
- Positioning (centered overlay vs right-docked sticky)
- Backdrop (blur overlay vs none)
- Focus behavior (trap vs split)
- Animation (scale-fade vs slide-right)
- Dismiss behavior

### ModalShell

- Fixed centered overlay
- Backdrop: `oklch(0% 0 0 / 0.7)` + `backdrop-filter: blur(4px)`
- Panel: `width: min(600px, 92vw)`, `max-height: 90vh`, `border-radius: 0.75rem`
- Focus trap — grid is inert, all nav confined to modal
- Entrance: `scale(0.96) translateY(8px)` → identity, 200ms
- Dismiss: Escape / B / click-outside / close button

### DrawerShell

- Right-docked, `position: sticky; top: 0; max-height: 100vh; overflow-y: auto`
- Width: 480px, `border-radius: 0` (flush with viewport edge)
- No backdrop overlay — grid remains visible and interactive
- Split focus — grid and drawer are independent nav zones
- Entrance: `translateX(100%)` → `translateX(0)`, 200ms
- Content swap: ~150ms cross-fade when switching entities
- Dismiss: Escape / B / close button
- Auto-closes on zone transition (navigating up into Continue Watching)

---

## Focus Rendering

### Focus Ring
All focusable elements use `outline: 2px solid var(--primary)` with offset. Visible during keyboard/gamepad input, hidden during mouse movement.

### Drawer Focus States

**Focus inside drawer** (user is navigating episodes/seasons):
- Active element (play button, episode row, season header) has the primary focus ring
- Grid cards have NO focus ring — the grid is not the active zone

**Left arrow → focus moves to grid:**
- Focus ring appears on the card that originally opened the drawer (the "associated" card)
- Drawer remains open at full brightness
- Internal focus ring inside the drawer disappears (no element is focused inside)
- Drawer content does NOT change — it still shows the entity from the explicit selection

**Arrow navigation in grid (while drawer is open):**
- Focus ring moves between grid cards normally
- Drawer content stays on the originally-selected entity (selection mode, not preview)
- To change the drawer content: press Enter/A on a different card, or click it

**Enter/A on a new grid card (while drawer is open):**
- Drawer content swaps to the new entity with ~150ms cross-fade
- Focus moves INTO the drawer (play button gets focus)
- The new card becomes the "associated" card

**Right arrow from grid → drawer:**
- Focus enters the drawer from ANY grid card, landing on the play button
- Grid focus ring disappears
- Drawer content does NOT change — it still shows the previously-selected entity
- Only works if drawer is already open (Right does normal spatial nav when drawer is closed)
- To change drawer content: must use Enter/A/click on the desired card first

### Modal Focus States

**Focus inside modal:**
- Standard focus trap — only elements inside the modal are focusable
- Active element has primary focus ring
- Grid is inert behind the backdrop overlay

**Dismiss (Escape/B/click-outside):**
- Focus returns to the card that opened the modal

---

## LiveView State

```elixir
@selected_entity_id   # which entity is shown in drawer/modal (nil = closed)
@detail_presentation  # :modal | :drawer (determines which shell renders)

# The presentation is determined by which zone triggered the open:
# - CW card click → :modal
# - Library card click → :drawer (or :modal if below lg breakpoint)
```

---

## CSS Strategy

```css
/* Shared DetailPanel styles */
.detail-hero { aspect-ratio: 21/9; /* ... */ }
.detail-body { /* padding, typography, episode rows */ }

/* ModalShell */
.modal-backdrop { /* fixed overlay with blur */ }
.modal-panel { /* centered, max-width, rounded */ }

/* DrawerShell */
.drawer-panel { /* sticky, right-0, 480px, slide-in */ }
.drawer-panel .detail-hero { /* same styles, just narrower container */ }

/* Grid adjustment when drawer is open */
.library-grid--with-drawer { /* flex or grid that accommodates 480px drawer */ }
```

### JS Hooks

The spatial nav hook needs a `data-detail-mode` attribute on the detail container:
- `data-detail-mode="modal"` → enable focus trap
- `data-detail-mode="drawer"` → enable split-zone navigation

---

## Changes Applied to Companion Plans

### Plan 003 (Continue Watching)
1. "Shared modal" → "Shared DetailPanel" — the modal is one of two presentation shells
2. Component extraction — DetailPanel is a standalone function component, not embedded in ModalShell
3. Added component architecture section describing DetailPanel + ModalShell
4. Updated companion plan references

### Plan 004 (Library Browse)
1. Removed "No Side Drawer" section — drawer is back, redesigned with DetailPanel
2. Replaced all "detail modal" references with "detail drawer" for Library Browse
3. Added drawer specs: 480px, sticky right, selection mode, cross-fade, auto-close
4. Grid shrinks to `calc(100% - 480px)` when drawer is open
5. Card interaction: Enter opens drawer (or swaps), P/Start plays focused card
6. Responsive fallback: drawer → modal on screens below `lg`
7. Added DrawerShell to implementation steps and files list

### Plan 005 (Input System)
1. Added Context 5: Detail Drawer with full nav spec
2. Updated Context 4 (Detail Modal) with responsive fallback note
3. Added Focus Management Modes section (modal trap vs drawer split)
4. Added Smart Play Rule table — P/Start always plays focused element
5. Added zone transition with drawer (auto-close on nav up to CW)
6. Added drawer focus rendering details
7. Updated verification checklist with drawer-specific tests

---

## Summary

| Plan | Entity Detail | Presentation | Focus | Dismiss |
|------|--------------|-------------|-------|---------|
| 003 (CW) | DetailPanel in ModalShell | Centered overlay | Trapped | Esc/B/click-outside |
| 004 (Library) | DetailPanel in DrawerShell | 480px right sidebar | Split with grid | Esc/B/close-btn, auto on zone exit |
| 005 (Input) | Context 4 (modal) + Context 5 (drawer) | — | Trap vs split | Per-context rules |
