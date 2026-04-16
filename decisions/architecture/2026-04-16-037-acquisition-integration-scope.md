---
status: accepted
date: 2026-04-16
---
# Acquisition integration scope — Prowlarr-first, no runtime introspection

## Context and Problem Statement

[ADR-035](2026-04-15-035-acquisition-prowlarr-integration.md) established Prowlarr as the single acquisition integration point, with a rule that media-centarr "never talks directly to qBittorrent, Transmission, or any other download client." Commit 87a08ff then added a qBittorrent driver because Prowlarr itself does not expose download progress — once Prowlarr forwards a grab, the active queue lives on the download client.

This ADR records the intent going forward and resolves a follow-on problem: **detected download-client URLs from Prowlarr are frequently unreachable from the host running media-centarr.** Prowlarr returns the host/port exactly as configured inside Prowlarr. In typical deployments Prowlarr is configured with a Docker service name (e.g. `qbittorrent:8080`), which resolves inside the Docker network but not from the host.

## Decision Outcome

### Integration scope

1. **Prowlarr is the integration surface.** Everything that can be done via Prowlarr *is* done via Prowlarr — search, grab, download-client discovery.
2. **Direct download-client drivers exist only where Prowlarr has no equivalent.** Today this is a single use case: reading active/completed download progress, which Prowlarr does not expose. The qBittorrent driver exists reluctantly for this reason and no other.
3. **New download-client drivers are justified only by a Prowlarr gap.** If a capability is available via Prowlarr, use Prowlarr. A driver is added only when Prowlarr cannot supply the capability and the feature is worth the integration cost.
4. **Docker/runtime introspection is out of scope.** Media-centarr will not inspect the Docker socket, resolve container names, or otherwise probe the user's runtime environment to make connections work. Users run media-centarr in many configurations (bare metal, systemd, various container setups); adopting one as canonical would break the others.

This supersedes the literal rule in ADR-035 ("never talks directly to qBittorrent"). The spirit — minimise the integration surface, route through Prowlarr wherever possible — is preserved.

### Detected values are suggestions

Because (4) means we cannot rewrite unreachable hostnames ourselves, and because the host Prowlarr returns is correct *from Prowlarr's perspective* but not necessarily from ours, the "Detect from Prowlarr" button does **not** persist detected values. Instead it pre-fills the form, and the user confirms or edits (typically replacing `qbittorrent` with `localhost` or a LAN IP) before clicking Save.

Rejected alternatives for URL reachability:

- **Auto-rewrite `localhost`/service names on detection.** Rejected: there is no reliable rule — the correct replacement depends on how the user runs each service. Any heuristic is wrong for some configuration.
- **Resolve Docker container ports via the Docker socket.** Rejected by (4) above.
- **Require Prowlarr to be configured with host-reachable URLs.** Rejected: users sensibly configure Prowlarr for its own runtime, not ours. We should not push that constraint onto them.

### Consequences

* Good, because the integration surface stays narrow and predictable — Prowlarr is the default answer; drivers are the exception, not the pattern.
* Good, because media-centarr works the same regardless of whether the user runs services in Docker, on bare metal, or mixed.
* Good, because the detection UX fails softly: the user sees what Prowlarr reported and decides whether it matches their network.
* Bad, because users always do one extra step after "Detect" — review the URL and usually edit it. This is accepted as the price of not imposing a runtime model.
* Bad, because progress-polling integrations may grow over time if users run non-qBittorrent clients. Each is evaluated individually against (3).
