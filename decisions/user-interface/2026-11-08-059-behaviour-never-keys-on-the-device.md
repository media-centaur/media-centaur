---
status: accepted
date: 2026-11-08
---
# Behaviour never keys on the device

## Context and Problem Statement

The one app runs on a desktop browser, on the TV app's WebView and on a phone. Each wants something different: a layout for its window, controls sized for its pointer, a page set that fits the hand holding it, and — the question that raised this record — where a flow ends. Cancel in the plan modal left a phone user on Downloads, a page the phone's bar does not carry. The cheap answer was a device branch: on a compact window, go back instead. Where should a difference between devices live, so that the next one does not become a flag somewhere else?

## Decision Outcome

Chosen option: "each kind of difference has one home, and behaviour is not one of the kinds", because every difference the app has needed so far is a fact the browser already states or a fact the host page already owns, and a server that asks "is this a phone?" would copy the browser's fact into a second place that goes stale on a resize and tempts the next branch.

1. **Layout differs by window class** — in CSS, under the one breakpoint token (`--breakpoint-compact`) and the templates' `max-compact:` utilities. One markup per surface; a compact form is the same component under a media query.
2. **Affordances differ by input class** — in CSS under `pointer`/`hover` media features, and in JavaScript through `matchMedia` where a hook must know (a hover-only scroll arrow, a touch slider). The touch floor belongs to the kit, once.
3. **The page set differs by device** — the bar's compact names (`SidebarLink`'s `compact`) say which pages a phone carries; a page absent from a device is unlisted, never forbidden.
4. **Behaviour never differs by device.** A server-side decision that seems to need the device is keyed on the wrong thing: the host page or the URL carries the fact. The plan modal's Cancel landing on Downloads was not a phone problem but a hosting problem — the picker was the one download surface not hosted by the page that opened it — and the fix (`Live.PlanHost`, every host of the title detail also hosting the plan modal, `overlay_path/2` the one path builder) needs no device anywhere.
5. **The server knows a device only as a paired player's session** (`data-player`, a remote player's identity), never as a sniffed window or user agent.

### Consequences

* Good, because a resize, a rotation or an external display changes nothing the server believes.
* Good, because a new surface has four questions to answer, not a matrix of devices.
* Bad, because a behaviour that truly must differ by device has no sanctioned place; the first such case amends this record rather than adding a flag.
