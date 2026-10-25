# Scroll Row Arrows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every scroll row (Home's Continue Watching and Recently Added, the title detail's collection rail) gets a pair of pointer-revealed edge arrows that glide the track one step, drawn as the house picture button and moved by the input system's one glider.

**Architecture:** One component, `ScrollRow.scroll_row/1`, owns the track and its arrows; the three row components become its tenants. The `ScrollRow` hook projects the track's edge state (`data-at-start` / `data-at-end`) onto the track and glides it on a press through a page-wide glider instance that the input system's DOM writer also uses. The play overlay's disc drawing becomes `.picture-button`, shared with the arrows. Spec: `docs/superpowers/specs/2026-10-25-scroll-row-arrows-design.md`.

**Tech Stack:** Phoenix function components + HEEx, Phoenix Storybook, Tailwind v4 CSS in `assets/css/app.css`, LiveView hooks in plain JS, bun tests, ExUnit.

**Branch:** `remote-players`, in the main checkout. Every `mix` runs as `~/scripts/agents/agent-mix` (CLAUDE.md). bun tests run from the repository root: `bun test assets/js/...`.

---

## File structure

| File | Responsibility |
|---|---|
| `assets/css/app.css` | `.picture-button` (split from `.play-overlay-btn`), `--hover-reveal-delay`, `.scroll-row` and `.scroll-row-arrow` rules |
| `lib/media_centaur_web/components/play_overlay.ex` | Carries `picture-button` on its button; doc names the shared disc |
| `assets/js/scroll_glider.js` | The page's one glider instance |
| `assets/js/input/config.js` | Hands the glider to the DOM writer (`glider:`) |
| `assets/js/hooks/scroll_row.js` | `edges`, `step`, and the `ScrollRow` hook |
| `assets/js/hooks/scroll_row.test.js` | Hook tests |
| `assets/js/app.js` | Registers `ScrollRow` |
| `lib/media_centaur_web/components/scroll_row.ex` | `scroll_row/1`: wrapper + track + two edge arrows |
| `storybook/composites/scroll_row.story.exs`, `storybook/composites/_composites.index.exs` | Story and index entry |
| `lib/media_centaur_web/components/continue_watching_row.ex`, `poster_row.ex`, `detail/collection_rail.ex` | Tenants |
| `test/media_centaur_web/live/home_live_test.exs`, `test/media_centaur_web/page_smoke_test.exs` | Row assertions |
| `.claude/skills/user-interface/SKILL.md`, `docs/input-system.md` | Component inventory row; the one-glider note |

---

### Task 1: The picture button

**Files:**
- Modify: `assets/css/app.css` (the play overlay block, lines ~2222–2340)
- Modify: `lib/media_centaur_web/components/play_overlay.ex`
- Test: `test/media_centaur_web/storybook_render_test.exs` (existing, `play_overlay` story)

- [ ] **Step 1: Move the disc's drawing into `.picture-button`**

In `assets/css/app.css`, replace the `:root` token and the `.play-overlay-btn` rules so the file reads:

```css
/* The delay before a hovered pointer affordance reveals (the play overlay,
   a scroll row's edge arrows): skimming the pointer across the page shows
   nothing. Tune freely. */
:root {
  --hover-reveal-delay: 450ms;
}
```

and the hover rule uses it:

```css
.play-overlay-host:hover .play-overlay {
  opacity: 1;
  transition-delay: var(--hover-reveal-delay);
}
```

Then split the button. The disc's drawing is `.picture-button`; the play button keeps its centring, sizes and release ring:

```css
/* ── Picture button ──
   The house disc control over a picture: a dark translucent disc with a
   light border, primary under the pointer, sinking while pressed. The
   play overlay's button is one; a scroll row's edge arrow is one. Every
   transition is a compositor property or a colour. */
.picture-button {
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 9999px;
  color: white;
  background: oklch(from var(--color-base-100) l c h / 0.75);
  border: 1.5px solid oklch(100% 0 0 / 0.85);
  cursor: pointer;
  /* The release half of the press: the disc settles back to size with a
     barely-there overshoot (the same curve also runs when the pointer
     lets go after a drag-off, which is the right answer for that case
     too). */
  transition:
    background-color 100ms ease,
    border-color 100ms ease,
    scale 240ms cubic-bezier(0.3, 1.15, 0.5, 1);
}

.picture-button:hover {
  background: var(--color-primary);
  border-color: var(--color-primary);
}

/* mousedown — the disc sinks and darkens at once (near-zero transition so
   there is no easing to wait on) and holds while pressed. */
.picture-button:active {
  scale: 0.88;
  background: color-mix(in oklab, var(--color-primary) 82%, black);
  border-color: color-mix(in oklab, var(--color-primary) 82%, black);
  transition-duration: 40ms;
}

@media (prefers-reduced-motion: reduce) {
  .picture-button {
    transition-duration: 100ms;
  }
}

/* The play button: a picture button centred in the card, with a release
   ring of its own. The server starts the player, and the player's window
   takes a moment to appear, so the click has to answer on the spot or it
   feels dropped: on release a primary ring leaves the disc's edge, growing
   a little past it as it fades — a quiet exhale, not a burst. The ring is
   a pseudo-element so the glyph never moves out from under the pointer,
   and `scale`/`translate` are separate properties so the press never
   disturbs the centring translate. */
.play-overlay-btn {
  position: absolute;
  left: 50%;
  top: 50%;
  translate: -50% -50%;
  width: 52px;
  height: 52px;
  /* This button's: its wrapper is pointer-transparent so card clicks pass
     through, and only the disc takes the pointer. */
  pointer-events: auto;
}

.play-overlay-btn::after {
  content: "";
  position: absolute;
  inset: -2px;
  border-radius: inherit;
  border: 2px solid var(--color-primary);
  pointer-events: none;
  opacity: 0;
  scale: 1.35;
  transition:
    opacity 360ms ease-out,
    scale 360ms cubic-bezier(0.2, 0.8, 0.2, 1);
}

.play-overlay-btn:active::after {
  opacity: 0.6;
  scale: 1;
  transition: none;
}

@media (prefers-reduced-motion: reduce) {
  .play-overlay-btn::after {
    transition: none;
  }
}

.play-overlay-btn-lg {
  width: 64px;
  height: 64px;
}
```

Delete the old `.play-overlay-btn`, `.play-overlay-btn:hover`, `.play-overlay-btn:active`, `::after` rules and the old reduced-motion block so nothing is defined twice. Keep the prose comment above `.play-overlay` and update its mention of the token name to `--hover-reveal-delay`.

- [ ] **Step 2: The play button carries both classes**

In `lib/media_centaur_web/components/play_overlay.ex`:

