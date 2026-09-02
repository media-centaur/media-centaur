> **Internal contributor guide.** High-level orientation for working *on* the codebase (human or AI). End users: see [README.md](README.md).
>
> Read [`AGENTS.md`](AGENTS.md) for Elixir/Phoenix/LiveView/Ecto/CSS/JS conventions. Read [`docs/architecture.md`](docs/architecture.md) for the architectural deep-dive (bounded contexts, PubSub topics, supervision tree, key principles).

Phoenix Storybook in this repo pins **component contracts** (typed attrs + their state matrix) and is enforced by `mix precommit`: every function component under `lib/media_centaur_web/components/**` must have a story (Credo check MC0009) and every story must compile + render in `storybook_compile_test` / `storybook_render_test`. When you change a component's attrs, default state, or variation matrix, update the story in the same change — the precommit will tell you if you didn't.

Stories are a **typed coupling check** and a **state-matrix forcing function**, not a guarantee of visual correctness in the app and not a substitute for integration testing. They render in isolation with attribute fixtures; they do not exercise click handlers, PubSub, or LiveView state machines. Interaction bugs (event → assign update → re-render) live in `*_live_test.exs`, not in stories. Don't oversell the storybook to yourself: if a regression is in the wiring rather than the render, no story will catch it.

You are free to design new visual surfaces directly in storybook (the isolated render is genuinely useful for iterating on a card or panel without booting the whole page), but you are not required to. Designing against the running app is fine as long as the story lands in the same commit and the variations cover the states the app exercises.

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

# Media Centaur — Backend

Phoenix/Elixir application managing the Media Centaur media library. **Write-side** of the system: it creates and edits entity records, scrapes metadata from external APIs, and downloads artwork. The LiveView UI provides library browsing, review, playback control, and administration.

Map of contributor docs:

| Topic | File |
|---|---|
| Architecture, bounded contexts, PubSub topics, key principles | [`docs/architecture.md`](docs/architecture.md) |
| Pipeline (Broadway: discovery, import, image) | [`docs/pipeline.md`](docs/pipeline.md) |
| Library data model (type-specific schemas, file tracking, deletion) | [`docs/library.md`](docs/library.md) |
| Download clients (two-slot model, prowlarr-stack bootstrap contract, add-a-client checklist) | [`docs/download-clients.md`](docs/download-clients.md) |
| Other domains | [`docs/watcher.md`](docs/watcher.md), [`docs/tmdb.md`](docs/tmdb.md), [`docs/playback.md`](docs/playback.md), [`docs/friends.md`](docs/friends.md), [`docs/input-system.md`](docs/input-system.md), [`docs/mpv.md`](docs/mpv.md) |
| Component catalog (Phoenix Storybook, dev-only) | [`docs/storybook.md`](docs/storybook.md) |
| Configuration keys and precedence | [`docs/configuration.md`](docs/configuration.md) |
| Prowlarr / acquisition setup | [`docs/acquisition/`](docs/acquisition/) |
| Protocol specs (data format, image caching) | [`specs/`](specs/) |
| Decision records (ADR-NNN + UIDR-NNN, indexed) | [`decisions/README.md`](decisions/README.md) |

Historical design specs and implementation plans live under [`docs/plans/`](docs/plans/) and [`docs/superpowers/`](docs/superpowers/). They record what was decided at the time and are **not** maintained against the current code — read them for rationale, not for present-tense truth. `docs/getting-started.md` and `docs/installation.md` are pointer stubs to the wiki.

## Version Control (Git)

This repository uses **git** directly.

- After completing a feature: `git commit -m "type: short description"` (conventional commits: `feat:`, `fix:`, `refactor:`)
- For follow-up fixes before pushing, `git commit --amend` is acceptable; after pushing, create a new commit.
- Start unrelated features on a new branch with `git switch -c <branch-name>`.

## Build & Run

```bash
mix setup              # install deps, create DB, run migrations, build assets
mix phx.server         # start dev server (http://localhost:2160 via the dev TOML; bare fallback 1080)
mix test               # run tests
mix precommit          # compile + format + credo + boundaries + deps.audit + sobelow + test
mix seed.review        # populate review UI test cases (one-shot, idempotent)
```

> Use `MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8` to parallelize compilation.

**Run `mix precommit` before finishing any change** and fix everything it reports. **Zero warnings policy** — every warning is a bug, including unused vars/aliases and log output indicating misconfigured stubs.

### Config overrides (isolated dev/demo instances)

