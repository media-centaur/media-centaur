# Download clients (contributor guide)

How Media Centaur integrates with download clients, the contract with
[`prowlarr-stack`](https://github.com/media-centaur/prowlarr-stack), and the
checklist for adding a new client so no surface gets overlooked.

End-user setup lives on the wiki:
[Download Clients](https://github.com/media-centaur/media-centaur/wiki/Download-Clients),
[Settings Reference → Acquisition](https://github.com/media-centaur/media-centaur/wiki/Settings-Reference).

## The two-slot model

One client per **protocol slot** — torrent and usenet. Prowlarr is configured
with both clients and routes each grab by the indexer's protocol (ADR-035:
Prowlarr is the integration point; MC never picks a client at grab time).
MC's drivers exist for the *queue view*, in-app cancel, and pursuit matching.

| Concern | Module |
|---|---|
| Slot values over the flat config keys | `MediaCentaur.Downloads.ClientConfig` (via `Downloads.configured_clients/0`) |
| Type → driver resolution | `Downloads.DownloadClient.Dispatcher` (`drivers/0`, `driver_for/1`) |
| Driver contract | `Downloads.DownloadClient` behaviour (`list_downloads` / `test_connection` / `sync` / `cancel_download`) |
| Drivers | `DownloadClient.QBittorrent` (torrent), `DownloadClient.SABnzbd` (usenet) |
| Merged polling, per-slot connectivity | `Downloads.QueueMonitor`, `Downloads.QueueState` |
| Per-slot readiness gating | `MediaCentaur.Capabilities` (`client_ready?/1`; subjects `:download_client`, `:usenet_download_client`) |
| Client-neutral queue entry | `Downloads.QueueItem` (protocol tag, state enum, `failure_message`, `content_path`) |

Config storage is flat keys in the Settings DB, set in-app only (never TOML —
credentials must not land in dotfiles or backups): `download_client_*` is the
torrent slot, `usenet_download_client_*` the usenet slot.

## The prowlarr-stack bootstrap contract (no API — deliberate gap)

**Media Centaur exposes no local setup/bootstrap API.** The `/api` scope in
`router.ex` is commented-out boilerplate; nothing in `prowlarr-stack` writes
configuration into MC. Anyone extending the stack↔MC integration should know
the handoff is manual, in three parts:

1. **Stack side** — `prowlarr-stack/./setup` brings up Prowlarr + qBittorrent +
   SABnzbd, registers both as Prowlarr download clients, auto-generates the
   SABnzbd API key into the stack's `.env` (`SABNZBD_API_KEY`), and **prints**
   the coordinates for the user to enter in MC.
2. **MC pull** — Settings → Acquisition → *Detect from Prowlarr* reads
   Prowlarr's `/api/v1/downloadclient` and pre-fills each detected client into
   its protocol slot's form (`ClientConfig.protocol_for_type/1` routes them).
   Prowlarr deliberately never returns credentials.
3. **User** — reviews URLs (Prowlarr often reports Docker-internal hostnames),
   enters the qBittorrent password / SABnzbd API key, saves, and runs each
   slot's *Test connection* (readiness is per-slot).

The API **is designed** — it is P4 ("Provisioning handshake") of the
[`download-stack-control-plane`](../campaigns/download-stack-control-plane.md)
campaign, backed by
[ADR-052](../decisions/architecture/2026-05-31-052-download-stack-control-plane.md):
a loopback-only receiver that stages a proposed wiring bundle (both protocol
slots, credentials included) behind a confirm-in-MC card. It has **no code
yet** — don't go looking for it, and don't grow an ad-hoc version from a
setup script; build it as that campaign phase. Until then: **when either repo
grows an integration surface (a new client, a new credential, a new service),
this contract and the checklist below are the places to update.**

## Checklist: adding a download client or protocol

Every surface the SABnzbd/usenet work touched, in dependency order. Use it as
the definition of done for the next driver (e.g. NZBGet, Transmission):

**Core**
- [ ] Config keys (`lib/media_centaur/config.ex`): `@runtime_settable_keys`,
      defaults, secret keys into `@sensitive_keys` (confirm
      `:phoenix, :filter_parameters` covers the name).
- [ ] `Downloads.ClientConfig`: slot reader in `Downloads.configured_clients/0`
      (new protocol only), `protocol_for_type/1` entry.
- [ ] Driver module implementing `Downloads.DownloadClient`, stubbed
      `Req.Test` tests (`test/media_centaur/downloads/download_client/`), and
      an entry in `Dispatcher.module_for_type/1`. Export from the
      `MediaCentaur.Downloads` boundary if the web layer calls
      `invalidate_client/0`.
- [ ] `QueueItem.from_*` constructor(s): protocol tag, state mapping (extend
      the state enum only for states the UI must distinguish), `content_path`
      only when the path is final.
- [ ] Test-support stub in `test/support/download_client_stubs.ex`.

**Readiness & UI**
- [ ] `Capabilities`: test subject + storage key, `@capability_input_keys`,
      per-slot flag in `compute_flags/0`.
- [ ] Settings → Acquisition form (save/test handlers in `settings_live.ex`,
      form in `acquisition_section.ex`), detect routing, setup-wizard copy.
- [ ] `QueueMonitor` needs no per-client changes — it polls whatever
      `Dispatcher.drivers/0` returns — but check state-enum additions against
      `Health.classify/3` (non-`:downloading` states must not read as stalled)
      and the Downloads page rendering.
- [ ] Failure semantics: does the client report terminal failures? Set
      `failure_message` so Policy's `{:auto_cancel, :download_failed}` rule
      applies.

**Cross-repo & docs**
- [ ] `prowlarr-stack`: service in the compose file, Prowlarr registration,
      completed dir inside MC's watched paths, VPN placement, `./setup`
      output + `.env` keys.
- [ ] Wiki: `Download-Clients.md` (table row + setup section),
      `Settings-Reference.md` (Acquisition subform), `Troubleshooting.md` if
      there's a new failure mode.
- [ ] This file, if the model itself changed.
- [ ] Live smoke test against the real client before calling it shipped.
