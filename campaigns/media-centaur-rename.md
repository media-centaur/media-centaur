---
status: complete
started: 2026-05-23
last_updated: 2026-05-23
---
# Rename "Media Centarr" → "Media Centaur"

## Goal

Eradicate the misspelled brand `Centarr` and replace it with
`Centaur` across every surface: the OTP application atom, all module
namespaces, the GitHub org and repos, the live production database
and XDG dirs, the local source tree, the website + domain, and the
wiki/docs. End state: zero `[Cc]entarr` in any forward-facing
artifact, the live instance running on the new name with its library
intact, `media-centaur.net` live with `media-centarr.net` 301-ing to
it, and the in-app updater + installer resolving against the new org.

This is a one-shot rename, but it spans irreversible external steps
(GitHub org rename, DNS cutover, prod DB migration) that must be
sequenced *after* the reversible in-repo work is proven green — hence
a campaign rather than a single commit.

## Status

`2026-05-23` (reconciled + session 2) — **COMPLETE** (modulo the optional
old-domain 301 + a bonus Hyprland-integration follow-up). Rename merged to
`main`; first `media-centaur` release published (`v0.72.2`); production
cut over and verified (running `media_centaur 0.72.2`, 40/40 children,
HTTP 200 on :2160, library intact — 39 movies / 8 collections / 37
seasons / 420 episodes); Pages live at `https://media-centaur.net`; org
display name "Media Centaur". Phase 7: `~/scripts` helpers (`mc-rpc`,
`mc-debug-browser`, `mc-soak-check-progress`) swept + `mc-rpc` verified
against the new node; Claude project memory (33 files incl. `MEMORY.md`)
re-keyed to the new path. **Session-2 remediation:** two migrated-memory
directives had been violated while memory was orphaned — Co-Authored-By
trailers were stripped from `main` + the `v0.72.2` tag (history rewrite +
force-push, release rebuilt clean), and `jj` was scrubbed from the wiki +
org-profile (now pure git). **Remaining (optional):** registrar 301
(`media-centarr.net` → new); Hyprland window-rules/keybinds/launcher that
reference the old name (stale `~/scripts/media-centarr/run`, port 4000 —
ownership unclear, deferred for operator review); cleanup of the old
`~/.local/lib/media-centarr/` install + orphaned old Claude project dir.

* **Phase 0** ✅ DB backup at `~/media-centarr-db-backup-20260523-132539.db`.
* **Phase 1** ✅ committed `d7c7d0ad`; `mix precommit` was green (3950
  Elixir + 436 bun tests). `git grep -niI centarr` is clean outside the
  two intentionally-frozen surfaces (CHANGELOG.md history, `campaigns/`).
* **Phase 2** ✅ source tree renamed; dev systemd unit fixed (session 2):
  `scripts/install-dev` rewrote `~/.config/systemd/user/media-centaur-dev.service`
  (correct WorkingDirectory, node name, config-override path); old
  `media-centarr-dev.service` removed; `daemon-reload`. (Its
  `MEDIA_CENTAUR_CONFIG_OVERRIDE` points at the new config path, migrated
  in Phase 5.)
* **Phase 3** ✅ org renamed (login `media-centaur`); product repos exist.
  Session 2: all four local git remotes (app, wiki, org-profile, assets)
  repointed to `media-centaur/*`; descriptions for `media-centaur-assets`
  and `.github` updated (the `media-centaur` repo desc was already clean).
  Org **display name set to "Media Centaur"** via `admin:org` (operator
  refreshed the scope; `gh api -X PATCH orgs/media-centaur -f
  name='Media Centaur'`). Org description was already clean. **No leftover.**
* **Phase 4** ✅ (bar old-domain 301): operator pointed `media-centaur.net`
  DNS at GitHub Pages (185.199.108–111.153) and set it as the Pages custom
  domain; cert approved. The merge to `main` triggered `pages.yml` (run
  `26335722435`) which deployed the renamed `docs-site` — site is live and
  correctly branded at `https://media-centaur.net` (200), HTTPS enforcement
  enabled via `gh api … -F https_enforced=true`. No `docs-site/CNAME` file
  is needed (workflow Pages uses the settings domain). ⚠️ **leftover**:
  `media-centarr.net` now 404s (it's no longer the Pages custom domain;
  Pages allows only one). The campaign's planned **301 old→new** must be a
  registrar/DNS URL-forward — operator-only, GitHub can't do it for a
  non-configured domain.
* **Phase 5** ❌ not started — live data dir (`~/.local/share/media-centarr`),
  `media-centarr.db` (+ wal, actively written), dotfiles config, and the
  prod `media-centarr.service` are all still old-named.
