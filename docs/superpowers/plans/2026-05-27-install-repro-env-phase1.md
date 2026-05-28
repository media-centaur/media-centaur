# Install reproduction environment — Phase 1 implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Linux-Mint-22.3 reproduction VM driven by a single bash script (`install-repro/bin/repro-vm`), with two scenarios that exercise the production `media-centaur` and `prowlarr-stack` installers and capture run-logs for evidence.

**Architecture:** libvirt+QEMU/KVM substrate on the developer's Arch host; one VM bootstrapped interactively from the official Mint ISO and snapshotted to `fresh-user`; subsequent runs revert the snapshot in seconds. Heavy state lives under XDG paths outside the repo; only the driver, scenarios, fixtures and README are tracked.

**Tech Stack:** bash, libvirt (`virsh`, `virt-install`, `virt-manager`), QEMU/KVM, `qemu-img`, `socat` (port forwarding), `ssh`, `shellcheck` (lint).

**Spec:** [`docs/superpowers/specs/2026-05-27-install-repro-env-design.md`](../specs/2026-05-27-install-repro-env-design.md)
**Campaign (Phase 2+ roadmap):** [`campaigns/install-repro-matrix.md`](../../../campaigns/install-repro-matrix.md)

---

## File map

| Path | Created/Modified | Responsibility |
|---|---|---|
| `install-repro/README.md` | Create | Developer-facing workflow + bootstrap walkthrough |
| `install-repro/bin/repro-vm` | Create | The single driver script (all verbs) |
| `install-repro/scenarios/mc-fresh-install` | Create | Production media-centaur curl\|sh + web-UI smoke |
| `install-repro/scenarios/prowlarr-fresh-install` | Create | Production prowlarr-stack curl\|sh; deliberately exposes the Docker-without-sudo bug |
| `install-repro/fixtures/tmdb-key.placeholder` | Create | Clearly-fake TMDB key seeded into config so first-run isn't blocked |
| `campaigns/install-repro-matrix.md` | Modify | Bump `last_updated`; mark Phase 1 status as `in progress (implementing)` |
| `CLAUDE.md` | Modify | One-line pointer to `install-repro/README.md` under the existing layout map |

No files under `~/.local/...` are committed. Driver creates them lazily on first invocation.

---

## Conventions

- All steps use `bash` (project precedent — `scripts/screenshot-tour`, `scripts/preflight` etc. are bash). The driver itself has a `#!/usr/bin/env bash` shebang and `set -euo pipefail`.
- Every script-touching task ends with `shellcheck` and a no-op invocation as a smoke gate.
- Commits use conventional commits (`feat:`, `chore:`, `docs:`) per `CLAUDE.md`. **No `Co-Authored-By: Claude` trailers** (per user memory).
- VM name: `mc-repro-mint-22.3`. Snapshot name: `fresh-user`. SSH user inside the guest: `tester`.
- Heavy paths used throughout:
  - `STATE="$HOME/.local/share/media-centaur-repro"`
  - `CACHE="$HOME/.cache/media-centaur-repro"`
  - `RUNS="$HOME/.local/state/media-centaur-repro/runs"`

---

### Task 1: Install host substrate (libvirt + QEMU/KVM + helpers)

**Files:** none committed; host-side packages only.

- [ ] **Step 1: Install packages on the Arch host**

```bash
sudo pacman -S --needed libvirt qemu-desktop virt-install virt-manager dnsmasq iptables-nft bridge-utils edk2-ovmf socat shellcheck
```

- [ ] **Step 2: Enable & start libvirt**

```bash
sudo systemctl enable --now libvirtd.socket
sudo systemctl start libvirtd
```

- [ ] **Step 3: Add the developer to the `libvirt` group (needed for non-root `virsh`)**

```bash
sudo usermod -aG libvirt "$USER"
# A logout/login is required for the group to take effect. If already logged in,
# use `newgrp libvirt` in the shell that will run the driver.
```

- [ ] **Step 4: Verify the default network is up and reachable**

Run:

```bash
sudo virsh net-list --all
sudo virsh net-start default || true
sudo virsh net-autostart default
```

Expected: `default` appears as `active` + `yes` (autostart) in the list.

- [ ] **Step 5: Smoke-test KVM availability**

Run:

```bash
test -w /dev/kvm && echo "kvm ok"
virt-host-validate qemu 2>&1 | head -30
```

Expected: `kvm ok`; `virt-host-validate` shows mostly `PASS`. Any `FAIL` on the QEMU section is a blocker — resolve before continuing.

- [ ] **Step 6: No commit (host setup is not in the repo).**

---

### Task 2: Scaffold the `install-repro/` directory tree

**Files:**
- Create: `install-repro/bin/.gitkeep`
- Create: `install-repro/scenarios/.gitkeep`
- Create: `install-repro/fixtures/.gitkeep`

- [ ] **Step 1: Create the directory skeleton**

```bash
cd /home/shawn/src/media-centaur/media-centaur-app
mkdir -p install-repro/bin install-repro/scenarios install-repro/fixtures
touch install-repro/bin/.gitkeep install-repro/scenarios/.gitkeep install-repro/fixtures/.gitkeep
```

- [ ] **Step 2: Verify**

```bash
find install-repro -type d
```

Expected:

```
install-repro
install-repro/bin
install-repro/scenarios
install-repro/fixtures
```

- [ ] **Step 3: Commit**

```bash
git add install-repro/
git commit -m "chore(install-repro): scaffold directory tree"
```

---

### Task 3: Write the driver skeleton with verb dispatch

