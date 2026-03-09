# Gamepad Support

**Status:** Pending
**Area:** Frontend input / navigation
**Prerequisites:** Keyboard spatial nav complete (Phase 5a), architecture in `docs/input-system.md`

---

## Context

The library page has a unified input system with keyboard spatial navigation, focus context state machine, per-context focus memory, and input method detection. Mouse and keyboard are first-class. This plan adds Xbox/PlayStation gamepad as the third input method, completing the TV-first experience.

---

## Gamepad API Integration

Create `assets/js/gamepad.js` — a pure module (no DOM coupling) that:

- Polls gamepad state on `requestAnimationFrame`
- Translates buttons/axes to navigation actions matching the existing keyboard action vocabulary
- Feeds actions into the existing spatial nav engine (same code path as arrow keys)
- Handles deadzone filtering for analog sticks

### Button Mapping (Fixed, No Remapping in v1)

| Gamepad Button | Action | Keyboard Equivalent |
|---------------|--------|-------------------|
| A | Select / Open | Enter |
| B | Back / Dismiss | Escape |
| Start (≡) | Smart Play | P |
| D-pad / Left stick | Navigate | Arrow keys |

### Input Method Detection

The existing input method detection (`keyboard` / `mouse` cooldown system) extends to include `gamepad`:
- Any gamepad button/axis input switches mode to `gamepad`
- Mouse movement switches back to `mouse`
- Keyboard input switches to `keyboard`
- Focus ring visibility: shown for `keyboard` and `gamepad`, hidden for `mouse`

---

## Gamepad Hint Bar

A persistent floating bar at the bottom center of the screen showing context-sensitive button mappings.

### Visual Design

```
[D] Navigate    [A] Select    [≡] Play    [B] Back
```

- Glass-nav style background, pill shape (`border-radius: 2rem`)
- Only visible when input method is `gamepad` (hides for mouse/keyboard)
- Entrance/exit: fade + slight translateY

### Contextual Updates

| Context | Hint Bar |
|---------|----------|
| Grid | `[D] Navigate  [A] Open  [≡] Play  [B] —` |
| Modal | `[D] Navigate  [A] Select  [≡] Play  [B] Close` |
| Drawer | `[D] Navigate  [A] Select  [≡] Play  [B] Close` |
| Sidebar | `[D] Navigate  [A] —  [≡] —  [B] —` |

### Controller Detection

- Auto-detect controller type (Xbox, PlayStation, etc.) from Gamepad API `id` string
- Show matching button icons (Xbox: A/B/X/Y, PlayStation: Cross/Circle/Square/Triangle)
- Settings: configurable override for manual controller type selection

---

## Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `assets/js/gamepad.js` | Create | Gamepad API polling, button mapping, deadzone handling |
| `assets/js/input.js` | Modify | Extend input method detection for `gamepad` source |
| `assets/js/hooks/spatial_nav_hook.js` | Modify | Initialize gamepad polling on mount, clean up on destroy |
| `lib/media_centaur_web/live/library_live.ex` | Modify | Hint bar component markup |
| `assets/css/app.css` | Modify | Hint bar styles, gamepad input-method visibility |

---

## Verification

1. **Gamepad detected:** Connect Xbox controller, hint bar appears
2. **D-pad navigation:** Moves focus through CW cards, Library grid, toolbar, sidebar — same paths as arrow keys
3. **A button:** Opens modal (CW) / drawer (Library) — same as Enter
4. **B button:** Closes modal/drawer, exits sidebar — same as Escape
5. **Start button:** Smart plays focused element — same as P
6. **Hint bar context:** Updates when focus moves between grid/modal/drawer/sidebar
7. **Hint bar hides:** Moving mouse hides hint bar, gamepad input shows it again
8. **Controller icons:** Xbox controller shows A/B labels, PlayStation shows Cross/Circle
9. **Analog stick:** Left stick navigates with deadzone filtering, same as D-pad
10. **No regression:** All keyboard and mouse navigation still works identically
11. `mix precommit` passes