`MEDIA_CENTAUR_CONFIG_OVERRIDE` points at a TOML file that fully replaces the default (`~/.config/media-centaur/media-centaur.toml`). It carries its own port, database path, and media dirs, so a misconfigured command can't clobber the real DB. Single mechanism for running dev + demo side-by-side with the installed release.

| TOML | Purpose | Binds |
|------|---------|-------|
| `defaults/media-centaur-showcase.toml` | Demo instance, public-domain media | :4003 |

```bash
MEDIA_CENTAUR_CONFIG_OVERRIDE=defaults/media-centaur-showcase.toml mix ecto.create
MEDIA_CENTAUR_CONFIG_OVERRIDE=defaults/media-centaur-showcase.toml mix ecto.migrate
MEDIA_CENTAUR_CONFIG_OVERRIDE=defaults/media-centaur-showcase.toml mix seed.showcase
MEDIA_CENTAUR_CONFIG_OVERRIDE=defaults/media-centaur-showcase.toml mix phx.server
scripts/screenshot-tour    # capture marketing screenshots (manual only)
```

`mix seed.showcase` refuses to run without `MEDIA_CENTAUR_CONFIG_OVERRIDE` — that guarantee is why the earlier profile mechanism collapsed into this single lever.

### Dev service (optional persistent server)

```bash
scripts/install-dev                              # install systemd user service
systemctl --user start media-centaur-dev         # start
journalctl --user -u media-centaur-dev -f        # logs
iex --name repl@127.0.0.1 --remsh media_centaur_dev@127.0.0.1   # remote REPL (Ctrl+\ to detach)
```

### Release + deployment

Shipping is tagging — nothing installed by hand. All release mechanics are deterministic in `scripts/ship` (`prepare` / `check` / `release` / `verify` — run with no args for usage); `scripts/preflight` is the prod build it gates on:

1. `/ship <major|minor|patch>` — commits pending work, runs `scripts/ship prepare` + `check` (upgrade-safety gate incl. preflight), drafts the user-facing CHANGELOG entry (the only non-mechanical step), then `scripts/ship release` bumps `mix.exs`, commits, tags `v<version>` from `mix.exs`, pushes. The tag triggers `.github/workflows/release.yml`; `scripts/ship verify` confirms the published assets.
2. **Local production catches up via Settings → *Update now***, same path as any end user. There is no `scripts/install`.

First-time install on a new machine uses the public installer (`curl … install.sh | sh`); every subsequent update uses the in-app button.

## Static Analysis

`mix precommit` runs format (with the **Quokka** plugin auto-rewriting many Credo violations), `credo --strict`, JS dependency-cruiser via `mix boundaries`, `deps.audit`, `sobelow`, and `test`. Tool configs: `.credo.exs`, `.sobelow-conf`, `.formatter.exs`, `.dependency-cruiser.cjs`. Each tuned/disabled check carries a comment explaining why.

**Custom Credo checks** live in `credo_checks/` — each `.ex` file's moduledoc explains its rule. **Boundary** is enforced as a Mix compiler — read each context's `use Boundary, deps: [...]` declaration as the canonical inter-context dependency list (see [ADR-029](decisions/architecture/2026-03-26-029-data-decoupling.md)).

When you add a new house rule that fits a static check, prefer adding a custom Credo check over prose in this file — code-as-spec keeps it enforced.

## Observability for Debugging

Every system must be designed so Claude Code can get diagnostic feedback at runtime. Tests passing while the app is broken means the observability gap is the first problem to solve.

