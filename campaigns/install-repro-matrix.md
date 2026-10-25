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
| **Scenario set** | The eight scenarios every platform implements: `sudo-refused`, `fresh-install`, `reinstall`, `disabled-label` (macOS) / `disabled-unit` (Linux), `manual-start`, `uninstall`, `fresh-install-log`, `in-app-update`. |
| **Environment** | Where a scenario runs: a **bare runner** (the GitHub-hosted machine itself), a **runner VM** (a cloud-image VM booted with QEMU/KVM inside a Linux runner), or a **real machine** by hand. |
| **Source** | What a run installs: `released` (the public install path for a published tag), `installer: checkout` (a released tarball with the branch's installer swapped in), or `branch` (a release built from the branch on the runner). |
| **Matrix** | The environments × the scenario set, run by one dispatch. |
| **Evidence** | What a job uploads whatever the outcome: app logs, update handoff logs, service-manager state, scenario output. |
| **macOS runner** | A GitHub-hosted Apple Silicon machine (`macos-14`). It has an Aqua `gui/501` login domain, so LaunchAgents load. |
| **LaunchAgent / label** | The launchd job that starts the app at login on macOS, named `com.media-centaur.app`. launchd keeps an enabled or disabled flag per label, separate from the plist file. |
| **gui domain** | launchd's per-user login session, `gui/<uid>`. |
| **Cloud image** | A distribution's official VM disk image that configures itself at first boot from cloud-init `user-data`. |

## Status

M0 (macOS) shipped in v1.60.2: the scenario set runs on the macOS runner and found four faults, all fixed. The redesign is decided. M1 (Linux on the bare ubuntu runner) is next.

## Principles

1. **Measure the environment before designing for it.** Every job starts with an environment step that prints the facts the scenarios depend on. An open question about the environment is answered by a temporary diagnostic step in one run, not by research alone.
2. **Assert outcomes, not reports.** A scenario checks the service manager, the port and the logs itself. The installer once printed a summary while `2>/dev/null` hid the failure underneath.
3. **Scenarios are plain scripts against the real installed paths.** The same script runs on a bare runner, in a runner VM and on a user's machine. The workflow is only the environment.
4. **Manual dispatch only.** Runs start when we decide, never from `release.yml` (owner, 2026-10-25).
5. **A fix carries its run.** A fix found by the matrix cites the run that found it, and is proven by a `checkout` or `branch` run before its tag where the source allows.
6. **No secrets in evidence.** `collect-evidence` never copies `secrets.env`, and diagnostics never print the process environment unfiltered.

## Open decisions

None open. Each milestone's design step records its own.

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
| M0 | macOS scenario set on the macOS runner | ✅ 2026-10-25 — eight scenarios, `install-repro-macos.yml` (dispatch, `installer: checkout`). Found four faults, all fixed in v1.60.2: reload over a running agent, Settings Stop, launchd detection, first-migration lock error. All install scenarios pass on v1.60.2. The in-app update result is in M0's notes below. |
| M1 | Linux scenario set on the bare `ubuntu-24.04` runner | open |
| M2 | `source: branch` — a release built from the branch, through a build workflow shared with `release.yml` | open |
| M3 | Runner VMs: Debian 12, Ubuntu 22.04, Ubuntu 24.04, Fedora (current) | open |
| M4 | One dispatch runs the whole matrix and writes a summary table | open |

### M0 — macOS (done)

Runs `40196579021`–`40199360910`. The macOS runner has an Aqua `gui/501` domain; mpv is absent and the app boots without it. Findings and fixes (v1.60.2):

- `launchctl bootout gui/<uid> <label>` reads the label as a plist path and fails with "Boot-out failed: 5". The installer hid it, so a reinstall or in-app update never reloaded the agent. The fix uses the service-target form `gui/<uid>/<label>`, then waits: launchd keeps the label about a second after bootout exits 0.
- `Platform.Autostart.Launchd.stop/1` used the same form.
- macOS 14 does not set `LAUNCHD_SOCKET`; launchd sets `XPC_SERVICE_NAME` to the label. The app now detects its agent by that.
- The migrator's two connections raced to switch a new database to WAL, logging "database is locked". Release tasks now use one connection (6/10 fresh databases logged it before, 0/10 after).
- The in-app update depends on GitHub's API, which a runner's shared IP often has rate-limited. The scenario waits for the reported reset once, then checks again.

Not fixed (`macos-platform-support.md` owns them): the Settings service card says "Not running under systemd." on macOS when the app was started by hand; `Apps.Launcher` runs `setsid`, which macOS lacks.

### M1 — Linux on the bare ubuntu runner

The Linux installer through the scenario set on `ubuntu-24.04`, `released` and `installer: checkout`.

- **Measure first:** does a systemd user manager run for `runner` (`systemctl --user status`, `loginctl show-user runner`, `XDG_RUNTIME_DIR`)? Can `loginctl enable-linger` start one? The Linux installer's autostart depends on it, as macOS's depended on the gui domain.
- **Port the scenarios:** `install-repro/scenarios/linux/`, sharing the macOS scenarios' structure. `disabled-unit` covers `systemctl --user disable` before an install. `manual-start` covers the release's `env.sh` loading `secrets.env` on Linux.
- **Apply M0's checks to Linux:** does the Linux installer hide errors with `2>/dev/null` where the outcome matters? Is its "loaded" state checked against systemd?
- **Done when** all eight scenarios pass against the latest release, or a scenario is dropped with a recorded reason.

### M2 — build from the branch

- One build workflow (`workflow_call`) that both `release.yml` and the repro workflows call. It builds the release tarball for one platform from the checked-out ref.
- The repro workflows gain `source: branch`: build, then install the tarball through its bundled installer, as the public installer does. It replaces `installer: checkout`, which a full build covers.
- `in-app-update` stays `released`-only: it needs two published releases.
- **Done when** a `source: branch` run on macOS and Linux passes the install scenarios, and `release.yml` builds through the shared workflow with an identical tarball file list.

### M3 — runner VMs

- One boot script: download the cloud image (cached), write cloud-init `user-data` (a user with passwordless `sudo`, an SSH key), boot with QEMU/KVM, wait for SSH, run a scenario inside, copy evidence out. The same script runs on this machine.
- Distros: Debian 12 (oldest glibc of the set), Ubuntu 22.04, Ubuntu 24.04 (the Mint proxy), Fedora current.
- Per distro: `fresh-install`, `reinstall`, `manual-start`, `uninstall`, `fresh-install-log`; `in-app-update` on Ubuntu 24.04.
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

* Scenarios: `install-repro/scenarios/macos/`; README: `install-repro/README.md`
* Workflow: `.github/workflows/install-repro-macos.yml`
* Installers: `installer/install.sh` (public), `rel/platforms/linux/bin/media-centaur-install`, `rel/platforms/darwin/bin/media-centaur-install`
* Release build: `.github/workflows/release.yml`
* KVM on standard Linux runners: GitHub changelog, 2024-04-02, "GitHub Actions: hardware accelerated Android virtualization now available"
* The 2026-05-27 Phase 1 spec, `docs/superpowers/specs/2026-05-27-install-repro-env-design.md`, is historical: its libvirt driver is superseded.
* macOS platform features and parity: `campaigns/macos-platform-support.md`