**Files:**
- Create: `install-repro/bin/repro-vm`

- [ ] **Step 1: Write the skeleton**

Create `install-repro/bin/repro-vm` with executable permission. The skeleton defines paths, prints usage, and dispatches verbs to stub functions that print "not yet implemented". Each later task replaces one stub.

```bash
#!/usr/bin/env bash
# repro-vm — install reproduction VM driver (Phase 1: Mint 22.3 only)
#
# See install-repro/README.md for the developer workflow.

set -euo pipefail

# ---- paths ----------------------------------------------------------------
STATE="${MC_REPRO_STATE:-$HOME/.local/share/media-centaur-repro}"
CACHE="${MC_REPRO_CACHE:-$HOME/.cache/media-centaur-repro}"
RUNS="${MC_REPRO_RUNS:-$HOME/.local/state/media-centaur-repro/runs}"

# ---- distro pin (Phase 1: Mint only) --------------------------------------
DISTRO_DEFAULT="mint-22.3"
VM_NAME="mc-repro-mint-22.3"
SNAPSHOT_NAME="fresh-user"
GUEST_USER="tester"
HOST_FORWARD_PORT="2160"

# Mint 22.3 Cinnamon — official mirror. SHA from Mint's release notes.
MINT_ISO_URL="https://mirrors.edge.kernel.org/linuxmint/stable/22.3/linuxmint-22.3-cinnamon-64bit.iso"
MINT_ISO_FILE="linuxmint-22.3-cinnamon-64bit.iso"
# NOTE: pin sha256 in Task 5 once verified against the live mirror; placeholder used
# only during skeleton bring-up.
MINT_ISO_SHA256="PLACEHOLDER_REPLACE_IN_TASK_5"

# ---- utilities ------------------------------------------------------------
die()    { printf 'repro-vm: error: %s\n' "$*" >&2; exit 1; }
banner() { printf '==> %s\n' "$*"; }
ensure_dirs() {
    mkdir -p "$STATE/vms/$DISTRO_DEFAULT" "$STATE/keys" "$CACHE/isos" "$RUNS"
}

require_distro() {
    if [[ "${1:-$DISTRO_DEFAULT}" != "$DISTRO_DEFAULT" ]]; then
        die "distro '${1}' is deferred to campaigns/install-repro-matrix.md (Phase 1 = $DISTRO_DEFAULT only)"
    fi
}

usage() {
    cat <<EOF
repro-vm — install reproduction VM driver (Phase 1: $DISTRO_DEFAULT only)

Usage:
  repro-vm bootstrap [<distro>]        One-time interactive Mint install + snapshot
  repro-vm up [<distro>]               Boot the VM
  repro-vm reset [<distro>]            Revert to fresh-user snapshot and boot
  repro-vm ssh [<distro>]              SSH into tester@<vm>
  repro-vm run <scenario> [<distro>]   Reset, boot, run scenario, capture logs
  repro-vm down [<distro>]             Graceful shutdown
  repro-vm port-forward [<distro>]     (Re)establish host :$HOST_FORWARD_PORT forward
  repro-vm tail-logs                   tail -f the most recent run's scenario.log
  repro-vm wipe                        Destroy VM, snapshots, ISO cache, run logs

<distro> defaults to '$DISTRO_DEFAULT'. Other distros are tracked in
campaigns/install-repro-matrix.md and will error out today.
EOF
}

# ---- verb stubs (replaced in later tasks) ---------------------------------
cmd_bootstrap()    { die "bootstrap not yet implemented (Task 6)"; }
cmd_up()           { die "up not yet implemented (Task 7)"; }
cmd_reset()        { die "reset not yet implemented (Task 9)"; }
cmd_ssh()          { die "ssh not yet implemented (Task 7)"; }
cmd_run()          { die "run not yet implemented (Task 10)"; }
cmd_down()         { die "down not yet implemented (Task 7)"; }
cmd_port_forward() { die "port-forward not yet implemented (Task 8)"; }
cmd_tail_logs()    { die "tail-logs not yet implemented (Task 11)"; }
cmd_wipe()         { die "wipe not yet implemented (Task 11)"; }

# ---- dispatch -------------------------------------------------------------
main() {
    ensure_dirs
    local verb="${1:-}"
    [[ -z "$verb" ]] && { usage; exit 0; }
    shift
    case "$verb" in
        bootstrap)    require_distro "${1:-}"; cmd_bootstrap    "$@" ;;
        up)           require_distro "${1:-}"; cmd_up           "$@" ;;
        reset)        require_distro "${1:-}"; cmd_reset        "$@" ;;
        ssh)          require_distro "${1:-}"; cmd_ssh          "$@" ;;
        run)          [[ $# -ge 1 ]] || die "run needs a scenario name"
                      require_distro "${2:-}"; cmd_run "$@" ;;
        down)         require_distro "${1:-}"; cmd_down         "$@" ;;
        port-forward) require_distro "${1:-}"; cmd_port_forward "$@" ;;
        tail-logs)    cmd_tail_logs    "$@" ;;
        wipe)         cmd_wipe         "$@" ;;
        -h|--help|help) usage ;;
        *) usage; die "unknown verb: $verb" ;;
    esac
}

main "$@"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x install-repro/bin/repro-vm
```

- [ ] **Step 3: Lint with shellcheck**

```bash
shellcheck install-repro/bin/repro-vm
```

Expected: exit 0, no output.

- [ ] **Step 4: Smoke-test dispatch**