```elixir
      <button
        type="button"
        class={["picture-button play-overlay-btn", @size == :lg && "play-overlay-btn-lg"]}
```

and in the moduledoc, change

```
  The press answers on the spot, in CSS alone (`.play-overlay-btn` in
  `app.css`): the disc sinks while the pointer is down, springs back on
  release, and a ring leaves its edge
```

to

```
  The button is a picture button (`.picture-button` in `app.css`, the house
  disc over a picture, shared with a scroll row's edge arrows): the disc
  sinks while the pointer is down and springs back on release. The release
  ring (`.play-overlay-btn::after`) is this button's own
```

Also change `--play-overlay-reveal-delay` in the moduledoc to `--hover-reveal-delay`.

- [ ] **Step 3: Run the storybook render test and the Home tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/storybook_render_test.exs test/media_centaur_web/live/home_live_test.exs`
Expected: all pass (the story renders; nothing in the tests names the old class list).

- [ ] **Step 4: Confirm no reference to the old token remains**

Run: `grep -rn "play-overlay-reveal-delay" assets lib decisions .claude`
Expected: only the historical line in `decisions/user-interface/2026-08-17-027-play-in-place.md`, which gets a dated amendment at the end of the file naming the new token and `.picture-button` (the spec and plan under `docs/superpowers` name the old token on purpose). The picture button block sits ABOVE the `── Play overlay ──` header (primitive before composer; the two classes share no property).

- [ ] **Step 5: Visual check of the play button**

Run: `page-shot --url http://127.0.0.1:2160/ --viewport 1920x1080 --wait-ms 3000` and Read the PNG. The page renders as before (the play button only shows under hover, so a still proves nothing broke the page). Then `chromium-probe http://127.0.0.1:2160/ 'getComputedStyle(document.querySelector(".play-overlay-btn")).borderRadius'` → `9999px`.

- [ ] **Step 6: Commit**

```bash
git add assets/css/app.css lib/media_centaur_web/components/play_overlay.ex
git commit -m "refactor(ui): the picture button — the play overlay's disc as the house control over a picture"
```

---

### Task 2: One glider

**Files:**
- Create: `assets/js/scroll_glider.js`
- Modify: `assets/js/input/config.js:9-12`
- Test: `assets/js/input/__tests__/index.test.js`

- [ ] **Step 1: Write the failing test**

Append to the `describe("App config", …)` block in `assets/js/input/__tests__/index.test.js`:

```js
  // The page's scroll motion has one owner. The DOM writer glides toward
  // the focused card with this instance; the scroll row hook glides on an
  // arrow press with the same one, so the orchestrator's wheel rule
  // (cancel every glide) reaches both and a cursor key mid-glide retargets
  // rather than races.
  test("hands the page's one glider to the DOM writer", async () => {
    const { scrollGlider } = await import("../../scroll_glider")
    expect(inputConfig.glider).toBe(scrollGlider)
    expect(typeof scrollGlider.glide).toBe("function")
    expect(typeof scrollGlider.cancelAll).toBe("function")
  })
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bun test assets/js/input/__tests__/index.test.js`
Expected: FAIL — cannot resolve `../../scroll_glider`.

- [ ] **Step 3: Create the glider module and pass it through the config**

`assets/js/scroll_glider.js`:

```js
// assets/js/scroll_glider.js
//
// The page's one scroll animator. The input system's DOM writer glides a
// scroller toward the focused card with it (`inputConfig.glider`), and the
// scroll row hook glides a track on an edge-arrow press with it. One
// instance, so the orchestrator's wheel rule — a wheel event cancels every
// glide where it stands — covers both, and a cursor key pressed mid-glide
// retargets the same track instead of racing a second animation.
//
// The browser globals are read lazily, per call, so importing this module
// under bun (no `requestAnimationFrame`) is harmless.
import { createScrollGlide } from "./input/core/scroll_glide.js"

export const scrollGlider = createScrollGlide({
  requestAnimationFrame: (fn) => globalThis.requestAnimationFrame(fn),
  now: () => performance.now(),
})
```

In `assets/js/input/config.js`, add the import and the key:

```js
import { Context } from "./core/index.js"
import { createPageBehavior } from "./page_behavior.js"
import { scrollGlider } from "../scroll_glider.js"

export const inputConfig = {
  // The page's one scroll animator (assets/js/scroll_glider.js); the DOM
  // writer glides with it, and so does the scroll row hook.
  glider: scrollGlider,

  // Context selectors — maps context keys to CSS selectors
  contextSelectors: {
```

- [ ] **Step 4: Run the input tests**

Run: `bun test assets/js/input/`
Expected: all pass. (`createDomWriter` already reads `config.glider`; the orchestrator tests inject their own.)

- [ ] **Step 5: Commit**

```bash
git add assets/js/scroll_glider.js assets/js/input/config.js assets/js/input/__tests__/index.test.js
git commit -m "feat(input): the page's one glider — created once, handed to the DOM writer through the config"
```

---

### Task 3: The hook's pure functions

**Files:**
- Create: `assets/js/hooks/scroll_row.js`
- Create: `assets/js/hooks/scroll_row.test.js`

- [ ] **Step 1: Write the failing tests**

`assets/js/hooks/scroll_row.test.js`:

```js
import { afterEach, describe, expect, test } from "bun:test"
import { edges, step } from "./scroll_row"
import { restoreGlobals } from "../test_support/dom_stubs"

afterEach(restoreGlobals)

describe("edges", () => {
  test("a track at scroll 0 is at its start", () => {
    expect(edges({ scrollLeft: 0, scrollWidth: 3000, clientWidth: 1000 })).toEqual({
      atStart: true,
      atEnd: false,
    })
  })

  test("a track mid-row is at neither end", () => {
    expect(edges({ scrollLeft: 800, scrollWidth: 3000, clientWidth: 1000 })).toEqual({
      atStart: false,
      atEnd: false,
    })
  })

  // Browsers report fractional scroll offsets under a root zoom; a track
  // 0.6px short of its maximum is at its end.
  test("a track within a pixel of its maximum is at its end", () => {
    expect(edges({ scrollLeft: 1999.4, scrollWidth: 3000, clientWidth: 1000 })).toEqual({
      atStart: false,
      atEnd: true,
    })
  })

  test("a track that fits is at both ends", () => {
    expect(edges({ scrollLeft: 0, scrollWidth: 900, clientWidth: 1000 })).toEqual({
      atStart: true,
      atEnd: true,
    })
  })
})

describe("step", () => {
  // One screenful less one card and its gap: the last visible card stays
  // as the reader's anchor, the rule the track's scroll padding states for
  // the cursor.
  test("is the scrollport less one card and its gap", () => {
    expect(step({ clientWidth: 1000, cardWidth: 200, gap: 8 })).toBe(792)
  })

  // A scrollport narrower than two cards (UI scale 2× on a small window)
  // still moves a whole card, never a sliver.
  test("is never less than one card", () => {
    expect(step({ clientWidth: 300, cardWidth: 200, gap: 8 })).toBe(200)
  })
})
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bun test assets/js/hooks/scroll_row.test.js`
Expected: FAIL — cannot resolve `./scroll_row`.

