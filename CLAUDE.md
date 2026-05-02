> **Internal contributor guide.** High-level orientation for working *on* the codebase (human or AI). End users: see [README.md](README.md).
>
> Read [`AGENTS.md`](AGENTS.md) for Elixir/Phoenix/LiveView/Ecto/CSS/JS conventions. Read [`docs/architecture.md`](docs/architecture.md) for the architectural deep-dive (bounded contexts, PubSub topics, supervision tree, key principles).

## Skills-First Development

**Always invoke the appropriate thinking skill BEFORE exploring code or writing implementation.** Skills contain paradigm-shifting insights that guide what patterns to look for and what anti-patterns to avoid.

| Area | Skill |
|------|-------|
| General Elixir implementation, refactoring, architecture | `elixir-thinking` |
| LiveView, PubSub, components, mount | `phoenix-thinking` |
| Ecto, schemas, changesets, contexts, migrations | `ecto-thinking` |
| GenServer, Supervisor, Task, ETS, concurrency | `otp-thinking` |
| Oban, background jobs, workflows, scheduling | `oban-thinking` |
| Broadway pipeline, producers, processors, batchers | `broadway` |
| Phoenix web layer, controllers, views, routing | `phoenix-framework` |
| Keyboard/gamepad nav, focus context, nav graphs, page behaviors | `input-system` |
| **ANY implementation** — features, bug fixes, refactors (test-first is mandatory) | `automated-testing` |
| General coding standards, naming, structure | `coding-guidelines` |
| Production debugging, service health, runtime logs | `troubleshoot` |
| UI work — components, CSS, styling, layout, modals, cards, themes | `user-interface` |
| Adding/changing a function component or writing a story | `storybook` |
| mpv Lua scripts, overlays, key bindings, playback UI | `mpv-extensions` |

Invoke the skill **first**, then explore the codebase, then write code.

# Media Centarr — Backend

Phoenix/Elixir application managing the Media Centarr media library. **Write-side** of the system: it creates and edits entity records, scrapes metadata from external APIs, and downloads artwork. The LiveView UI provides library browsing, review, playback control, and administration.

Map of contributor docs:

| Topic | File |
|---|---|
| Architecture, bounded contexts, PubSub topics, key principles | [`docs/architecture.md`](docs/architecture.md) |
| Pipeline (Broadway: discovery, import, image) | [`docs/pipeline.md`](docs/pipeline.md) |
| Library data model (type-specific schemas, file tracking, deletion) | [`docs/library.md`](docs/library.md) |
| Other domains | [`docs/watcher.md`](docs/watcher.md), [`docs/tmdb.md`](docs/tmdb.md), [`docs/playback.md`](docs/playback.md), [`docs/input-system.md`](docs/input-system.md), [`docs/mpv.md`](docs/mpv.md) |
| Component catalog (Phoenix Storybook, dev-only) | [`docs/storybook.md`](docs/storybook.md) |
| Protocol specs (data format, image caching) | [`specs/`](specs/) |
| Decision records | [`decisions/`](decisions/) |

## Version Control (Jujutsu)

All repositories use **JJ (Jujutsu)** — never use raw `git` commands.

- After completing a feature: `jj describe -m "type: short description"` (conventional commits: `feat:`, `fix:`, `refactor:`)
- Amend the existing change for follow-up fixes (if not yet pushed)
- Start unrelated features with `jj new`

## Build & Run

```bash
mix setup              # install deps, create DB, run migrations, build assets
mix phx.server         # start dev server (http://localhost:1080)
mix test               # run tests
mix precommit          # compile + format + credo + boundaries + deps.audit + sobelow + test
mix seed.review        # populate review UI test cases (one-shot, idempotent)
```

> Use `MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8` to parallelize compilation.

**Run `mix precommit` before finishing any change** and fix everything it reports. **Zero warnings policy** — every warning is a bug, including unused vars/aliases and log output indicating misconfigured stubs.

### Config overrides (isolated dev/demo instances)

`MEDIA_CENTARR_CONFIG_OVERRIDE` points at a TOML file that fully replaces the default (`~/.config/media-centarr/media-centarr.toml`). It carries its own port, database path, and watch dirs, so a misconfigured command can't clobber the real DB. Single mechanism for running dev + demo side-by-side with the installed release.

