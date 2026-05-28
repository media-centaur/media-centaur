# Install reproduction environment — design

**Date:** 2026-05-27
**Status:** Approved, planning
**Scope:** Phase 1 only — Linux Mint 22.3 Cinnamon. Multi-distro matrix and remote image hosting are tracked in [`campaigns/install-repro-matrix.md`](../../../campaigns/install-repro-matrix.md).

## Problem

When a tester installed Media Centaur on a fresh Linux Mint box, they hit several failures: missing OS packages, first-run / web-UI issues, and (for `prowlarr-stack`) Docker installed but not usable without `sudo`. We currently have no way to *reproduce* those failures locally — the developer's Arch box is too unlike a fresh Mint user-space to expose them. Without reproduction, we cannot prove a bug exists, cannot prove a fix works, and cannot keep either claim true across releases.

Mint specifically matters here because it is **Ubuntu 24.04-based but identifies itself by its own codename** (`xia` for 22.3). Several upstream apt repos — Docker's chief among them — key packages by `lsb_release -cs`, so the literal docker.com instructions return a 404 on Mint. The visible "Docker without sudo" symptom is almost certainly downstream of *that*.

## Goal

A repeatable Linux Mint 22.3 VM that boots in seconds from a known-clean snapshot, runs the production `curl | sh` installer (or a local tarball), and lets the developer observe both the failure and the fix without manual re-imaging.

## Scope (Phase 1)

In:

- One distro: **Linux Mint 22.3 Cinnamon, x86_64**.
- Two scenarios: `mc-fresh-install` (media-centaur via curl|sh) and `prowlarr-fresh-install` (prowlarr-stack via its own curl|sh).
- Driver script that handles VM lifecycle, snapshot reset, port forwarding, log capture.
- Web UI reachable on the host at `http://127.0.0.1:2160` while the VM is up.
- All artefacts the developer touches live in this repo at `install-repro/`. All heavy state (qcow2, snapshots, ISO cache, run logs) lives under XDG paths outside the repo.

Out (deferred to campaign):

- Any second distro (Debian 12, Ubuntu 24.04, Fedora 41, Pop!_OS).
- Pre-built shareable VM images (Packer + GHCR + signed manifest).
- Upgrade / uninstall-reinstall / `--from-local` scenarios.
- CI integration.
- macOS reproduction.

## Architecture

**Substrate:** **libvirt + QEMU/KVM**. Already available on the developer's Arch host. Other substrates were considered and rejected for Phase 1:

- LXC/Incus — Docker-in-container reproduces the failure mode less authentically; the very bug we want to reproduce (Docker post-install group setup on Mint) needs a real init system and real apt flow.
- Vagrant — wraps libvirt but adds a Ruby toolchain for marginal gain over a small driver script.
- Docker + systemd-in-container — DinD permissions don't faithfully match a real desktop user.

**Base image flow:** Mint ships no cloud image. We install Mint 22.3 Cinnamon from the official ISO **once, interactively, in virt-manager**, then take a libvirt **external snapshot** named `fresh-user`. Every subsequent test reverts to that snapshot — typically a sub-second operation. The interactive install is a one-time ~30–45 minute cost.

The snapshot represents *a real Mint user who just finished the installer and logged in for the first time*. No Media Centaur, no prowlarr-stack, no extra system packages — that is the state we want to test the installer against.

**VM specifics:**

- 2 vCPU, 4 GB RAM, 25 GB qcow2 disk.
- NAT network with a libvirt-managed forward of host `127.0.0.1:2160` → guest `:2160`.
- qemu-guest-agent installed (for ssh-key injection and `virsh shutdown`).
- One test user `tester` with passwordless `sudo` and an ssh key authorized — the key is generated on first `repro-vm up` if it doesn't exist (`~/.local/share/media-centaur-repro/keys/id_ed25519`).

**Snapshot strategy:** libvirt snapshots (the implementation may pick internal or external qcow2 chains — whichever gives sub-second revert in practice). Revert is a single driver verb (`repro-vm reset`); the developer never types `virsh` directly.

## Repo layout

```
install-repro/
├── README.md                       # workflow + how to bootstrap the VM the first time
├── bin/
│   └── repro-vm                    # driver script (bash; matches scripts/ convention)
├── scenarios/
│   ├── mc-fresh-install            # runs curl|sh inside the VM, captures output
│   └── prowlarr-fresh-install      # runs prowlarr-stack curl|sh inside the VM
└── fixtures/
    └── tmdb-key.placeholder        # clearly fake key, used by mc-fresh-install
```

No `matrix.toml`, no `seeds/`, no `packer/` yet — single-distro Phase 1 doesn't need that abstraction, and the campaign introduces it when the second distro lands.

## Out-of-repo paths

```
~/.local/share/media-centaur-repro/
├── vms/mint-22.3/
│   ├── disk.qcow2                  # base image after interactive Mint install
│   └── snapshots/                  # libvirt external snapshots
└── keys/
    └── id_ed25519, id_ed25519.pub  # ssh key injected into the test user

~/.cache/media-centaur-repro/
└── isos/
    └── linuxmint-22.3-cinnamon-64bit.iso

~/.local/state/media-centaur-repro/
└── runs/<UTC-timestamp>/
    ├── scenario.log                # captured stdout/stderr of the scenario
    ├── journalctl-user.log         # systemd user journal at end of run
    └── meta.json                   # scenario, distro, snapshot, mc version, exit code
```

`repro-vm wipe` deletes all three trees for a full reset.

## Driver CLI surface

