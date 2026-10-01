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
    mix context_map --list                        # jump list: path:line: message per site

Query modes — `--check`, `--list` — answer a question and write nothing
unless an output is named explicitly with `--json`, `--html` or `--page`.
A plain `mix context_map` still writes the JSON.

`--list` prints one line per site, sorted by path then line:
`path:line: RULE schema.field[ = value] — summary`, where the summary is
`reinterpreted in Consumer` (R3), `written from Context` or
`never read by Owner` (R1), and `keys into Target (not in deps)`,
`keys into Target` or `unresolved key` (R4). An editor that reads
`file:line:` locations jumps from line to line. A Sublime Text build
system, saved as `Context map.sublime-build`:

```json
{
  "shell_cmd": "mix context_map --list",
  "file_regex": "^([^:]+):(\\d+): (.*)$",
  "working_dir": "${project_path}"
}
```

In an agent shell, run `~/scripts/agents/agent-mix context_map --list`
instead of `mix` (see `CLAUDE.md`).