```bash
install-repro/bin/repro-vm
install-repro/bin/repro-vm help
install-repro/bin/repro-vm up && echo SHOULD_NOT_REACH || echo "stub errored as expected"
install-repro/bin/repro-vm up debian-12 && echo SHOULD_NOT_REACH || echo "distro guard tripped as expected"
```

Expected (in order): usage printed; usage printed; "up not yet implemented (Task 7)"; "distro 'debian-12' is deferred …".

- [ ] **Step 5: Commit**

```bash
git add install-repro/bin/repro-vm
git commit -m "feat(install-repro): driver skeleton with verb dispatch and distro guard"
```

---

### Task 4: Generate the host-side SSH key once, on demand

**Files:**
- Modify: `install-repro/bin/repro-vm` (replace `ensure_dirs`; add `ensure_ssh_key`)

- [ ] **Step 1: Update the script**

Replace `ensure_dirs` with:

```bash
ensure_dirs() {
    mkdir -p "$STATE/vms/$DISTRO_DEFAULT" "$STATE/keys" "$CACHE/isos" "$RUNS"
    chmod 700 "$STATE/keys"
}

ensure_ssh_key() {
    local key="$STATE/keys/id_ed25519"
    if [[ ! -f "$key" ]]; then
        banner "Generating host-side ssh key at $key"
        ssh-keygen -t ed25519 -N "" -C "media-centaur-repro" -f "$key" >/dev/null
    fi
    printf '%s' "$key"
}
```

Call `ensure_ssh_key >/dev/null` once at the top of `main`, after `ensure_dirs`.

- [ ] **Step 2: Lint + smoke-test**

```bash
shellcheck install-repro/bin/repro-vm
install-repro/bin/repro-vm help
ls -l ~/.local/share/media-centaur-repro/keys/
```

Expected: shellcheck clean; usage prints; `id_ed25519` + `id_ed25519.pub` exist with `chmod 600`/`644`.

- [ ] **Step 3: Commit**

```bash
git add install-repro/bin/repro-vm
git commit -m "feat(install-repro): generate host-side ssh key lazily"
```

---

### Task 5: Pin the Mint ISO sha256 and add an `iso_present` helper

**Files:**
- Modify: `install-repro/bin/repro-vm` (replace `MINT_ISO_SHA256`; add `ensure_iso`)

- [ ] **Step 1: Resolve the real sha256 from Mint's published checksum**

Mint publishes `sha256sum.txt` next to the ISO on the same mirror. Resolve it:

```bash
curl -fsSL https://mirrors.edge.kernel.org/linuxmint/stable/22.3/sha256sum.txt \
  | awk '/linuxmint-22.3-cinnamon-64bit.iso/ {print $1}'
```

Capture that hash and use it verbatim in Step 2. If the mirror is unreachable, fall back to `https://www.linuxmint.com/edition.php?id=323` (release notes) which links the same `sha256sum.txt` from the official site.

- [ ] **Step 2: Replace the placeholder and add `ensure_iso`**

```bash
MINT_ISO_SHA256="<paste-the-hash-from-step-1>"
```

Add the helper:

```bash
ensure_iso() {
    local iso="$CACHE/isos/$MINT_ISO_FILE"
    if [[ -f "$iso" ]]; then
        printf '%s  %s\n' "$MINT_ISO_SHA256" "$iso" | sha256sum -c - >/dev/null 2>&1 \
            && { printf '%s' "$iso"; return; } \
            || { banner "Cached ISO failed sha256 — re-downloading"; rm -f "$iso"; }
    fi
    banner "Downloading $MINT_ISO_FILE (~3 GB)"
    curl -fL --progress-bar -o "$iso" "$MINT_ISO_URL"
    printf '%s  %s\n' "$MINT_ISO_SHA256" "$iso" | sha256sum -c - >/dev/null \
        || die "Mint ISO sha256 mismatch — refusing to use"
    printf '%s' "$iso"
}
```

- [ ] **Step 3: Lint**

```bash
shellcheck install-repro/bin/repro-vm
```

Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add install-repro/bin/repro-vm
git commit -m "feat(install-repro): pin Mint ISO sha256 and add cache-aware download"
```

---

### Task 6: Implement `bootstrap` — interactive Mint install + snapshot

**Files:**
- Modify: `install-repro/bin/repro-vm` (replace `cmd_bootstrap`)

This verb is half-automated: VM creation and snapshot capture are scripted; the actual OS install through Mint's Calamares installer is interactive in the spawned `virt-viewer` window.

- [ ] **Step 1: Replace the stub**

```bash
cmd_bootstrap() {
    if virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
        die "VM '$VM_NAME' already exists — run 'wipe' first if you want to redo bootstrap"
    fi
    local iso; iso=$(ensure_iso)
    local disk="$STATE/vms/$DISTRO_DEFAULT/disk.qcow2"
    mkdir -p "$(dirname "$disk")"
    if [[ ! -f "$disk" ]]; then
        banner "Creating $disk (25 GB sparse qcow2)"
        qemu-img create -f qcow2 "$disk" 25G >/dev/null
    fi

    banner "Launching virt-install — Calamares will open in virt-viewer"
    cat <<EOF
=== Manual steps inside the installer window ===
  - Language/keyboard: defaults are fine
  - User: create username '$GUEST_USER', password 'tester' (will be replaced by ssh key)
  - Install Mint to the 25G virtual disk; do NOT install third-party codecs
    (keeps the snapshot small and representative)
  - At the end, REBOOT inside the VM and LOG IN ONCE so the first-login
    profile setup runs to completion. THEN power off the VM (System menu).
  - Return to this terminal — bootstrap will resume.
===
EOF
    virt-install \
        --name "$VM_NAME" \
        --memory 4096 --vcpus 2 \
        --cpu host-passthrough \
        --osinfo linuxmint22 \
        --disk path="$disk",format=qcow2,bus=virtio \
        --cdrom "$iso" \
        --network network=default,model=virtio \
        --graphics spice \
        --noautoconsole \
        --wait -1
    # virt-install --wait -1 blocks until the guest shuts down (i.e. when the
    # developer powers it off after first login).

    banner "Detaching the install CD-ROM so subsequent boots are from disk"
    virsh change-media "$VM_NAME" sda --eject --config || true

    banner "Booting the VM to inject the host ssh key"
    cmd_up
    inject_ssh_key

    banner "Powering off cleanly"
    virsh shutdown "$VM_NAME" || true
    # Wait up to 60s for shutdown
    for _ in $(seq 1 60); do
        virsh domstate "$VM_NAME" | grep -q "shut off" && break
        sleep 1
    done

    banner "Taking snapshot '$SNAPSHOT_NAME'"
    virsh snapshot-create-as "$VM_NAME" "$SNAPSHOT_NAME" \
        --description "fresh Mint $DISTRO_DEFAULT user, no media-centaur" \
        --atomic
    banner "Bootstrap complete. Use 'repro-vm reset && repro-vm run <scenario>'."
}