- [ ] **Step 3: Write the pure functions**

`assets/js/hooks/scroll_row.js`:

```js
// assets/js/hooks/scroll_row.js
//
// A scroll row's pointer chrome: two edge arrows over a `.row-scroll`
// track, each gliding the track one step toward its end. The arrows are a
// pointer affordance in the play overlay's sense (UIDR-027): revealed on
// hover by CSS, outside the input system, never seen by keyboard, gamepad
// or the TV.
//
// The hook owns two things. The track's EDGE STATE — at its start, at its
// end — is the track's own geometry, projected as `data-at-start` and
// `data-at-end` on the track so CSS can drop the arrow that points at an
// end already reached (a track that fits carries both and shows none). And
// the PRESS: one step is a scrollport less one card and its gap, so the
// last visible card stays as the reader's anchor; the glide is the page's
// one glider (assets/js/scroll_glider.js), so the orchestrator's wheel rule
// cancels it like any other and a cursor key mid-glide retargets it.
//
// The hook attaches only where a pointer is (`(hover: hover)`), the same
// truth the CSS reveal rests on: the TV's glide frames carry no scroll
// listener for chrome it can never show.
//
// Layout pixels throughout (`offsetWidth`, `clientWidth`, `scrollLeft`),
// never `getBoundingClientRect`: the UI runs under a root zoom, and rects
// come back in visual pixels.

/** Within this many px of an end counts as at it (fractional offsets under zoom). */
const EDGE_TOLERANCE = 1

/**
 * Which ends of a track are reached.
 * @param {{scrollLeft: number, scrollWidth: number, clientWidth: number}} track
 * @returns {{atStart: boolean, atEnd: boolean}}
 */
export function edges({ scrollLeft, scrollWidth, clientWidth }) {
  const max = Math.max(0, scrollWidth - clientWidth)
  return {
    atStart: scrollLeft <= EDGE_TOLERANCE,
    atEnd: scrollLeft >= max - EDGE_TOLERANCE,
  }
}

/**
 * How far one press moves the track: the scrollport less one card and its
 * gap, and never less than a card.
 * @param {{clientWidth: number, cardWidth: number, gap: number}} geometry
 * @returns {number}
 */
export function step({ clientWidth, cardWidth, gap }) {
  return Math.max(cardWidth, clientWidth - (cardWidth + gap))
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bun test assets/js/hooks/scroll_row.test.js`
Expected: 6 pass.

- [ ] **Step 5: Commit**

```bash
git add assets/js/hooks/scroll_row.js assets/js/hooks/scroll_row.test.js
git commit -m "feat(hooks): scroll row edge state and step — the pure half of the ScrollRow hook"
```

---

### Task 4: The hook

**Files:**
- Modify: `assets/js/hooks/scroll_row.js`
- Modify: `assets/js/hooks/scroll_row.test.js`
- Modify: `assets/js/app.js:39-50`

- [ ] **Step 1: Write the failing tests**

In `assets/js/hooks/scroll_row.test.js`, add one more `edges` test inside its describe block (overscroll pins the clamp and the comparison direction):

```js
  // Trackpad and touch overscroll report offsets past either end.
  test("overscroll past either end still reads as that end", () => {
    expect(edges({ scrollLeft: -5, scrollWidth: 3000, clientWidth: 1000 })).toEqual({ atStart: true, atEnd: false })
    expect(edges({ scrollLeft: 2500, scrollWidth: 3000, clientWidth: 1000 })).toEqual({ atStart: false, atEnd: true })
  })
```

Then append (add `ScrollRow` to the import from `./scroll_row`, and `installGlobal`, `installResizeObserver` to the import from `../test_support/dom_stubs`):

