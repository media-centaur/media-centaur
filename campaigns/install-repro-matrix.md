---
status: in-progress
started: 2026-05-27
last_updated: 2026-10-25
---
# Install reproduction matrix

## Goal

Every way a user installs, updates, starts and removes Media Centaur runs, on demand, on each supported platform, against real operating systems. A fault is then proven by a run, fixed, and proven fixed before the tag carrying the fix ships. Redesigned 2026-10-25 from what the macOS milestone (M0) taught: hosted runners are real machines, and GitHub's standard Linux runners can run KVM. So the whole matrix runs on GitHub by manual dispatch, with no local VM fleet.

## Glossary

| Term | Meaning |
|---|---|
| **Scenario** | One script that runs one install path and ends in pass or fail. It checks the outcome directly (the service manager's state, the HTTP port, the logs), never only the installer's own summary. |
| **Scenario set** | The nine scenarios every platform implements: `sudo-refused`, `fresh-install`, `reinstall`, `<platform>/disabled-service`, `manual-start`, `uninstall`, `upgrade`, `fresh-install-log`, `in-app-update`. |
| **Environment** | Where a scenario runs: a **bare runner** (the GitHub-hosted machine itself), a **runner VM** (a cloud-image VM booted with QEMU/KVM inside a Linux runner), or a **real machine** by hand. |
| **Source** | What a run installs: `released` (a published release, through the public installer) or `branch` (a release built from the dispatched ref by `build-release.yml`, versioned `<next patch>-branch.g<sha>`). |
| **Matrix** | The environments × the scenario set, run by one dispatch. |
| **Evidence** | What a job uploads whatever the outcome: app logs, update handoff logs, service-manager state, scenario output. |
| **macOS runner** | A GitHub-hosted Apple Silicon machine (`macos-14`). It has an Aqua `gui/501` login domain, so LaunchAgents load. |
| **LaunchAgent / label** | The launchd job that starts the app at login on macOS, named `com.media-centaur.app`. launchd keeps an enabled or disabled flag per label, separate from the plist file. |
| **gui domain** | launchd's per-user login session, `gui/<uid>`. |
| **Cloud image** | A distribution's official VM disk image that configures itself at first boot from cloud-init `user-data`. |

## Status

M0 (macOS), M1 (Linux, bare ubuntu runner) and M2 (build from the branch) are done: one `install-repro.yml` dispatch runs the nine scenarios on both platforms against a published release or a release built from the branch, through the same build workflow `release.yml` uses. M3 (runner VMs) is next.

## Principles

1. **Measure the environment before designing for it.** Every job starts with an environment step that prints the facts the scenarios depend on. An open question about the environment is answered by a temporary diagnostic step in one run, not by research alone.
2. **Assert outcomes, not reports.** A scenario checks the service manager, the port and the logs itself. The installer once printed a summary while `2>/dev/null` hid the failure underneath.
3. **Scenarios are plain scripts against the real installed paths.** The same script runs on a bare runner, in a runner VM and on a user's machine. The workflow is only the environment.
4. **Manual dispatch only.** Runs start when we decide, never from `release.yml` (owner, 2026-10-25).
5. **A fix carries its run.** A fix found by the matrix cites the run that found it, and is proven by a `source: branch` run before its tag.
6. **Change the version.** Installing a release over itself proves nothing about the version switch. Every environment runs `upgrade` (the release before, then the tag) and checks the version the running app reports, not only the symlink.
7. **No secrets in evidence.** `collect-evidence` never copies `secrets.env`, and diagnostics never print the process environment unfiltered.

## Open decisions

1. **An install over a disabled service: keep it off, or turn it back on?** After `service remove`, or after a user disabled autostart, a later install or update on Linux leaves autostart off ("unit installed, not enabled"); on macOS it turns autostart back on. One product should follow one rule. Recommendation: keep it off on both — a disable is the user's choice, and since v1.60.1 only `service remove` disables the macOS label. The cost: macOS installs left disabled by the pre-1.60.1 bug stay off after updating, so the macOS change needs a one-time re-enable of labels that were never deliberately removed, which an installer cannot tell apart. Until decided, each platform's `disabled-service` scenario asserts its current rule.

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
* `2026-10-25` — **Redesign: the matrix runs on GitHub, by manual dispatch** (owner). GitHub's standard Linux runners have had KVM since April 2024, which removes the premise of the 2026-05-27 "no CI" and libvirt entries. Supersedes both, and the Phase 1–7 roadmap: Linux runs on the bare ubuntu runner (M1) and in cloud-image runner VMs (M3); the local `repro-vm` driver and its Mint snapshot are dropped. The VM boot script also runs locally for interactive debugging.
* `2026-10-25` — **Mint is covered by Ubuntu 24.04 first** (owner). Mint 22 is built on Ubuntu 24.04. A Mint image (autoinstall from the ISO) is built only if a Mint-specific fault appears, or a Mint report does not reproduce on Ubuntu. Supersedes "Phase 1 ships Mint 22.3 only".
* `2026-10-25` — **prowlarr-stack's installer gets its own repro, in its repo, on this design** (owner). This campaign covers Media Centaur's installers only.
* `2026-10-25` — **M1 first: Linux on the bare ubuntu runner** (owner) — the primary platform, the cheapest environment, and its first run answers the systemd user-session question.
* `2026-10-25` — **Building from the branch (M2) factors the release build out of `release.yml` into one shared workflow**, so the repro and the release build the tarball the same way. Taken with the redesign; the alternative, a copy of the build steps, would let the two drift.

## Milestones

| | | |
|---|---|---|
| M0 | macOS scenario set on the macOS runner | ✅ 2026-10-25 — nine scenarios on `macos-14`, dispatch-only. Found five faults, fixed in v1.60.2 (reload over a running agent, Settings Stop, launchd detection, first-migration lock error) and v1.60.3 (no upgrade switched versions). Run `40202430776`: every scenario passes on v1.60.3, the in-app update from v1.60.2 included. |
| M1 | Linux scenario set on the bare `ubuntu-24.04` runner | ✅ 2026-10-25 — shared scenarios with a per-platform adapter; `install-repro.yml` with a platform matrix (M4's first half). Run `40204388498`: all nine scenarios pass on Linux and macOS against v1.60.3, the in-app update from v1.60.2 included. No Linux fault found. |
| M2 | `source: branch` — a release built from the branch, through a build workflow shared with `release.yml` | ✅ 2026-10-25 — `build-release.yml`; `release.yml` builds through it; `source: released\|branch` replaces `installer: checkout`. Run `40208897190`: both platforms build `1.60.4-branch.ge853f4a` and pass the install scenarios, `upgrade` from v1.60.3 included. Tarball file lists match v1.60.3's on both platforms (3,598 files). |
| M3 | Runner VMs: Debian 12, Ubuntu 22.04, Ubuntu 24.04, Fedora (current) | open |
| M4 | One dispatch runs the whole matrix and writes a summary table | open — one dispatch already runs both platforms (M1); the VMs and the summary table remain |

### M0 — macOS ✅

Runs `40196579021`–`40199360910`. The macOS runner has an Aqua `gui/501` domain; mpv is absent and the app boots without it. Findings and fixes (v1.60.2):

- `launchctl bootout gui/<uid> <label>` reads the label as a plist path and fails with "Boot-out failed: 5". The installer hid it, so a reinstall or in-app update never reloaded the agent. The fix uses the service-target form `gui/<uid>/<label>`, then waits: launchd keeps the label about a second after bootout exits 0.
- `Platform.Autostart.Launchd.stop/1` used the same form.
- macOS 14 does not set `LAUNCHD_SOCKET`; launchd sets `XPC_SERVICE_NAME` to the label. The app now detects its agent by that.
- The migrator's two connections raced to switch a new database to WAL, logging "database is locked". Release tasks now use one connection (6/10 fresh databases logged it before, 0/10 after).
- The in-app update depends on GitHub's API, which a runner's shared IP often has rate-limited. The scenario waits for the reported reset once, then checks again.
- **No macOS upgrade ever switched versions** (found by run `40199360910`, after v1.60.2). The installer flips `current` with `mv -f current.new current`; BSD `mv` follows `current`, a symlink to a directory, and moves the new link into the old release. The installer reported the new version and restarted the agent, which kept running the old one — including the terminal `--update` workaround v1.60.1's notes gave. The scenarios missed it because no scenario changed version before `in-app-update`. Fix: `mv -fh`, the BSD counterpart of the Linux installer's GNU `mv -T`. A new `upgrade` scenario reproduces it with the released installer (run `40200911520`) and passes with the fixed one (run `40200918075`). Ships in v1.60.3; `in-app-update` (v1.60.2 → v1.60.3) proves it after the release.

Not fixed (`macos-platform-support.md` owns them): the Settings service card says "Not running under systemd." on macOS when the app was started by hand; `Apps.Launcher` runs `setsid`, which macOS lacks.

### M1 — Linux on the bare ubuntu runner ✅

The Linux installer through the scenario set on `ubuntu-24.04`, `released` and `installer: checkout`.

Record (2026-10-25):

1. **Scope.** The scenario set on `ubuntu-24.04`. In: porting the scenarios, the systemd user-manager measurement, the 2>/dev/null and unchecked-state audit of the Linux installer. Moved to M4 early: one `install-repro.yml` with a platform matrix, because the Linux job is the macOS job with another adapter.
2. **Research.** The Linux installer already flips `current` with GNU `mv -T`. It reports "enabled + running" from `systemctl --user enable --now` without checking the app; the scenarios check it. It enables the unit only on a first install, so an upgrade over a disabled unit keeps it off — the macOS installer re-enables instead (see Open decisions). The systemd user-manager question is measured by the first run's environment step.
2a. **Measured** (run `40204212480`): Ubuntu 24.04.5, kernel 6.17 (azure). `runner` (uid 1001) is lingering with a reachable systemd user manager (`XDG_RUNTIME_DIR=/run/user/1001`), so autostart needs no setup. mpv is absent; the app boots without it.
3. **Design unification.** Copying the nine macOS scripts would make two representations of every install path. Instead each scenario is written once in `install-repro/scenarios/`, and `<platform>/platform` answers the service-manager questions (`service_manager_ok`, `service_autostarts`, `service_running`, `service_stop`, `assert_service_removed`). Per platform stay only `disabled-service` (the two platforms' rules differ), `environment` and `collect-evidence`. `install-repro-macos.yml` becomes `install-repro.yml` with a `platform` input.
4. **Plan unification.** The macOS scenarios moved, not copied (`git mv`), and run through the macOS adapter; the macOS lifecycle and update passed on the refactor before merge. The branch `push` trigger was scaffolding, removed before merge.
5. **Execution.** First Linux run green; the audit of the Linux installer's `2>/dev/null` uses (stop and disable at uninstall and `service remove`) found none on a step whose outcome no scenario checks.

- **Measure first:** does a systemd user manager run for `runner` (`systemctl --user status`, `loginctl show-user runner`, `XDG_RUNTIME_DIR`)? Can `loginctl enable-linger` start one? The Linux installer's autostart depends on it, as macOS's depended on the gui domain.
- **Port the scenarios:** `install-repro/scenarios/linux/`, sharing the macOS scenarios' structure. `disabled-unit` covers `systemctl --user disable` before an install. `manual-start` covers the release's `env.sh` loading `secrets.env` on Linux.
- **Apply M0's checks to Linux:** does the Linux installer hide errors with `2>/dev/null` where the outcome matters? Is its "loaded" state checked against systemd?
- **Done when** all nine scenarios pass against the latest release, or a scenario is dropped with a recorded reason.

### M2 — build from the branch ✅

- One build workflow (`workflow_call`) that both `release.yml` and the repro workflows call. It builds the release tarball for one platform from the checked-out ref.
- The repro workflows gain `source: branch`: build, then install the tarball through its bundled installer, as the public installer does. It replaces `installer: checkout`, which a full build covers.
- `in-app-update` stays `released`-only: it needs two published releases.
- **Done when** a `source: branch` run on macOS and Linux passes the install scenarios, and `release.yml` builds through the shared workflow with an identical tarball file list.

Record (2026-10-25):

1. **Scope.** The shared build workflow, `release.yml` on it, and `source: released|branch` in `install-repro.yml`. Dropped: `installer: checkout` — a branch build covers it.
2. **Research.** Each platform's release build takes about 1.5 minutes with caches. `Version.parse("1.60.4-branch.g3be7b8b")` parses as a pre-release, and the installers' tag pattern accepts it. A branch build's version must differ from the latest release, or `upgrade` would reinstall the same version and prove nothing.
3. **Design unification.** One build: `build-release.yml` (`workflow_call`, inputs `platform` and `version`) owns the platform → runner, tarball tag and required unit path mapping that `release.yml`'s matrix carried. It sets `mix.exs` to the given version (a no-op for a release); checking the tag against `mix.exs` stays in `release.yml`, a release rule. The scenarios get one `release_tarball` helper for every path that needs a tarball. Kept apart deliberately: the build's Linux runner (`ubuntu-22.04`, older glibc) and the test's (`ubuntu-24.04`).
4. **Plan unification.** `release.yml` keeps its publish job unchanged; only the build moved. The branch `push` trigger is scaffolding, removed before merge. `release.yml` can only be fully proven by a tag; `actionlint` passes on all workflows, and the repro exercises `build-release.yml` itself.
5. **Execution.** First run failed at compile: the build got the tag (`v1.60.4-…`) as its version; the resolve job now outputs the bare version. Second run (`40208897190`) green on both platforms; the branch build's tarball file lists equal v1.60.3's. The next tag is the first `release.yml` run on the shared build — `scripts/ship verify` checks its assets.

### M3 — runner VMs

- One boot script: download the cloud image (cached), write cloud-init `user-data` (a user with passwordless `sudo`, an SSH key), boot with QEMU/KVM, wait for SSH, run a scenario inside, copy evidence out. The same script runs on this machine.
- Distros: Debian 12 (oldest glibc of the set), Ubuntu 22.04, Ubuntu 24.04 (the Mint proxy), Fedora current.
- Per distro: `fresh-install`, `reinstall`, `upgrade`, `manual-start`, `uninstall`, `fresh-install-log`; `in-app-update` on Ubuntu 24.04.
- The VM needs a graphical-session-like user login only if M1 shows systemd user services need one; cloud images start a user manager on SSH login.
- **Done when** each distro passes its scenarios against the latest release.

### M4 — one dispatch, one summary

- One `install-repro.yml` dispatch fans out to every environment (macOS runner, ubuntu runner, each runner VM) and writes a table — environment × scenario, pass/fail, each linked to its evidence — to the run summary.
- **Done when** one `gh workflow run install-repro.yml` produces the full table.

## Completion criteria

* One dispatch runs the full matrix: macOS runner, bare ubuntu runner, and the four runner VMs.
* Every environment passes the scenario set against the latest release, or a scenario is dropped there with a recorded reason.
* `source: branch` proves an app-side and an installer fix on macOS and Linux before a tag.
* `install-repro/README.md` documents every environment, the sources, and how to run a scenario on a real machine.
* At least one shipped fix cites a repro run as its evidence. ✅ v1.60.2 (runs `40196579021`, `40197286363`).

## Pointers

* Scenarios: `install-repro/scenarios/` (shared) and `install-repro/scenarios/<platform>/`; README: `install-repro/README.md`
* Workflows: `.github/workflows/install-repro.yml` (the matrix), `.github/workflows/build-release.yml` (the one release build)
* Installers: `installer/install.sh` (public), `rel/platforms/linux/bin/media-centaur-install`, `rel/platforms/darwin/bin/media-centaur-install`
* Release build: `.github/workflows/release.yml`
* KVM on standard Linux runners: GitHub changelog, 2024-04-02, "GitHub Actions: hardware accelerated Android virtualization now available"
* The 2026-05-27 Phase 1 spec, `docs/superpowers/specs/2026-05-27-install-repro-env-design.md`, is historical: its libvirt driver is superseded.
* macOS platform features and parity: `campaigns/macos-platform-support.md`
