---
status: accepted
date: 2026-10-25
---
# The TV app is the performance floor

Campaign: `campaigns/remote-players.md`. The rules, the device and how to measure: [`docs/tv-performance.md`](../../docs/tv-performance.md).

## Context and Problem Statement

The host's pages render in the TV app's Android WebView on a Sony BRAVIA (MediaTek MT5895, 3 GB of RAM) as well as in desktop browsers. On 2026-10-24/25 the TV glided at 9–14 fps through the library while the desktop showed nothing wrong: backdrop blur over every poster card and a fixed-attachment body background each cost the TV what a desktop GPU absorbs without trace. Nothing in the process caught it, because every check ran on the desktop.

## Decision Outcome

1. The TV app is the performance floor: a UI change is done when it holds on the TV. The floor device is the slowest one the app supports — today the Sony.
2. A change touching CSS, layout, images, animation, scrolling or the input system's motion is measured on the TV against its base, interleaved in one run (`mc-tv-smooth`), and lands with no regression beyond the noise between rounds. The numbers go in the commit or the campaign.
3. The rules learned so far are standing rules (the doc lists each with its measurement): no backdrop blur on a remote player; no `background-attachment: fixed`; animate only `transform` and `opacity`; nothing added to a scroll frame's main-thread work; images decoded no larger than the display; the TV draws the 1920 px composition.
4. Where a rule can be checked mechanically it is a test (`tv_performance_css_test.exs`), not prose.
5. Smoothness is measured as presented frames on the device, never as the page's `requestAnimationFrame` rate.

### Consequences

* UI work costs a TV run when it touches the listed areas; the owner's TV doubles as the development machine's display, so the run waits for a moment it is free.
* Desktop-only visual effects that the TV cannot afford are scoped off on a remote player (`data-player="remote"`) rather than dropped everywhere, where the effect is worth keeping on the desktop.
