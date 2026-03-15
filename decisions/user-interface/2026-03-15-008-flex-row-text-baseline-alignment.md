---
status: accepted
date: 2026-03-15
---
# Flex rows with mixed-size text use baseline alignment

## Context and Problem Statement

Flex rows containing a label and a value in different font sizes (e.g. base label + mono `text-xs` path) visually misalign when using `align-items: center` — the text bottoms don't line up, creating a subtle but noticeable vertical offset.

## Decision Outcome

Chosen option: "align-items: baseline", because it aligns the text baselines of both items regardless of font size, producing visually correct alignment for label/value pairs.

### Rules

- **Text/text rows** (label + value, both rendered as text): use `align-items: baseline`
- **Text/control rows** (label + toggle, checkbox, button): use `align-items: center` — controls are UI elements, not text, so baseline has no meaning

### Consequences

* Good, because text rows look aligned at any font-size combination
* Good, because the rule is simple: text pairs → baseline, control pairs → center
