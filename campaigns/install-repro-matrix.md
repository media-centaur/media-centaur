---
status: planning
started: 2026-05-27
last_updated: 2026-06-10
---
# Install reproduction matrix

## Goal

Build out a multi-distro, snapshot-driven reproduction environment for the Media Centaur and prowlarr-stack installers, so install bugs can be proven, fixed, and kept-fixed across releases. Phase 1 (Linux Mint only) is a focused start — this campaign carries the larger roadmap from the brainstorm so the deferred decisions are not lost.

## Status

**Phase 1 in progress.** Brainstorm complete; design spec written at [`docs/superpowers/specs/2026-05-27-install-repro-env-design.md`](../docs/superpowers/specs/2026-05-27-install-repro-env-design.md). Implementation plan to be written next via the writing-plans skill. No code yet.

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

### Phase 7 — CI integration (only if/when warranted)

`larger` GitHub-hosted runner with KVM, or a self-hosted runner on a small workstation, running a subset of the matrix on release tag. Skip unless local iteration starts dropping regressions.

## Next steps

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

## Pointers

* Spec: [`docs/superpowers/specs/2026-05-27-install-repro-env-design.md`](../docs/superpowers/specs/2026-05-27-install-repro-env-design.md)
* Production installer: [`installer/install.sh`](../installer/install.sh)
* Bundled installer: `rel/platforms/linux/bin/media-centaur-install`
* prowlarr-stack installer: `../prowlarr-stack/install.sh`
* Wiki Installation page: `~/src/media-centaur/media-centaur.wiki/Installation.md`
* macOS reproduction is **not** in this campaign — see [`campaigns/macos-platform-support.md`](macos-platform-support.md) for that line of work.
