# Ignore rules — unification design

**Status:** approved 2026-09-15, implementing
**Trigger:** TMDB searches firing on every boot for Windows Game Bar clips in
`/home/shawn/videos/media-library/Captures`, a directory already listed in
`exclude_dirs`.

## Glossary

| Term | Meaning |
|---|---|
| **media directory** | A configured root the watcher watches. Config key `media_dirs`. |
| **ignore rule** | A statement that some part of a media directory is not library content. Two kinds below. |
| **path rule** | An ignore rule matching an absolute path prefix: the path itself and everything under it. Config key `exclude_dirs`. UI: Library → *Excluded directories*. |
| **name rule** | An ignore rule matching a directory *name* wherever it appears, case-insensitively. Config key `skip_dirs`. UI: Media Import → *Ignored folder names*. |
| **reserved name rule** | A name rule the app always applies regardless of config: `.staging`, the download-client assembly contract. |
| **derived path rule** | A path rule the app adds per media directory: that directory's image cache and image staging roots. |
| **extras name** | A directory name whose video contents are bonus features of the enclosing title, not titles of their own. Config key `extras_dirs`. A *classification* rule, not an ignore rule. |
| **library content** | A path that is a recognised video file and is not ignored. The single admission predicate. |
| **admission** | The decision to let a path enter the pipeline at all. |
| **retraction** | Removing recorded state for paths that a newly-added ignore rule now covers. |

`exclude_dirs` and `skip_dirs` keep their config-key names — renaming stored keys
buys nothing. The glossary is where they are stated to be two matching modes of
one idea, which is what the code will encode.

## 1. Core idea

> **"Is this path library content?" is one question about one path, answered by one
> rule set derived from configuration, and every code path that admits a path into
> the library asks it.**

Everything else in this design follows from that sentence. The bug that started
this is not "rescan forgot a filter" — it is that there are three independent
answers to that question and a fourth caller that never asks.

A second half follows from the same sentence: if an ignore rule says a subtree is
not library content, then recorded state must not claim otherwise. Adding a rule
is therefore a retraction, not only a filter on future work.

## 2. Greenfield shape

One module owning the rule set and the predicate:

```elixir
MediaCentaur.Watcher.IgnoreRules

  load(media_dir)          :: t()       # path rules + derived + name rules + reserved
  ignored?(path, rules)    :: boolean   # prefix match, or any *parent* component is a name rule
  ignored_dir?(path, rules):: boolean   # prefix match, or the dir's own basename is a name rule
  library_content?(path, rules) :: boolean   # VideoFile.video?(path) and not ignored?(path, rules)
```

`ignored_dir?/2` exists only so traversal can stop descending. It can never
disagree with `ignored?/2` — a file under an ignored directory is already not
library content — so it is an optimisation, not a second decision.

Three consumers, one predicate:

| Boundary where a path enters | Calls |
|---|---|
| inotify event (`Watcher.interesting?/2`) | `library_content?/2` |
| directory scan (`Walk.walk/2`) | `ignored_dir?/2` to prune, `library_content?/2` per file |
| recovery re-emit (`Rescan.rescan_unlinked/0`) | `library_content?/2` |

Ownership of the rule set: rules are a value, `load/1` is two config reads. Each
`Watcher` GenServer caches one instance to avoid a config read per inotify event,
and refreshes it on a `:config_updated` broadcast for **either** key. `Rescan`
builds a `media_dir => rules` map per pass. No new process, no ETS.

The invariant that keeps it honest:

> **No linked file's path may sit under an ignore rule.**

Enforced where a rule is created (Settings validation, both kinds), and
maintained thereafter by construction: nothing imports from an ignored path, and
a file moved into an ignored folder leaves the library through the existing
absence path, which is the correct reading of that move.

## 3. Audit — where exclusion is and is not applied today

Verified against the running dev instance and the code at `6ff240d3`.

