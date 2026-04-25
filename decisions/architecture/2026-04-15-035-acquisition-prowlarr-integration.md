---
status: accepted
date: 2026-04-15
amended-by: decisions/architecture/2026-04-16-037-acquisition-integration-scope.md
---
# Prowlarr as the single optional integration point for media acquisition

> **Amended by ADR-037.** The literal rule "never talks directly to qBittorrent, Transmission, or any other download client" was relaxed: a download-client driver is permitted *only* where Prowlarr has no equivalent capability (today: reading download progress). The spirit — Prowlarr is the integration surface; drivers are the exception — is preserved. See [ADR-037](2026-04-16-037-acquisition-integration-scope.md).

## Context and Problem Statement

Media-centarr manages a media library but has no way to search for or download new content. Users currently place files manually in watch directories. Two acquisition use-cases need to be supported: manual search (user finds and grabs a title) and automated acquisition (release tracking triggers a download when a tracked item becomes available).

The challenge is supporting a range of user setups without locking into one specific stack. Users may run Prowlarr + qBittorrent, Prowlarr + Transmission, or no download stack at all. The system must degrade gracefully when no acquisition tooling is configured, and it must be extensible as new integrations become desirable.

## Decision Outcome

Chosen option: **Prowlarr as the single integration point, optional**, because:

- Prowlarr is an indexer aggregator that already abstracts over dozens of tracker sources. Users configure their download client (qBittorrent, Transmission, Deluge, SABnzbd, etc.) inside Prowlarr. Media-centarr only needs to talk to Prowlarr — never directly to the download client.
- The grab API (`POST /api/v1/release`) lets media-centarr submit a chosen release to Prowlarr, which routes it to whatever client the user has configured. This keeps the integration surface minimal.
- When Prowlarr is not configured, all acquisition UI surfaces are hidden and no acquisition features are active. The application remains fully functional as a library manager.
- A `SearchProvider` behaviour wraps Prowlarr as an implementation detail, keeping call sites decoupled from the specific adapter.

**Rule (as amended by ADR-037):** Media-centarr integrates with Prowlarr as the integration surface. A direct download-client driver is permitted only where Prowlarr has no equivalent capability — today, reading download progress. If a user wants to use a different indexer/search stack in the future, they implement `Acquisition.SearchProvider`; existing call sites do not change.

### Quality preference

The system prefers 4K (2160p/UHD) releases. 1080p is accepted when 4K is unavailable. Releases below 1080p are filtered out in automated grabs. Manual search shows all results so the user can choose.

### Retry policy

When automated acquisition searches and finds nothing acceptable, it retries every 4 hours via an Oban job. This handles the common case where a release is announced but not yet available on indexers. Once a grab is submitted (4K or 1080p), the retry loop stops.

### Rejected options

- **Direct download client integration** (e.g. talking to qBittorrent's API): rejected because it would require maintaining adapters for every download client individually. Prowlarr already provides this abstraction.
- **Delegation to Radarr/Sonarr**: rejected because it requires users to run additional services beyond their indexer and download client, and because media-centarr already handles library management — duplicating that in Radarr/Sonarr would create two sources of truth.

### Consequences

* Good, because users configure their download client once (in Prowlarr) rather than in two places
* Good, because media-centarr maintains a single integration point with a narrow API surface
* Good, because users without Prowlarr lose no existing functionality — acquisition surfaces are simply absent
* Good, because the `SearchProvider` behaviour allows a second adapter (e.g. Jackett) to be added without touching call sites
* Bad, because users who want acquisition must run Prowlarr (and configure a download client inside it) — there is no lighter-weight path
