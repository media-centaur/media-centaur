# Scroll row arrows — design

Date: 2026-10-25. Branch: `remote-players`. Approved by the owner in conversation
(edge arrows; the collection rail included; the disc class named `picture-button`).

A mouse user cannot comfortably move Home's Continue Watching and Recently Added
rows sideways. The rows are `overflow-x: auto` tracks with the scrollbar hidden
and no snap, so a mouse moves them only with Shift+wheel or a trackpad swipe, and
nothing on screen says the rows scroll except the cut-off last card. This design
gives every scroll row a pair of pointer-revealed edge arrows.

## Glossary

| Term | Meaning |
|---|---|
| **Scroll row** | A horizontally scrolling track of cards plus its pointer chrome. The markup named it in `data-scroll-row`, an attribute nothing read; the component takes the name and the attribute goes. Home's Continue Watching and Recently Added rows and the title detail's collection rail are scroll rows. The hero's single full-bleed item is not. |
| **Track** | The `.row-scroll` element that scrolls. It owns the ring reserve, the hidden scrollbar, the cursor peek and the edge fades (`app.css`). |
| **Edge arrow** | A button at one end of a scroll row that moves the track one step toward that end. Shown on hover, gone at the end it points to. |
| **Edge state** | Whether the track is at its start, at its end, both (it fits) or neither. The track's own geometry, projected as `data-at-start` and `data-at-end` on the track. |
| **Step** | How far one arrow press moves the track: one scrollport width minus one card and its gap, so the last visible card stays as the reader's anchor. |
| **Picture button** | The house disc control over a picture: a dark translucent disc with a light border, primary on hover, sinking on press. The play overlay's button is one; an edge arrow is one. |
| **Pointer affordance** | A control that exists only for a pointer: a reveal wrapper that fades in on hover (opacity only, after `--hover-reveal-delay`) around a control that is outside the input system (`tabindex="-1"`, no `data-nav-item`) and never takes the cursor; never seen by keyboard, gamepad or the TV. The play overlay set the rule (UIDR-027). |
| **Glider** | The input system's scroll animator (`scroll_glide.js`). The page's one scroll motion. |

## Core idea

An edge arrow is a second instance of what the play overlay already is: a
pointer affordance drawn as a picture button over a browse surface. Everything
below follows from that: how it reveals, what draws it, what moves the track,
and why the TV never sees it.

## Design

### The scroll row component

`MediaCentaurWeb.Components.ScrollRow.scroll_row/1` renders a scroll row: a
`relative` wrapper carrying the `ScrollRow` hook, the track for the chosen
variant with the caller's cards in its inner block, and the two edge arrows
over the track's ends.

```heex
<ScrollRow.scroll_row id="continue-watching-row" variant={:backdrop_lg}
  data-component="continue-watching">
  <div :for={item <- @items} ... data-row-item data-nav-item>…</div>
</ScrollRow.scroll_row>
```

- `id` (required): the hook needs one.
- `variant`: `:backdrop_lg` (Continue Watching), `:poster` (Recently Added),
  `:backdrop_sm` (the collection rail). Each maps to the existing
  `.row-scroll-*` class. No default, as the CSS has none.
- `rest` (global): lands on the track, so `data-component` and the collection
  rail's `data-nav-zone="detail_rail"` keep their places and every existing
  test selector and nav zone holds. The old `data-scroll-row` attribute, which
  nothing read, goes from the rows and the hero.

The arrows, each the play overlay's shape — a reveal wrapper around the disc:

```heex
<div class="scroll-row-arrow" data-scroll-row-arrow="left">
  <button type="button" class="picture-button" tabindex="-1" aria-label="Scroll left">
    <.icon name="hero-chevron-left-mini" class="size-5" />
  </button>
</div>
```

The wrapper fades and positions; the button presses. `aria-label`, not
`aria-hidden`: an icon-only control keeps its accessible name (the house rule
behind MC0042), and `tabindex="-1"` keeps it out of the tab order.

Tenants: `ContinueWatchingRow`, `PosterRow` and `Detail.CollectionRail` render
their track through `scroll_row/1`. The hero keeps its plain `.row-scroll-hero`
track: one full-bleed item has nothing to scroll.

