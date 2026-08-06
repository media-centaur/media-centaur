---
status: accepted
date: 2026-05-31
amends: decisions/architecture/2026-04-15-035-acquisition-prowlarr-integration.md
---
# The download stack owns its control plane; Media Centaur stays thin

> **Amends ADR-035.** ADR-035 framed the stack as a single static integration
> point reached through "a narrow API surface" (the grab/search API). This ADR
> reframes the stack as a *managed component with an operational lifecycle*, and
> adds two further MC↔stack surfaces — a provisioning handshake and a read-only
> health endpoint — both thin and versioned. Prowlarr remains the acquisition
> integration point (ADR-035) and direct client polling stays the progress
> exception (ADR-037); this ADR governs *where the stack's control plane lives*
> and *how MC relates to the stack as a component*.

## Context and Problem Statement

The download infrastructure (`prowlarr-stack`: gluetun VPN + Prowlarr +
FlareSolverr + qBittorrent, soon SABnzbd) is delivered as a one-shot `curl | sh`
installer that bakes choices — most visibly VPN routing — at install time. As
more download clients and options accrue, the installer is being stretched to
cover concerns it was never shaped for: reconfiguring after install, observing
health across containers, and diagnosing the seam failure that hurts most ("MC
says a download completed, but no file ever showed up in the watched dir").

These are not installer features. They are the stack's **operational
lifecycle** — desired state, apply, observe, reconfigure — and a one-shot
installer only covers the first. The growing brittleness is **accidental**
complexity (choices frozen at install time, no aggregated health view), not
**inherent** (multiple third-party services, genuine per-user routing
variation, and a cross-process seam failure that no single container can see).

The open question: where should the control plane that owns that lifecycle
live — inside Media Centaur (best UX, the app the user already opens), or in the
stack itself?

## Decision Outcome

Chosen option: **the stack owns its own control plane; Media Centaur stays
thin**, governed by **change-axis isolation** — MC may change *only* when the
MC↔stack protocol changes, and for no other reason. Adding a download client, a
VPN provider, or a routing toggle is not a protocol change, so none may touch
MC. Folding a cockpit into MC would wire every one of the stack's
reasons-to-change into MC's reasons-to-change; we decline that coupling
deliberately.

Concretely:

- **Config-as-truth control plane in the stack.** A single `stack.toml` is the
  source of desired state; an `apply` reconciler renders compose/env and
  converges the stack; a `status` surface reports actual state. VPN routing
  becomes a **runtime toggle**, not an install-time fork.
- **v1 contract: drain-before-change.** Downloads must be completed or removed
  before upgrading or changing config. The reconciler operates on a *quiesced*
  stack (stop → apply → restart) and never live-migrates in-flight downloads or
  active seeding. The precondition is enforced/warned, not silently violated.
- **MC↔stack seam = three thin, versioned surfaces:**
  1. the existing grab/search via Prowlarr (ADR-035) + direct client polling for
     progress (ADR-037);
  2. a **provisioning handshake** — the installer POSTs a wiring proposal to MC
     on `localhost:2160`; MC stages it and applies only on explicit
     **confirm-in-MC**; loopback-only, same-host, versioned; the payload is the
     full wiring bundle (client endpoints + creds + watched dir), because MC
     polls clients directly;
  3. a **read-only health endpoint** the stack exposes and MC consumes, so the
     cross-seam failure is observable from MC's side without MC owning the
     stack.
- **The stack ships as a new `download-stack` repo** that ports the proven parts
  of `prowlarr-stack` (compose topology, gluetun kill-switch, mountpoint
  hardening, backup/restore) onto the control-plane model, and supersedes it at
  parity-plus-maturity.

The control plane is **not** a bundled web UI in v1: `stack.toml` is the truth,
the polished "toggle and it just works" UX for the acquisition side lives on MC
via the handshake, and a UI may sit on the schema later if the file-driven model
proves to need it.

### Rejected options

- **MC as the cockpit** (Settings UI drives `docker compose`, MC's Console
  aggregates stack health): best end-user UX, but it couples MC's release cycle
  to docker orchestration, makes MC change on every kind of stack change, hands
  MC docker privileges, and complicates the macOS port. The decisive cost is the
  lost change-axis isolation.
- **Bundled web UI in the stack (v1):** relocates the exact churn we are avoiding
  out of MC into the stack, for UX the handshake already delivers on the
  acquisition side. YAGNI until the file-driven model proves insufficient.
- **Refactor `prowlarr-stack` in place:** the old repo's shape *is* the
  install-time-baked model being moved away from; greenfield-with-heritage is
  cleaner than carrying that shape forward.
- **Live-migration of in-flight/seeding state across reconfigures:** large,
  fragile (Tier-2/Tier-3 state, version-coupled), and unnecessary once
  drain-before-change is accepted as the v1 contract.

### Consequences

* Good, because MC's change surface stays minimal — it moves only when a
  versioned MC↔stack protocol moves, not when the stack grows a client or knob.
* Good, because VPN routing (and other choices) become reconfigurable runtime
  state instead of install-time forks, addressing the original reliability/UX
  complaint.
* Good, because the worst failure (MC-says-done / file-absent) becomes
  observable from MC via the health endpoint, with one front door, without MC
  owning the stack.
* Good, because drain-before-change collapses the hardest tier of complexity,
  trading a documented user precondition for a far more reliable reconciler.
* Bad, because there are now two repos to keep coherent during cutover, and the
  new repo must reach real parity before `prowlarr-stack` is removed.
* Bad, because the provisioning endpoint is privileged on localhost; safety
  rests entirely on confirm-in-MC, so the receiver must never auto-apply.
* Relates to [ADR-035](2026-04-15-035-acquisition-prowlarr-integration.md),
  [ADR-037](2026-04-16-037-acquisition-integration-scope.md),
  [ADR-043](2026-05-10-043-acquisition-split.md). Rollout tracked in
  `campaigns/download-stack-control-plane.md` (removed on completion — see git history).