| Site | Today | Verdict |
|---|---|---|
| `Watcher.interesting?/2` (`watcher.ex:421`) | `video?` + `ExcludeDirs.excluded?` (state, refreshed) + `in_skip_dir?` (state, **loaded once at `init/1`, never refreshed**) | Name rules go stale until restart |
| `Watcher.scan_directory_with_paths/4` (`watcher.ex:447`) | `Walk.walk` with state path rules + **freshly loaded** name rules, then `Enum.filter(&VideoFile.video?/1)` | Correct, but a third lifetime for one value |
| `Walk.walk/4` (`walk.ex:35`) | the only place `ExcludeDirs` is consulted | Sound; needs to own the whole predicate |
| `Rescan.rescan_unlinked/0` (`rescan.ex:68`) | **no filter at all** — reads `FilePresence` rows, filters on `File.exists?` only | **The reported bug** |
| `Rescan.scan/0` | delegates to each watcher's `:scan` | Inherits the scan path, fine |
| `Review.Intake` / `Review.add_pending_file/1` | no filter | Correct — upstream should be clean |
| `Import.Producer` | no filter | Correct — only receives matched files |
| `Library.Relink.moved_files/3` | destinations come pre-filtered from the scan; **candidate set (`FilePresence.list_relink_candidates/1`) is not filtered** | Fixed for free by retraction |
| `Library.AbsenceSweeper.purge_expired/1` | purges on stale `last_seen_at` alone — **does not require the file to be gone** | Latent data loss, see I-5 |
| `Watcher.DirValidator.build_preview/2` | counts videos with no rules, one level deep, at add-time | Cosmetic, droppable |
| `Settings` path-rule validation (`settings_live.ex:1690`) | absolute + exists + readable + not duplicate | Missing: inside a media dir; no linked content underneath |
| `Settings` name-rule validation (`settings_live.ex:999`) | non-empty, not duplicate | Same two gaps |
| `Library.Files.linked_paths_subquery/0` (`files.ex:136`) | `WatchedFile` only — **ignores `ExtraFile`** | Half of every re-emit is waste |
| `Pipeline.Discovery.already_linked?/1` (`discovery.ex:216`) | `WatchedFile` **or** `ExtraFile` | The correct definition; two definitions exist |
| Pending-review rows | nothing removes one when its file disappears | Pre-existing orphan bug, adjacent |

Measured on the live instance: `rescan_unlinked/0` re-emits **20** rows per boot.
Ten are already linked as `ExtraFile` (wasted pass, skipped cheaply by
`already_linked?`). Ten are genuinely unlinked and each costs a parse plus **two**
TMDB searches — `Parser` types these as `:unknown`, and `Stages.Search.search/3`
fans out to `/search/movie` and `/search/tv` in parallel. Eight of those ten sit
under the configured path rule. The HTTP cache is an ETS table owned by
`Cache.Coordinator`, so it dies with the BEAM and the cost is paid again on every
restart.

## 4. Incoherences and dispositions

**I-1 — Three lifetimes for one rule set.** Path rules cached and refreshed; name
rules cached and never refreshed; name rules also loaded fresh per scan.
→ **Fix now.** One `rules` field, refreshed on either config key.

**I-2 — `rescan_unlinked/0` bypasses admission.** The reported bug.
→ **Fix now.** Filter through `library_content?/2`.

**I-3 — Two definitions of "linked".** `linked_paths_subquery/0` says
`WatchedFile`; `already_linked?/1` says `WatchedFile ∪ ExtraFile`.
→ **Fix now.** `linked_paths_subquery/0` unions both; `already_linked?/1` uses it.

**I-4 — Adding a rule filters the future but does not retract the past.** Stale
`FilePresence` rows keep feeding the pipeline; pending-review rows keep sitting in
the queue.
→ **Fix now.** A retraction pass on config change and at boot: drop unlinked
presence rows under the rules, and have Review drop pending rows for the same
paths. Review cannot be called from Watcher (`Watcher` deps `[Library]`), and the
existing `{:files_removed, paths}` broadcast on `Topics.library_file_events()` is
already the removal channel — so Review subscribes to it. That also closes the
orphan bug in the last audit row, at the seam rather than beside it.

**I-5 — `AbsenceSweeper` will purge linked content under an ignored path.** Once a
subtree stops being walked its rows stop being re-stamped; after
`file_absence_ttl_days` (default 30) the sweeper purges them and runs the deletion
cascade, for files that are still on disk. Today that is reachable by excluding a
directory that contains imported titles.
→ **Fix now, by invariant** (owner decision, 2026-09-15). Settings rejects a rule
that would cover linked files, naming the count. The boot-time retraction pass
logs a warning for any pre-existing violation instead of purging it. No change to
the sweeper, no new dependency edge — "ignored but still imported" is
unrepresentable.
*Alternative rejected:* move `IgnoreRules` (and `VideoFile`) into `Library` so
`AbsenceSweeper` can skip ignored paths, permitting a partially-ignored subtree.
More movement, and it legitimises a state the product has no use for.

