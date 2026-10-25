---
status: in-progress
started: 2026-05-27
last_updated: 2026-10-25
---
# Install reproduction matrix

## Goal

Build out a multi-distro, snapshot-driven reproduction environment for the Media Centaur and prowlarr-stack installers, so install bugs can be proven, fixed, and kept-fixed across releases. Phase 1 (Linux Mint only) is a focused start — this campaign carries the larger roadmap from the brainstorm so the deferred decisions are not lost.

## Glossary

| Term | Meaning |
|---|---|
| **Scenario** | One scripted install path run against one environment, ending in pass or fail. |
| **macOS runner** | A GitHub-hosted Apple Silicon machine that runs a workflow job (`macos-14` today). |
| **LaunchAgent** | The launchd job that starts Media Centaur at login on macOS — the systemd user unit's counterpart. |
| **Label** | The LaunchAgent's name, `com.media-centaur.app`. launchd keeps an enabled or disabled flag per label, separate from the plist file. |
| **gui domain** | launchd's per-user login session, `gui/<uid>`. LaunchAgents load into it, and it exists only for a user with a GUI login. |

## Status

**In progress; Phase 8 built on branch `install-repro-macos` and run on GitHub's macOS runners; it found four macOS faults, fixed on the branch. The install scenarios pass with the fixed installer; the in-app update and the app-side fixes wait on a release carrying them.** Added 2026-10-25 by the owner after the first macOS user report. *Reconciled 2026-10-25:* still no `install-repro/` directory and no code for any phase. Phase 1's earlier status: brainstorm complete; design spec written at [`docs/superpowers/specs/2026-05-27-install-repro-env-design.md`](../docs/superpowers/specs/2026-05-27-install-repro-env-design.md). Implementation plan to be written next via the writing-plans skill. No code yet.

*Reconciled 2026-06-10:* no `install-repro/` directory exists — untouched
since the spec. Note the macOS public-installer support (v0.72.10) does not
change the scope decision here (macOS repro stays out, per Decisions).

## Decisions made

* `2026-05-27` — **Substrate: libvirt + QEMU/KVM.** LXC/Incus, Vagrant, and DinD all weaken the fidelity of the Docker-on-Mint failure mode we most need to reproduce. (brainstorm)
* `2026-05-27` — **Repo location: top-level `install-repro/`** as a peer of `installer/`. Not under `scripts/` (subdir bloat), not under `test/` (Elixir tests only), not a sibling repo (context fragmentation). (brainstorm)
* `2026-05-27` — **Heavy state lives outside the repo** under XDG paths (`~/.local/share`, `~/.cache`, `~/.local/state`). Git holds only driver, scenarios, fixtures, README. (brainstorm)
* `2026-05-27` — **Phase 1 ships Mint 22.3 only** to validate the substrate against the bugs we actually hit. Multi-distro is a follow-on. (this campaign)
* `2026-05-27` — **Driver takes a `<distro>` positional from day one**, defaulting to `mint-22.3`, so adding distros later is data-only, not a CLI rewrite. (brainstorm)
* `2026-05-27` — **Scenarios pull from the released tarball by default**, not the local repo, because faithfulness to what the real user experiences is the point. A `--from-local` mode is a future phase. (brainstorm)
* `2026-05-27` — **No CI integration in any phase yet.** GH Actions runners can't run KVM on the standard tier; the `larger` runners can but cost money. Revisit only if the matrix grows beyond what local iteration can keep green. (brainstorm)
* `2026-05-27` — **macOS reproduction is out of scope.** Apple Silicon needs real Mac hardware (or licensed macOS-on-QEMU, which is legally and operationally dodgy). Surface separately if darwin issues recur — `campaigns/macos-platform-support.md` is the better home. (brainstorm)
* `2026-10-25` — **macOS reproduction is in scope, as Phase 8 on GitHub's macOS runners** (owner). Supersedes the 2026-05-27 entry above: GitHub hosts Apple Silicon at the standard tier, so the hardware objection no longer applies. The trigger was the first macOS user report, fixed in v1.60.1: the LaunchAgent never loaded, `sudo` left root-owned files, a manual start had no `SECRET_KEY_BASE`, and the in-app update needed `setsid`, which macOS lacks. None of these could have shipped had the installer run once on a Mac. (commit `66b9b74b`)
* `2026-10-25` — **Phase 8 runs in CI**, an exception to "no CI integration": a macOS runner needs no KVM, and `ci.yml` already runs the test suite on `macos-14`. (owner)
* `2026-10-25` — **Phase 8 trigger: `release.yml` calls it after publish, plus manual dispatch**, taken at the recommendation. A failure does not unpublish; it signals a fix release. Gating before the tag waits on Phase 5.
* `2026-10-25` — **Phase 8 runs only by manual dispatch, periodically, when we decide to** (owner). Supersedes the entry above: no `release.yml` call.
* `2026-10-25` — **Phase 8 runner image: `macos-14`**, taken at the recommendation, matching `ci.yml` and `release.yml`.
* `2026-10-25` — **macOS scenarios live at `install-repro/scenarios/macos/`**, plain bash scripts against the real installed paths, so the same scripts run on a runner and on a real Mac. The workflow is only the environment, as `repro-vm` is for Phase 1.