* **Phase 6** ✅ done (session 2). Wiki (207 hits, 22 files) and
  org-profile (4 hits) swept and pushed. Both are **plain git** (branches
  `master` / `main`). [Note: they were briefly committed via jj before the
  no-jj directive surfaced from migrated memory; the `.jj/` colocation was
  then removed and they reattached to their git branches.] Logo files
  (`centaur-logo*.png`) confirmed in the app repo, so org-profile images
  resolve.
* **Phase 7** ❌ not started — `~/scripts/*` and Claude memory unmigrated.

Next (blocked on operator): (1) merge `rename/media-centaur` → `main`;
(2) `/ship patch` to build the first `media_centaur` artifact; (3) org
display name via `admin:org`; (4) registrar DNS for Phase 4. Then I run
the irreversible Phase 5 prod cutover (step-by-step, explicit go-ahead at
each destructive step) and finish Phase 7.

## Decisions made

Append-only log.

* `2026-05-23` — **Full rename including the OTP app atom.**
  `:media_centarr` → `:media_centaur` (not just modules/display).
  Changes release name, DB filename/path, Erlang node names, cookie,
  and config keys. Cleanest end state; cost is a one-time prod
  migration + updater discontinuity (see Risks).
* `2026-05-23` — **Rename the GitHub org in place** (`media-centarr`
  → `media-centaur`) rather than create a new org and transfer.
  GitHub auto-redirects old URLs (clone, releases API, raw, Pages),
  so the live updater/installer keep resolving during cutover, and
  stars/issues/history are preserved.
* `2026-05-23` — **`freedia-center` org is out of scope.** Only the
  `media-centarr` org and this app are in scope. Legacy siblings
  (`ctl`, `dock`, `frontend`, `backend.backup`) and local backup
  folders are left untouched; they ride along under the renamed
  parent dir but keep their names and remotes.
* `2026-05-23` — **Keep `media-centarr.net` as a 301 redirect** to
  `media-centaur.net`. Preserves old links, the installer URL, and
  existing installs. Retire later.
* `2026-05-23` — **CHANGELOG history is immutable.** Past version
  entries keep `Media Centarr`; only new entries use `Media Centaur`.
  CHANGELOG.md is excluded from the bulk name swap. The two
  `media-centarr.net` links in it stay valid via the 301.
* `2026-05-23` — **Prod cutover is a deliberate one-time manual
  migration**, not a self-migrating updater. For a single
  self-hosted instance the engineering cost of bridging the
  artifact-name discontinuity isn't worth it.
* `2026-05-23` — **`campaigns/` excluded from the content sweep**
  (extends the CHANGELOG-history-is-immutable decision). This doc and
  the README entry intentionally hold both names; historical campaign
  narratives stay as written. (commit `d7c7d0ad`)
* `2026-05-23` — Sweep reduced to **three case-variant substring
  substitutions** (`Centarr→Centaur`, `centarr→centaur`,
  `CENTARR→CENTAUR`); covers every token, idempotent (`centaur` never
  contains `centarr`), equal-length so formatting never drifts.

## Next steps

Phased. Reversible/local first; irreversible/external last. Each
phase ends with a verifiable gate.

### Phase 0 — Safety net (local, reversible) ✅ done
DB snapshot saved to `~/media-centarr-db-backup-20260523-132539.db`.
1. `git switch -c rename/media-centaur`.
2. Back up the live prod DB: copy
   `~/.local/share/media-centarr/media-centarr.db` somewhere safe;
   record the currently-installed version (Settings → About or
   `mc-rpc`).