- **Elixir/OTP:** use `MediaCentaur.Log` (component-tagged macros). Captured into the in-memory ring buffer (`MediaCentaur.Console.Buffer`) and viewable via the Guake-style Console drawer (`` ` ``) or `/console`. See `MediaCentaur.Log` and `MediaCentaur.Console` moduledocs. Production access via the `troubleshoot` skill.
- **JavaScript:** the input system has `debug()` from `assets/js/input/core/debug.js` — toggle `window.__inputDebug = true`, read via Chrome DevTools MCP. Pattern: toggle-gated function, never bare `console.log`. See the `input-system` skill.
- **New systems:** if it's not obvious how to surface runtime diagnostics back to Claude Code, stop and consult the user before fixing. The feedback loop is a prerequisite — don't guess.

## Testing

Load the `automated-testing` skill before writing any test or implementation. It covers test-first workflow, factories, TMDB/image stubs, page smoke tests, JS bun tests, Playwright E2E, and policies (zero flakes, [ADR-027](decisions/architecture/2026-03-07-027-regression-tests-append-only.md) regression-tests-are-append-only).

### Test and example content (no real show titles)

Anything we author into the codebase — test queries, fixture titles, `@doc`/`@moduledoc` examples, comment examples, seed data — must use **generic placeholders** (`Sample Show`, `Movie A`, `Sample.Show.S01E01.1080p.WEB-DL.mkv`) or PD/CC titles. Real titles drift into screenshots, demos, and grep results. Exempt: `test/media_centaur/parser_test.exs` (real filenames the parser has been observed to handle, append-only per ADR-027) and production runtime data.

## Public-facing documentation

End-user docs live across three surfaces:

| Surface | Location | Audience |
|---|---|---|
| README | `README.md` | GitHub visitors |
| GitHub Pages | `docs-site/index.html` (auto-deployed via `.github/workflows/pages.yml`) | Marketing landing |
| GitHub Wiki | `../media-centaur.wiki/` (git, sibling repo) | Fleshed-out user docs |

**Internal contributor docs** (`docs/`) stay in this repo. The two user-facing entry points under `docs/` — `getting-started.md` and `installation.md` — are pointer stubs to the wiki; everything else in `docs/` is written for contributors.

**Keep the wiki in sync with user-visible changes** — same unit of work as the code. New setting → `Settings-Reference.md`; new config key → `Configuration-File.md`; keybinding change → `Keyboard-and-Gamepad.md`; new UI flow → corresponding *Using Media Centaur* page; new download driver → `Prowlarr-Integration.md` / `Download-Clients.md`; new failure mode → `Troubleshooting.md`; non-obvious behaviour decision → `FAQ.md`.

```sh
cd ~/src/media-centaur/media-centaur.wiki
# edit the relevant page(s)
git add -A
git commit -m "wiki: <short summary>"
git push
```

If a feature is WIP and the user-visible shape hasn't settled, note the wiki update as a follow-up — but don't mark the feature done without it.

`docs-site/index.html` auto-deploys on any push to `main` that touches `docs-site/**`.

## Decision Records

Decision records live in `decisions/` ([MADR 4.0](https://adr.github.io/madr/)). Filename convention: `YYYY-MM-DD-NNN-short-title.md`, numbered per category (`architecture/`, `user-interface/`). [`decisions/README.md`](decisions/README.md) indexes every record — regenerate it when you add or retire one.

Architecture records are cited as **ADR-NNN**, user-interface records as **UIDR-NNN**. They number independently, so `ADR-012` and `UIDR-012` are different documents — cite the right prefix. Numbering gaps are deliberate: a record that became fictional, was superseded, or is now enforced by a Credo check gets retired rather than left to mislead.

**Prefer moduledocs for technical concepts.** Document module-internal contracts (syntax, parsing behavior, struct shape, format details) in the relevant `@moduledoc`. Reserve ADRs for decisions that apply repository-wide or supersede an existing ADR. Test: would a contributor want to read this looking at the module, or while browsing `decisions/`? Former → moduledoc; latter → ADR.

## Campaigns

`campaigns/` holds one markdown per long-running, multi-session initiative (3+ sessions, definable end state, resumable context). ADRs capture *decisions*; campaigns capture the *rollout*. See [ADR-042](decisions/architecture/2026-05-10-042-multi-session-campaigns.md) for the full convention and `campaigns/README.md` for the active list.

**Reconciliation rule:** when resuming a campaign, the first action is to read the campaign file, reconcile it against `git log` and the current code, and update Status / Decisions / Next steps **before** writing any new code. Drift makes the file worse than nothing.

## Defaults

`defaults/` contains git-tracked starter configs — seed values shipped with the repo, **never overwritten at runtime**. `defaults/media-centaur.toml` carries **only bootstrap state** — `database_path`, `port`, and the initial `media_dirs` seed (the values the app needs before its database is reachable). Every runtime preference lives in the Settings database and is set in-app; TOML is no longer read for those keys (see the `MediaCentaur.Settings.Config` moduledoc). Keep every bootstrap key present in the file with a comment and a logical default — commented out where the built-in default is right, but always shown, so a user editing the file can see the key's shape without reading the source. The file must always be valid TOML.

`defaults/` also holds `media-centaur-showcase.toml` and `media-centaur-profile.toml` (config overrides, above) plus the `media-centaur*.service` systemd units.

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
<!-- usage_rules:otp-start -->
## usage_rules:otp usage
[usage_rules:otp usage rules](deps/usage_rules/usage-rules/otp.md)
<!-- usage_rules:otp-end -->
<!-- usage-rules-end -->
