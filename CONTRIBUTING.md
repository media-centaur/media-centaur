# Contributing to Media Centarr

Thanks for your interest. This is a small project with a specific scope (see [Non-Goals](README.md#non-goals) in the README) — contributions that fit that scope are very welcome.

## Ways to contribute

- **Bug reports** — open a [GitHub issue](https://github.com/media-centarr/media-centarr/issues) with repro steps, what you expected, what happened, and relevant logs (the in-app `/console` drawer captures thinking logs; press `` ` `` to open it).
- **Feature requests** — open an issue to discuss first. If it lands in the [Non-Goals](README.md#non-goals) list, I'll almost certainly close it — that's not personal, just scope discipline.
- **Download-client drivers** — adding support for Transmission, Deluge, SABnzbd, NZBGet, etc. is contained work with a clear `@behaviour`. See [Adding a download-client driver](README.md#adding-a-download-client-driver) for the contract.
- **Parser rules** — the `lib/media_centarr/parser.ex` module matches filename patterns to media metadata. If a filename you own isn't being parsed correctly, a failing test case (with the real path) is a great contribution.
- **Pull requests** — for anything non-trivial, open an issue first so we agree on the approach before you spend time.

## Development setup

```bash
git clone https://github.com/media-centarr/media-centarr.git
cd media-centarr
mix setup          # install deps, create DB, run migrations, build assets
mix phx.server     # start dev server at http://localhost:4001
```

Requirements: Elixir 1.15+, Erlang/OTP 26+, SQLite3, mpv, inotify-tools. See [README.md#requirements](README.md#requirements) for distro-specific install commands.

## Running tests

```bash
mix test           # run the test suite
mix precommit      # full pre-commit: compile (warnings-as-errors), format, credo --strict, sobelow, deps.audit, test
```

JavaScript tests for the input system run with **bun** (not vitest or npx):

```bash
bun test assets/js/input/
```

## Expectations for pull requests

- **Test-first.** Write the test before the implementation, especially for parser rules, pipeline stages, and LiveView logic. The test is the executable specification.
- **Zero warnings.** Application code and tests must compile and run with zero warnings. `mix precommit` enforces this.
- **No flaky tests.** Every test must pass deterministically. A flaky test is a bug — diagnose and fix, never retry or skip.
- **Keep it focused.** One PR = one change. Refactors that are strictly necessary for the change are fine; opportunistic cleanup in unrelated files is not.
- **Conventional commits.** Use `feat:`, `fix:`, `refactor:`, `docs:`, `test:` prefixes. Concise, high-level messages.

## Internal contributor docs

- [`AGENTS.md`](AGENTS.md) — Elixir/Phoenix/LiveView/Ecto conventions specific to this codebase.
- [`CLAUDE.md`](CLAUDE.md) — architecture principles, bounded contexts, testing strategy, and Claude-Code-specific notes.
- [`decisions/`](decisions/) — MADR-format architecture decision records.
- [`.claude/skills/`](.claude/skills/) — task-specific skills for AI-assisted development.

These files target people (or agents) working *on* the codebase. Users only need the README.

## Code of conduct

Be decent. That's it.