3. Curate the replace exclude-list: `deps/`, `_build/`,
   `assets/node_modules/`, `priv/static/`, and `CHANGELOG.md`
   (history is immutable). Parser regression titles are unaffected
   (they don't contain the brand).

### Phase 1 — In-repo code rename (verifiable, nothing shipped) ✅ done
Committed `d7c7d0ad`; `mix precommit` green. Note: the renamed
`.gitignore` entry exposed a stale build artifact
(`rel/platforms/shared/share/defaults/media-centarr.toml`) which was
deleted (CI/`preflight` regenerate the new-named copy). Required a
clean `_build` (app-atom rename changes the per-app build dir).
Casing-aware sweep, in this order so narrower tokens don't corrupt
wider ones:
1. `MediaCentarr` → `MediaCentaur` — module namespace + rename dirs
   `lib/media_centarr/`, `lib/media_centarr_web/`, `test/media_centarr*`,
   storybook, credo_checks references, and the module files within.
2. `media_centarr` → `media_centaur` — OTP app atom (`mix.exs`
   `app:` + `releases:` key), config keys (`config :media_centarr`),
   `Application.get_env/3` calls, cookie `media-centarr-local` →
   `media-centaur-local`, `RELEASE_NODE` in `rel/env.sh.eex`, DB
   filename in `config/config.exs`.
3. `media-centarr` → `media-centaur` — the 6 hardcoded repo URLs
   (`issue_url.ex`, `release_artifact.ex`, `update_checker.ex`,
   `updater.ex`, `settings_live/system_section.ex` bootstrap,
   `scripts/troubleshoot`), domain refs in `docs-site/index.html`,
   `defaults/*.toml` + `defaults/*.service` *filenames and contents*,
   data/config dir paths.
4. `MEDIA_CENTARR` → `MEDIA_CENTAUR` — env-var prefix
   (`MEDIA_CENTARR_CONFIG_OVERRIDE` etc.).
5. `Media Centarr` → `Media Centaur` — display name in moduledocs,
   UI strings, `docs/`, README (excluding CHANGELOG.md).
6. Straggler sweep: `git grep -niI 'centarr'` → resolve remainder.
7. **Gate: `mix precommit` fully green** (compile, format, credo,
   boundaries, sobelow, deps.audit, test). The new org URLs are
   "ahead of reality" until Phase 3 — acceptable, nothing ships yet.
   No Ecto migration needed: schema is unchanged; only the DB *path*
   moves (Phase 5).
8. Commit on the branch.

### Phase 2 — Local source tree & dev env ✅ done (dev-unit leftover)
1. Rename parent `~/src/media-centarr` → `~/src/media-centaur` and
   the in-scope children: `media-centarr-app` → `media-centaur-app`,
   `media-centarr-assets` → `media-centaur-assets`,
   `media-centarr-org-profile` → `media-centaur-org-profile`,
   `media-centarr.wiki` → `media-centaur.wiki`. Out-of-scope siblings
   keep their names.
2. Rename + fix paths in the dev systemd unit
   (`~/.config/systemd/user/media-centarr-dev.service`); `daemon-reload`.

### Phase 3 — GitHub org + repos (IRREVERSIBLE — only after Phase 1 green) ✅ done
1. Rename org `media-centarr` → `media-centaur` (Settings → rename;
   needs `admin:org` — gh currently lacks the scope, so
   `gh auth refresh -h github.com -s admin:org` or do it in browser).
2. Rename product-named repos: `media-centarr` → `media-centaur`,
   `media-centarr-assets` → `media-centaur-assets`. The wiki repo
   (`<repo>.wiki`) follows automatically. `contrib`, `.github`,
   `prowlarr-stack`, `shell`, `torrent-stack`, `legacy-torrent-stack`
   need only the org rename.
3. Update org display name (`Media Centarr` → `Media Centaur`) and
   every repo description still saying the old name.
4. Repoint local git remotes to canonical new URLs (in-scope repos).
5. Verify redirects resolve: clone of old path, releases API
   (`api.github.com/repos/media-centarr/media-centarr/releases/latest`),
   `raw.githubusercontent.com/.../installer/install.sh`.

### Phase 4 — Website / domain ✅ done (bar old-domain 301, operator-only)
1. Point `media-centaur.net` DNS at GitHub Pages; set it as the app
   repo's Pages custom domain (replaces current `media-centarr.net`).
2. Add a registrar/DNS **301: media-centarr.net → media-centaur.net**.
3. Push docs-site changes (canonical/og URLs already flipped in
   Phase 1; auto-deploys on push touching `docs-site/**`).
4. Verify `https://media-centaur.net` live and old domain 301s.

### Phase 5 — Production cutover (live instance + library data) ✅ done
**Session 2 (2026-05-23):** stopped + disabled old `media-centarr.service`;
fresh backup at `~/media-centaur-cutover-backup-20260523-171010/` (db +
wal + shm). Moved `~/.local/share/media-centarr` →
`~/.local/share/media-centaur`, renamed `media-centarr.db*` →
`media-centaur.db*` (a stray empty `media-centaur.db` from the earlier
`mix ecto.migrations` had pre-created the target dir, briefly nesting the
move — un-nested, no data lost). Config: created a new dotfiles
`media-centaur/` dir, moved+swept both TOMLs (`database_path` → new path)
+ `secrets.env`; **left legacy `dock.toml`/`frontend.toml` in the old
`media-centarr` dir** (no consumers); symlinked `~/.config/media-centaur`.
Installed `v0.72.2` via the public installer (`--version v0.72.2`):
migrations reported "already up", `media-centaur.service` enabled +
running. Removed the old unit. Verified healthy (see Status). Old install
`~/.local/lib/media-centarr/` left for rollback (cleanup later).

The in-app updater **cannot** bridge this: the new release artifact
is `media_centaur-*.tar.gz`, but the installed updater looks for
`media_centarr-*`. First hop is a deliberate manual cutover; after
it, the in-app updater works normally forever.
1. `systemctl --user stop media-centarr.service`.
2. Confirm the Phase-0 DB backup exists.
3. Migrate data dir: move `~/.local/share/media-centarr` →
   `~/.local/share/media-centaur`, rename `media-centarr.db` →
   `media-centaur.db` (config path now points here).
4. Migrate config **in the dotfiles repo** (the `~/.config/media-centarr`
   symlink targets it): rename the dir → `media-centaur`, rename
   `media-centarr.toml` → `media-centaur.toml` and
   `media-centarr-dev.toml` → `media-centaur-dev.toml`, recreate the
   symlink. Edit working tree only — the sync timer pushes; never
   manual-commit dotfiles.
5. Install the new `media-centaur` release manually (public installer
   from the new org, or `scripts/preflight` + manual swap). Install
   `media-centaur.service` (+ dev unit), `daemon-reload`, enable;
   disable/remove old `media-centarr.service`.
6. Start `media-centaur.service`; verify health (console drawer /
   `troubleshoot` skill / `mc-rpc`) and library intact via `Library.*`
   context functions (not raw SQL).

### Phase 6 — Wiki & org-profile docs ✅ done
Both `media-centaur.wiki` (branch `master`) and `media-centaur-org-profile`
(branch `main`) are **plain git** — use git for commit + push, never jj
(project-wide no-jj directive; any `.jj/` colocation was removed in
session 2).
1. Swept the wiki repo: titles, install commands, GitHub URLs. No
   `media-centaur.net` refs, so nothing depended on the pending Phase-4 DNS.
2. Swept the `.github` org-profile repo.

### Phase 7 — Ship & final verification ✅ done
1. ✅ done — `/ship patch` tagged **`v0.72.2`**, the first `media-centaur`
   release (build `26336006331` green; linux + darwin tarballs +
   `SHA256SUMS`). CHANGELOG documents the rename + the one-time
   manual-migration note for external installs. (Shipped before Phase 5
   per the "ship first" decision, so the cutover installs a real
   published artifact.)
2. ✅ done — swept the dotfiles-managed `~/scripts` helpers (`mc-rpc`,
   `mc-debug-browser`, `mc-soak-check-progress`); `mc-rpc` now targets the
   new install and was verified against `media_centaur@…` (39 movies).
   (No script hardcoded the dev node name after all — `mc-rpc` uses the
   release `rpc`.) **Out of scope / deferred:** the Hyprland config
   (`rules.conf` class/namespace, `keybinds.conf`/`hyprland.conf` →
   `~/scripts/media-centarr/run`) still references the old name; the app
   does **not** emit a `media-centarr` window class (live mpv window is
   class `mpv`), so those rules are likely stale and `run` itself is stale
   (port 4000). Left for operator review — touching live WM config blind
   is riskier than the payoff.
3. ✅ done — re-keyed Claude project memory from
   `…-media-centarr-media-centarr-app/memory/` to the new
   `…-media-centaur-media-centaur-app/memory/` (33 files incl. `MEMORY.md`,
   swept). The old session-start ran *without* this memory (orphaned),
   which is why the no-Co-Authored-By / no-jj directives were missed and
   then remediated. Old project dir left as an inert backup.

## Completion criteria

* `git grep -niI 'centarr'` returns nothing in tracked files except
  the intentionally-frozen CHANGELOG history.
* `mix precommit` green on the renamed tree.
* Prod instance running as `media-centaur` with the full library
  intact (verified via `Library.*`, not SQL).
* `media-centaur.net` live; `media-centarr.net` 301s to it.
* In-app updater finds the new release; installer URL resolves
  against the new org.
* GitHub org + product-named repos renamed; descriptions updated.
* Wiki + org-profile swept; `~/scripts` and Claude memory migrated.

## Risks & gotchas

* **Updater discontinuity** (artifact-name mismatch) → accepted via
  the one-time manual cutover in Phase 5.
* **Dotfiles symlink is auto-synced by a timer** → edit working tree
  only; never manual-commit/push dotfiles.
* **Claude memory is path-keyed** → dir rename orphans it (Phase 7).
* **`~/scripts/*` live outside the repo** and hardcode the old node
  name + URLs (Phase 7).
* **gh CLI lacks `admin:org`** → org rename is a manual/refresh step.
* **New org URLs land in code before the org exists** (Phase 1 vs 3)
  → safe because nothing ships until Phase 3.

## Pointers

* OTP app atom + release block + cookie: `mix.exs`.
* DB path default: `config/config.exs` (`~/.local/share/media-centarr/...`).
* Node name: `rel/env.sh.eex` (`RELEASE_NODE`).
* Hardcoded org URLs: `lib/media_centarr/error_reports/issue_url.ex`,
  `lib/media_centarr/platform/release_artifact.ex`,
  `lib/media_centarr/self_update/{update_checker,updater}.ex`,
  `lib/media_centarr_web/live/settings_live/system_section.ex`,
  `scripts/troubleshoot`.
* Pages custom domain: app repo Settings → Pages (currently
  `media-centarr.net`).
* Campaign convention: [ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md).
