---
status: accepted
date: 2026-03-03
last-updated: 2026-05-02
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

### Component-enforced (2026-05-02 amendment)

Rules 2 and 3 (the cases that actually use a `<span class="badge …">`) now live in the `<.badge>` component (`MediaCentarrWeb.CoreComponents.badge/1`) as named `variant` values: `metric`, `type`, `info`, `success`, `warning`, `error`, `ghost`, `primary`, `soft_primary`. The `MediaCentarr.Credo.Checks.RawBadgeClass` Credo check (precommit) flags any raw `class="badge …"` string in templates under `lib/media_centarr_web/`. The badge component file (`core_components.ex`) is exempt — it owns the literal `badge` token.

The `primary` / `soft_primary` variants were added during the migration sweep to cover (a) active filter pills that need to grab attention (solid primary blue) and (b) tonal annotations like rewatch counters or manual-origin labels (soft primary). They are deliberately separate variants so the design conversation around "is this a filter pill or a tonal annotation?" stays explicit.

Rule 1 (status/reason labels) deliberately remains plain colored text — no badge element, no component. The check does not flag `<span class="text-error">…</span>`.

### Consequences

* Good, because dense lists are easier to scan without competing badge backgrounds
* Good, because the convention is simple — color alone carries the semantic meaning
* Bad, because plain text labels are less visually distinct than bordered badges in isolation; mitigated by consistent use of semantic colors
