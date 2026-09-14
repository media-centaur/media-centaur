---
status: accepted
date: 2026-04-16
amended: 2026-09-14
---
# Acquisition integration scope — Prowlarr-first, no runtime introspection

Supersedes ADR-035 (retired); its surviving rules are restated here.

## Context and Problem Statement

Acquisition has to work across many user setups — Prowlarr with qBittorrent, with SABnzbd, or no download stack at all — without adopting one runtime as canonical. Prowlarr does not expose download progress, so a direct client driver exists, and the client URLs Prowlarr reports are often unreachable from the host running Media Centaur (a Docker service name such as `qbittorrent:8080`).

## Decision Outcome

1. **Prowlarr is the integration surface.** Search, grab, and download-client discovery go through Prowlarr. `MediaCentaur.Search` is the Prowlarr-facing boundary; call sites depend on it, not on the client module.
2. **Acquisition is optional.** Without a passing Prowlarr connection test (`MediaCentaur.Capabilities`) every acquisition surface is absent, and the application is a complete library manager.
3. **Direct download-client drivers exist only where Prowlarr has no equivalent.** Today that is one capability: reading active and completed download progress (`MediaCentaur.Downloads`, qBittorrent and SABnzbd drivers). A new driver is justified only by a Prowlarr gap worth the integration cost.
4. **No Docker or runtime introspection.** Media Centaur never inspects the Docker socket, resolves container names, or probes the user's runtime to make a connection work.
5. **Detected values are suggestions.** "Detect from Prowlarr" pre-fills the client form; the user confirms or edits (typically replacing a service name with `localhost` or a LAN address) and saves. Detected values are never persisted directly.

Delegating to Radarr or Sonarr was rejected: it adds services and a second source of truth for the library. [ADR-052](2026-05-31-052-download-stack-control-plane.md) governs how Media Centaur relates to the download stack as a managed component.

### Consequences

* Users who want acquisition run Prowlarr with a download client configured inside it.
* Every detection ends with the user reviewing a URL.
* Each additional client type users run is a driver evaluated against rule 3.