```js
// A wrapper element with a track inside it, as the component renders them,
// under a fake glider that records what it was asked. `hover` is what the
// page's `(hover: hover)` query answers.
function mount({ hover = true, scrollLeft = 0, scrollWidth = 3000, clientWidth = 1000, cardWidth = 200, gap = 8 } = {}) {
  installGlobal("matchMedia", (query) => ({ matches: query === "(hover: hover)" && hover }))
  installGlobal("getComputedStyle", () => ({ columnGap: `${gap}px` }))
  const observers = installResizeObserver()

  function element() {
    const attributes = {}
    const listeners = {}
    return {
      attributes,
      listeners,
      setAttribute: (name, value) => {
        attributes[name] = value
      },
      removeAttribute: (name) => {
        delete attributes[name]
      },
      hasAttribute: (name) => name in attributes,
      toggleAttribute(name, force) {
        if (force) attributes[name] = ""
        else delete attributes[name]
      },
      addEventListener: (type, fn) => {
        listeners[type] = fn
      },
      removeEventListener: (type, fn) => {
        if (listeners[type] === fn) delete listeners[type]
      },
    }
  }

  const track = Object.assign(element(), {
    scrollLeft,
    scrollWidth,
    clientWidth,
    firstElementChild: { offsetWidth: cardWidth },
  })
  const el = Object.assign(element(), { querySelector: (sel) => (sel === ".row-scroll" ? track : null) })

  const glides = []
  const hook = Object.assign(Object.create(ScrollRow), {
    el,
    glider: { glide: (box, target) => glides.push({ box, target }) },
  })
  hook.mounted()

  const arrow = (direction) => ({
    target: { closest: (sel) => (sel === "[data-scroll-row-arrow]" ? { dataset: { scrollRowArrow: direction } } : null) },
  })

  return { hook, el, track, glides, observers, arrow, press: (direction) => el.listeners.click(arrow(direction)) }
}

describe("ScrollRow", () => {
  test("projects the edge state onto the track at mount", () => {
    const { track } = mount({ scrollLeft: 0 })
    expect(track.attributes).toEqual({ "data-at-start": "" })
  })

  test("a track that fits is at both ends", () => {
    const { track } = mount({ scrollWidth: 900 })
    expect(track.attributes).toEqual({ "data-at-start": "", "data-at-end": "" })
  })

  test("follows the track's scroll", () => {
    const { track } = mount()
    track.scrollLeft = 2000
    track.listeners.scroll()
    expect(track.attributes).toEqual({ "data-at-end": "" })
  })

  test("follows a resize", () => {
    const { track, observers } = mount()
    expect(observers[0].targets).toEqual([track])
    track.clientWidth = 3000
    observers[0].fire()
    expect(track.attributes).toEqual({ "data-at-start": "", "data-at-end": "" })
  })

  // morphdom syncs a patched element back to the server's markup, which
  // has no edge attributes; after a patch the hook puts them back.
  test("re-asserts the edge state after a patch", () => {
    const { hook, track } = mount({ scrollLeft: 2000 })
    delete track.attributes["data-at-end"]
    hook.updated()
    expect(track.attributes).toEqual({ "data-at-end": "" })
  })

  test("a press on the right arrow glides one step", () => {
    const { track, glides, press } = mount({ scrollLeft: 0 })
    press("right")
    expect(glides).toEqual([{ box: track, target: { left: 792 } }])
  })

  test("a press on the left arrow glides one step back, clamped at 0", () => {
    const { track, glides, press } = mount({ scrollLeft: 500 })
    press("left")
    expect(glides).toEqual([{ box: track, target: { left: 0 } }])
  })

  test("a press near the end is clamped at the maximum", () => {
    const { track, glides, press } = mount({ scrollLeft: 1500 })
    press("right")
    expect(glides).toEqual([{ box: track, target: { left: 2000 } }])
  })

  test("a click elsewhere in the row is not a press", () => {
    const { el, glides } = mount()
    el.listeners.click({ target: { closest: () => null } })
    expect(glides).toEqual([])
  })

  // Chrome never takes the cursor: in the collection rail the arrows sit
  // outside every nav zone, and a focused arrow would read as foreign focus
  // to the input system's reconciler (`hasForeignFocus`), which would then
  // cede the cursor to it.
  test("mousedown on an arrow is prevented, so the button never takes focus", () => {
    const { el, arrow } = mount()
    let prevented = false
    el.listeners.mousedown({ ...arrow("left"), preventDefault: () => (prevented = true) })
    expect(prevented).toBe(true)
  })

  test("mousedown elsewhere in the row is left alone", () => {
    const { el } = mount()
    let prevented = false
    el.listeners.mousedown({ target: { closest: () => null }, preventDefault: () => (prevented = true) })
    expect(prevented).toBe(false)
  })

  // No pointer, no chrome: the TV's glide frames carry no scroll listener.
  test("without a hovering pointer the hook attaches nothing", () => {
    const { el, track, observers } = mount({ hover: false })
    expect(track.attributes).toEqual({})
    expect(track.listeners).toEqual({})
    expect(el.listeners).toEqual({})
    expect(observers).toEqual([])
  })

  test("destroyed releases the listeners and the observer", () => {
    const { hook, el, track, observers } = mount()
    hook.destroyed()
    expect(track.listeners).toEqual({})
    expect(el.listeners).toEqual({})
    expect(observers[0].targets).toEqual([])
  })
})
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bun test assets/js/hooks/scroll_row.test.js`
Expected: the six pure tests pass; the `ScrollRow` block fails — `ScrollRow` is not exported.

- [ ] **Step 3: Write the hook**

Append to `assets/js/hooks/scroll_row.js` (and add the import at the top, after the header comment):

```js
import { scrollGlider } from "../scroll_glider.js"
```

```js
export const ScrollRow = {
  mounted() {
    if (!globalThis.matchMedia?.("(hover: hover)").matches) return
    this.track = this.el.querySelector(".row-scroll")
    if (!this.track) return
    this.glider = this.glider ?? scrollGlider

    this.onScroll = () => this.project()
    this.track.addEventListener("scroll", this.onScroll, { passive: true })

    this.observer = new ResizeObserver(() => this.project())
    this.observer.observe(this.track)

    this.onClick = (event) => {
      const arrow = event.target.closest?.("[data-scroll-row-arrow]")
      if (arrow) this.press(arrow.dataset.scrollRowArrow)
    }
    this.el.addEventListener("click", this.onClick)

    // Chrome never takes the cursor. Chromium focuses a clicked
    // `tabindex="-1"` button; in the collection rail the arrows sit outside
    // every nav zone, and the input system's reconciler would read that
    // focus as foreign (`hasForeignFocus`) and cede the cursor to it.
    this.onMouseDown = (event) => {
      if (event.target.closest?.("[data-scroll-row-arrow]")) event.preventDefault()
    }
    this.el.addEventListener("mousedown", this.onMouseDown)

    this.project()
  },

  updated() {
    if (this.track) this.project()
  },

  destroyed() {
    if (!this.track) return
    this.track.removeEventListener("scroll", this.onScroll)
    this.el.removeEventListener("click", this.onClick)
    this.el.removeEventListener("mousedown", this.onMouseDown)
    this.observer.disconnect()
  },

  /** Write the track's edge state onto it. */
  project() {
    const { atStart, atEnd } = edges(this.track)
    this.track.toggleAttribute("data-at-start", atStart)
    this.track.toggleAttribute("data-at-end", atEnd)
  },

  /** Glide the track one step toward `direction` ("left" | "right"). */
  press(direction) {
    const track = this.track
    const cardWidth = track.firstElementChild?.offsetWidth ?? 0
    const gap = parseFloat(globalThis.getComputedStyle(track).columnGap) || 0
    const distance = step({ clientWidth: track.clientWidth, cardWidth, gap })
    const max = Math.max(0, track.scrollWidth - track.clientWidth)
    const wanted = direction === "left" ? track.scrollLeft - distance : track.scrollLeft + distance
    this.glider.glide(track, { left: Math.min(Math.max(wanted, 0), max) })
  },
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bun test assets/js/hooks/scroll_row.test.js`
Expected: 20 pass.

- [ ] **Step 5: Register the hook**

In `assets/js/app.js`, add the import beside the other hooks and the entry in `hooks:`:

```js
import {ImageCrop} from "./hooks/image_crop"
import {ScrollRow} from "./hooks/scroll_row"
```

```js
    FeedHead,
    ImageCrop,
    ScrollRow,
```

- [ ] **Step 6: Run the whole JS suite and the boundaries check**

Run: `bun test assets/js/` then `~/scripts/agents/agent-mix boundaries`
Expected: all pass; no dependency-cruiser violation (a hook importing `scroll_glider.js`, which imports `input/core`, is app code importing core).

- [ ] **Step 7: Commit**

```bash
git add assets/js/hooks/scroll_row.js assets/js/hooks/scroll_row.test.js assets/js/app.js
git commit -m "feat(hooks): the ScrollRow hook — edge state on the track, an arrow press glides one step on the page's glider"
```

---

### Task 5: The component, its CSS and its story

