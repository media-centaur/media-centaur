---
description: Commit and push git changes — and optionally tag a release with a user-facing changelog and upgrade-safety check
allowed-tools: Bash, AskUserQuestion, Read, Write, Edit
---

You are shipping one or more git repos for Media Centaur, and optionally tagging a release the end-user updater will see. Media Centaur end users are media-center users — not engineers. Release notes they see must be written for them.

> This skill supersedes the global `/ship` (`~/.claude/commands/ship.md`) when invoked from the Media Centaur repo. Both skills share the same arg modes (`/ship` / `patch` / `minor` / `major`), the same halt-on-failure discipline, the same end-user changelog voice, and the same tag flow. This local version adds the Media-Centaur-specific safety checks (pending migrations, `scripts/preflight`, Settings.Entry schema compatibility, updater-contract stability). When updating either skill, update the other to keep the concepts aligned.

## Arguments

Invocation modes:

- `/ship` — plain ship. Commit working change(s), push `main`. No tag.
- `/ship major` — ship AND bump **major** version in `mix.exs` (X.y.z → (X+1).0.0), generate a user-facing changelog, validate upgrade safety, tag, push tag.
- `/ship minor` — ship AND bump **minor** version (x.Y.z → x.(Y+1).0), same tag flow.
- `/ship patch` — ship AND bump **patch** version (x.y.Z → x.y.(Z+1)), same tag flow.

If the argument is anything else, treat it as invalid and stop with a clear message.

## Step 1: Discover repos

Determine which repos to operate on:

```bash
if [ -d ".git" ]; then
  echo "SINGLE:$(pwd)"
else
  for d in */; do
    [ -d "$d/.git" ] && echo "REPO:$(cd "$d" && pwd)"
  done
fi
```

- If CWD has `.git/` → operate on CWD alone
- Otherwise → immediate subdirectories containing `.git/`
- 0 repos → tell the user "No git repos found in this directory" and stop
- More than 8 repos → tell the user "Found N repos — are you in the right directory?" and stop

## Step 2: Scan each repo

For each discovered repo, run (in parallel where possible):

```bash
cd <repo_path>
git rev-parse --abbrev-ref HEAD                  # current branch
git status --porcelain                           # uncommitted changes
git log --oneline origin/main..HEAD              # unpushed commits
git log --oneline HEAD..origin/main 2>/dev/null  # behind upstream?
```

Classify:

- **has changes** — non-empty `git status --porcelain` OR non-empty unpushed-commit list
- **skip** — clean working tree AND no unpushed commits

Halt conditions per repo:

- Current branch is not `main` → note the deviation; if version-bump mode, halt.
- Repo is behind `origin/main` → halt with "Pull or rebase first; refusing to push from a stale tip."

## Step 3: Plan and confirm

Show a summary table of all repos with their status. If a version bump was requested, also show:

- Current version (from `mix.exs`)
- Target version after bump
- Which repo will be tagged (the Media Centaur app — the one containing `mix.exs`)

Use `AskUserQuestion` to get explicit confirmation before any mutations. If the user declines, stop.

If every repo would be skipped AND no tag is requested, tell the user there's nothing to ship and stop.

## Step 4: Execute the ship (per repo)

Only after confirmation. For each repo with changes, sequentially:

### 4a: Commit working changes (if any)

If `git status --porcelain` was non-empty, the working tree has uncommitted changes. Commit them BEFORE pushing:

- Run `git diff` and `git diff --cached` to read the changes
- Write a concise commit message: imperative verb phrase, sentence case, no trailing period, under 72 chars
- Use conventional prefixes when they fit: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`
- If the diff contains multiple DISTINCT types of work, split into separate commits with `git add <files>` + `git commit -m "..."` per logical group — don't bundle unrelated changes

```bash
cd <repo_path>
git add <files>                            # specific paths, NEVER `git add -A` blindly
git commit -m "<message>"
```

Be careful with `git add -A` / `git add .` — they can stage secrets (`.env`), large binaries, or files you didn't intend to ship. Prefer named paths.

### 4b: Push

```bash
cd <repo_path>
git push origin main
```

Never force-push `main`. If the push is rejected as non-fast-forward, the repo is behind upstream — halt with that message and ask the user to pull/rebase. If a push fails, report the error and continue to the next repo. Do not abort the entire operation.

## Step 5: Version bump + tag (only when mode is major|minor|patch)

Run these in the Media Centaur app repo (the one with `mix.exs`). If shipping multiple repos, the tag applies to the main app repo only. These steps happen AFTER the working-copy ship in Step 4 has been pushed, so `main` already includes the feature commits being released.

### 5a: Validate safe upgrade path

**Before** bumping anything, confirm the release will be safely consumable by the in-app updater (`MediaCentaur.SelfUpdate`). If any check fails, **halt** and prompt the engineer using Claude Code to resolve before continuing. Checks:

1. **No pending migrations.** Run `mix ecto.migrations 2>&1 | grep -v "up"` in the app repo. Any line showing a migration in state other than `up` → halt with the offending migration listed.
2. **Tests green.** Run `mix test` (fast subset acceptable if the full suite was just run). Any failure → halt with the failing test names.
3. **Full release workflow builds.** Run `scripts/preflight` and confirm it produces `_build/prod/rel/media_centaur/` containing `bin/media-centaur-install` and `share/systemd/media-centaur.service`. Missing files or build failure → halt with details. (`scripts/preflight` never installs anything.)
4. **Settings.Entry schema compatibility.** Check if the diff from the previous tag touches `lib/media_centaur/settings/entry.ex` or migrations under `priv/repo/migrations/` in a way that renames or drops keys under the `update.*` namespace (`update.last_check_at`, `update.latest_known`, or anything the updater reads). Any such change → halt with a note that in-app hydration would break.
5. **Updater contract intact.** Check if the diff from the previous tag touches `rel/overlays/bin/media-centaur-install` in a backward-incompatible way (removing `--update` flag, changing argv contract of the default install path). Any such change → halt with the offending diff hunks.
6. **Changelog present.** Check that `CHANGELOG.md` (or `docs/changelog.md`) exists and has an entry header matching the target version. If missing, it will be generated in 5b — do NOT halt for this.

Halt format: print `UPGRADE SAFETY CHECK FAILED` followed by a bulleted list of failures, then tell the engineer exactly which files to look at and what decision they need to make. Use `AskUserQuestion` to ask whether to abort or continue anyway (override is explicit, never silent).

### 5b: Draft a user-facing changelog

Media Centaur end users are media-center users. Technical commit messages are useless to them. Generate release notes they can actually read.

1. Collect commits since the previous tag:
   ```bash
   last_tag=$(git tag --sort=-v:refname | head -n1)
   git log --pretty=format:"- %s" "${last_tag}..HEAD"
   ```
2. For each commit, rewrite the message in end-user language:
   - **Translate jargon.** `fix(self_update): handle 404 on stale tag` → `Fixed an issue where the app could show a stale update warning when a release was removed.`
   - **Drop contributor-only items.** Refactors, test-only changes, CI tweaks, dependency bumps with no user impact, internal boundary reshuffles → omit from the changelog unless they affect behavior.
   - **Group by intent:**
     - **New** — user-visible features
     - **Improved** — UX, performance, or quality improvements users will notice
     - **Fixed** — bugs with user impact
   - **Voice:** present tense, active, second person where natural ("You can now …", "The Library page loads faster …"). No emoji, no hype.
   - **Skip empty sections.** A release with no "New" doesn't need the heading.
3. Present the draft changelog via `AskUserQuestion` with two options: "Use as-is" or "Edit before tagging". If the engineer picks "Edit", write the draft to a scratch file (e.g., `/tmp/release-notes-<version>.md`), tell the engineer to edit it, and ask them to confirm when done. Read the edited file back in.
4. Prepend the final notes to `CHANGELOG.md` under a `## <version> — <YYYY-MM-DD>` header. If `CHANGELOG.md` doesn't exist, create it with a brief intro line.
5. Commit the changelog update as its own commit:
   ```bash
   git add CHANGELOG.md
   git commit -m "docs: changelog for v<version>"
   ```

### 5c: Bump version in mix.exs

Read `mix.exs`, replace the `version: "x.y.z"` line with the new version. Commit as its own commit:

```bash
git add mix.exs
git commit -m "chore: bump version to <version>"
```

### 5d: Push and tag

Push the changelog + version-bump commits to `main`, then read the version from the bumped `mix.exs` — the tag follows that value exactly. Pre-computed variables are not the source of truth; `mix.exs` is.

```bash
git push origin main

version=$(grep -E '^\s*version:' mix.exs | head -1 | sed 's/.*"\(.*\)".*/\1/')
git tag "v$version"
git push origin "v$version"
```

The GitHub Actions release workflow at `.github/workflows/release.yml` is triggered by the tag and builds the tarball. The release notes on the GitHub Release page come from the tag body or the workflow — if the workflow supports a release-notes input, pass the changelog contents; otherwise point the engineer at the GitHub release page to paste the notes manually.

Check the GitHub release after a minute with `gh release view "v<version>"` and confirm the tarball + SHA256SUMS are present. Report the result.

## Step 6: Summary

After everything, show a final table:

- Repo name → commit(s) used → push result
- If tagged: target version, upgrade-safety check result, changelog preview location, tag push result, GitHub release status

## Important

- NEVER force-push `main` — only fast-forward pushes from a local tip that's ahead of upstream
- NEVER use `git add -A` / `git add .` blindly — name specific files to avoid staging secrets, large binaries, or unintended changes
- NEVER mutate anything before the user confirms in Step 3
- Create NEW commits rather than amending already-pushed commits
- If the working tree is clean AND there are no unpushed commits, skip that repo — don't create empty commits
- Each repo is independent — a failure in one does not block the others
- When operating on multiple repos, always `cd` to the repo's absolute path before running git commands
- **Halt on upgrade-safety failures.** Don't silently override. The in-app updater runs on end users' machines — a broken upgrade path is worse than a delayed release.
- **End-user voice.** Changelog entries go in front of media-center users. If a line sounds like a commit message, rewrite it until it doesn't.
