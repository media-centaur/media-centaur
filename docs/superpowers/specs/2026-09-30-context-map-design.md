# Context map — design

Date: 2026-09-30. Status: draft, awaiting review (§ 10).

A generated map of every data entity, the bounded context that owns it, and
every place another context reaches into it — built so that a concept
crossing a context boundary is a visible, reviewable line rather than
something noticed by accident.

The motivating instance: Discovery's `TitleIntent.rung` value `:ignored` is
documented as "keeps it off the Feed, and nothing else", yet the Incoming
search results, the title detail panel and the tracking controls each
interpret that value on their own. Nothing in the code held the documented
line. A second instance sits on the same table: `title_intents.source`
(`:friend`) and `title_intents.activity_id` serve the social feed, not
Discovery — a social feature bolted onto Discovery's representation of a
title.

## 1. Glossary

Terms already in use, restated so this document is self-contained:

| Term | Meaning |
|---|---|
| **Bounded context** | A top-level `MediaCentaur.<Name>` namespace with a `use Boundary` declaration on its facade module. The Boundary compiler enforces its `deps` and `exports` (ADR-029). |
| **Facade** | The context's top-level module, the only module other contexts call. |
| **Export** | A module a context lists in `use Boundary, exports: [...]`, which other contexts may reference directly. |
| **Schema** | An Ecto schema module. Its owner is the context whose namespace contains it. |
| **Shared kernel** | A context whose representation is deliberately shared: other contexts read its entities directly, and that sharing is not a crossing. Evans' term. Assumed membership: `Library` and the TMDB title store (`MediaCentaur.TMDB`, ADR-071). See § 10. |

New terms, defined here before first use:

| Term | Meaning |
|---|---|
| **Context map** | Evans' name for the diagram of bounded contexts and the relationships between them. Here: the generated document (JSON plus its HTML rendering) described in § 5 and § 6. |
| **Representation** | The set of schemas a context holds for one concept. Discovery's representation of a title is `TitleIntent`; Release Tracking's is `ReleaseTracking.Item`. |
| **Crossing** | A place where one context's code or schema depends on another context's representation. Three kinds are detected, defined in § 3: *reinterpretation*, *cross-context key*, *foreign field*. |
| **Consumer** | The module, and the context or web surface it belongs to, at which a crossing occurs. |
| **Surface** | For a consumer in the web layer, the LiveView that renders it, resolved through the component reference graph. `Components.Title.Logic` is a consumer; Incoming and the title detail host are its surfaces. |
| **Finding** | One crossing the extractor reports: rule, owner, schema, field, value where applicable, consumer, file and line. |
| **Verdict** | A person's recorded judgment of one finding: **leak** (the rule is right, the code is wrong), **allowed** (the code is right, the rule gains a stated exception), or **rule wrong** (the signal fires on something the rule does not forbid; the signal is refined). |
| **Fixture instance** | A known crossing the extractor must always report. Recall floor for every version of the signals. |
| **Calibration pass** | One full run of the extractor followed by a verdict on every finding (§ 7). |

## 2. Goal and non-goals

**Goal.** Make every crossing of a context boundary at the data level
visible in one place, deterministic to produce, and impossible to add
without a reviewable line in the same change. The map measures distance
from the ownership rule in § 3; the rule, not the tool, defines what a leak
is.

**Non-goals for this spec.**

* Migrating existing crossings. The map produces the backlog; each
  migration is its own change.
* Shrinking `exports` to view structs only. That is the structural end
  state the map points at (§ 8) and is decided per context, later.
* Code-level reads of exported structs that are not field or value
  interpretations, such as passing a struct through unchanged.
* Anything the AST cannot see: dynamic field access with a variable key,
  meaning reconstructed from a boolean a facade returned. § 3 names these
  limits per rule.

## 3. The ownership rule, as testable claims

Each rule has an ownership statement, the signal the extractor uses, and
the signal's known limits. A rule with no expressible signal is guidance,
not a rule, and is marked as such.

### R1 — Own representation

