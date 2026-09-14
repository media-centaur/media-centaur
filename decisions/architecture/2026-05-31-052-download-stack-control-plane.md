---
status: accepted
date: 2026-05-31
---
# The download stack owns its control plane; Media Centaur stays thin

Amends [ADR-037](2026-04-16-037-acquisition-integration-scope.md): Prowlarr remains the acquisition surface and direct client polling the progress exception; this record governs how Media Centaur relates to the stack as a component.

## Context and Problem Statement

The download infrastructure (`prowlarr-stack`: VPN, Prowlarr, FlareSolverr, qBittorrent, SABnzbd) ships as a one-shot installer that freezes choices such as VPN routing at install time. Reconfiguring, observing health across containers, and diagnosing "the app says a download completed but no file arrived" are the stack's operational lifecycle, and an installer covers only the first step. The question is where that lifecycle's control plane lives.

## Decision Outcome

1. **The stack owns its control plane; Media Centaur changes only when the MC↔stack protocol changes.** Adding a client, a VPN provider or a routing toggle is not a protocol change and touches nothing in this app.
2. **Config-as-truth in the stack.** One `stack.toml` is desired state, an `apply` reconciler converges the stack, a `status` surface reports actual state; VPN routing is a runtime toggle.
3. **Drain-before-change.** Reconfiguration and upgrade run on a quiesced stack (stop, apply, restart); in-flight downloads are never live-migrated, and the precondition is enforced or warned, never silently violated.
4. **Three thin, versioned seams:** grab and search through Prowlarr plus direct client polling for progress; a provisioning handshake in which the installer POSTs a wiring bundle to Media Centaur on loopback, staged and applied only on an explicit confirm in the app; a read-only stack health endpoint the app consumes.

Rejected: Media Centaur as the cockpit (Settings driving `docker compose`), because it couples the app's release cycle to every stack change and hands it docker privileges.

### Consequences

* Only the first seam exists in code. The handshake is designed and has no implementation; Settings → *Detect from Prowlarr* plus a manual paste remains the handoff (`docs/download-clients.md`), and nothing consumes a stack health endpoint.
* The successor `download-stack` repository was never created; `prowlarr-stack` and `torrent-stack` are what exist, and the campaign has stood at planning since 2026-06-10.
* The provisioning receiver, when built, is privileged on localhost; its safety rests entirely on confirm-in-app and it must never auto-apply.
