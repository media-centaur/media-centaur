---
status: accepted
date: 2026-05-31
amended: 2026-11-19
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

**Amendment 2026-11-19.** Point 1 stands. Points 2 to 4 were written for a successor repository that was never built; `prowlarr-stack` matured in place instead (optional VPN and VPN routing changed by `./setup --reconfigure`, SABnzbd as the second client, migrations, `./update` gated on `./check`), and it is the stack.

* **Point 2.** The stack's desired state is its `.env`, and `./setup` is the reconciler. No `stack.toml`, no `apply`, no successor repository.
* **Point 3.** Restarting the clients with a live queue has not lost downloads, so the rule narrows to the change that can strand data: `./setup` refuses to change the download or completed directory while a client has a queue.
* **Point 4, provisioning.** [ADR-085](2026-11-09-085-the-local-api-is-admitted-by-its-key.md) established that loopback is not a trusted address: a page in the host's browser can send a request to 127.0.0.1. The installer therefore sends nothing to the app. The stack writes a versioned wiring bundle to a file only its user can read; the app reads it, compares it with its saved settings, and shows a difference as a proposal that is applied only on an explicit confirm. Trust rests on file ownership and the confirm.
* **Point 4, health.** The stack serves no health endpoint. The app reads the stack's condition through the connections it already has to Prowlarr and the download clients; `./check` remains the stack's verifier.

None of this is built yet; `docs/download-clients.md` states the current handoff.

### Consequences

* Only the first seam exists in code. The handshake is designed and has no implementation; Settings → *Detect from Prowlarr* plus a manual paste remains the handoff (`docs/download-clients.md`), and nothing consumes a stack health endpoint.
* The successor `download-stack` repository was never created; `prowlarr-stack` and `torrent-stack` are what exist, and the campaign has stood at planning since 2026-06-10.
* The provisioning receiver, when built, is privileged on localhost; its safety rests entirely on confirm-in-app and it must never auto-apply.
