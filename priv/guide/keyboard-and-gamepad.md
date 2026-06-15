---
title: Keyboard & gamepad
part: Watching
slug: keyboard-and-gamepad
order: 11
---
The whole app is built to run without a mouse — by keyboard at your desk, or by gamepad from
the couch. Both drive the same navigation model, so once you know one you know both.

## The model

Navigation is focus-based. The screen is divided into contexts — a grid, a shelf, a toolbar,
the sidebar, a modal — and an arrow key moves focus within the current context; reaching an
edge crosses into the neighbouring one. The core actions:

- **Arrows** — move focus up / down / left / right
- **Enter** — select or activate what's focused
- **Escape** — go back: close an overlay, leave the sidebar
- **`[` / `]`** — cycle between zones (Watching, Library, Upcoming, Settings…)
- **`` ` ``** (backtick) — toggle the Console drawer from anywhere

The app remembers where you were in each zone, so leaving and coming back puts focus where
you left it rather than resetting to the top.

## Gamepad

Plug a standard controller into the machine running the app (not a remote browser), and it's
detected automatically. It maps onto the same actions:

- **D-pad or left stick** — move focus (it repeats if you hold a direction)
- **A / Cross** — select · **B / Circle** — back · **Y / Triangle** — clear a filter
- **LB/RB or L1/R1** — previous / next zone · **Start** — play the focused title

A hint bar along the bottom shows the available actions with labels matching your controller,
and you can switch between Xbox and PlayStation glyphs.

> [!TIP]
> Gamepad input only registers when the app window is actually focused and visible — a
> deliberate gate so a backgrounded window or a headless browser can't quietly capture your
> controller. If the pad seems dead, click the window first. (Keyboard doesn't need this; the
> OS already routes keys to the focused window.)

## Remapping

Every binding is yours to change under **Settings → Controls**. Pick an action's keyboard or
gamepad slot, press the key or button you want, and it's saved — the change takes effect
immediately, with no reload. You can reset a category, or everything, back to the defaults.

In short: a focus-and-arrows model shared by keyboard and gamepad, the backtick for the
Console, a controller plugged into the host for couch use (when the window's focused), and
every binding remappable live under Settings → Controls.