*Statement.* Each context keeps its own representation of a concept,
holding only the fields it reads and writes for its own purpose. It never
adds a field to another context's table for its own need.

*Signal — foreign field.* For every field of every schema, the extractor
attributes each read and write to a context (or to the web layer). A field
is reported when the owning context, excluding the schema module itself,
migrations and tests, never reads it (a field the owner writes but never
reads is still reported), or when another context writes it.

*Amendment 2026-10-01.* A write is a key in a map or struct literal in
expression position, or a `cast`/`put_change`/`force_change` call on the
line; keyword arguments are not writes. The distinctiveness test counts the
keys of every `defstruct` under `lib/`, not only schema fields.

*Limits.* A write made through a helper the owning schema provides
(`TitleIntent.friend_provenance/2` called from the web layer) is a
function call to the signal, not a key literal, and is attributed to the
owner. Reads are anchored on the field name (`.field`, `field:` in a
pattern or keyword, `x.field` in a query, `Map.get(_, :field)`, `cast/3`
lists). For a field name that is not distinctive (`name`, `status`, `id`,
`inserted_at`), the count is restricted to files that reference the owning
schema module by alias, struct expansion or `from x in Schema`. A file that
receives the struct through a variable without naming the module is not
counted for those fields. Timestamps and primary keys are excluded.

### R2 — Shared kernel

*Statement.* `Library` and the TMDB title store are shared. Reading their
entities from another context is not a crossing. Writing them from another
context is.

*Signal.* Findings under R3 and R4 whose owner is a shared-kernel context
and whose crossing is a read are suppressed. Keys into the kernel are
listed as kernel reads, so the map shows that fan-out without findings;
interpretations of a kernel enum value are skipped and not counted
(amended 2026-10-01 to match the extractor).
Writes are reported under R1.

*Amendment 2026-10-01.* "Owner" here means the referenced side: the schema
whose value is interpreted (R3) or the key's target (R4).

*Limits.* Kernel membership is declared, not detected (§ 10).

### R3 — No reinterpretation

*Statement.* A context never interprets another context's values. It asks
the owner's facade a question and acts on the answer.

*Signal — reinterpretation.* For every `Ecto.Enum` field and every field
with a declared value set (`@type` union of atoms on the schema module —
not implemented as of 2026-10-01: every value set in the application is an
`Ecto.Enum`, so the `@type` form is a stated limit until a schema needs it),
the extractor reports each occurrence outside the owning context of a
literal value of that field in a function-clause pattern, a struct or map
pattern with the field name, a query filter on the field, an `in` list, or
a comparison.

*Limits.* A bare atom literal is ambiguous (`:ignored` is also an
`Activities.ingest/1` return). An occurrence is *anchored* when the field
name appears in the same expression, or the file names the owning schema
module; it is *unanchored* otherwise. Both are reported; unanchored
findings are labelled as candidates and expected to carry more rule-wrong
verdicts. Meaning derived inside the owner and returned as a boolean or a
label is invisible to this signal by design: that is the correct shape.

*Amendment 2026-10-01.* An unanchored value is reported only when exactly
one schema field in the application declares it (`Schemas.value_owners/1`);
a vocabulary shared by several schemas (`:movie`) is reported only when
anchored. A value declared by schema fields in two or more contexts is
shared vocabulary with no owner and is never reported.

### R4 — Keys follow ownership and the dependency direction

*Statement.* A context references another context's entity by identity
only, and only in the direction its Boundary `deps` allow. A key pointing
into a context the owner does not depend on is a crossing.

*Signal — cross-context key.* Every `belongs_to`, `has_*`, `many_to_many`
whose target schema belongs to another context; every field named `*_id`
or `*_ids` with no association, resolved to the schema whose table or
module name it names. A finding records whether the target context is in
the owner's declared `deps`. A key whose target cannot be resolved is
reported as *unresolved* rather than guessed.

*Limits.* Polymorphic keys (`owner_type` + `owner_id`, `container_type` +
`container_id`) resolve through their discriminator's value set when it
names schemas, otherwise stay unresolved. External identifiers (`tmdb_id`,
`imdb_id`, `tvdb_id`) are identity of a shared-kernel record and are
listed as kernel references, not findings.