## Roadmap

Phases are ordered by *value-per-unit-effort* given the failures we've actually seen. Each is independently shippable.

### Phase 1 — Mint-only repro (in progress)

Spec: [`docs/superpowers/specs/2026-05-27-install-repro-env-design.md`](../docs/superpowers/specs/2026-05-27-install-repro-env-design.md).

Validates the substrate against the bugs that triggered this work. Driver, two scenarios (`mc-fresh-install`, `prowlarr-fresh-install`), Mint VM bootstrapped once interactively.

### Phase 2 — Tier-1 cloud-image distros

Add **Debian 12, Ubuntu 24.04 LTS, Fedora 41**. All three publish official cloud images + accept cloud-init; per-distro cost is ~15 min one-time. Introduces:

- `install-repro/matrix.toml` (or per-distro file) — pulls the one-distro Phase 1 driver into a multi-distro shape.
- `install-repro/seeds/` — cloud-init `user-data` / `meta-data` templates.
- The driver gains `repro-vm run <scenario> <distro>` semantics with `<distro>` no longer defaulting.

Catches: glibc-version-skew bugs (Debian 12 has the oldest glibc of the supported set), Fedora-style packaging differences, the Ubuntu baseline.

### Phase 3 — Pop!_OS 22.04

ISO-only like Mint; same one-time-install + snapshot pattern. Worth doing because Pop has its own apt-pinning quirks for Firefox and an Nvidia-default kernel that diverges from Ubuntu's.

### Phase 4 — Pre-built shareable VM images

This is the "build once, anyone pulls" idea from the brainstorm. **Scoped to ISO-only distros only** — cloud-image distros already get their cache from upstream and don't benefit.

- `install-repro/packer/` — Packer HCL templates for Mint and Pop!_OS that take an ISO + autoinstall + post-install (`apt install sqlite3 mpv inotify-tools docker-ce …`) and produce a sealed qcow2.
- GitHub Actions workflow (manual / monthly cron) runs Packer on a runner with KVM, uploads the qcow2 to **GHCR as an OCI artifact** via `oras`.
- `install-repro/manifest.toml` — committed-in-repo `(distro, sha256, pull-url)` table. Driver gains `repro-vm pull <distro>` that fetches, verifies the sha256, and stages — same trust model as `installer/install.sh`'s tarball verification.
- New ADR documenting the trust posture: recipe-in-repo, sha-in-repo, image-out-of-repo.

Audience question to settle when Phase 4 starts: solo (across your own machines) vs. open-source contributors. Solo → checksum is enough. Contributors → add Sigstore/cosign signing.

### Phase 5 — `--from-local` scenarios

Default scenarios pull from released tarballs. Add `--from-local PATH` so a developer can test an *unreleased* change without tagging. For media-centaur: mounts `_build/prod/rel/media_centaur/`. For prowlarr-stack: mounts the sibling repo at `../prowlarr-stack`.

### Phase 6 — Upgrade / uninstall scenarios

- `mc-upgrade` — install prior released version, exercise in-app "Update now" (via `~/.local/lib/media-centaur/current/bin/media-centaur-install --update`), verify upgrade lands.
- `mc-uninstall-reinstall` — full uninstall cycle followed by clean reinstall; asserts config/data preservation rules in the wiki are accurate.
- `mc-rollback` — symlink-swap rollback flow per the wiki.

