---
status: planning
started: 2026-05-31
last_updated: 2026-05-31
---
# Usenet download client (SABnzbd) + multi-client downloads

## Goal

Extend Media Centaur from a **single download client** (qBittorrent) to a
**set of clients routed by protocol**, with SABnzbd as the first usenet
driver. The end state: a user can pursue releases without caring whether each
one lands via torrent or usenet — search `My Show S02E{01-05}`, and some
episodes may come from usenet and some from torrents, transparently.

This campaign builds the **infrastructure** for that. The "user doesn't care"
mixed grab is a *consequence* once both clients exist — the coverage planner
(see the media-search campaign — complete 2026-06-10, in git history)
picks best-available-now per unit and Prowlarr routes each grab to the right
client. **No mixed-grab UX is built here.**

Spans two repos: `prowlarr-stack` (sibling — add the SABnzbd service) and this
one (the driver + the multi-client refactor).

## The model

Settled in the 2026-05-31 design session. Resumable context — read before
writing code.

**Prowlarr routes by protocol (thin Media Centaur).** Prowlarr is configured
with two download clients (qBittorrent + SABnzbd) and already routes each grab
to the right one by the indexer's protocol — torrent indexers → qBit, usenet
indexers → SABnzbd. Media Centaur keeps grabbing exactly as today
(`POST` guid+indexerId to Prowlarr); it does **not** detect protocol or pick a
client at grab time. This keeps [ADR-035](../decisions/architecture/2026-04-15-035-acquisition-prowlarr-integration.md)
intact (Prowlarr = the integration point) and adds zero routing logic to MC.
*(Rejected: MC-owns-routing — it duplicates what Prowlarr does for free.)*

**SABnzbd owns assembly, repair, and extraction.** MC never touches a `.par2`
or `.rar`. SABnzbd downloads all segments → par2 verify → repair → unrar →
delete the archive cruft → leaves the final media file in its *completed*
folder (the linuxserver image ships `par2`/`unrar`). By the time a job is
`Completed`, the `.mkv` sits in a folder, the same shape as a finished torrent.

**The one real refactor: one client → a set, polled & matched together.**
`Dispatcher.driver()` (one module) becomes `Dispatcher.drivers()` (the
configured set). `QueueMonitor` polls **each** client, tags every item with a
`protocol`, and merges into one unified queue state. Everything downstream
(health classification, UI, the pursuit matcher) keeps seeing a single queue.

**Config: one client → two protocol slots.** Today's single
`download_client_*` config becomes a **torrent slot** and a **usenet slot**.
The existing config migrates into the torrent slot — zero change for current
users. *(Rejected: a fully general list of N clients — YAGNI; Prowlarr's
protocol routing maps cleanly to one client per protocol.)*

**Usenet lifecycle differs in three ways** (extraction aside):
1. **Completion comes from SABnzbd *history*, not the live queue.** The final
   file only exists after post-processing, so `content_path` is captured from
   the `storage` path SABnzbd reports in history — not mid-download.
2. **Richer status enum.** `verifying / repairing / extracting` states so the
   UI shows "Repairing…" instead of looking stalled.
3. **New terminal failures.** par2-unrepairable / unpack-failed map to pursuit
   *failed*, distinct from a torrent stall.

**Identity is explicitly provisional / deferred.** Usenet releases have no
infohash, so v1 matches the first queue sighting by **release title** (the
existing Rule-2 fallback in `QueueMatcher`), then pins `nzo_id` + the history
`storage` path as the durable handle — match loosely once, then ride a stable
identifier. This **knowingly leans on the title-match fallback that caused the
earlier query-pursuit landing bugs** (the durable-infohash-at-grab work in
v0.77.3–4). It is a
functional placeholder to make v1 work against stubs, **not a settled answer**.
A better identity strategy gets designed once a live setup is producing real
SABnzbd payloads to learn from. Do not over-harden this now.