### G1 — Facades return answers, not raw state *(guidance)*

*Statement.* A facade function returning another context's raw enum values
in bulk (`Discovery.rungs/0`) invites reinterpretation. Prefer predicates
and view structs.

*No signal.* Return types are not statically known. R3 catches the
consequence at the consumer.

## 4. Fixture instances

Every version of the extractor must report these, in `findings` or, for
the R2 row, in `kernel_reads`. They are the recall floor; a refinement
that loses one is rejected.

| Rule | Owner | Schema.field (value) | Consumer |
|---|---|---|---|
| R3 | Discovery | `TitleIntent.rung` (`:ignored`) | `MediaCentaurWeb.Components.Title.Logic` — surfaces Incoming, title detail |
| R3 | Discovery | `TitleIntent.rung` (`:ignored`) | `MediaCentaurWeb.Components.Title.WatchlistToggle` |
| R3 | Discovery | `TitleIntent.rung` (`:ignored`) | `MediaCentaurWeb.Components.Title.TrackingControls` |
| R3 | Discovery | `TitleIntent.rung` (`:ignored`) | `MediaCentaurWeb.DiscoveryLive.FeedEntries` (the one documented consumer; expected verdict *allowed*) |
| R1 | Discovery | `TitleIntent.activity_id` | never read in Discovery (`owner_never_reads`) |
| R1 | Discovery | `TitleIntent.source` (`:friend`) | never read in Discovery (`owner_never_reads`) |
| R4 | Discovery | `TitleIntent.activity_id` → Activities | target context not in Discovery's `deps` |
| R2 | Release Tracking | `Item.library_container_id` → Library | resolves through `library_container_type`; expected in `kernel_reads`, not in `findings` |
| R2 | Watch History | `Event.movie_id` → `Library.Movie` | expected in `kernel_reads` (row added 2026-10-01) |

The fixture list grows with every leak found by other means; it is
append-only (ADR-027 applies to the test that encodes it).

*Amendment 2026-10-01.* The first draft listed `activity_id` and `source`
as "written from Activities". By the time the extractor ran, the friend
provenance was built by the owner's own helper
(`TitleIntent.friend_provenance/2`) and called from the web layer, so no
non-owner file holds the key literal. R1 attributes a write through an
owner-provided helper to the owner — a stated limit (§ 3 R1) — and the
bolt-on is caught by `owner_never_reads` instead. The rows above say so.

## 5. The extractor

A Mix task, `mix context_map`, that produces one JSON document from the
compiled application and the source tree. Pure function of the tree: same
tree, same bytes.

**Inputs.**

1. Contexts, deps and exports: `Boundary.Mix.View.build/0` and
   `Boundary.all/1`, the same view the compiler checks.
2. Schemas: every module exporting `__schema__/1`, read for `:source`,
   `:fields`, `:type` per field, `:associations`, and `Ecto.Enum` value
   sets via `Ecto.Enum.values/2`. Declared atom-union `@type`s are read
   from the schema's source.
3. Consumers: every file under `lib/`, parsed with `Sourceror` (already a
   dev dependency) so each finding carries a line. Migrations under
   `priv/repo/migrations` are excluded; they are the one place literals
   are legitimately written.
4. Surfaces: the module reference graph inside `lib/media_centaur_web`,
   from which each component is followed to the LiveViews that render it.

**Output** — `docs/context-map/context-map.json`:

