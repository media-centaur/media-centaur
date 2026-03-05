---
status: accepted
date: 2026-03-03
---
# Badge style convention

## Context and Problem Statement

Status labels, metric values, and type classifications were inconsistently styled — some used filled badges, some used outlined badges, some used plain text. The visual noise from bordered/filled badges made dense lists harder to scan, especially on glassmorphism surfaces where saturated backgrounds compete with the backdrop.

## Decision Outcome

Chosen option: "semantic plain text for status, outline for type classification", because colored text alone provides sufficient signal for inline labels without adding visual clutter.

Rules:

1. **Status/reason labels** (review reasons, entity states): plain colored text (`text-error`, `text-warning`, `text-info`) — no badge border or fill.
2. **Metric badges** (confidence scores, counts): solid fill is acceptable — data values benefit from stronger visual weight to aid scanning.
3. **Type badges** (Movie, TV, Extra): `badge-outline` with no color override — neutral classification, not status.

### Consequences

* Good, because dense lists are easier to scan without competing badge backgrounds
* Good, because the convention is simple — color alone carries the semantic meaning
* Bad, because plain text labels are less visually distinct than bordered badges in isolation; mitigated by consistent use of semantic colors