**Files:**
- Create: `lib/media_centaur_web/components/scroll_row.ex`
- Create: `storybook/composites/scroll_row.story.exs`
- Modify: `storybook/composites/_composites.index.exs`
- Modify: `assets/css/app.css` (after the `.row-scroll-hero` block, before `/* ── Poster grid ──`)
- Test: `test/media_centaur_web/storybook_compile_test.exs`, `test/media_centaur_web/storybook_render_test.exs`, `test/media_centaur/credo/checks/storybook_coverage_test.exs`

- [ ] **Step 1: Write the story first (the failing test is the storybook coverage check)**

`storybook/composites/scroll_row.story.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.Composites.ScrollRow do
  @moduledoc """
  A scroll row: the `.row-scroll` track with its two edge arrows. The arrows
  reveal on hover (move the pointer over a variation to see them), and the
  track's edge state decides which: `data-at-start` drops the left arrow,
  `data-at-end` the right, both drop both. In the app the `ScrollRow` hook
  writes those from the track's geometry; the storybook loads no hooks, so
  each variation sets them as a fixture — the state matrix, not the motion.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaurWeb.Components.ScrollRow

  def function, do: &ScrollRow.scroll_row/1
  def render_source, do: :function
  def layout, do: :one_column

  def variations do
    [
      %Variation{
        id: :at_start,
        description: "Scroll 0 — only the right arrow shows under hover",
        attributes: %{id: "scroll-row-at-start", variant: :poster, "data-at-start": true},
        slots: [cards(12)]
      },
      %Variation{
        id: :mid_row,
        description: "Mid-row — both arrows show under hover",
        attributes: %{id: "scroll-row-mid-row", variant: :poster},
        slots: [cards(12)]
      },
      %Variation{
        id: :at_end,
        description: "At the end — only the left arrow shows under hover",
        attributes: %{id: "scroll-row-at-end", variant: :poster, "data-at-end": true},
        slots: [cards(12)]
      },
      %Variation{
        id: :fits,
        description: "A row that fits carries both edge attributes and shows no arrows",
        attributes: %{id: "scroll-row-fits", variant: :poster, "data-at-start": true, "data-at-end": true},
        slots: [cards(3)]
      },
      %Variation{
        id: :backdrop_lg,
        description: "The Continue Watching variant: 16:9 cards on the wider gap",
        attributes: %{id: "scroll-row-backdrop-lg", variant: :backdrop_lg},
        slots: [backdrop_cards(8)]
      }
    ]
  end

  defp cards(count) do
    Enum.map_join(1..count, "\n", fn n ->
      ~s|<div class="aspect-[2/3] rounded glass-inset grid place-items-center text-sm text-base-content/55" data-row-item>#{n}</div>|
    end)
  end

  defp backdrop_cards(count) do
    Enum.map_join(1..count, "\n", fn n ->
      ~s|<div class="aspect-[16/9] rounded-lg glass-inset grid place-items-center text-sm text-base-content/55" data-row-item>#{n}</div>|
    end)
  end
end
```

Add to `storybook/composites/_composites.index.exs`:

```elixir
  def entry("scroll_row"), do: [icon: {:fa, "arrows-left-right", :thin}, name: "Scroll row"]
```

- [ ] **Step 2: Run the storybook tests to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/storybook_compile_test.exs`
Expected: FAIL — `MediaCentaurWeb.Components.ScrollRow` is undefined.

- [ ] **Step 3: Write the component**

`lib/media_centaur_web/components/scroll_row.ex`:

```elixir
defmodule MediaCentaurWeb.Components.ScrollRow do
  @moduledoc """
  A scroll row: a horizontally scrolling `.row-scroll` track of cards with
  its pointer chrome — an edge arrow at each end that glides the track one
  step that way. Home's Continue Watching and Recently Added rows and the
  title detail's collection rail render their track through it; the hero,
  one full-bleed item, has nothing to scroll and keeps its plain track.

  The track owns the scroll system (`app.css`: the ring reserve, hidden
  scrollbar, cursor peek, edge fades); the `variant` picks its card size.
  `rest` lands on the track, so a caller's `data-component`,
  `data-scroll-row` or `data-nav-zone` sit where they always did.

  The arrows are a pointer affordance in the play overlay's sense
  (UIDR-027) and take its shape: a reveal wrapper (`.scroll-row-arrow`) that
  hover fades in — opacity only, after `--hover-reveal-delay`, under
  `(hover: hover)` — around a `.picture-button`, the disc the play overlay
  draws. The button is outside the input system (`tabindex="-1"`, no
  `data-nav-item`) and never takes the cursor (the hook prevents default on
  mousedown); it keeps an `aria-label`, as every icon-only control does. The
  TV, which has no pointer, never sees them. The `ScrollRow` hook
  (`assets/js/hooks/scroll_row.js`) writes the track's edge state onto it as
  `data-at-start` / `data-at-end`; CSS drops the arrow pointing at an end
  already reached, so a track that fits shows none.
  """

  use Phoenix.Component
  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  attr :id, :string, required: true, doc: "the hook element's id; unique on the page"

  attr :variant, :atom,
    required: true,
    values: [:backdrop_lg, :poster, :backdrop_sm],
    doc:
      "the track's card size: `:backdrop_lg` (Continue Watching), `:poster` (Recently Added), `:backdrop_sm` (the collection rail)"

  attr :rest, :global, doc: "lands on the track"

  slot :inner_block, required: true, doc: "the cards"

  def scroll_row(assigns) do
    ~H"""
    <div id={@id} phx-hook="ScrollRow" class="scroll-row">
      <div class={["row-scroll", track_class(@variant)]} {@rest}>
        {render_slot(@inner_block)}
      </div>
      <.edge_arrow direction="left" />
      <.edge_arrow direction="right" />
    </div>
    """
  end

  attr :direction, :string, values: ["left", "right"], required: true

  defp edge_arrow(assigns) do
    ~H"""
    <div class="scroll-row-arrow" data-scroll-row-arrow={@direction}>
      <button type="button" class="picture-button" tabindex="-1" aria-label={"Scroll #{@direction}"}>
        <.icon name={"hero-chevron-#{@direction}-mini"} class="size-5" />
      </button>
    </div>
    """
  end

  defp track_class(:backdrop_lg), do: "row-scroll-backdrop-lg"
  defp track_class(:poster), do: "row-scroll-poster"
  defp track_class(:backdrop_sm), do: "row-scroll-backdrop-sm"