### Phase 8 — macOS on GitHub's macOS runners (next)

A workflow job on a macOS runner that installs Media Centaur with the real installer and runs these scenarios, each as its own step:

1. **Fresh install without `sudo`.** The summary reports the agent loaded and running. `launchctl print gui/$(id -u)/com.media-centaur.app` succeeds, and `http://localhost:2160` answers.
2. **Re-run over an existing install.** The upgrade path loads the agent again.
3. **Install over a disabled label.** `launchctl disable` first, then install. The agent loads, which proves the v1.60.1 fix.
4. **`sudo` is refused.** The installer exits non-zero and writes nothing.
5. **Manual start.** Boot the agent out, run `bin/media_centaur start`, and the app boots with the secrets file loaded.
6. **In-app update.** Install the previous release, trigger the update the way **Settings → System → Update now** does, and assert the agent ends on the new version.
7. **Uninstall.** The agent is gone, the label is disabled, and config and data are kept.

The job uploads the installer output, `handoff.log` and `~/Library/Logs/Media Centaur/` as artifacts, so a failure carries its evidence.

Research before building:

- Whether a macOS runner has a gui domain for its user. Scenarios 1–3, 6 and 7 need one. If it doesn't, the job can only cover `--no-service` installs, and real-Mac checks stay with users.
- How scenario 6 triggers the update without a browser: a release command (`bin/media_centaur rpc`) or the HTTP route the Settings button uses.
- Whether the app boots without `mpv` on the runner, or the job needs `brew install mpv`.

Milestone record (2026-10-25):

1. **Scope.** All seven scenarios. Moved out: nothing. A fresh install goes through the public `installer/install.sh`; the other scenarios use the installed `current/bin/media-centaur-install`.
2. **Research.** *gui domain* — no source settles it for GitHub-hosted runners (GitLab and CircleCI report `gui/501` failing on headless EC2 Macs); the first run measures it in its "Runner environment" step, and `fresh-install` fails with a named reason if the domain is missing. *Update trigger* — `bin/media_centaur rpc` calling `SelfUpdate.run_check(:manual)` then `SelfUpdate.apply_pending()`, the same two calls the Settings button makes; `auto_update_enabled` defaults to false, so nothing updates before the scenario asks. *mpv* — read only by the setup wizard and playback, so the app boots without it (to confirm on the first run).
3. **Decisions.** Trigger and runner image, above.
4. **Design unification.** Scenarios follow Phase 1's `install-repro/scenarios/` layout; the workflow is the environment. Recorded, not fixed: the in-app update always targets GitHub's latest release, so `in-app-update` proves the tag under test only when that tag is the latest — true when `release.yml` calls it. The workflow's branch `push` trigger and a diagnostic step were development scaffolding, removed before merge.
5. **Plan.** `install-repro/scenarios/macos/{lib,sudo-refused,fresh-install,reinstall,disabled-label,manual-start,uninstall,in-app-update,collect-evidence}`; `.github/workflows/install-repro-macos.yml` (resolve tags; lifecycle job runs scenarios 4,1,2,3,5,7 in order; update job runs 6 on a clean runner; evidence artifact per job); `install-repro/README.md`. (The `release.yml` call was dropped the same day: manual dispatch only.)
6. **Plan unification.** No old path kept, no copied constants beyond the installer's own (label, paths, port), which a scenario must assert independently of the installer.
7. **Execution.** Runs `40196579021`–`40197286363` on `macos-14` (14.8.9). The runner has an Aqua `gui/501` login domain, so every LaunchAgent scenario runs there; mpv is absent and the app boots without it. Found and fixed on the branch, each proven on the runner or locally:
   - **Every install over a running install failed to load the agent** (v1.60.1): `launchctl bootout gui/<uid> <label>` reads the label as a plist path and fails with "Boot-out failed: 5", hidden by `2>/dev/null`, so the agent stayed loaded and the bootstrap was refused. The in-app update runs the same step. Fix: the service-target form `bootout gui/<uid>/<label>`, then wait until launchd drops the label — it still lists it for about a second after bootout exits 0. Proven: with the checkout's installer, `reinstall`, `disabled-label`, `manual-start` and `uninstall` pass.
   - **`Platform.Autostart.Launchd.stop/1`** (the Settings Stop control) used the same failing form. Fixed, with a test.
   - **The app never knew it ran under launchd**: `LAUNCHD_SOCKET` is not set on macOS 14; launchd sets `XPC_SERVICE_NAME` to the job's label. Settings → System showed "Not running under systemd." with no restart or stop controls. Fixed to `XPC_SERVICE_NAME == label`, with tests; seen on the runner via `rpc`.
   - **The first install logged `[error] … database is locked`**: the migrator's two connections switch a new database to WAL at once, and exqlite sets `journal_mode` before `busy_timeout`. Fix: `Release` starts the repo with one connection. Measured locally: 6/10 fresh databases logged it before, 0/10 after. The `fresh-install-log` scenario checks it on the runner once a release carries the fix.
   - Still red by design: `in-app-update` from v1.60.0 (its installer refuses its own bootstrap) and `fresh-install-log` against v1.60.1. Both need a release carrying the fixes; the runner can swap only the installer, not the app.


