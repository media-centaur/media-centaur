# Context map

`mix context_map` generates `docs/context-map/context-map.json` — every Ecto
schema by owning bounded context, and every crossing of a context boundary
at the data level — and, with `--html PATH`, a self-contained page.

Rules and signals: `docs/superpowers/specs/2026-09-30-context-map-design.md` § 3.
Verdicts: `docs/context-map/verdicts.json`, one `{key, verdict, reason}` per
finding, `verdict` ∈ `leak | allowed`. A *rule wrong* judgment changes the
rule, never the file. `mix context_map --check` fails on a finding without a
verdict or a verdict without a finding; it joins `mix precommit` once the
calibration loop (spec § 7) reaches stability.

A verdict key takes one of two forms. An exact key names one consumer of a
concept, as `Finding.key/1` builds it:
`R3|MediaCentaur.Activities.Activity|kind|review|MediaCentaurWeb.ReviewLive`.
A concept key replaces that last (consumer) segment with `*` and covers
every consumer of the concept `{rule, schema, field, value}`:
`R3|MediaCentaur.Activities.Activity|kind|review|*`. An exact key overrides
the concept key for its consumer; the page shows the concept verdict on the
concept and marks a consumer whose own verdict overrides it. A `*` anywhere
else is rejected. `--check` counts a finding covered by either form and
reports a concept key that matches no finding as stale.

    mix context_map --html tmp/context-map.html   # regenerate and view
    mix context_map --page                        # regenerate, page at tmp/context-map.html
    mix context_map --check                       # every finding has a verdict?
