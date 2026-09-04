---
description: Documentation audit across every surface — contributor docs, moduledocs, decision records, campaigns, skills, README, wiki, and the marketing page — verified against source code.
argument-hint: "[file-or-path (optional)]"
---

# Documentation Audit

You are auditing Media Centaur's documentation for accuracy, staleness, placement,
and cross-reference integrity. Every finding cites the documentation file *and* the
source file or filesystem evidence that contradicts it.

**Brutal honesty is mandatory.** Do not soften, hedge, or balance criticism with
praise. The user wants to know what is wrong.

**Scope:** If `$ARGUMENTS` is provided, focus on that file or path. Otherwise audit
every surface below.

**The cardinal rule: read the code.** Documents can be wrong about each other; only
source and the filesystem are ground truth.

## The surfaces

| Surface | Location | Audience | Notes |
|---|---|---|---|
| Contributor guide | `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md` | contributors and AI agents | `CLAUDE.md` is orientation plus the docs map; conventions live in `AGENTS.md` |
| Contributor docs | `docs/*.md`, `docs/acquisition/` | contributors | `docs/plans/` and `docs/superpowers/` are **historical by declaration** — never flag them as stale; flag only present-tense docs that cite them as current |
| Glossary | `docs/GLOSSARY.md` | contributors | terms with a precise project meaning; user vocabulary is governed by the `writing-copy` skill |
| Moduledocs | `lib/**/*.ex` | contributors | the preferred home for module-internal contracts |
| Decision records | `decisions/architecture/` (ADR-NNN), `decisions/user-interface/` (UIDR-NNN), `decisions/README.md` index | contributors | numbered independently; gaps are deliberate retirements |
| Campaigns | `campaigns/*.md` | contributors | rollout state for multi-session work ([ADR-042]); must reconcile with `git log` |
| Skills | `.claude/skills/*/SKILL.md`, `.claude/commands/*.md` | AI agents | loaded before work; stale content here silently misdirects every session |
| Specs | `specs/` | protocol consumers | data format and image caching |
| End-user docs | `README.md`, `docs-site/index.html`, `../media-centaur.wiki/*.md` | users | the wiki is a sibling git repo; `docs/getting-started.md` and `docs/installation.md` are pointer stubs to it; `scripts/sync-wiki-docs` copies pages whose canonical source is in this repo (e.g. `docs/social-protocol.md`) |

Read `CLAUDE.md` first: it states which docs are maintained, the wiki-sync rule, and
the moduledoc-versus-ADR placement test.

---

## Analysis Passes

### Pass 1 — Structural accuracy

- **Paths and modules:** every path, module, mix task, script, and skill named in a
  doc exists (glob/grep to verify). Every route claimed exists in `router.ex`.
- **Configuration:** `docs/configuration.md` and `defaults/media-centaur.toml` must
  agree with `MediaCentaur.Settings.Config` (its moduledoc is the contract). The TOML
  carries only bootstrap keys (`database_path`, `port`, `media_dirs` seed) and every
  bootstrap key must appear in the file, commented where the default is right.
  Runtime preferences are Settings-database entries; docs that describe them as TOML
  keys are wrong. The wiki's `Configuration-File.md` and `Settings-Reference.md` must
  match.
- **Data model:** `docs/library.md` entity and file-tracking descriptions versus the
  schemas actually present in `lib/media_centaur/library/` (list the directory; do
  not assume a fixed set).
- **Architecture claims:** `docs/architecture.md` bounded contexts, PubSub topics,
  and supervision tree versus `ls lib/media_centaur/`, `MediaCentaur.Topics`, the
  `use Boundary` declarations, and `application.ex`.
- **Build, run, ship:** commands in `CLAUDE.md`, `README.md`, and the wiki
  (`mix setup`, `mix precommit`, config overrides, `scripts/ship`, the installer
  one-liner, Settings → Update now) match the scripts and mix aliases.
- **Toolchain:** stated Elixir/OTP minimums match `mix.exs` and the CI/release
  workflows.

### Pass 2 — Freshness

- References to removed files, modules, dependencies, settings, routes, or UI
  surfaces (check merged/renamed pages: Upcoming and Downloads became `/incoming`;
  the dashboard became `/status`; Library zones changed more than once).
- Present-tense text describing behaviour that `git log` shows was replaced.
- Campaign files whose Status or Next steps disagree with the code and history
  (the reconciliation rule in `CLAUDE.md`).
- Decision records still cited as current after being superseded, and the
  `decisions/README.md` index versus the files on disk.
- Skills that name components, files, tables, or pages that no longer exist
  (the `user-interface` skill's page table and UIDR table are frequent drift points).
- Marketing screenshots are **accepted stale** — do not flag them.

### Pass 3 — Placement and duplication

- Content in the wrong surface for its audience: contributor mechanics in the
  README or wiki; user how-tos in `docs/`; module-internal contracts in an ADR
  instead of a moduledoc; repository-wide decisions in a moduledoc instead of an ADR.
- The same fact maintained in two places (CLAUDE.md versus AGENTS.md versus a skill
  versus a doc) where one should point at the other.
- Prose rules that should be a Credo check (`credo_checks/`) — the house preference
  is code-as-spec.

### Pass 4 — Vocabulary and clarity

- Terms used without a `docs/GLOSSARY.md` entry; two names for one concept; coined
  or metaphorical terms where an industry term exists.
- User-facing surfaces (README, wiki, docs-site, changelog) using code vocabulary:
  "entity" instead of "entry", "release" outside acquisition, internal component
  names, or the banned word "floor".
- Sections that assume context not given anywhere; verbose sections that could be
  materially shorter.

### Pass 5 — Cross-reference integrity

- Every relative markdown link resolves (docs, decisions, campaigns, skills, wiki).
- ADR/UIDR citations use the right prefix and number (`ADR-012` and `UIDR-012` are
  different documents) and point at files that exist.
- Wiki pages that `CLAUDE.md` says must be updated with a feature (Settings
  Reference, Configuration File, Keyboard and Gamepad, Troubleshooting, FAQ, the
  Using pages) versus what shipped in `CHANGELOG.md` since the last wiki commit.
- `docs-site/index.html` claims versus the current feature set.

---

## Output Format

Number findings **D1, D2, …** and group by pass. For each:

1. **Document** — the file with the issue
2. **Source** — the source file(s) or filesystem evidence
3. **Issue** — one sentence
4. **Evidence** — the doc text and what the source actually shows
5. **Suggested fix** — concrete and minimal

End with a **summary**: findings per pass, the top 5 highest-impact fixes, and a
one-paragraph documentation health assessment.

## Rules

- **Analysis only.** Do not modify files. Output goes to the chat.
- **Evidence, not speculation.** Only flag discrepancies you can prove.
- **Cite every finding** with both the doc and the contradicting source.
- **No unearned praise.** One sentence for a clean area.
- **Scope to arguments.**