end
```

- [ ] **Step 4: Write the CSS**

Two edits in `assets/css/app.css`.

First, the reveal becomes one grouped rule for both pointer affordances. In the play overlay block (Task 1), replace

```css
.play-overlay {
  position: absolute;
  inset: 0;
  opacity: 0;
  transition: opacity 240ms ease;
  pointer-events: none;
```

with

```css
/* The reveal, shared by every pointer affordance: the play overlay and a
   scroll row's edge arrows. Each is a wrapper that fades in on hover of its
   host — opacity only, after the intent delay — around a picture button
   that presses. Gated on `(hover: hover)`, the same query the ScrollRow
   hook asks, so there is one pointer truth: where no pointer can hover
   there is neither chrome nor listener. Without the gate a touch device's
   sticky hover would reveal arrows the unattached hook never answers. The
   TV never hovers, so it sees neither. */
.play-overlay,
.scroll-row-arrow {
  opacity: 0;
  transition: opacity 240ms ease;
}

@media (hover: hover) {
  .play-overlay-host:hover .play-overlay,
  .scroll-row:hover .scroll-row-arrow {
    opacity: 1;
    transition-delay: var(--hover-reveal-delay);
  }
}

.play-overlay {
  position: absolute;
  inset: 0;
  pointer-events: none;
```

and delete the old `.play-overlay-host:hover .play-overlay { … }` rule below it (its declarations now live in the grouped rule). The play overlay keeps its halo `background`, its `pointer-events: none` (card clicks pass through; `.play-overlay-btn` carries `pointer-events: auto`, Task 1) and the rest of its block. Pointer-events are deliberately NOT in the grouped rule: each affordance decides who takes the pointer. The play overlay's wrapper never does; the arrow's wrapper does only while revealed.

Second, after the `.row-scroll-hero` block and before `/* ── Poster grid ──`:

```css
/* ── Scroll row arrows ──
   A scroll row's pointer chrome: an edge arrow at each end of the track —
   a reveal wrapper (the grouped reveal rule beside `.play-overlay`) around
   a picture button that glides the track one step that way (the ScrollRow
   hook, assets/js/hooks/scroll_row.js). They sit inside the track's ends,
   over the edge fade, centred on the cards, above a hovered card's
   z-index. The wrapper's `position: relative` is what they are placed in;
   the track keeps its negative inline margin, so the content edge is the
   wrapper's edge.

   The track's edge state (`data-at-start` / `data-at-end`, written by the
   hook from the track's own geometry) drops the arrow that points at an
   end already reached: `display: none`, not opacity 0, so a hidden arrow
   can never take a click. A track that fits carries both and shows none. */
.scroll-row {
  position: relative;
}

/* Pointer-transparent until revealed, so a hidden arrow never takes a
   click meant for the card beneath; the disc inherits `auto` on hover
   (`.picture-button` sets no pointer-events of its own). */
.scroll-row-arrow {
  position: absolute;
  top: 50%;
  translate: 0 -50%;
  z-index: 3;
  pointer-events: none;
}

@media (hover: hover) {
  .scroll-row:hover .scroll-row-arrow {
    pointer-events: auto;
  }
}

.scroll-row-arrow[data-scroll-row-arrow="left"] {
  left: 0.5rem;
}

.scroll-row-arrow[data-scroll-row-arrow="right"] {
  right: 0.5rem;
}

.scroll-row-arrow .picture-button {
  width: 44px;
  height: 44px;
}

.row-scroll[data-at-start] ~ .scroll-row-arrow[data-scroll-row-arrow="left"],
.row-scroll[data-at-end] ~ .scroll-row-arrow[data-scroll-row-arrow="right"] {
  display: none;
}
```

- [ ] **Step 5: Run the storybook and Credo coverage tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs test/media_centaur/credo/checks/storybook_coverage_test.exs`
Expected: all pass (five variations render; MC0009 finds the story).

- [ ] **Step 6: Look at the story**

Run: `page-shot --url http://127.0.0.1:2160/storybook/composites/scroll_row --viewport 1920x1080 --wait-ms 3000` and Read the PNG: five tracks of placeholder cards. Then hover a row to see the arrows:

```
chromium-probe http://127.0.0.1:2160/storybook/composites/scroll_row 'const a = document.querySelector("#scroll-row-mid-row .scroll-row-arrow"); getComputedStyle(a).display + " " + getComputedStyle(document.querySelector("#scroll-row-fits .scroll-row-arrow")).display + " " + document.querySelector("#scroll-row-mid-row .scroll-row-arrow .picture-button").getAttribute("aria-label")'
```
Expected: `block none Scroll left`.

- [ ] **Step 7: Commit**

```bash
git add lib/media_centaur_web/components/scroll_row.ex storybook/composites/scroll_row.story.exs storybook/composites/_composites.index.exs assets/css/app.css
git commit -m "feat(ui): the scroll row — one component for a track and its edge arrows, with its story"
```

---

### Task 6: The tenants

**Files:**
- Modify: `lib/media_centaur_web/components/continue_watching_row.ex:68-75`
- Modify: `lib/media_centaur_web/components/poster_row.ex:50-57`
- Modify: `lib/media_centaur_web/components/detail/collection_rail.ex:54-66`
- Test: `test/media_centaur_web/live/home_live_test.exs` (describe "See all destinations"), `test/media_centaur_web/page_smoke_test.exs:409-417`

- [ ] **Step 1: Write the failing tests**

In `test/media_centaur_web/live/home_live_test.exs`, inside `describe "See all destinations"` (its setup seeds one movie into both rows), add:

```elixir
    # Both rows are scroll rows: the track keeps its `data-component`, and
    # the wrapper carries the two edge arrows a mouse user presses.
    test "both rows render as scroll rows with edge arrows", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/")

      for id <- ["continue-watching-row", "recently-added-row"] do
        assert has_element?(view, ~s|##{id}.scroll-row[phx-hook="ScrollRow"]|)
        assert has_element?(view, ~s|##{id} > .row-scroll|)

        for direction <- ["left", "right"] do
          assert has_element?(
                   view,
                   ~s|##{id} > [data-scroll-row-arrow="#{direction}"] > .picture-button[tabindex="-1"][aria-label="Scroll #{direction}"]|
                 )
        end

        refute has_element?(view, ~s|##{id} [data-scroll-row-arrow] [data-nav-item]|)
      end

      assert has_element?(view, ~s|#continue-watching-row > [data-component="continue-watching"]|)
      assert has_element?(view, ~s|#recently-added-row > [data-component="poster-row"]|)
      refute has_element?(view, "[data-scroll-row]")
    end
```

In `test/media_centaur_web/page_smoke_test.exs`, in the test `"home detail panel mounts and renders the member panel + rail for a collection"`, after `assert html =~ "rail-tile-"` add:

```elixir
      # The rail is a scroll row; its track keeps the nav zone.
      assert html =~ ~s(id="collection-rail-row")
      assert html =~ ~s(data-scroll-row-arrow="right")
      assert html =~ ~s(data-nav-zone="detail_rail")
```

- [ ] **Step 2: Run them to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/home_live_test.exs test/media_centaur_web/page_smoke_test.exs`
Expected: the two new tests FAIL (no `#continue-watching-row`, no `collection-rail-row`); everything else passes.

- [ ] **Step 3: Continue Watching renders through the scroll row**

In `lib/media_centaur_web/components/continue_watching_row.ex`, add `alias MediaCentaurWeb.Components.ScrollRow` beside the `PlayOverlay` alias, and replace the track:

```heex
    <ScrollRow.scroll_row
      :if={@items != []}
      id="continue-watching-row"
      variant={:backdrop_lg}
      data-component="continue-watching"
    >
      <%!-- A div, not a <button>: the play overlay nests a real button
            inside (UIDR-027) and buttons cannot nest. --%>
      <div
        :for={item <- @items}
        …unchanged…
      </div>

      <.link
        …unchanged…
      </.link>
    </ScrollRow.scroll_row>
```

The old `<div :if={@items != []} data-component="continue-watching" data-scroll-row="continue-watching" class="row-scroll row-scroll-backdrop-lg">` and its closing `</div>` go. In the moduledoc, change "the row scrolls horizontally" sentence to name the scroll row: "The track is a `ScrollRow.scroll_row/1`, which adds the mouse user's edge arrows."

- [ ] **Step 4: Recently Added renders through the scroll row**

In `lib/media_centaur_web/components/poster_row.ex`, add `alias MediaCentaurWeb.Components.ScrollRow`, and replace the track:

```heex
    <ScrollRow.scroll_row
      :if={@items != []}
      id="recently-added-row"
      variant={:poster}
      data-component="poster-row"
    >
      …cards and the See all link, unchanged…
    </ScrollRow.scroll_row>
```

Moduledoc: after "How many fit is left to `.row-scroll-poster`…", add "The track is a `ScrollRow.scroll_row/1`, which adds the mouse user's edge arrows."

- [ ] **Step 5: The collection rail renders through the scroll row**

In `lib/media_centaur_web/components/detail/collection_rail.ex`, add `alias MediaCentaurWeb.Components.ScrollRow` and replace the track:

```heex
      <%!-- The home shelves' scroll system, wholesale, through the scroll
            row: `.row-scroll` owns the ring reserve, hidden scrollbar,
            cursor peek (scroll-padding stops the cursor one tile short and
            slides the row instead) and the scroll-linked edge fades; the
            scroll row adds the mouse user's edge arrows. The variant only
            sets tile width and gap. --%>
      <ScrollRow.scroll_row id="collection-rail-row" variant={:backdrop_sm} data-nav-zone="detail_rail">
        <.rail_tile
          :for={item <- @movie_items}
          item={item}
          selected={match?(%MovieRow.Library{}, item) && item.movie.id == @selected_id}
          available={@available}
        />
      </ScrollRow.scroll_row>
```

- [ ] **Step 6: The orphan attribute goes from the hero too**

`data-scroll-row` had three writers and no reader (app, tests, scripts, E2E). The rows above no longer set it; in `lib/media_centaur_web/live/home_live.ex` remove the line `data-scroll-row="hero"` from the hero's wrapper (the `div` carrying `data-nav-zone="hero"`), leaving `data-nav-zone` and `data-nav-reveal`.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/home_live_test.exs test/media_centaur_web/page_smoke_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: all pass, including the existing `[data-component="continue-watching"] [data-row-item]` click tests and the See all selectors.

- [ ] **Step 8: Confirm no hand-written scroll track and no orphan attribute remain**

Run: `grep -rn 'class="row-scroll' lib storybook; grep -rn "data-scroll-row=" lib assets/js e2e`
Expected: the first prints only `lib/media_centaur_web/live/home_live.ex` (the hero's `row-scroll row-scroll-hero`); the second prints nothing (the `data-scroll-row-arrow` attribute has a different name and does not match `data-scroll-row=`).

- [ ] **Step 9: Commit**

```bash
git add lib/media_centaur_web/components/continue_watching_row.ex lib/media_centaur_web/components/poster_row.ex lib/media_centaur_web/components/detail/collection_rail.ex lib/media_centaur_web/live/home_live.ex test/media_centaur_web/live/home_live_test.exs test/media_centaur_web/page_smoke_test.exs
git commit -m "feat(ui): Continue Watching, Recently Added and the collection rail are scroll rows — edge arrows for the mouse"
```

---

### Task 7: Browser verification and tuning

**Files:**
- Possibly modify: `assets/css/app.css` (`.scroll-row-arrow` inset and size)

- [ ] **Step 1: See the arrows on Home**

The dev server (`media-centaur-dev`, http://127.0.0.1:2160) reloads the checkout's code on its own. Hover the Continue Watching row and capture:

```
chromium-probe http://127.0.0.1:2160/ 'const row = document.querySelector("#continue-watching-row"); const r = row.getBoundingClientRect(); window.__probeHover = [r.left + r.width/2, r.top + r.height/2]; "ok"'
```

If `chromium-probe` cannot move the pointer, force the revealed state for the capture instead and check the geometry by computed style:

```
chromium-probe http://127.0.0.1:2160/ 'document.querySelectorAll("#continue-watching-row .scroll-row-arrow").forEach(a => { a.style.opacity = 1; a.style.pointerEvents = "auto" }); const t = document.querySelector("#continue-watching-row .row-scroll"); JSON.stringify({ atStart: t.hasAttribute("data-at-start"), atEnd: t.hasAttribute("data-at-end"), scrollWidth: t.scrollWidth, clientWidth: t.clientWidth })'
```
Expected: `atStart: true`, `atEnd: false` when the row overflows.

Then `page-shot --url http://127.0.0.1:2160/ --viewport 1920x1080 --wait-ms 3000` and Read the PNG. Judge: the right-hand disc sits inside the row's end, centred on the cards, legible over the artwork, not touching the See all card's text. Adjust `left`/`right` inset or the 44px size in `.scroll-row-arrow` if it reads wrong (CSS only; no precommit per iteration).

- [ ] **Step 2: A press moves the row one step and the left arrow appears**

```
chromium-probe http://127.0.0.1:2160/ 'const t = document.querySelector("#continue-watching-row .row-scroll"); const before = t.scrollLeft; document.querySelector("#continue-watching-row [data-scroll-row-arrow=right]").click(); await new Promise(r => setTimeout(r, 700)); JSON.stringify({ before, after: t.scrollLeft, atStart: t.hasAttribute("data-at-start"), card: t.firstElementChild.offsetWidth, port: t.clientWidth })'
```
Expected: `after ≈ port − (card + gap)`, `atStart: false`. (If `chromium-probe` does not accept top-level `await`, wrap the expression in an async IIFE.)

Also judge quick repeated presses by hand in the browser: a press measures `scrollLeft` mid-glide, so two presses 100 ms apart land about 1.6 steps out, not 2. If whole-step accumulation feels better, base the next target on the last requested one while `glider.isGliding(track)`; the trade-off is a stale remembered target after a keyboard retarget. Owner's call; record it either way.

- [ ] **Step 3: The end hides the right arrow**

```
chromium-probe http://127.0.0.1:2160/ 'const t = document.querySelector("#recently-added-row .row-scroll"); t.scrollLeft = t.scrollWidth; await new Promise(r => setTimeout(r, 50)); JSON.stringify({ atEnd: t.hasAttribute("data-at-end"), rightDisplay: getComputedStyle(document.querySelector("#recently-added-row [data-scroll-row-arrow=right]")).display })'
```
Expected: `atEnd: true`, `rightDisplay: "none"`.

- [ ] **Step 4: The keyboard cursor is untouched**

Run: `~/scripts/agents/mc-nav-trace 'ArrowDown ArrowRight ArrowRight ArrowRight'` on Home.
Expected: the same focused items and zero clip as before the change (the arrows are not nav items; the focus walk never lands on one).

- [ ] **Step 5: The collection rail**

Open a collection's detail (`/?entity=<a collection member's id>`, pick one with `~/scripts/agents/mc-eval` or the Library), capture at 1920×1080 and confirm the rail's arrows sit inside the modal's rail with the tiles.

- [ ] **Step 6: Commit any tuning**

```bash
git add assets/css/app.css
git commit -m "fix(ui): scroll row arrows — inset and size settled against Home at 1920"
```

(Skip if nothing changed.)

---

### Task 8: Docs, precommit, wiki

**Files:**
- Modify: `.claude/skills/user-interface/SKILL.md` (Component Inventory; the Anti-Patterns list)
- Modify: `docs/input-system.md` (the wheel paragraph, ~line 543)
- Modify: `campaigns/remote-players.md` (a verification item)
- Modify: `../media-centaur.wiki/` — the Home page under *Using Media Centaur*

- [ ] **Step 1: Component inventory**

In `.claude/skills/user-interface/SKILL.md`, in the Component Inventory table after the `poster_row/1` row, add:

```
| `scroll_row/1` | `scroll_row.ex` | A scrolling track with its edge arrows — the mouse user's way along Home's rows and the collection rail; a pointer affordance like the play overlay, drawn with `.picture-button` | ✅ |
```

Change the `poster_row/1` and `continue_watching_row/1` rows' purpose to end with "(a `scroll_row/1` tenant)". In the Anti-Patterns list add:

```
- A hand-written `.row-scroll` track for a row of cards — render it through `scroll_row/1`, which owns the track and the mouse user's edge arrows. The hero's single full-bleed item is the one plain track.
- A second disc over a picture — `.picture-button` is the one; the play overlay and the scroll row arrows both carry it.
```

- [ ] **Step 2: The one glider, in the input-system doc**

In `docs/input-system.md`, after the paragraph beginning "**The wheel takes scroll authority.**", add:

```
**One glider.** The page creates one scroll glide instance
(`assets/js/scroll_glider.js`) and hands it to the DOM writer through
`inputConfig.glider`; the `ScrollRow` hook glides a track on an edge-arrow
press with the same instance. So the wheel rule above cancels an arrow glide
like any other, and a cursor key pressed mid-glide retargets the track instead
of racing a second animation. A new scroller that animates its scroll imports
that instance; it never creates its own.
```

- [ ] **Step 3: The TV verification item**

In `campaigns/remote-players.md`, under the open items of the current section (after the owner's walk entry), add:

```
* **Scroll row arrows on the TV** (2026-10-25). Home's rows and the collection
  rail carry mouse edge arrows (`ScrollRow`, spec
  `docs/superpowers/specs/2026-10-25-scroll-row-arrows-design.md`). CSS reveals
  them on `:hover` only, so the TV never shows them; the hook attaches only where
  `matchMedia("(hover: hover)")` matches. To read what the Sony's WebView
  answers, when the TV is free: `mc-tv` with a page probe evaluating
  `matchMedia("(hover: hover)").matches`. `false` means no listener on the TV;
  `true` means one passive scroll listener per row, the arrows still unseen.
  Record the answer here.
```

- [ ] **Step 4: Wiki**

In `~/src/media-centaur/media-centaur.wiki/`, find the *Using Media Centaur* page that describes Home (`grep -ril "continue watching" .`), and in its description of the rows add one sentence:

```
With a mouse, hover a row to show an arrow at each end; a press slides the row along by a screenful. Shift+wheel and a trackpad swipe slide it too.
```

Then:

```bash
cd ~/src/media-centaur/media-centaur.wiki && git add -A && git commit -m "wiki: Home rows — mouse edge arrows" && git push
```

- [ ] **Step 5: Precommit**

Run: `~/scripts/agents/agent-mix precommit`
Expected: green — format, credo (MC0009 satisfied by the story; MC0016 untouched, no new `<img>`; no raw `btn`/`badge` class), boundaries, deps.audit, sobelow, tests. Fix anything it reports.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/user-interface/SKILL.md docs/input-system.md campaigns/remote-players.md
git commit -m "docs: scroll row in the component inventory; one glider in the input-system doc; the TV hover check on the campaign"
```

---

## Self-review against the spec

- Scroll row component with `id`, `variant`, `rest` to the track: Task 5. Tenants and the hero left alone: Task 6.
- Picture button split with no visual change; `--hover-reveal-delay`: Task 1.
- The reveal as one grouped rule for both pointer affordances under `(hover: hover)`; the arrow as a wrapper around a `.picture-button`; edge-state CSS with `display: none` for a hidden arrow: Task 5.
- `aria-label` on the arrow button, no `aria-hidden`; `data-scroll-row` removed from the rows and the hero: Tasks 5–6.
- Hook: hover gate, `edges`, `step`, projection on scroll/resize/`updated`, clamped glide, delegated click, `mousedown` prevented so chrome never takes the cursor: Tasks 3–4. Edge attributes live on the **track** (the spec's "on the row"; the track is the scrolling element and the story's fixtures reach it through `rest`), and the CSS uses the sibling selector accordingly.
- One glider through `inputConfig.glider`: Task 2.
- Tests named in the spec: bun (Tasks 3–4, config in Task 2), ExUnit (Task 6), story (Task 5), browser (Task 7), precommit (Task 8).
- Verification item on the TV: Task 8.
- Out of scope held: no wheel hijack, no drag, no hero, no person rail.
