---
status: accepted
date: 2026-03-06
---
# Playback card hierarchy

## Context and Problem Statement

The dashboard playback summary card displays "paused S1E3 · 9:00 A.M." with raw timestamps below — but omits the show name entirely. For TV episodes, the user cannot tell *what* they are watching at a glance. The flat layout also forces mental math to gauge progress from raw timestamps alone.

## Decision Outcome

Chosen option: "stacked hierarchy with visual progress bar", because it surfaces the most important information (show name) prominently and replaces mental math with a scannable progress bar.

Layout (three rows):

1. **Header row:** "Playback" title left, state label right (`flex justify-between`).
2. **Identity block:** Show/movie name on its own line (`text-base font-medium`), episode detail below (`text-sm text-base-content/60`). Movies show only the title with no detail line.
3. **Progress row:** DaisyUI `<progress>` bar (`h-1.5`) with timestamps right-aligned. Bar color matches playback state: `progress-success` for playing, `progress-warning` for paused. Omitted entirely when duration is zero or absent.

Content variants:

| State | Title line | Detail line | Progress |
|-------|-----------|-------------|----------|
| TV episode | Series name | S1E3 · Episode Name | bar + timestamps |
| Movie | Movie title | *(none)* | bar + timestamps |
| Extra | Entity name | Extra name (no S/E prefix) | bar + timestamps |
| Idle | *(none)* | "Idle" muted text | *(none)* |

No percentage label — the bar plus timestamps is sufficient; three representations would be clutter.

### Consequences

* Good, because the show name is immediately visible without hovering or reading episode codes
* Good, because the progress bar provides instant visual feedback on playback position
* Good, because state-colored bar reinforces the playing/paused distinction already shown in text
* Good, because movies and extras degrade gracefully with fewer lines
* Neutral, because the card is slightly taller; acceptable given the information density gain