**Verification is bounded.** No usenet provider/indexer is available during
this build, so all driver work is against SABnzbd's **documented JSON API**
with **stubbed HTTP** (same pattern as the qBittorrent stub). Tests go green
without network; the **real end-to-end grab is deferred** to a manual smoke
test once a provider + indexer are wired up.

## Decisions made

Append-only log.

* `2026-05-31` — **Prowlarr routes by protocol (thin MC).** Configure two download clients in Prowlarr; MC stays out of grab routing. Keeps [ADR-035](../decisions/architecture/2026-04-15-035-acquisition-prowlarr-integration.md).
* `2026-05-31` — **SABnzbd is the first usenet driver** (de-facto default, clean JSON API). NZBGet can follow later on the same behaviour.
* `2026-05-31` — **SABnzbd owns par2/repair/unrar.** MC never decompresses; it consumes the post-processed file.
* `2026-05-31` — **Core refactor: `Dispatcher.driver()` → `drivers()`; QueueMonitor polls the set and merges**, tagging items with `protocol`.
* `2026-05-31` — **Config grows to two protocol slots** (torrent + usenet); existing config migrates into the torrent slot, backward-compatible. *(Rejected: general N-client list — YAGNI.)*
* `2026-05-31` — **Usenet completion reads SABnzbd history** (`storage` path → `content_path`), not the live queue; QueueItem gains a richer status enum + usenet failure mapping.
* `2026-05-31` — **Identity is provisional/deferred.** Title-match → pin `nzo_id` + storage path is a placeholder; redesign with real payloads later. Flagged as leaning on the known-fragile title fallback.
* `2026-05-31` — **Verification bounded to stubs.** No provider available; build against the documented API, real e2e is a deferred manual smoke test.
* `2026-05-31` — **Boundary: this campaign only enables mixed-protocol acquisition.** The "user doesn't care" mixed grab falls out of the media-search planner; no mixed-grab UX is built here.

## Next steps

Phased; each phase ships something real without depending on the harder logic
that follows.