### The picture button

The disc's drawing moves out of `.play-overlay-btn` into `.picture-button`:
flex centring of the glyph, the round shape, `color: white`, the
`base-100`-at-75% background, the 1.5px light border, `cursor: pointer`,
primary on hover, the sink and darkening on `:active`, the transitions and the
reduced-motion rule. `.play-overlay-btn` keeps what is the play button's own:
its absolute centring in the card, its two sizes, `pointer-events: auto` (its
wrapper is pointer-transparent), and the release ring (`::after`), which
answers the player's window delay. The picture button block sits above the
play overlay's in `app.css`: primitive before composer. Both buttons carry both
classes where they apply. No visual change to the play button.

The hover-intent delay token `--play-overlay-reveal-delay` becomes
`--hover-reveal-delay`: it is the delay before any hovered pointer affordance
reveals, and the scroll row uses the same one, so skimming the pointer across
the page shows nothing.

### Reveal and edge state (CSS)

The reveal is one rule for both pointer affordances, grouped:

```css
.play-overlay, .scroll-row-arrow { opacity: 0; transition: opacity 240ms ease; }
@media (hover: hover) {
  .play-overlay-host:hover .play-overlay,
  .scroll-row:hover .scroll-row-arrow { opacity: 1; transition-delay: var(--hover-reveal-delay); }
}
```