**I-6 — WITHDRAWN (2026-09-15). `Sample` in two lists is not a contradiction.**
The claim as written was wrong on the facts. `Config`'s `extras_dirs` default does
*not* contain `sample`/`samples` — those live in `Parser`'s `@default_extras_dirs`,
the fallback used when a caller passes no `:extras_dirs` option. The two lists
serve two populations: name rules decide what the watcher *admits from disk*,
while the parser's sample handling classifies *release names and grabbed
filenames* that reach it by other routes (`Search.TitleMatcher`,
`Pursuits.Commands.StartFromPick`). `test/media_centaur/parser_test.exs:772-800`
pins the sample-clip behaviour on real observed paths and is append-only
(ADR-027), so it is a deliberate contract, not dead config.
→ **No change.**

**I-6b — the extras list has two versions, and one file can get both.** Found
while checking I-6, and genuinely broken. `Stages.Parse` parses with the
configured `extras_dirs` (6 entries); `Pipeline.Import` (`import.ex:82`) and
`Review.parsed_pending_attrs` (`review.ex:204`) re-parse the same path with
`Parser.parse/1` and get the hardcoded fallback (8 entries, adding
`sample`/`samples`). A file at `<media>/Film/Samples/clip.mkv` is admitted — the
name rule is `Sample`, not `Samples` — then classified as a normal title by
discovery and as an extra by import.
→ **Scheduled convergence, not this change.** It is the extras-*classification*
slice, not admission, and closing it means deciding which list wins, which
changes how existing installs import. Convergence point: the next change that
touches extras classification — `Pipeline.ExtraRederive` is the natural one,
since it already re-derives extras names from config. Until then the fallback
stays, and this paragraph is the record.

**I-7 — A path rule is accepted for any absolute readable directory,** including
one outside every media directory, where it does nothing.
→ **Fix now.** Validate that it is inside a media directory.

**I-8 — One idea, two Settings cards.** Path rules live under Library, name rules
under Media Import, cross-referenced in prose.
→ **Fix now** (owner decision, 2026-09-15). One *Ignore rules* card with two
lists — path rules and name rules — matching the model the code now encodes. The
card lands wherever the media directories are configured, since a rule is scoped
to them; Media Import keeps only *extras names*, which is classification, not
admission. `settings_live/library.ex` and `settings_live/import_section.ex` both
change, so both stories change with them (MC0009).

**I-9 — `DirValidator.build_preview/2` counts videos without rules.** A candidate
directory's preview can promise videos the watcher will never admit.
→ **Dropped** (owner decision, 2026-09-15). Partial fix for a cosmetic preview;
not worth the coupling.

## 5. Scope cost

Honest accounting. The cheap path — one `Enum.reject` in `rescan_unlinked/0` — is
about 5 lines and leaves I-1, I-3, I-4, I-5, I-7 and I-8 in place.

| Work | Size |
|---|---|
| `Watcher.IgnoreRules` replacing `Watcher.ExcludeDirs`; rewrite its test | small |
| `Walk.walk/2` takes rules, returns library content; rewrite walk tests | small |
| `Watcher` GenServer: one `rules` field, refresh on both keys, delete `load_skip_dirs/0` `load_exclude_dirs/1` `in_skip_dir?/2` `refresh_exclude_dirs/1` | small |
| `Rescan.rescan_unlinked/0` filter + tests | small |
| `linked_paths_subquery/0` union; `already_linked?/1` uses it; tests | small |
| Retraction pass + Review subscriber to `{:files_removed, paths}`; tests | medium |
| Settings validation for both rule kinds (inside a media dir, no linked content) + tests | medium |
| Merge the two Settings cards into one *Ignore rules* card + stories | medium |
| One-time cleanup of the 8 stale rows on this instance | trivial |
| Docs: `docs/watcher.md`, `docs/GLOSSARY.md` entries, wiki *Settings-Reference* / *Configuration-File* | small |

No ADR: this is one subsystem's internal contract, so the reasoning belongs in the
`IgnoreRules` moduledoc, with this file kept for the audit.