The driver is a single bash script. Verbs:

| Verb | Behaviour |
|---|---|
| `repro-vm bootstrap`           | One-time interactive Mint install via virt-manager. Prompts the developer through the steps, then prompts them to confirm before taking the `fresh-user` snapshot. |
| `repro-vm up`                  | Boots the VM. Idempotent. |
| `repro-vm reset`               | Reverts to `fresh-user` snapshot and boots. The 95% verb. |
| `repro-vm ssh`                 | Opens an interactive ssh into `tester@<vm>`. |
| `repro-vm run <scenario>`      | Resets, boots, runs `scenarios/<scenario>` inside the VM, captures stdout/stderr/journal into `~/.local/state/.../runs/<timestamp>/`, prints a one-line summary. |
| `repro-vm down`                | Graceful shutdown. |
| `repro-vm port-forward`        | (Re)establishes the host `127.0.0.1:2160` → guest `:2160` forward; runs automatically on `up`/`reset`. |
| `repro-vm tail-logs`           | `tail -f` of the most recent run's `scenario.log`. |
| `repro-vm wipe`                | Destroys the VM, snapshots, ISO cache, and run logs. Confirms before deleting. |

The script takes an optional first positional `<distro>` defaulting to `mint-22.3` — present from day one so the multi-distro evolution doesn't require a CLI rewrite. Phase 1 only knows the one value; any other value errors out with "deferred to campaign".

## Scenarios (Phase 1)

Each scenario is a small shell script the driver `scp`s into the VM and runs over ssh. The scenario itself stays minimal — heavy lifting happens in the production installer, which is what we're testing.

### `scenarios/mc-fresh-install`

```sh
#!/bin/sh
set -eu
# Pre-flight: verify the OS packages the installer assumes are present
sudo apt-get update
sudo apt-get install -y sqlite3 mpv inotify-tools

# Run the production bootstrap
curl -fsSL https://raw.githubusercontent.com/media-centaur/media-centaur/main/installer/install.sh | sh

# Seed a placeholder TMDB key into the config so first-run doesn't block
install -m 0600 /home/tester/fixtures/tmdb-key.placeholder \
    ~/.config/media-centaur/secrets.tmdb-key || true

# Enable lingering so the user service survives ssh disconnect, then start it
loginctl enable-linger "$USER"
systemctl --user enable --now media-centaur.service

# Wait for the web UI to respond — bounded
for _ in $(seq 1 30); do
  curl -fsSL -o /dev/null http://127.0.0.1:2160/ && exit 0
  sleep 1
done
echo "web UI did not come up within 30s" >&2
exit 1
```

The fixtures dir is `scp`d into `/home/tester/fixtures/` by the driver before the scenario runs.

### `scenarios/prowlarr-fresh-install`

```sh
#!/bin/sh
set -eu
# Bare repro: run the prowlarr-stack installer with no prior setup.
# This is the failing path on Mint — Docker apt key + group membership.
curl -fsSL https://raw.githubusercontent.com/media-centaur/prowlarr-stack/main/install.sh | sh
docker ps   # The bug surface: prints permission-denied without sudo
```

The scenario is intentionally *not* protective — its job is to expose the failure, not to work around it.

## Networking

libvirt's default NAT network plus a host-side port forward from `127.0.0.1:2160` to the guest's `:2160`. The driver script encapsulates the actual mechanism (likely a `qemu-hook` script or a `socat` sidecar — picked during implementation), so the developer just runs `repro-vm port-forward` (or relies on the auto-invocation from `up`/`reset`).

The web UI is reachable from the host's Chromium / `chromium-probe` during the test, exactly as if the developer were the Mint user.

## Workflow

Reproducing and fixing a failure:

1. `repro-vm reset && repro-vm run mc-fresh-install`
2. Observe the failure — `repro-vm tail-logs`, or open `http://127.0.0.1:2160/` in Chromium.
3. Fix the installer / `installer/install.sh` / wiki on the host.
4. If the fix is in an unreleased branch: `repro-vm reset && repro-vm run mc-fresh-install --from-local _build/prod/rel/media_centaur/` *(deferred to campaign — Phase 1 always pulls from the latest released tarball)*.
5. Otherwise tag a release via `/ship`, then `repro-vm reset && repro-vm run mc-fresh-install`.
6. Watch the scenario exit 0 → fix confirmed against a fresh Mint user.

## Success criteria

Phase 1 is done when:

- A developer who has never touched `install-repro/` can run `repro-vm bootstrap` once (following the README), then `repro-vm run mc-fresh-install` and `repro-vm run prowlarr-fresh-install` repeatedly with no further setup.
- `repro-vm reset` returns to a known-clean Mint user state in under 10 seconds.
- Both scenarios capture a run-log under `~/.local/state/media-centaur-repro/runs/` that the developer can grep / paste into a bug report.
- The Docker-without-sudo failure on `prowlarr-fresh-install` is **observably reproduced** — that is the acceptance test for the whole reproduction environment.
- The README documents how the developer should report a bug they reproduce (which logs to attach, what version the VM is on).

## Out of scope (tracked in campaign)

- Adding any second distro.
- Pre-built shareable VM images.
- `--from-local` scenarios for unreleased code.
- Upgrade / uninstall-reinstall scenarios.
- Trust/verifiability (Sigstore signing).
- CI integration.
- macOS reproduction.

See [`campaigns/install-repro-matrix.md`](../../../campaigns/install-repro-matrix.md) for the roadmap and the decisions captured during this brainstorm so they don't get lost.