Who takes the pointer is each affordance's own, not the disc's: `.picture-button`
sets no `pointer-events`. The play overlay's wrapper is always `pointer-events:
none` (card clicks pass through) and `.play-overlay-btn` is `auto`; the arrow's
wrapper is `none` until hovered, when it turns `auto` and the disc inherits it,
so a hidden arrow never takes a click meant for the card beneath.

The arrow's own rules place it and drop it at a reached end:

```css
.scroll-row { position: relative; }
.scroll-row-arrow { position: absolute; top: 50%; translate: 0 -50%; z-index: 3; pointer-events: none; }
@media (hover: hover) { .scroll-row:hover .scroll-row-arrow { pointer-events: auto; } }
.scroll-row-arrow[data-scroll-row-arrow="left"]  { left: 0.5rem; }
.scroll-row-arrow[data-scroll-row-arrow="right"] { right: 0.5rem; }
.scroll-row-arrow .picture-button { width: 44px; height: 44px; }
.row-scroll[data-at-start] ~ .scroll-row-arrow[data-scroll-row-arrow="left"],
.row-scroll[data-at-end]   ~ .scroll-row-arrow[data-scroll-row-arrow="right"] { display: none; }
```

The arrows sit inside the track's ends, over the edge fade, vertically centred
on the cards, above a hovered card's `z-index: 2`. The exact inset is settled
against a screenshot. Opacity is the only animated property on the wrapper;
the disc's own transitions stay on `.picture-button`. A row that fits carries
both edge attributes and shows no arrows. The hidden arrow is `display: none`,
not opacity 0, so it can never take a click.

The reveal is gated on `(hover: hover)`, the same query the hook asks, so there
is one pointer truth: where no pointer can hover, neither chrome nor listener
exists. Without the gate a touch device's sticky hover would reveal arrows that
the unattached hook never answers. The TV draws the same composition and has
no hovering pointer, so it sees none.

### The hook

`assets/js/hooks/scroll_row.js`, `ScrollRow`, mounted on the wrapper.

- **Attach only where a pointer is.** On `mounted()`, if
  `matchMedia("(hover: hover)")` does not match, the hook does nothing: no
  listeners, no observer. The TV's glide frames carry no scroll listener. One
  truth for CSS and JS. Which answer the Sony's WebView gives is a check for
  when the TV is free; either answer is correct, the check is about cost.
- **Edge state.** `edges({ scrollLeft, scrollWidth, clientWidth })` is a pure
  function returning `{ atStart, atEnd }` with a 1px tolerance. The hook writes
  `data-at-start` / `data-at-end` on the track from a passive `scroll`
  listener on the track and a `ResizeObserver` on it, and re-asserts them in
  `updated()`: morphdom syncs patched elements back to the server's markup and
  wipes client-written attributes (the branch's `DetailScrollGeometry` note).
- **Step.** `step({ clientWidth, cardWidth, gap })` returns
  `clientWidth - (cardWidth + gap)`, floored at `cardWidth`. Card width is the
  track's first element child's `offsetWidth`; the gap is the track's computed
  `column-gap`. Layout pixels throughout, never `getBoundingClientRect`, since
  the UI runs under a root zoom.
- **A press glides.** A click on `[data-scroll-row-arrow]` (delegated on the
  wrapper) calls `glider.glide(track, { left: target })` with the target
  clamped to `[0, scrollWidth - clientWidth]`. The glider clamps per frame as
  well.
- **Focus.** Chrome never takes the cursor: the hook prevents default on
  `mousedown` within `[data-scroll-row-arrow]`, so a press leaves focus where
  it was. Without that, Chromium would focus the `tabindex="-1"` button, and
  in the collection rail — where the arrows sit outside every nav zone — the
  input system's reconciler would read that as *foreign focus*
  (`hasForeignFocus`, ADR-053) and cede the cursor to a piece of chrome. The
  play button has no such problem: it lives inside a card, inside a zone.

### One glider

`assets/js/scroll_glider.js` creates the page's glider once:

```js
export const scrollGlider = createScrollGlide({
  requestAnimationFrame: fn => globalThis.requestAnimationFrame(fn),
  now: () => performance.now(),
})
```

`input/config.js` passes it as `inputConfig.glider`, which `createDomWriter`
already accepts; the hook imports the same instance. Consequences, for free:
the orchestrator's wheel rule (`cancelScrollMotion` on any wheel event) cancels
an arrow glide where it stands, and a cursor key pressed mid-glide retargets
the same track instead of racing a second animation.

### Out of scope

- The wheel over a row stays the browser's: vertical wheel scrolls the page,
  Shift+wheel and trackpad swipe scroll the row. No hijack.
- No drag-to-scroll.
- The hero.
- The person rail on Social, which is not a `.row-scroll`.

## Testing

- **Bun, `assets/js/hooks/scroll_row.test.js`:** `edges` at start, middle, end
  and for a track that fits; `step` for a wide and a narrow scrollport; a
  mounted hook writes the edge attributes from the track's geometry and
  updates them on `scroll`; a press on each arrow calls the glider with the
  clamped target; with `(hover: hover)` unmatched the hook attaches nothing.
  Stubs through `test_support/dom_stubs.js`.
- **Bun, input tests:** `inputConfig.glider` is the shared instance (one
  assertion in the config tests).
- **ExUnit, `home_live_test.exs`:** both rows render inside a `.scroll-row`
  with two `[data-scroll-row-arrow]` buttons, and the existing
  `[data-component]` selectors still hold. `detail_panel` tests: the
  collection rail's track keeps `data-nav-zone="detail_rail"`.
- **Storybook:** `storybook/composites/scroll_row.story.exs` with placeholder
  cards and four variations by attribute fixture (through `rest`, which lands on the track): at start, mid-row, at end,
  fits. The storybook iframe loads no hooks, so the fixtures are the state
  matrix. Enforced by MC0009 and the storybook compile and render tests. The
  existing `storybook/play_overlay/play_overlay.story.exs` renders unchanged.
- **Browser:** `page-shot` of Home at 1920×1080 with the pointer over each row
  (via `chromium-probe` hover) showing the arrows; a press moves the row by one
  step; at the row's end the right arrow is gone.
- `mix precommit` green.

## Verification items

- The Sony's WebView `(hover: hover)` report, read through `mc-tv` when the TV
  is free. If it matches, the hook attaches on the TV at the cost of one passive
  scroll listener per row; the arrows still never show. Record the answer in
  the remote-players campaign.

## Amendment 2026-10-25, after the browser walk

The disc's size is `.picture-button`'s one size, 52 px; the 44 px rule above
went (the arrows read too small, and a second size was a second
representation). The story carries six variations, not four: a Credo check
requires every `variant` value exercised, and a full-width template keeps the
row in the sandbox's column. The walk's other findings are recorded in the
plan's Task 7.
