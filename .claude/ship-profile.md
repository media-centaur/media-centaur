# Media Centaur ship profile

Consumed by the user-level `ship` skill. Only what is local to Media Centaur lives here.

**Audience:** media-center users, not engineers. Notes land on the GitHub release page
AND in the in-app updater (`Changelog.for_version/1` reads `CHANGELOG.md`).

Because the updater parses `CHANGELOG.md` at runtime, a malformed entry fails on end
users' update screens rather than in CI. Match the structure of the existing entries
exactly — `### New` / `### Improved` / `### Fixed` subheadings under the version
header, bullets beginning with a bold phrase. If you need a construct the existing
entries do not already use, check `Changelog.for_version/1` first.

**Version source of truth:** `mix.exs`. The release workflow rejects a tag/`mix.exs`
mismatch, so never tag by hand.

**Prerequisite:** `mix precommit`.

**`scripts/ship check` runs** `scripts/preflight` — a production build. Takes minutes.

**`verify` expects:** both platform tarballs + `SHA256SUMS`.

## Judgment gates

- **`Settings.Entry` / `update.*` keys touched** → `--allow-settings-change`.
  Overridable when no `update.*` key the updater reads is renamed or dropped.
  Otherwise in-app update hydration breaks on end users' machines.
- **Installer script touched** (`rel/platforms/*/bin/media-centaur-install`) →
  `--allow-installer-change`. The PREVIOUS release's updater executes this file.
  Overridable when the argv contract (default install path, `--update` flag) is intact.

Pending migrations are a hard failure, not a judgment gate.

## Opt-in: multi-repo fan-out

`/ship` here may span sibling repos. If CWD has `.git/`, operate on it alone;
otherwise operate on each immediate subdirectory that has one. Zero repos → stop.
More than eight → ask whether this is the right directory.

A failed push still stops rather than continuing to the next repo — a locked key or
being offline will fail for the remaining repos too, and a partial ship is worse than
a clean halt.

**Fan-out applies to plain `/ship` only.** A release ship (`/ship major|minor|patch`)
always operates on this repo alone: the version, changelog and tag are Media
Centaur's. A sibling repo that needs its own release has its own profile and its own
`scripts/ship`.

So a release ship invoked where fan-out would otherwise trigger — CWD has no `.git/`
— has no target. **Stop** and ask the user to run it from the repo they mean to
release. Do not guess a subdirectory.

## Extra steps

After `verify`: run `scripts/sync-wiki-docs` (copies pages whose canonical source is
this repo, e.g. `docs/social-protocol.md` → *Social Protocol*), then update any
`../media-centaur.wiki/` pages the release makes stale.

Which pages: the ones documenting behaviour this release's notes describe as new or
changed. If the release is fixes only, there is usually nothing to do — say so rather
than inventing edits.

If `../media-centaur.wiki/` is not cloned, skip the wiki step and report it; do not
clone it as a side effect of shipping. If the wiki push fails, report it and stop —
the release itself is already published and is not affected.