```json
{
  "contexts": [
    {
      "name": "MediaCentaur.Discovery",
      "kernel": false,
      "deps": ["MediaCentaur.Library", "MediaCentaur.TMDB", "MediaCentaur.TmdbArtwork"],
      "exports": ["MediaCentaur.Discovery.TitleIntent", "..."],
      "schemas": [
        {
          "module": "MediaCentaur.Discovery.TitleIntent",
          "table": "title_intents",
          "fields": [
            {"name": "rung", "type": "Ecto.Enum", "values": ["ignored", "list", "follow", "grab"],
             "reads": {"MediaCentaur.Discovery": 6, "MediaCentaur.Activities": 1, "web": 9},
             "writes": {"MediaCentaur.Discovery": 2, "MediaCentaur.Activities": 1}}
          ],
          "associations": []
        }
      ]
    }
  ],
  "kernel_reads": [ {"owner": "...", "schema": "...", "field": "...", "consumer": "...", "file": "...", "line": 0} ],
  "findings": [
    {
      "key": "R3|MediaCentaur.Discovery.TitleIntent|rung|ignored|MediaCentaurWeb.Components.Title.Logic",
      "rule": "R3",
      "owner": "MediaCentaur.Discovery",
      "schema": "MediaCentaur.Discovery.TitleIntent",
      "field": "rung",
      "value": "ignored",
      "consumer": "MediaCentaurWeb.Components.Title.Logic",
      "consumer_context": "web",
      "surfaces": ["MediaCentaurWeb.IncomingLive", "MediaCentaurWeb.TitleDetailHost"],
      "anchored": true,
      "file": "lib/media_centaur_web/components/title/logic.ex",
      "line": 189
    }
  ]
}
```

Every list is sorted by its key. No timestamps, no git metadata, no
absolute paths. A finding's `key` is stable across runs and is what the
verdicts file references (§ 7).

**Structure.** `MediaCentaur.ContextMap` is a dev-only namespace
(`elixirc_paths(:dev)` and `:test`, beside `credo_checks/`), with one
module per input (`Contexts`, `Schemas`, `Consumers`, `Surfaces`), one per
rule signal (`Rules.ForeignField`, `Rules.Reinterpretation`,
`Rules.CrossContextKey`), a `Report` that joins findings with verdicts, and
the Mix task as the only entry point. No runtime process, no application
dependency on it.

*Amendment 2026-10-01.* `kernel_reads` entries are `{owner, schema, field,
target}`, and each schema in the document also carries its `file`. Fields
are listed in declaration order, which is deterministic.

## 6. The map (HTML)

`mix context_map --html PATH` (default `tmp/context-map.html`, which is
gitignored) renders the JSON as one self-contained page with no external
scripts. Two views of the same data, plus the findings list:

1. **Context matrix.** Rows are owning contexts, columns are consuming
   contexts and the web layer. A cell holds the finding count by rule;
   the diagonal is muted; kernel-read cells are shaded differently and
   labelled as such. Clicking a cell lists its findings.
2. **Entity panels.** One panel per context, listing each schema and its
   fields. A field shows its read and write counts per context; a field
   with findings carries a chip per rule naming the consumer; an enum
   field lists per value the consumers that interpret it. Beside the
   value list, the owner's declared meaning where one exists (today, the
   moduledoc table; § 8 moves it into code).
3. **Findings**, filterable by rule, owner, consumer, anchored, verdict.
   Unverdicted findings are listed first.

The renderer is a plain HEEx-free EEx template producing static HTML; no
graph layout library, since the matrix and panels need none. The page
follows the `user-interface` skill's theme tokens so it reads like the
rest of the product in both schemes.

## 7. Calibration loop

The rules in § 3 are hypotheses until a full pass agrees with a person's
judgment. The loop:

1. **Run** `mix context_map`. Findings without a verdict are listed first.
2. **Verdict** every finding, in `docs/context-map/verdicts.json`:

   ```json
   [{"key": "R3|...|Title.Logic", "verdict": "leak", "reason": "search marker reinterprets a Feed-only value"},
    {"key": "R4|...|Item|library_container_id|MediaCentaur.Library", "verdict": "allowed", "reason": "kernel reference"}]
   ```

   *Rule wrong* is a verdict given in review, not stored: it changes the
   signal or the rule text in § 3, and the pass is rerun. An *allowed*
   verdict that applies to a class of findings, not one, is also a rule
   change: the exception is written into the rule and the signal, so the
   verdicts file holds only individual judgments.