1. **P0 · stack: add the SABnzbd service.** *(Relocated — now owned by
   [`download-stack-control-plane`](download-stack-control-plane.md)'s P1.)* The
   stack-side SABnzbd service lands in the **new `download-stack` repo**, not
   `prowlarr-stack`: new `sabnzbd` compose service, **outside** the gluetun VPN
   tunnel (usenet is SSL-to-provider, no P2P leak — same posture as qBit today),
   completed folder volume-mapped into the same downloads location MC watches,
   registered as Prowlarr's second download client. Provider NNTP creds + usenet
   indexer stay user-supplied at runtime. This campaign keeps the **MC-side**
   work below (P1–P4).
2. **P1 · config & dispatcher.** Single `download_client_*` → two protocol
   slots; backward-compatible migration of the existing config into the torrent
   slot. `Dispatcher.driver()` → `drivers()` returning the configured set.
   Settings UI gains a usenet-client section. No behaviour change for torrent
   users yet.
3. **P2 · SABnzbd driver.** Implement the `DownloadClient` behaviour against
   SABnzbd's JSON API (`mode=queue`, `mode=history`, API-key auth), stubbed
   tests. `QueueItem` gains `protocol` + the richer status enum + history-based
   completion / `content_path` capture.
4. **P3 · multi-client monitor + matching.** `QueueMonitor` polls the set and
   merges; protocol-aware identity in `QueueMatcher` / `DownloadIdentity`
   (provisional usenet scheme); usenet terminal-failure mapping.
5. **P4 · verify & document.** Stubs green; wiki **Download Clients** page
   (SABnzbd setup) + prowlarr-stack README; real end-to-end smoke test deferred
   to when a provider is available. Consider an ADR if the multi-client /
   two-slot model warrants one (amends ADR-035's single-client assumption).

## Risk surface

`(exists)` works today · `(extends)` grows existing code · `(net-new)` new.

1. **Provisional identity leans on the fragile path** *(extends)* — usenet has
   no infohash, so it rides the title-match fallback that already caused the
   query-pursuit landing bugs. Mitigation: pin `nzo_id` + storage path early;
   accept it's a placeholder; redesign with real data. **Highest risk.**
2. **Completion timing** *(net-new)* — capturing `content_path` from the live
   queue (as torrents do) is wrong for usenet; it must come from history after
   post-processing, or MC pins an obfuscated incomplete path.
3. **Multi-client queue merge** *(net-new)* — id collisions across clients,
   one client offline while the other is healthy, per-client RID/poll cadence.
   The merged queue state must stay coherent when a client drops.
4. **Status enum drift** *(extends)* — health classification + UI assume
   torrent-ish states; usenet `verifying/repairing/extracting` must map without
   reading as "stalled."
5. **Config migration** *(extends)* — moving the single client into a torrent
   slot must not strand existing users' qBit settings.
6. **prowlarr-stack network/path** *(net-new)* — SABnzbd's completed dir must
   land inside MC's watched paths, and outside-VPN placement must be correct.

## Completion criteria

* A `DownloadClient.SABnzbd` driver implements the behaviour
  (`list_downloads/test_connection/cancel_download`) and passes stubbed tests.
* `QueueMonitor` polls a **set** of clients and merges them; downstream
  (health, UI, matcher) sees one unified, protocol-tagged queue.
* Config exposes two protocol slots; an existing single-client install
  migrates cleanly into the torrent slot with no regression.
* Usenet completion is read from SABnzbd history; `content_path` is captured
  from the reported storage path; usenet failures map to pursuit *failed*.
* prowlarr-stack ships a working SABnzbd service + setup docs.
* Wiki **Download Clients** page covers SABnzbd setup.
* *(Deferred, not blocking)* a real end-to-end grab is smoke-tested once a
  provider + indexer exist; the provisional identity scheme is revisited then.

## Pointers

* **Download-client abstraction** — `lib/media_centaur/downloads/download_client.ex` (behaviour), `downloads/download_client/dispatcher.ex` (the seam to grow to `drivers()`), `downloads/download_client/qbittorrent.ex` (reference driver: auth, sync, list, cancel).
* **Queue monitoring** — `lib/media_centaur/downloads/queue_monitor.ex`, `downloads/queue_state.ex`, `downloads/queue_item.ex` (gains `protocol` + status enum), `downloads/download_client/qbittorrent/sync.ex` (qBit RID delta — SABnzbd has no equivalent; poll full queue+history).
* **Health** — `lib/media_centaur/downloads/health.ex`, `downloads/health_history.ex`.
* **Pursuit matching / identity** — `lib/media_centaur/acquisition/queue_matcher.ex` (infohash-first + title fallback), `acquisition/pursuits/download_identity.ex` (`content_path` capture), `acquisition/info_hash.ex`.
* **Grab flow** — `lib/media_centaur/acquisition/jobs/pursue_target.ex`, `search/prowlarr.ex` (the `POST /api/v1/search` grab), `search/search_result.ex` (no protocol field today).
* **Config** — `lib/media_centaur/config.ex` (`download_client_*` keys ~L48), `defaults/media-centaur.toml`, plus the Settings DB / UI for download-client config.
* **Lifecycle** — `lib/media_centaur/acquisition/pursuits/pursuit.ex`, `acquisition/target.ex`, `acquisition/pursuits/inbound_listener.ex` (file-landed → IdentityVerifier).
* **prowlarr-stack** — `~/src/media-centaur/prowlarr-stack/docker-compose.yml` (qBit + gluetun today), `README.md`, `defaults/`.
* [ADR-035](../decisions/architecture/2026-04-15-035-acquisition-prowlarr-integration.md) (Prowlarr integration), [ADR-037](../decisions/architecture/2026-04-16-037-acquisition-integration-scope.md) (integration scope / direct-driver relaxation), [ADR-043](../decisions/architecture/2026-05-10-043-acquisition-split.md) (Search/Downloads context split), [ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md) (campaign convention).
* **Sibling campaign** — media-search (complete 2026-06-10, in git history): the coverage planner that turns this infrastructure into the "user doesn't care" mixed grab.
