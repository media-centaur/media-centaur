# X · Motion — reasoning

Deliverable: `index.html`. An exploration, not a direction: the Everyone state of 1 · Cinematic rows with three kinds of motion, each behind its own checkbox. Written from what is built.

## The base

The sixteen bands are direction 1's `#f1`, verbatim; geometry, type and scrim recipe untouched. Two differences: the crop is MEASUREMENT.md's rule (`50% 30%` everywhere, `50% 38%` on rows 3 and 7, adjacent rows of one title), and each still sits in a `.bdbox` that owns the box and the mask, so the translate (box) and the scale (image) never share one `transform`. Against direction 1's 1920 render the text zone differs by zero pixels at 3% fuzz; only the stills differ, by the crop rule. The checkboxes are read by `body:has(#id:checked)`; no script tag. Every motion rule is inside `@media (prefers-reduced-motion: no-preference)`: with reduce set, the page is the static base whatever is checked.

## The three motions

**1 · Scroll parallax.** Each `.row` names a view timeline (`view-timeline-name: --band`). Checked, the image box grows 24px past the band's top and bottom and animates `translateY(-24px → 24px)` over `cover 0% → 100%`, linear: the still climbs 48px less than its band. Needs Chromium 115 (scroll-driven animations); the shell's 152 has them. `@supports (animation-timeline: view())` wraps the rule: elsewhere the box stays 152px and nothing animates. No scroll handler.

Cost: each box becomes a compositor layer, 1260×200px ≈ 1 MB at 1920; sixteen bands ≈ 16 MB, plus the scrim, poster and text above each still re-layered to keep painting on top, roughly the same again. Per scrolled frame the compositor moves sixteen masked, rounded-clipped textures: no main-thread work, no repaint, nothing while the page is still — but sixteen layers on a TV box where today there are none. And the crop moves: 28.6% of the still at the viewport's centre, 27% at the bottom edge, 36% at the top; MEASUREMENT.md's sweep fails at 25% and 35%+, so a band's last tenth of travel off the top of the screen is in the failure zone.

**2 · Ambient drift.** The first band's still alone: `scale(1 → 1.04)` over 40s, ease-in-out, alternate, infinite; `animation-composition: add` so hover composes with it. Cost: one layer, but a running animation — a compositor frame every vsync while the page is open; the GPU never idles. 0.1% per second reads as "alive", not as movement.

**3 · Hover ease.** `transition: transform .4s ease`, `scale(1.03)` on `.row:hover`. The scrim step and ground lift stay instant, as in the base: easing the scrim would animate a gradient (a repaint per frame) or an `opacity` on the scrim, altering the recipe. Cost: a layer for 400ms under the pointer, then dropped; nothing at rest. The band is 152px throughout.

## House rules

| Rule | Status | Exception, precisely |
|---|---|---|
| UIDR-012 — no entrance animations on routine renders | Kept | Nothing animates on mount or patch; parallax is scroll progress, not time; the drift starts at scale 1. |
| UIDR-012 — the 150ms modal scale-in is the ceiling | Bent by 2 and 3 | 400ms and 40s on artwork in its own clipped box, never on chrome or layout; the ceiling was written for chrome that signals layering. Read as absolute, they break it. |
| Only opacity and transform; never backdrop-filter, box-shadow, layout; no hover height change | Kept | Three transforms; the box's 48px growth is a static change on the switch; 152px throughout. |
| MEASUREMENT.md — one crop rule | Bent by 1 while scrolling | 27–36% over a band's travel; 30% at rest. |

## If only one could ship

Hover ease. The reader asks for it — the pointer is already on the band — it ends, costs nothing at rest, and is the page's idiom already (the toolbar fades in on hover). The parallax is the most beautiful and the only one that changes what the band shows, turning the measured crop into a range, on sixteen new layers. The drift makes one band special by the code's choice, not the reader's, and never stops. Unsettled: the shell has no hover; the cursor ring could carry the ease.

## The case against any motion on a feed people scan

The Feed is read as sixteen sentences: who, verb, title; the picture is where the eye stops to confirm. Motion is the strongest pre-attentive signal there is, and all three spend it on the picture — the part the reader has decided not to read. Parallax makes every scrolled frame differ in sixteen places; whoever reads while flick-scrolling loses the fixed spine. Drift claims the newest action matters most, which position already says. Hover ease is invisible on the shell and, at ten feet, 4px. Today the page has one transition and the app's claim is Linear's restraint; a feed that moves is a different app. None of the three makes a sentence easier to find; each makes a picture harder to ignore. Unless the owner wants the Feed looked at rather than read, motion does not belong on it.

## Width checks

1280×800: window 44%, so ±24px is 7% of it (3.4% at 1920); the toggles fit on one line. 2560×1440: window 14%, a slow slide of a letterbox, layers 1.5 MB each; UI scale renders 2560 near 1920 CSS px anyway.
