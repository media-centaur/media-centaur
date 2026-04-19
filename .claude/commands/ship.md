---
description: Describe, bookmark, push jj changes — and optionally tag a release with a user-facing changelog and upgrade-safety check
allowed-tools: Bash, AskUserQuestion, Read, Write, Edit
---

You are shipping one or more Jujutsu (jj) changes for Media Centarr, and optionally tagging a release the end-user updater will see. Media Centarr end users are media-center users — not engineers. Release notes they see must be written for them.

## Arguments

Invocation modes:

- `/ship` — plain ship. Describe working change(s), advance, bookmark, push `main`. No tag.
- `/ship major` — ship AND bump **major** version in `mix.exs` (X.y.z → (X+1).0.0), generate a user-facing changelog, validate upgrade safety, tag, push tag.
- `/ship minor` — ship AND bump **minor** version (x.Y.z → x.(Y+1).0), same tag flow.
- `/ship patch` — ship AND bump **patch** version (x.y.Z → x.y.(Z+1)), same tag flow.

If the argument is anything else, treat it as invalid and stop with a clear message.

## Step 1: Discover repos

Determine which repos to operate on:

```bash
if [ -d ".jj" ]; then
  echo "SINGLE:$(pwd)"
else
  for d in */; do
    [ -d "$d/.jj" ] && echo "REPO:$(cd "$d" && pwd)"
  done
fi
```

- If CWD has `.jj/` → operate on CWD alone
- Otherwise → immediate subdirectories containing `.jj/`
- 0 repos → tell the user "No jj repos found in this directory" and stop
- More than 8 repos → tell the user "Found N repos — are you in the right directory?" and stop

## Step 2: Scan each repo

For each discovered repo, run `jj diff --stat` and `jj log --limit 1` (in parallel when possible). Classify:

- **has changes** — diff is non-empty OR the change already has a description (not "(no description set)")
- **skip** — empty diff AND no description

## Step 3: Plan and confirm

Show a summary table of all repos with their status. If a version bump was requested, also show:

- Current version (from `mix.exs`)
- Target version after bump
- Which repo will be tagged (the Media Centarr app — the one containing `mix.exs`)

Use `AskUserQuestion` to get explicit confirmation before any mutations. If the user declines, stop.

If every repo would be skipped AND no tag is requested, tell the user there's nothing to ship and stop.

## Step 4: Execute the ship (per repo)

Only after confirmation. For each repo with changes, sequentially:

### 4a: Write the description

- Run `jj diff` in the repo to read the full diff
- Write a concise description: imperative verb phrase, sentence case, no trailing period, under 72 chars
- Use conventional prefixes when they fit: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`
- If the change already has a description (not "(no description set)"), keep it unless the diff clearly doesn't match

### 4b: Split if needed

If the diff contains multiple DISTINCT types of work, split with `jj split -m "<description>" <files>` (the `-m` flag avoids opening an editor). The last group remains in the working copy.

### 4c: Describe, advance, bookmark, push

```bash
cd <repo_path>
jj desc -m "<message>"
jj new
jj bookmark set main -r @-
jj git push --bookmark main
```

If a push fails, report the error and continue to the next repo. Do not abort the entire operation.

## Step 5: Version bump + tag (only when mode is major|minor|patch)

Run these in the Media Centarr app repo (the one with `mix.exs`). If shipping multiple repos, the tag applies to the main app repo only.

### 5a: Validate safe upgrade path

**Before** bumping anything, confirm the release will be safely consumable by the in-app updater (`MediaCentarr.SelfUpdate`). If any check fails, **halt** and prompt the engineer using Claude Code to resolve before continuing. Checks:

1. **No pending migrations.** Run `mix ecto.migrations 2>&1 | grep -v "up"` in the app repo. Any line showing a migration in state other than `up` → halt with the offending migration listed.
2. **Tests green.** Run `mix test` (fast subset acceptable if the full suite was just run). Any failure → halt with the failing test names.
3. **Full release workflow builds.** Run `scripts/preflight` and confirm it produces `_build/prod/rel/media_centarr/` containing `bin/media-centarr-install` and `share/systemd/media-centarr.service`. Missing files or build failure → halt with details. (`scripts/preflight` never installs anything.)
4. **Settings.Entry schema compatibility.** Check if the diff from the previous tag touches `lib/media_centarr/settings/entry.ex` or migrations under `priv/repo/migrations/` in a way that renames or drops keys under the `update.*` namespace (`update.last_check_at`, `update.latest_known`, or anything the updater reads). Any such change → halt with a note that in-app hydration would break.
5. **Updater contract intact.** Check if the diff from the previous tag touches `rel/overlays/bin/media-centarr-install` in a backward-incompatible way (removing `--update` flag, changing argv contract of the default install path). Any such change → halt with the offending diff hunks.
6. **Changelog present.** Check that `CHANGELOG.md` (or `docs/changelog.md`) exists and has an entry header matching the target version. If missing, it will be generated in 5b — do NOT halt for this.

Halt format: print `UPGRADE SAFETY CHECK FAILED` followed by a bulleted list of failures, then tell the engineer exactly which files to look at and what decision they need to make. Use `AskUserQuestion` to ask whether to abort or continue anyway (override is explicit, never silent).

### 5b: Draft a user-facing changelog

Media Centarr end users are media-center users. Technical commit messages are useless to them. Generate release notes they can actually read.

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
5. Commit the changelog update as its own jj change:
   ```bash
   jj desc -m "docs: changelog for v<version>"
   jj new
   jj bookmark set main -r @-
   jj git push --bookmark main
   ```

### 5c: Bump version in mix.exs

Read `mix.exs`, replace the `version: "x.y.z"` line with the new version. Commit as its own jj change:

```bash
jj desc -m "chore: bump version to <version>"
jj new
jj bookmark set main -r @-
jj git push --bookmark main
```

### 5d: Tag and push

Read the version from the bumped `mix.exs` — the tag follows that value exactly. Pre-computed variables are not the source of truth; `mix.exs` is.

```bash
version=$(grep -E '^\s*version:' mix.exs | head -1 | sed 's/.*"\(.*\)".*/\1/')
git tag "v$version"
git push origin "v$version"
```

(Git is the source of truth for tags in a jj-colocated repo; `jj git push` doesn't push tags.)

The GitHub Actions release workflow at `.github/workflows/release.yml` is triggered by the tag and builds the tarball. The release notes on the GitHub Release page come from the tag body or the workflow — if the workflow supports a release-notes input, pass the changelog contents; otherwise point the engineer at the GitHub release page to paste the notes manually.

Check the GitHub release after a minute with `gh release view "v<version>"` and confirm the tarball + SHA256SUMS are present. Report the result.

## Step 6: Summary

After everything, show a final table:

- Repo name → description used → push result
- If tagged: target version, upgrade-safety check result, changelog preview location, tag push result, GitHub release status

## Important

- NEVER use `jj commit` — jj's working copy is already a commit
- NEVER mutate anything before the user confirms in Step 3
- If `jj diff` is empty and there's no description, skip that repo
- Each repo is independent — a failure in one does not block the others
- When operating on multiple repos, always `cd` to the repo's absolute path before running jj commands
- **Halt on upgrade-safety failures.** Don't silently override. The in-app updater runs on end users' machines — a broken upgrade path is worse than a delayed release.
- **End-user voice.** Changelog entries go in front of media-center users. If a line sounds like a commit message, rewrite it until it doesn't.