### Phase 7 — CI integration (only if/when warranted)

`larger` GitHub-hosted runner with KVM, or a self-hosted runner on a small workstation, running a subset of the matrix on release tag. Skip unless local iteration starts dropping regressions.

## Next steps

0. **Phase 8: close the loop** (owner, 2026-10-25) — merge `install-repro-macos`, ship v1.60.2, then `gh workflow run install-repro-macos.yml` with no tag: `in-app-update` then tests v1.60.1 → v1.60.2 and `fresh-install-log` the migrator fix; also check `Autostart.state()` reports `under_supervisor: true` via `rpc`. Then **Phase 8 first**, ahead of Phase 1: it covers the platform with no tester and no owned hardware. Start with its three research items. Its open decisions:
   - **Trigger** — on every release tag after `release.yml` publishes, by manual dispatch, or as a gate before the tag. Recommendation: after release plus manual dispatch first. Gating before the tag needs a darwin tarball built from an untagged commit, which is Phase 5's `--from-local` idea on macOS.
   - **Runner image** — `macos-14`, as `ci.yml` and `release.yml` use, or a newer image. Recommendation: `macos-14`, matching the build.
1. **Write implementation plan** for Phase 1 via the writing-plans skill, using the spec as input.
2. Execute Phase 1: driver script, Mint VM bootstrap, two scenarios, README.
3. Reproduce the reported Mint installation failures end-to-end and capture the run logs; attach to whatever bug tickets/wiki notes those become.
4. Fix the reproduced bugs (installer changes, wiki docs, prowlarr-stack codename override) — out of scope for *this* campaign but the trigger for it.
5. Hold Phase 2 until Phase 1 has proven its value across at least one real fix cycle.

## Completion criteria

This campaign is **done** when:

* All seven phases are shipped, *or* an explicit decision is made that a later phase will not happen (and recorded in **Decisions made** above with the reasoning).
* `install-repro/README.md` documents the matrix and the bootstrap path for every supported distro.
* At least one shipped media-centaur or prowlarr-stack fix references a `repro-vm` run-log as the bug evidence — proving the environment is being used, not just maintained.
* The Phase 8 workflow runs by manual dispatch, and all seven of its scenarios pass, or a scenario is dropped with a recorded reason (for example, no gui domain on the runner).

## Pointers

* Spec: [`docs/superpowers/specs/2026-05-27-install-repro-env-design.md`](../docs/superpowers/specs/2026-05-27-install-repro-env-design.md)
* Production installer: [`installer/install.sh`](../installer/install.sh)
* Bundled installer: `rel/platforms/linux/bin/media-centaur-install`
* prowlarr-stack installer: `../prowlarr-stack/install.sh`
* Wiki Installation page: `~/src/media-centaur/media-centaur.wiki/Installation.md`
* macOS: Phase 8 here owns the macOS test environment. [`campaigns/macos-platform-support.md`](macos-platform-support.md) owns the platform's features and parity.
* macOS installer: `rel/platforms/darwin/bin/media-centaur-install`, plist `rel/platforms/darwin/share/launchd/com.media-centaur.app.plist`
