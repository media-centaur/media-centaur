---
title: Keyboard & gamepad
part: Watching
slug: keyboard-and-gamepad
order: 11
---
The whole app runs without a mouse — by keyboard at the desk or by gamepad from the couch.
Both drive the same focus-based navigation: the screen is divided into contexts (a grid, a
shelf, the sidebar, a modal), an arrow moves focus within the current one, and reaching an
edge crosses into the next. Focus position is remembered per zone.

## Keyboard

| Key | Action |
|---|---|
| Arrows | Move focus up / down / left / right |
| Enter | Select or activate the focused item |
| Escape | Go back — close an overlay, leave the sidebar |
| `[` / `]` | Cycle between zones (Watching, Library, Upcoming, Settings…) |
| `` ` `` (backtick) | Toggle the Console drawer from anywhere |

## Gamepad

Plug a standard controller into the machine running the app (not a remote browser); it's
detected automatically.

| Button (Xbox / PlayStation) | Action |
|---|---|
| D-pad or left stick | Move focus (repeats while held) |
| A / Cross | Select |
| B / Circle | Back |
| Y / Triangle | Clear a filter |
| LB / L1, RB / R1 | Previous / next zone |
| Start | Play the focused title |

A hint bar shows the available actions with labels matching your controller; switch between
Xbox and PlayStation glyphs in Settings.

## Remapping

Rebind any action under **Settings → Controls**: pick the action's keyboard or gamepad slot,
press the key or button, and it saves and takes effect immediately — no reload. Reset a
category, or everything, to the defaults from the same page.

> [!TIP]
> Gamepad input only registers when the app window is focused and visible — a deliberate gate
> so a backgrounded window or a headless browser can't capture your controller. If the pad
> seems dead, click the window first. (Keyboard needs no such gate; the OS already routes keys
> to the focused window.)
