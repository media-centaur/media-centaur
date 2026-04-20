# Settings → Controls page — design spec

**Date:** 2026-04-20
**Status:** Accepted
**Scope:** A new Settings subpage for customizing keyboard and gamepad bindings and viewing a cheat sheet of every binding in the app.

## Goal

Give users a single place to:

1. **See** every keyboard key and gamepad button the app responds to, grouped by purpose.
2. **Rebind** any of them with a press-to-capture interaction.
3. **Clear** any binding explicitly (empty state is a valid choice, not an error).
4. **Reset** individual bindings, categories, or the whole page to defaults.

The page doubles as a cheat sheet — each row shows the current binding regardless of whether the user is in "edit" mode — so there is no separate view page.

## Non-goals

- Modifier combos (`Shift+X`, `Ctrl+Y`). Single-key bindings only, matching today's input system.
- Multiple dark theme variants. Covered by a separate future spec; this page styles itself for today's `dark` theme while using daisyUI tokens + three new custom properties so the next theme drops in cleanly.
- Light theme support. Dark-only per project direction.
- Per-user profiles (single-user app).
- E2E test coverage of remap interactions in v1.

## Architecture

### Module layout

| Module | Responsibility | Boundary deps |
|---|---|---|
| `MediaCentarr.Controls` (facade) | Public API: `get/0`, `put/3`, `clear/2`, `reset_category/1`, `reset_all/0`, `subscribe/0`, `glyph_style/0` | `Settings` |
| `MediaCentarr.Controls.Catalog` | Compile-time list of `%Binding{}` structs — the single source of truth for every binding, its metadata, and its defaults | (none) |
| `MediaCentarr.Controls.Store` | Reads/writes `Settings.Entry` rows, decodes JSON, applies defaults for missing keys | `Settings` |
| `MediaCentarrWeb.SettingsLive.Controls` | LiveView section rendered inside `SettingsLive` (same pattern as `Overview`, `SystemSection`) | `Controls`, `Settings` |
| `MediaCentarrWeb.SettingsLive.ControlsLogic` | Pure helpers: catalog→view model, conflict detection, swap resolution, glyph-style display mapping | (none) |

A full bounded context is not justified for ~11 bindings; `Controls` is a thin facade over `Settings.Entry` plus a catalog and conflict logic. It still follows the context facade subscribe pattern (ADR).

### The binding catalog

`MediaCentarr.Controls.Catalog` exposes `all/0` returning a list of:

```elixir
%MediaCentarr.Controls.Binding{
  id: :navigate_up,                 # atom, stable forever
  category: :navigation,            # :navigation | :zones | :playback | :system
  name: "Move up",                  # display string
  description: "Focus the item above the current one",
  default_key: "ArrowUp",           # KeyboardEvent.key value, or nil
  default_button: 12,               # gamepad button index, or nil
  scope: :input_system              # :input_system | :global
}
```

Initial catalog (v1):

| id | category | name | default_key | default_button | scope |
|---|---|---|---|---|---|
| `:navigate_up` | navigation | Move up | `"ArrowUp"` | 12 | input_system |
| `:navigate_down` | navigation | Move down | `"ArrowDown"` | 13 | input_system |
| `:navigate_left` | navigation | Move left | `"ArrowLeft"` | 14 | input_system |
| `:navigate_right` | navigation | Move right | `"ArrowRight"` | 15 | input_system |
| `:select` | navigation | Select | `"Enter"` | 0 | input_system |
| `:back` | navigation | Back | `"Escape"` | 1 | input_system |
| `:clear` | navigation | Clear | `"Backspace"` | 3 | input_system |
| `:zone_next` | zones | Next zone | `"]"` | 5 | input_system |
| `:zone_prev` | zones | Previous zone | `"["` | 4 | input_system |
| `:play` | playback | Play | `"p"` | 9 | input_system |
| `:toggle_console` | system | Toggle console | `` "`" `` | nil | global |