inject_ssh_key() {
    local key_pub; key_pub="$(ensure_ssh_key).pub"
    # Wait for ssh to come up
    local ip; ip=$(wait_for_guest_ip)
    banner "Guest is at $ip; copying key (one-time password prompt)"
    # On first run the password is 'tester' (set during Calamares); after this
    # the key is authorized and we never type the password again.
    ssh-copy-id -i "$key_pub" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$GUEST_USER@$ip"
}

wait_for_guest_ip() {
    local ip="" mac
    mac=$(virsh domiflist "$VM_NAME" | awk '/network/ {print $5}')
    for _ in $(seq 1 60); do
        ip=$(virsh net-dhcp-leases default | awk -v m="$mac" '$0 ~ m {print $5}' | cut -d/ -f1)
        [[ -n "$ip" ]] && { printf '%s' "$ip"; return; }
        sleep 2
    done
    die "Could not resolve guest IP from DHCP leases after 120s"
}
```

- [ ] **Step 2: Lint**

```bash
shellcheck install-repro/bin/repro-vm
```

Expected: clean.

- [ ] **Step 3: Verify the verb error-paths**

(We are not yet running the real bootstrap — that's a ~45 min interactive procedure deferred to Task 13. Just verify the verb is reachable.)

```bash
# Pretend the VM exists to hit the early die branch
virsh list --all | grep -q mc-repro-mint-22.3 && echo "(skip dry-run, real VM present)" \
                                               || install-repro/bin/repro-vm bootstrap </dev/null 2>&1 | head -5
```

The exact output depends on whether a stale VM lingers; the important thing is no syntax error and the script doesn't blow past `ensure_iso` (which would start the download).

- [ ] **Step 4: Commit**

```bash
git add install-repro/bin/repro-vm
git commit -m "feat(install-repro): bootstrap verb — interactive Mint install + snapshot"
```

---

### Task 7: Implement `up`, `down`, `ssh`

**Files:**
- Modify: `install-repro/bin/repro-vm` (replace `cmd_up`, `cmd_down`, `cmd_ssh`)

- [ ] **Step 1: Replace the stubs**

```bash
cmd_up() {
    virsh dominfo "$VM_NAME" >/dev/null 2>&1 \
        || die "VM not found — run 'repro-vm bootstrap' first"
    if virsh domstate "$VM_NAME" | grep -q running; then
        banner "VM is already running"
    else
        banner "Starting $VM_NAME"
        virsh start "$VM_NAME"
    fi
    # Wait for ssh to answer
    local ip; ip=$(wait_for_guest_ip)
    for _ in $(seq 1 30); do
        ssh -i "$(ensure_ssh_key)" \
            -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=2 -o BatchMode=yes \
            "$GUEST_USER@$ip" true 2>/dev/null && { banner "SSH ready at $ip"; printf '%s\n' "$ip" > "$STATE/vms/$DISTRO_DEFAULT/ip"; return; }
        sleep 2
    done
    die "SSH did not come up within 60s"
}

cmd_down() {
    if virsh domstate "$VM_NAME" 2>/dev/null | grep -q running; then
        banner "Shutting down $VM_NAME"
        virsh shutdown "$VM_NAME"
        for _ in $(seq 1 60); do
            virsh domstate "$VM_NAME" | grep -q "shut off" && return
            sleep 1
        done
        banner "Graceful shutdown timed out — forcing"
        virsh destroy "$VM_NAME" || true
    fi
}

cmd_ssh() {
    cmd_up
    local ip; ip=$(cat "$STATE/vms/$DISTRO_DEFAULT/ip")
    ssh -i "$(ensure_ssh_key)" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$GUEST_USER@$ip"
}
```

- [ ] **Step 2: Lint**

```bash
shellcheck install-repro/bin/repro-vm
```

Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add install-repro/bin/repro-vm
git commit -m "feat(install-repro): up/down/ssh verbs"
```

---

### Task 8: Implement `port-forward` via `socat`

**Files:**
- Modify: `install-repro/bin/repro-vm` (replace `cmd_port_forward`; auto-invoke from `up`)