| TOML | Purpose | Binds |
|------|---------|-------|
| `defaults/media-centarr-showcase.toml` | Demo instance, public-domain media | :4003 |

```bash
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix ecto.create
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix ecto.migrate
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix seed.showcase
MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-showcase.toml mix phx.server
scripts/screenshot-tour    # capture marketing screenshots (manual only)
```

`mix seed.showcase` refuses to run without `MEDIA_CENTARR_CONFIG_OVERRIDE` — that guarantee is why the earlier profile mechanism collapsed into this single lever.

### Dev service (optional persistent server)

```bash
scripts/install-dev                              # install systemd user service
systemctl --user start media-centarr-dev         # start
journalctl --user -u media-centarr-dev -f        # logs
iex --name repl@127.0.0.1 --remsh media_centarr_dev@127.0.0.1   # remote REPL (Ctrl+\ to detach)
```

### Release + deployment

Shipping is tagging — nothing installed by hand:

1. `scripts/preflight` — pre-flight build at `_build/prod/rel/media_centarr/`. Verifies the build is clean. Does NOT install.
2. `/ship <major|minor|patch>` — runs upgrade-safety checks, drafts the user-facing CHANGELOG entry, bumps `mix.exs`, commits, tags `v<version>`, pushes. The tag triggers `.github/workflows/release.yml`.
3. **Local production catches up via Settings → *Update now***, same path as any end user. There is no `scripts/install`.

First-time install on a new machine uses the public installer (`curl … install.sh | sh`); every subsequent update uses the in-app button.

## Static Analysis

`mix precommit` runs format (with the **Quokka** plugin auto-rewriting many Credo violations), `credo --strict`, JS dependency-cruiser via `mix boundaries`, `deps.audit`, `sobelow`, and `test`. Tool configs: `.credo.exs`, `.sobelow-conf`, `.formatter.exs`, `.dependency-cruiser.cjs`. Each tuned/disabled check carries a comment explaining why.

**Custom Credo checks** live in `credo_checks/` — each `.ex` file's moduledoc explains its rule. **Boundary** is enforced as a Mix compiler — read each context's `use Boundary, deps: [...]` declaration as the canonical inter-context dependency list (see [ADR-029](decisions/architecture/2026-03-26-029-data-decoupling.md)).

When you add a new house rule that fits a static check, prefer adding a custom Credo check over prose in this file — code-as-spec keeps it enforced.

## Observability for Debugging

Every system must be designed so Claude Code can get diagnostic feedback at runtime. Tests passing while the app is broken means the observability gap is the first problem to solve.