3. **Recall check.** The fixture instances (§ 4) are a test; the pass
   fails if any is missing. In addition, one manual audit per calibration
   round: the reviewer reads two contexts end to end, lists every
   crossing seen by hand, and compares with the findings. Anything seen
   and not reported is a false negative and either extends a signal or is
   recorded as a stated limit in § 3.
4. **Stable** means: a full pass with zero rule-wrong verdicts, every
   fixture instance reported, and the manual sample fully covered. At
   that point the rule text is moved into an ADR (drafted alongside this
   spec as *proposed*, accepted at stability) and enforcement (§ 8) is
   switched on.

Until stable, the task reports and nothing fails.

## 8. After stability

**Verdict check in precommit.** `mix context_map --check` fails when a
finding has no verdict, or a verdict has no finding. A new crossing
therefore cannot land without a verdict line in the same change, and a
removed crossing cleans its verdict up. This replaces the earlier idea of a
snapshot equality check: the verdicts file *is* the snapshot, and each
line carries its reason.

**Declared meaning on the schema.** The moduledoc rung table becomes a
module attribute on the owning schema naming, per value, what it means and
which consumers may act on it. The map renders it beside the consumers; a
later revision of R3 can read it and report only undeclared consumers,
which turns MC0014 GrabStatusContract and MC0031 PursuitStateContract
into instances of one data-driven check.

**Exports shrink.** The findings backlog, ordered by consumer count per
schema, is the migration order for replacing exported schemas with view
structs and facade predicates, one context at a time, Discovery first.
Each migration is its own change with its own tests.

## 9. Testing

Test-first throughout (`automated-testing` skill).

* **Signals**: unit tests per rule module against source strings and a
  small set of schema modules (as built, inline source strings and real
  application schema modules, since the schema file is located from the
  compiled module; no `test/support/context_map/` directory exists),
  covering each anchor form named in § 3 and each stated limit (a limit
  is asserted as *not* reported, so a later improvement is a deliberate
  change).
* **Fixture instances**: one test asserting each row of § 4 appears in
  a full run against the real application. Append-only.
* **Determinism**: two consecutive runs produce identical bytes.
* **Verdict join**: unverdicted and stale verdicts are each reported;
  `--check` exits non-zero on either.
* **Renderer**: the HTML page compiles from the JSON and contains every
  finding key; no browser test.

## 10. Assumptions to confirm

* Shared kernel membership is `Library` and `MediaCentaur.TMDB`. Any
  other context whose entities are read broadly by design — `Settings`
  as shared infrastructure per ADR-029 point 3 — is declared here or is
  not kernel.
* The verdicts file and the generated JSON live under
  `docs/context-map/`; the HTML rendering is not committed.
* The task name `mix context_map` and the term *context map* are the
  chosen names, after Evans; *crossing*, *finding*, *verdict* and
  *fixture instance* are the new terms and are elevated to
  `docs/GLOSSARY.md` when the rule is stable.

## 11. Reading aids (added 2026-10-01)

Decided after the first full run produced 416 findings under about 300
verdict keys. Each aid serves the calibration pass or the review-time use
of the map; none changes a rule.

* **Excerpts.** Every finding carries the trimmed source line. R1
  `owner_never_reads` and R4 findings point at the field's declaration
  line in the schema file and carry that declaration. Schema fields and
  associations record their declaration line.
* **Concept grouping.** The page groups findings by concept —
  `{rule, schema, field, value}` — then by consumer, then by site, so one
  reinterpreted value is read once with all its sites under it.
* **Concept verdicts.** A verdict key may end in `*` in the consumer
  segment and then covers every consumer of that concept; an exact key
  overrides it. The check still requires every finding to be covered, and
  reports wildcard keys that match nothing as stale.
* **Jump list.** `mix context_map --list` prints `path:line: message` per
  site for editor navigation.
* **Semantic diff.** `mix context_map --diff [PATH]` lists verdict keys
  added and removed between the fresh analysis and the committed map; line
  moves are ignored. This is the review-time reading of a change.
* **Query modes write nothing** unless an output path is given explicitly.

In-app verdicting (a dev-only LiveView writing the verdicts file) is
deferred until the rules are stable and the verdict shape has stopped
moving.