Adding a binding later = one struct added to the catalog.

### Data model & persistence

Three `Settings.Entry` rows, one key each:

- **`controls.keyboard`** — JSON object mapping `binding_id_string → key_string`. Missing key ⇒ use default. Explicit JSON `null` ⇒ user-cleared (unbound).
- **`controls.gamepad`** — JSON object mapping `binding_id_string → button_index` (integer). Same missing/null semantics.
- **`controls.glyph_style`** — `"xbox"` (default) or `"playstation"`. Display-only; does not affect runtime.

Example after a user rebinds Select to Space and clears Back:

```json
// controls.keyboard
{"select": " ", "back": null}
```

`Controls.get/0` returns a map keyed by binding id with both `:key` and `:button` resolved (explicit user value if set — including `nil` for cleared — else default):

```elixir
%{
  navigate_up: %{key: "ArrowUp", button: 12},
  select: %{key: " ", button: 0},
  back: %{key: nil, button: 1},
  ...
}
```

### Write path: conflict detection and auto-swap

`Controls.put(binding_id, :keyboard | :gamepad, value)`:

1. Resolve the current **full** map via `get/0`.
2. Find any other binding currently using `value` (for the same kind — keyboards don't conflict with gamepad indices).
3. If a conflict exists:
   - Capture the **currently-resolved** value of `binding_id` — this is what the user sees in the row right now (the user's stored override if any, otherwise the catalog default, which may be `nil`).
   - The displaced binding gets that resolved value (true swap).
   - Catalog invariant: default values are unique per kind (no two bindings share a default key, no two share a default button). This is enforced by a compile-time assertion in `Catalog`.
4. Apply both writes to `Settings.Entry` inside an `Ecto.Multi`.
5. Broadcast `{:controls_changed, new_map}` on topic `"controls:updates"`.

Clearing — `Controls.clear(binding_id, :keyboard | :gamepad)` — does **not** swap. It writes an explicit `null` for that slot. Auto-swap is a convenience for rebinding; clearing is an intentional un-binding and must be non-destructive to other bindings.

**Listening-state cancel key.** `Escape` is always hardcoded as the cancel during listening state, regardless of the user's `:back` binding. This avoids a lock-out if the user rebinds `:back` to a key and then wants to cancel.

### PubSub topic

New topic in `MediaCentarr.Topics`:

```elixir
def controls_updates, do: "controls:updates"
```

`MediaCentarr.Controls.subscribe/0` wraps the subscribe call (context facade pattern, per the custom Credo check).

### JS integration

The input system's `core/actions.js` already supports a custom key/button map parameter. Two pieces wire it to runtime config:

1. **Initial load.** `MediaCentarrWeb.Layouts.root` reads `Controls.get/0` server-side and renders the current bindings as a `data-input-bindings="…"` attribute on the root LiveView container (JSON-encoded). `assets/js/input/index.js`'s `createInputHook()` reads that attribute and passes the resulting `keyMap` and `buttonMap` into `KeyboardSource` / `GamepadSource` / `orchestrator`. The existing `DEFAULT_KEY_MAP` / `DEFAULT_BUTTON_MAP` become the fallback when no attr is present.

2. **Hot-swap on change.** On `{:controls_changed, map}`, the Controls LiveView pushes `phx:controls:updated` to the client with the new maps. A small bridge module `assets/js/input/controls_bridge.js` listens for this window event and rebuilds maps in the running input hook. No page reload.

3. **Global bindings.** For the `:toggle_console` binding (scope `:global`), `app.js`'s capture-phase keydown listener also reads the current binding from a separate data attr (`data-global-bindings`) and listens for `phx:controls:updated`. Default remains `` ` ``.

4. **One-shot capture listener (for remap).** When the LiveView enters listening state for keyboard, it pushes `phx:controls:listen` with `{kind: "keyboard"}`. The bridge installs a one-shot `window.addEventListener("keydown", handler, {capture: true, once: true})` that preventDefaults, reads `event.key`, pushes `"controls:bind"` back to the server with the value, and the LiveView's `handle_event` calls `Controls.put/3`. `Escape` is special-cased to push `"controls:cancel"` instead. For gamepad, the bridge hooks into the existing `GamepadSource`'s button-edge detection for a single next edge, same shape.

### UI specification

Rendered inside `SettingsLive` under section id `"controls"`, placed **in the General group** between `preferences` and `library` (so the `@sections` list gains one entry).

#### Page structure

```
┌ Page header ─────────────────────────────────────────────┐
│  Controls                         [Reset all to defaults]│
│  Customize keyboard and gamepad bindings.                │
│  [PlayStation / Xbox] glyph toggle                       │
├──────────────────────────────────────────────────────────┤
│ Navigation  (7 bindings)                  Reset category │
│   Move up         │ Key [↑]      Pad [D-Pad Up]   [✎ ✕]  │
│   Move down       │ Key [↓]      Pad [D-Pad Down] [✎ ✕]  │
│   ...                                                     │
├──────────────────────────────────────────────────────────┤
│ Zones  (2 bindings)                       Reset category │
│   Next zone       │ Key []]      Pad [R1]         [✎ ✕]  │
│   Previous zone   │ Key [[]      Pad [L1]         [✎ ✕]  │
├──────────────────────────────────────────────────────────┤
│ Playback (1) ...                                          │
├──────────────────────────────────────────────────────────┤
│ System (1) ...                                            │
└──────────────────────────────────────────────────────────┘
```

Each binding row:
- **Left:** action name (bold) + description (muted).
- **Right-center:** `Key` label + keycap glyph; `Pad` label + gamepad glyph.
- **Right:** pencil (remap) and X (clear) icons, visible on row hover OR when the row is in listening state.

#### Visual treatment

- Keycap: custom CSS gradient + shadow to feel like a physical key. Sized per content (arrow keys square, word keys wider).
- Gamepad glyph: circular button with colored face-button glyphs (green ✕ for A/Cross, red ○ for B/Circle, blue □ for X/Square, yellow △ for Y/Triangle). D-pad rendered with arrow SVG. Shoulders as rounded pills. Options button as a small chip.
- Glyph-style toggle swaps labels: Xbox shows "A / B / X / Y / LB / RB / Menu", PlayStation shows "✕ / ○ / □ / △ / L1 / R1 / Options". Button indexes themselves are identical — glyphs are display-only.
- Unbound slot: dashed outline with "unset" placeholder, muted.
- Listening slot: pulsing primary-colored border + "press…" placeholder + a banner row `Press any key to bind <action>. Esc to cancel.`
- No connected gamepad: remap button for the `Pad` slot is disabled with tooltip "Connect a controller to remap". Keyboard slot remains fully usable.

#### Styling scope

- All custom CSS in a new file `assets/css/controls.css`, imported by `app.css`. Rules are scoped to `[data-page="controls"]` on the LiveView container so no global bleed.
- Color values use daisyUI tokens (`bg-base-100`, `text-primary`, `border-base-300`).
- Three new custom props define the keycap look, inside `[data-theme="dark"]`:
  - `--keycap-top` — gradient top stop
  - `--keycap-face` — gradient bottom stop
  - `--keycap-glow` — pulse accent
- When the future "Midnight" theme lands, it adds its own block with alternate values. No changes to this page required.

#### CSS animation rules compliance

- The "listening" pulse uses CSS `@keyframes` but is applied to a **single non-stream row**, not a LiveView stream item. Safe per the project's CSS rules.
- No `backdrop-filter` on any element.
- Only `opacity` and `transform` animated.

### Event flow — remap keyboard example

```
User clicks pencil on "Move down (keyboard)"
  LiveView: assign listening = {:keyboard, :navigate_down}
  LiveView: push_event "controls:listen", %{kind: "keyboard"}
  Row enters listening visual state

Client bridge installs one-shot capture listener

User presses F2
  Bridge: event.preventDefault(); event.stopPropagation()
  Bridge: pushEvent "controls:bind", %{id: "navigate_down", kind: "keyboard", value: "F2"}

LiveView handle_event "controls:bind"
  Controls.put(:navigate_down, :keyboard, "F2")
    Store resolves current map; finds "F2" unused; writes {"navigate_down": "F2"}
    Broadcast {:controls_changed, map}

LiveView handle_info {:controls_changed, map}
  assign bindings = map, listening = nil
  push_event "controls:updated", %{keyboard: ..., gamepad: ...}

Bridge receives "controls:updated" → rebuilds input system maps live
Console hotkey listener in app.js also receives and rebinds if :toggle_console changed
```

If `value` was already in use by another binding, `Controls.put/3` performs the swap (see Write path) and the same broadcast covers both rows.

## Testing

### Elixir (ExUnit)

**Pure, `async: true`:**

- `ControlsTest.Catalog` — lookup by id, lookup by category, defaults present for every binding, ids/categories consistent.
- `SettingsLive.ControlsLogicTest` — view model grouping by category; glyph-style display mapping (button index → glyph string for xbox/playstation); conflict detection given an arbitrary current map.

**Resource, `DataCase`:**

- `ControlsTest` — full flow:
  - `get/0` returns defaults when no entries.
  - `put/3` writes override, `get/0` reflects it.
  - `put/3` with existing conflicting value performs swap (both rows updated atomically).
  - `clear/2` sets `nil`, does not affect any other binding.
  - `reset_category/1` removes overrides only for the requested category.
  - `reset_all/0` removes all overrides.
  - Broadcast asserted via `Controls.subscribe/0` → receive.

**LiveView integration:**

- `SettingsLive.ControlsTest` — mount shows all 11 bindings; click pencil → listening assign set; server-side `"controls:bind"` event updates the slot; reset buttons work.

### JavaScript (bun)

- `actions.test.js` — extend existing tests: custom `keyMap` param actually overrides defaults; nil/undefined entries behave as "not bound".
- `controls_bridge.test.js` (new) — one-shot capture listener fires exactly once; `Escape` during listen pushes cancel, not bind; `phx:controls:updated` replaces `keyMap` and `buttonMap` on the mock orchestrator.

### E2E

Not in v1. Document as a future candidate: one parameterized test that rebinds Select to Space and confirms Space activates a library card.

## Wiki updates (same unit of work)

- **`Keyboard-and-Gamepad.md`** — new section "Customizing bindings" pointing at Settings → Controls with a screenshot; update any stale claims about hardcoded bindings.
- **`Keyboard-Shortcuts.md`** — replace the hand-maintained table with (a) a note that Settings → Controls is the authoritative list, and (b) the default bindings for reference.

## Rollout / migration

- No existing user data to migrate. The input system already reads from frozen defaults today; swap the module to read from `data-input-bindings` + fall back to frozen defaults means zero behavior change for users who never visit the Controls page.
- `app.js`'s backtick hotkey moves from hardcoded to attr-driven in the same PR that ships the Controls page (otherwise the catalog has a binding the user can't actually rebind yet, which is worse than shipping nothing).

## Open risks

- **Gamepad capture UX requires a live pad.** If a user has no gamepad, they cannot remap gamepad bindings. Acceptable — the row still shows the default button and label, the keycap side is fully usable, and the remap button tooltip explains.
- **`KeyboardEvent.key` locale sensitivity.** Non-US layouts produce different `key` values for the same physical key. Current input system already has this property; Controls page stores whatever `event.key` produces. If users on AZERTY report issues, the fix is future work (probably display both `.code` and `.key`).
- **Config import/export.** Users who wipe the DB lose their bindings. Acceptable for v1 — bindings are lightweight to re-enter. Future: add a toml export/import on the Controls page.