`socat` is the simplest reliable approach for a single port. The forwarder runs on the host as a background process; a PID file in `$STATE` lets us stop the previous one before starting a new one.

- [ ] **Step 1: Replace the stub and call it from `up`**

```bash
cmd_port_forward() {
    local pidfile="$STATE/vms/$DISTRO_DEFAULT/portforward.pid"
    if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
        kill "$(cat "$pidfile")" || true
        sleep 0.5
    fi
    local ip; ip=$(cat "$STATE/vms/$DISTRO_DEFAULT/ip" 2>/dev/null) \
        || die "VM not up — run 'repro-vm up' first"
    banner "Forwarding host 127.0.0.1:$HOST_FORWARD_PORT → $ip:$HOST_FORWARD_PORT"
    nohup socat \
        TCP-LISTEN:"$HOST_FORWARD_PORT",bind=127.0.0.1,reuseaddr,fork \
        TCP:"$ip":"$HOST_FORWARD_PORT" \
        >/dev/null 2>&1 &
    echo $! > "$pidfile"
}
```

At the end of `cmd_up` (after the "SSH ready" line and writing the ip file), add:

```bash
    cmd_port_forward
```

And at the start of `cmd_down`, before the shutdown block, add:

```bash
    local pidfile="$STATE/vms/$DISTRO_DEFAULT/portforward.pid"
    [[ -f "$pidfile" ]] && kill "$(cat "$pidfile")" 2>/dev/null || true
    rm -f "$pidfile"
```

- [ ] **Step 2: Lint**

```bash
shellcheck install-repro/bin/repro-vm
```

Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add install-repro/bin/repro-vm
git commit -m "feat(install-repro): host:2160 port forward via socat sidecar"
```

---

### Task 9: Implement `reset` — snapshot revert + up

**Files:**
- Modify: `install-repro/bin/repro-vm` (replace `cmd_reset`)

- [ ] **Step 1: Replace the stub**

```bash
cmd_reset() {
    virsh snapshot-info "$VM_NAME" "$SNAPSHOT_NAME" >/dev/null 2>&1 \
        || die "snapshot '$SNAPSHOT_NAME' not found — run 'repro-vm bootstrap' first"
    if virsh domstate "$VM_NAME" | grep -q running; then
        banner "Stopping VM before snapshot revert"
        virsh destroy "$VM_NAME" >/dev/null
    fi
    banner "Reverting to snapshot '$SNAPSHOT_NAME'"
    virsh snapshot-revert "$VM_NAME" "$SNAPSHOT_NAME" --running
    local ip; ip=$(wait_for_guest_ip)
    # Refresh the ip file and port-forward (snapshot revert may give a new DHCP lease)
    printf '%s\n' "$ip" > "$STATE/vms/$DISTRO_DEFAULT/ip"
    cmd_port_forward
}
```

- [ ] **Step 2: Lint**

```bash
shellcheck install-repro/bin/repro-vm
```

Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add install-repro/bin/repro-vm
git commit -m "feat(install-repro): reset verb — revert snapshot and re-forward"
```

---

### Task 10: Implement `run <scenario>` — execute, capture, summarize

**Files:**
- Modify: `install-repro/bin/repro-vm` (replace `cmd_run`)

- [ ] **Step 1: Replace the stub**

```bash
cmd_run() {
    local scenario="$1"; shift
    local repo_root scenario_file
    repo_root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
    scenario_file="$repo_root/install-repro/scenarios/$scenario"
    [[ -x "$scenario_file" ]] \
        || die "scenario not found or not executable: $scenario_file"

    cmd_reset

    local ts run_dir ip key
    ts=$(date -u +%Y-%m-%dT%H-%M-%SZ)
    run_dir="$RUNS/$ts-$scenario"
    mkdir -p "$run_dir"
    ip=$(cat "$STATE/vms/$DISTRO_DEFAULT/ip")
    key=$(ensure_ssh_key)

    banner "Copying scenario + fixtures into the guest"
    scp -i "$key" -q \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$scenario_file" "$GUEST_USER@$ip:/home/$GUEST_USER/scenario.sh"
    scp -i "$key" -qr \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$repo_root/install-repro/fixtures" "$GUEST_USER@$ip:/home/$GUEST_USER/"

    banner "Running scenario '$scenario' in guest (capturing to $run_dir/scenario.log)"
    set +e
    ssh -i "$key" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$GUEST_USER@$ip" "chmod +x /home/$GUEST_USER/scenario.sh && /home/$GUEST_USER/scenario.sh" \
        2>&1 | tee "$run_dir/scenario.log"
    local exit_code="${PIPESTATUS[0]}"
    set -e

    banner "Capturing systemd user journal"
    ssh -i "$key" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$GUEST_USER@$ip" "journalctl --user --no-pager || true" \
        > "$run_dir/journalctl-user.log" 2>&1 || true

    cat > "$run_dir/meta.json" <<EOF
{
  "scenario": "$scenario",
  "distro": "$DISTRO_DEFAULT",
  "vm": "$VM_NAME",
  "snapshot": "$SNAPSHOT_NAME",
  "guest_ip": "$ip",
  "exit_code": $exit_code,
  "started_utc": "$ts"
}
EOF

    banner "Run complete. Exit: $exit_code. Logs: $run_dir"
    return "$exit_code"
}
```

- [ ] **Step 2: Lint**