- **Elixir/OTP:** use `MediaCentarr.Log` (component-tagged macros). Captured into the in-memory ring buffer (`MediaCentarr.Console.Buffer`) and viewable via the Guake-style Console drawer (`` ` ``) or `/console`. See `MediaCentarr.Log` and `MediaCentarr.Console` moduledocs. Production access via the `troubleshoot` skill.
- **JavaScript:** the input system has `debug()` from `assets/js/input/core/debug.js` — toggle `window.__inputDebug = true`, read via Chrome DevTools MCP. Pattern: toggle-gated function, never bare `console.log`. See the `input-system` skill.
- **New systems:** if it's not obvious how to surface runtime diagnostics back to Claude Code, stop and consult the user before fixing. The feedback loop is a prerequisite — don't guess.

## Testing

Load the `automated-testing` skill before writing any test or implementation. It covers test-first workflow, factories, TMDB/image stubs, page smoke tests, JS bun tests, Playwright E2E, and policies (zero flakes, [ADR-027](decisions/architecture/2026-03-07-027-regression-tests-append-only.md) regression-tests-are-append-only).

### Test and example content (no real show titles)

Anything we author into the codebase — test queries, fixture titles, `@doc`/`@moduledoc` examples, comment examples, seed data — must use **generic placeholders** (`Sample Show`, `Movie A`, `Sample.Show.S01E01.1080p.WEB-DL.mkv`) or PD/CC titles. Real titles drift into screenshots, demos, and grep results. Exempt: `test/media_centarr/parser_test.exs` (real filenames the parser has been observed to handle, append-only per ADR-027) and production runtime data.

## Public-facing documentation

End-user docs live across three surfaces:

| Surface | Location | Audience |
|---|---|---|
| README | `README.md` | GitHub visitors |
| GitHub Pages | `docs-site/index.html` (auto-deployed via `.github/workflows/pages.yml`) | Marketing landing |
| GitHub Wiki | `../media-centarr.wiki/` (jj-colocated, sibling repo) | Fleshed-out user docs |

**Internal contributor docs** (`docs/`) stay in this repo. User-facing pages under `docs/` are pointer stubs to the wiki.

**Keep the wiki in sync with user-visible changes** — same unit of work as the code. New setting → `Settings-Reference.md`; new config key → `Configuration-File.md`; keybinding change → `Keyboard-and-Gamepad.md`; new UI flow → corresponding *Using Media Centarr* page; new download driver → `Prowlarr-Integration.md` / `Download-Clients.md`; new failure mode → `Troubleshooting.md`; non-obvious behaviour decision → `FAQ.md`.

```sh
cd ~/src/media-centarr/media-centarr.wiki
# edit the relevant page(s)
jj describe -m "wiki: <short summary>"
jj bookmark set master -r @
jj git push
```

If a feature is WIP and the user-visible shape hasn't settled, note the wiki update as a follow-up — but don't mark the feature done without it.

`docs-site/index.html` auto-deploys on any push to `main` that touches `docs-site/**`.

## Decision Records

Decision records live in `decisions/` ([MADR 4.0](https://adr.github.io/madr/)). Filename convention: `YYYY-MM-DD-NNN-short-title.md`, numbered per category (`architecture/`, `user-interface/`). See `decisions/README.md` for the index.

**Prefer moduledocs for technical concepts.** Document module-internal contracts (syntax, parsing behavior, struct shape, format details) in the relevant `@moduledoc`. Reserve ADRs for decisions that apply repository-wide or supersede an existing ADR. Test: would a contributor want to read this looking at the module, or while browsing `decisions/`? Former → moduledoc; latter → ADR.

## Defaults

`defaults/` contains git-tracked starter configs — seed values shipped with the repo, **never overwritten at runtime**. Keep `defaults/media-centarr.toml` complete: every key recognised by `MediaCentarr.Config` must have an entry with a logical default and a comment. The file must always be valid TOML.

<!-- usage-rules-start -->
<!-- usage_rules-start -->
## usage_rules usage
_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

[usage_rules usage rules](deps/usage_rules/usage-rules.md)
<!-- usage_rules-end -->
<!-- usage_rules:elixir-start -->
## usage_rules:elixir usage
[usage_rules:elixir usage rules](deps/usage_rules/usage-rules/elixir.md)
<!-- usage_rules:elixir-end -->
<!-- usage_rules-start -->
## usage_rules usage
_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

[usage_rules usage rules](deps/usage_rules/usage-rules.md)
<!-- usage_rules-end -->
<!-- usage_rules:otp-start -->
## usage_rules:otp usage
[usage_rules:otp usage rules](deps/usage_rules/usage-rules/otp.md)
<!-- usage_rules:otp-end -->
<!-- ex_code_view-start -->
## ex_code_view usage
_⚠️ ALPHA — expect rough edges. Interactive code visualizations for Elixir projects — 3D software city and Ecto ERD, rendered as self-contained HTML._

[ex_code_view usage rules](deps/ex_code_view/usage-rules.md)
<!-- ex_code_view-end -->
<!-- ex_code_view:schema-extractors-start -->
## ex_code_view:schema-extractors usage
[ex_code_view:schema-extractors usage rules](deps/ex_code_view/usage-rules/schema-extractors.md)
<!-- ex_code_view:schema-extractors-end -->
<!-- ex_code_view:viewer-js-start -->
## ex_code_view:viewer-js usage
[ex_code_view:viewer-js usage rules](deps/ex_code_view/usage-rules/viewer-js.md)
<!-- ex_code_view:viewer-js-end -->
<!-- ex_code_view:views-start -->
## ex_code_view:views usage
[ex_code_view:views usage rules](deps/ex_code_view/usage-rules/views.md)
<!-- ex_code_view:views-end -->
<!-- usage-rules-end -->
