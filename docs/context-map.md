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

    mix context_map --html tmp/context-map.html   # regenerate and view
    mix context_map --page                        # regenerate, page at tmp/context-map.html
    mix context_map --check                       # every finding has a verdict?