```bash
shellcheck install-repro/bin/repro-vm
```

Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add install-repro/bin/repro-vm
git commit -m "feat(install-repro): run verb — execute scenario, capture logs"
```

---

### Task 11: Implement `tail-logs` and `wipe`

**Files:**
- Modify: `install-repro/bin/repro-vm` (replace `cmd_tail_logs`, `cmd_wipe`)

- [ ] **Step 1: Replace the stubs**

```bash
cmd_tail_logs() {
    local latest
    latest=$(ls -1dt "$RUNS"/*/ 2>/dev/null | head -1) \
        || die "no runs found under $RUNS"
    [[ -n "$latest" ]] || die "no runs found under $RUNS"
    tail -f "$latest/scenario.log"
}

cmd_wipe() {
    printf 'This will destroy:\n  VM: %s\n  State: %s\n  Cache: %s\n  Runs: %s\nProceed? [y/N] ' \
        "$VM_NAME" "$STATE" "$CACHE" "$RUNS"
    read -r reply
    [[ "$reply" =~ ^[yY]$ ]] || { banner "Aborted"; return; }

    local pidfile="$STATE/vms/$DISTRO_DEFAULT/portforward.pid"
    [[ -f "$pidfile" ]] && kill "$(cat "$pidfile")" 2>/dev/null || true

    if virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
        virsh destroy "$VM_NAME" 2>/dev/null || true
        # Delete snapshots first (some libvirt versions block undefine otherwise)
        for snap in $(virsh snapshot-list "$VM_NAME" --name 2>/dev/null); do
            virsh snapshot-delete "$VM_NAME" "$snap" 2>/dev/null || true
        done
        virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
    fi

    rm -rf "$STATE" "$CACHE" "$RUNS"
    banner "Wiped."
}
```

- [ ] **Step 2: Lint + smoke**

```bash
shellcheck install-repro/bin/repro-vm
echo n | install-repro/bin/repro-vm wipe
```

Expected: shellcheck clean; wipe prompts and "Aborted" on `n`.

- [ ] **Step 3: Commit**

```bash
git add install-repro/bin/repro-vm
git commit -m "feat(install-repro): tail-logs and wipe verbs"
```

---

### Task 12: Write fixtures + scenarios

**Files:**
- Create: `install-repro/fixtures/tmdb-key.placeholder`
- Create: `install-repro/scenarios/mc-fresh-install`
- Create: `install-repro/scenarios/prowlarr-fresh-install`
- Delete: `install-repro/fixtures/.gitkeep`, `install-repro/scenarios/.gitkeep`

- [ ] **Step 1: Write the placeholder TMDB key**

`install-repro/fixtures/tmdb-key.placeholder`:

```
0000000000000000000000000000000000000000
# This is a placeholder TMDB key. It is intentionally NOT a real key.
# The reproduction environment seeds it so the first-run wizard does not
# block on the API key prompt. TMDB lookups will fail; that is expected.
# Replace with a real key only if you need to exercise live TMDB calls.
```

- [ ] **Step 2: Write `mc-fresh-install`**

`install-repro/scenarios/mc-fresh-install`:

```bash
#!/bin/sh
# mc-fresh-install — exercise the production media-centaur curl|sh on a fresh
# Mint user. Acceptance: web UI answers on 127.0.0.1:2160 within 30s.

set -eu

echo "=== apt: install runtime deps the wiki says to install ==="
sudo apt-get update
sudo apt-get install -y sqlite3 mpv inotify-tools

echo "=== curl|sh: production bootstrap ==="
curl -fsSL https://raw.githubusercontent.com/media-centaur/media-centaur/main/installer/install.sh | sh

echo "=== seed placeholder TMDB key so first-run does not block ==="
mkdir -p "$HOME/.config/media-centaur"
install -m 0600 "$HOME/fixtures/tmdb-key.placeholder" \
    "$HOME/.config/media-centaur/secrets.tmdb-key" || true

echo "=== enable lingering + start the user service ==="
loginctl enable-linger "$(whoami)"
systemctl --user daemon-reload
systemctl --user enable --now media-centaur.service

echo "=== wait up to 30s for the web UI ==="
i=0
while [ "$i" -lt 30 ]; do
    if curl -fsS -o /dev/null http://127.0.0.1:2160/; then
        echo "OK: web UI responded after ${i}s"
        exit 0
    fi
    i=$((i + 1))
    sleep 1
done
echo "FAIL: web UI did not come up within 30s"
systemctl --user status media-centaur.service --no-pager || true
exit 1
```

- [ ] **Step 3: Write `prowlarr-fresh-install`**

`install-repro/scenarios/prowlarr-fresh-install`:

```bash
#!/bin/sh
# prowlarr-fresh-install — exercise the production prowlarr-stack curl|sh on a
# fresh Mint user. Deliberately does NOT pre-configure docker — the bug this
# reproduces is "docker installed but not usable without sudo", and the
# scenario's job is to expose it, not work around it.

set -eu

echo "=== curl|sh: production prowlarr-stack bootstrap ==="
curl -fsSL https://raw.githubusercontent.com/media-centarr/prowlarr-stack/main/install.sh | sh

echo "=== bug-surface check: docker without sudo ==="
echo "(expected to fail with permission-denied on a fresh Mint until installer fixes the group)"
docker ps
```

- [ ] **Step 4: Make scenarios executable, drop the gitkeeps**

```bash
chmod +x install-repro/scenarios/mc-fresh-install install-repro/scenarios/prowlarr-fresh-install
rm install-repro/scenarios/.gitkeep install-repro/fixtures/.gitkeep
```

- [ ] **Step 5: Lint the scenarios**

```bash
shellcheck install-repro/scenarios/mc-fresh-install install-repro/scenarios/prowlarr-fresh-install
```

Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add install-repro/scenarios install-repro/fixtures
git commit -m "feat(install-repro): mc-fresh-install + prowlarr-fresh-install scenarios"
```

---

### Task 13: Bootstrap the Mint VM (interactive, one-time)

**Files:** none committed; produces `~/.local/share/media-centaur-repro/vms/mint-22.3/disk.qcow2` and a `fresh-user` snapshot.

This task is genuinely interactive — budget 45 minutes for the Mint install + first-login. Cannot be automated further without a full autoinstall harness, which is Phase-4 work.

- [ ] **Step 1: Run bootstrap**

```bash
install-repro/bin/repro-vm bootstrap
```

Expected sequence:

1. `==> Downloading linuxmint-22.3-cinnamon-64bit.iso (~3 GB)` — first time only.
2. `==> Launching virt-install — Calamares will open in virt-viewer`.
3. `virt-viewer` window opens; click through Mint's installer (user `tester`, password `tester`, 25G disk, no third-party codecs).
4. Reboot, log in once as `tester`, then power off via the Cinnamon menu.
5. Control returns to the terminal: `==> Detaching the install CD-ROM`, `==> Booting the VM to inject the host ssh key`.
6. `ssh-copy-id` prompts for `tester`'s password — type `tester` once.
7. `==> Powering off cleanly`, `==> Taking snapshot 'fresh-user'`, `==> Bootstrap complete.`

- [ ] **Step 2: Verify the snapshot exists**

```bash
virsh snapshot-list mc-repro-mint-22.3
```

Expected: a row with `fresh-user` in `current` state.

- [ ] **Step 3: Verify reset is fast**

```bash
time install-repro/bin/repro-vm reset
```

Expected: reset + boot + ssh-ready in under ~20s (snapshot revert itself is sub-second; the time is dominated by the guest booting Mint).

- [ ] **Step 4: Verify SSH works without a password**

```bash
install-repro/bin/repro-vm ssh
# Inside the guest:
whoami
exit
```

Expected: `tester`.

- [ ] **Step 5: Tear back down**

```bash
install-repro/bin/repro-vm down
```

- [ ] **Step 6: No commit (state is out-of-repo).**

---

### Task 14: End-to-end verification — reproduce the Docker-without-sudo bug

**Files:** none committed; produces a run-log under `~/.local/state/media-centaur-repro/runs/`.

This is the acceptance test for the whole Phase 1 effort: we must observably reproduce the failure that triggered this work.

- [ ] **Step 1: Run the prowlarr scenario**

```bash
install-repro/bin/repro-vm run prowlarr-fresh-install
```

Expected: scenario exits **non-zero**, with `docker ps` reporting a permission denied / cannot connect to the Docker daemon error. This is the bug. Capture the exit code and last lines:

```bash
LATEST=$(ls -1dt ~/.local/state/media-centaur-repro/runs/*/ | head -1)
cat "$LATEST/meta.json"
tail -20 "$LATEST/scenario.log"
```

- [ ] **Step 2: Run the media-centaur scenario**

```bash
install-repro/bin/repro-vm run mc-fresh-install
```

Two possible outcomes — both valid Phase-1 results:

- **Exit 0, "web UI responded after Ns":** the production installer works end-to-end on fresh Mint. Great, we now have a regression guard.
- **Non-zero:** we have reproduced an install bug. Capture the log and file it as a bug ticket (per the README).

- [ ] **Step 3: Confirm web UI was reachable from the host**

Even if the scenario printed OK, double-check from the host while the VM is running:

```bash
curl -fsS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:2160/
```

Expected: `200`.

- [ ] **Step 4: Tear down**

```bash
install-repro/bin/repro-vm down
```

- [ ] **Step 5: No commit (state is out-of-repo). Findings go into bug tickets, not the repo.**

---

### Task 15: Write `install-repro/README.md`

**Files:**
- Create: `install-repro/README.md`

- [ ] **Step 1: Write the README**

`install-repro/README.md`:

```markdown
# Install reproduction (Phase 1 — Linux Mint 22.3)

A repeatable Linux Mint VM for reproducing media-centaur and prowlarr-stack
installation issues. Boots from a known-clean snapshot, runs the production
`curl | sh` installers, captures full run-logs.

> **Phase 1** ships Mint 22.3 only. Other distros, pre-built shareable images,
> upgrade/uninstall scenarios, and CI integration are tracked in
> [`campaigns/install-repro-matrix.md`](../campaigns/install-repro-matrix.md).
>
> Spec: [`docs/superpowers/specs/2026-05-27-install-repro-env-design.md`](../docs/superpowers/specs/2026-05-27-install-repro-env-design.md).

## One-time setup

1. **Install the host substrate** (Arch):
   ```bash
   sudo pacman -S --needed libvirt qemu-desktop virt-install virt-manager \
       dnsmasq iptables-nft bridge-utils edk2-ovmf socat shellcheck
   sudo systemctl enable --now libvirtd.socket
   sudo usermod -aG libvirt "$USER"          # then log out / log in
   sudo virsh net-autostart default
   ```

2. **Bootstrap the Mint VM** (~45 min, interactive):
   ```bash
   install-repro/bin/repro-vm bootstrap
   ```
   - Downloads the Mint 22.3 ISO once (cached at
     `~/.cache/media-centaur-repro/isos/`).
   - Opens Calamares in virt-viewer; click through the installer with username
     `tester` / password `tester`, 25 GB disk, **no third-party codecs**.
   - After first boot + login + power-off, the script injects an ssh key and
     captures the `fresh-user` snapshot. From this point you never touch the
     installer again.

## Daily use

Reproduce a failure:
```bash
install-repro/bin/repro-vm run mc-fresh-install         # or prowlarr-fresh-install
install-repro/bin/repro-vm tail-logs                    # follow live
```

Each run produces a directory under `~/.local/state/media-centaur-repro/runs/`
with `scenario.log`, `journalctl-user.log`, and `meta.json`. **These are what
you attach to a bug ticket.**

Other verbs:
```bash
install-repro/bin/repro-vm up           # boot without resetting
install-repro/bin/repro-vm reset        # revert to fresh-user, ~20s
install-repro/bin/repro-vm ssh          # interactive shell in the VM
install-repro/bin/repro-vm down         # graceful shutdown
install-repro/bin/repro-vm wipe         # destroy VM + all cached state
```

While the VM is up, the web UI is reachable from the host at
**http://127.0.0.1:2160/** — useful for Chromium / chromium-probe testing.

## How to file a reproduced bug

Run the scenario, then:
```bash
LATEST=$(ls -1dt ~/.local/state/media-centaur-repro/runs/*/ | head -1)
echo "Run: $LATEST"
cat "$LATEST/meta.json"
```

Attach to the bug:
- `$LATEST/scenario.log` — what the installer printed
- `$LATEST/journalctl-user.log` — what systemd saw
- `$LATEST/meta.json` — scenario name, distro, exit code

Note the **Mint ISO sha256** and the **scenario commit sha** in the ticket so
the reproduction is fully pinned.

## Scenarios

- **`mc-fresh-install`** — installs OS deps (sqlite3/mpv/inotify-tools), runs
  the production media-centaur bootstrap, seeds the placeholder TMDB key,
  enables lingering, starts the user service, asserts the web UI answers
  within 30s.
- **`prowlarr-fresh-install`** — runs the production prowlarr-stack bootstrap.
  Deliberately does **not** pre-configure Docker — the scenario's job is to
  expose the "docker without sudo" failure on Mint, not work around it.

Adding a scenario is one file in `scenarios/`, made executable, plus a sentence
here.

## Layout

```
install-repro/
├── README.md                 (this file)
├── bin/repro-vm              (driver)
├── scenarios/                (one file per scenario)
└── fixtures/                 (placeholder TMDB key, etc.)
```

Heavy state lives outside the repo:

```
~/.local/share/media-centaur-repro/   # VM disks, snapshots, ssh keys
~/.cache/media-centaur-repro/         # Mint ISO cache
~/.local/state/media-centaur-repro/   # run logs
```

`repro-vm wipe` deletes all three trees.
```

- [ ] **Step 2: Commit**

```bash
git add install-repro/README.md
git commit -m "docs(install-repro): README — workflow, bootstrap, bug-filing"
```

---

### Task 16: Update CLAUDE.md pointer and bump the campaign

**Files:**
- Modify: `CLAUDE.md`
- Modify: `campaigns/install-repro-matrix.md`

- [ ] **Step 1: Add a pointer in `CLAUDE.md`**

Find the "Map of contributor docs" table and add a row beneath the existing rows:

```markdown
| Install reproduction environment (host VM, scenarios) | [`install-repro/README.md`](install-repro/README.md) |
```

- [ ] **Step 2: Bump the campaign**

In `campaigns/install-repro-matrix.md`, update the frontmatter `last_updated` to today and change the Status block to:

```markdown
## Status

**Phase 1 shipped.** Driver, two scenarios, README, and one bootstrapped Mint VM
delivered. Acceptance test (`prowlarr-fresh-install` exposing Docker-without-sudo
on fresh Mint) reproduced and captured. Phase 2 (Tier-1 cloud-image distros) on
hold until Phase 1 has driven at least one shipped fix — see Completion criteria.
```

In the **Roadmap → Phase 1** section, prepend `(shipped 2026-05-27)` to the heading.

- [ ] **Step 3: Lint nothing (markdown). Commit**

```bash
git add CLAUDE.md campaigns/install-repro-matrix.md
git commit -m "docs: point CLAUDE.md at install-repro/; mark campaign Phase 1 shipped"
```

---

## Self-review checklist

- [x] **Spec coverage:** every section of the spec maps to a task.
  - Substrate (libvirt + QEMU/KVM) → Task 1
  - Repo layout → Task 2
  - Driver CLI surface → Tasks 3, 6–11
  - Scenarios → Task 12
  - Networking / port-forward → Task 8
  - Out-of-repo paths → Task 3 (`ensure_dirs`) + Task 4 (keys) + Task 5 (ISO cache) + Task 10 (runs)
  - Workflow + bug-filing → Task 15 README
  - Acceptance ("Docker-without-sudo observably reproduced") → Task 14
  - Distro guard ("any other value errors out") → Task 3
  - Campaign update → Task 16
- [x] **Placeholder scan:** the only "PLACEHOLDER" string is `MINT_ISO_SHA256` in Task 3, which Task 5 explicitly resolves and replaces with the live hash.
- [x] **Type/name consistency:** `VM_NAME`, `SNAPSHOT_NAME`, `GUEST_USER`, `HOST_FORWARD_PORT`, `STATE`/`CACHE`/`RUNS` paths, ssh key path, ip file path, pidfile path — all referenced consistently across Tasks 3–11.
- [x] **Bite-sized:** every task ends with a `git commit` and produces a working, lintable artifact (or, for Tasks 1/13/14, a verified host/VM state change).
