---
description: Commit and push git changes — and optionally tag a release with a user-facing changelog and upgrade-safety check
allowed-tools: Bash, AskUserQuestion, Read, Write, Edit
---

You are shipping Media Centaur. All release mechanics are deterministic and live in `scripts/ship` (run it with no args for full usage) — your job is only the parts that need judgment: commit messages, the user-facing release notes, and reviewing any safety-check hunks the script flags.

> This skill supersedes the global `/ship` (`~/.claude/commands/ship.md`) when invoked from the Media Centaur repo. Do not pause for mid-flow confirmations (changelog approval, "ship now?") — the user has standing instructions to proceed; halt only on safety-check failures.

## Arguments

- `/ship` — plain ship. Commit working change(s), push `main`. No tag.
- `/ship major|minor|patch` — ship AND release: bump version, changelog, upgrade-safety gate, tag. Anything else: invalid, stop.

## Plain ship (no version argument)

1. If CWD has `.git/`, operate on it alone; otherwise on each immediate subdirectory with `.git/` (0 repos → stop; >8 → ask if in the right directory).
2. Per repo: skip if clean with no unpushed commits. Halt if behind `origin/main` ("pull/rebase first"). If the tree is dirty, read the diff and commit with conventional-prefix messages (`feat:`, `fix:`, `refactor:`, …) — split distinct work into separate commits, stage by named paths (never blind `git add -A`).
3. `git push origin main`. Never force-push. A failed push reports and continues to the next repo.

## Release ship (`/ship major|minor|patch`)

1. **Commit pending work** as in plain ship (don't push yet — the release push carries it).
2. **`scripts/ship prepare <level>`** — prints `NEXT_VERSION`, `NOTES_FILE`, and the commits since the last tag. Read-only.
3. **Start the safety gate in the background**: `scripts/ship check` (runs `scripts/preflight` — takes minutes). Write the release notes while it builds.
4. **Write the notes** to the `NOTES_FILE` path from step 2 — body only, no version header (the script adds `## v<version> — <date>`). This is the one creative step; voice rules below. Do not ask for approval — best-effort and proceed.
5. **When the gate passes**: `scripts/ship release <level> --notes <NOTES_FILE>`. This inserts the changelog entry, commits, bumps `mix.exs`, commits, pushes `main`, tags from `mix.exs`, pushes the tag.
6. **`scripts/ship verify`** — polls the GitHub release until both platform tarballs + SHA256SUMS are present (fails fast if the workflow run failed). Report the result.
7. **Wiki sync** — if the release contains user-visible changes not yet reflected in `../media-centaur.wiki/`, update the relevant pages and push the wiki too.

### If `scripts/ship check` fails

Print the failure list to the user verbatim. Two of the checks flag diffs for *judgment*, not as hard failures:

- **Settings.Entry / `update.*` keys touched** — read the printed hunks. If no `update.*` key the updater reads is renamed/dropped, re-run with `--allow-settings-change`. Otherwise halt: in-app update hydration would break on end users' machines.
- **Installer script touched** (`rel/platforms/*/bin/media-centaur-install`) — the PREVIOUS release's updater executes this file. If the argv contract (default install path, `--update` flag) is intact, re-run with `--allow-installer-change`. Otherwise halt.

Everything else (pending migrations, preflight build failure, malformed changelog) must be fixed, not overridden. A broken upgrade path is worse than a delayed release.

## Release-notes voice

Media Centaur end users are media-center users, not engineers. The notes land on the GitHub release page AND in the in-app updater (`Changelog.for_version/1` reads `CHANGELOG.md`).

- **Translate jargon.** `fix(self_update): handle 404 on stale tag` → `Fixed an issue where the app could show a stale update warning when a release was removed.`
- **Drop contributor-only items.** Refactors, test-only changes, CI tweaks, dependency bumps with no user impact → omit unless behavior changes.
- **Group under `### New` / `### Improved` / `### Fixed`** — skip empty sections. Lead each bullet with a bold plain-language summary (see existing CHANGELOG.md entries for the house style).
- **Voice:** present tense, active, second person where natural. No emoji, no hype.
- **Mention migrations** when the release ships one (safe-migration policy).

## Important

- NEVER force-push `main`; never `git add -A` blindly.
- Create NEW commits rather than amending already-pushed ones.
- `mix precommit` green is a prerequisite for a release ship — `scripts/ship check` gates the upgrade path, not code quality. If precommit hasn't run this session, run it first.
- The tag follows `mix.exs` exactly (the release workflow rejects a mismatch); `scripts/ship release` owns that — never tag by hand.
