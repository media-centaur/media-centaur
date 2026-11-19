# Download clients (contributor guide)

How Media Centaur integrates with download clients, the contract with
[`prowlarr-stack`](https://github.com/media-centaur/prowlarr-stack), and the
checklist for adding a new client so no surface gets overlooked.

End-user setup lives on the wiki:
[Download Clients](https://github.com/media-centaur/media-centaur/wiki/Download-Clients),
[Settings Reference → Acquisition](https://github.com/media-centaur/media-centaur/wiki/Settings-Reference).

## The two-slot model

One client per **protocol slot** — torrent and usenet. Prowlarr is configured
with both clients and routes each grab by the indexer's protocol (ADR-037:
Prowlarr is the integration point; MC never picks a client at grab time).
MC's drivers exist for the *queue view*, in-app cancel, and pursuit matching.

| Concern | Module |
|---|---|
| Slot values over the flat config keys | `MediaCentaur.Downloads.ClientConfig` (via `Downloads.configured_clients/0`) |
| Type → driver resolution | `Downloads.DownloadClient.Dispatcher` (`drivers/0`, `driver_for/1`) |
| Driver contract | `Downloads.DownloadClient` behaviour (`test_connection` / `sync` / `cancel_download` / `list_files`), pinned per driver by `download_client/conformance_test.exs` |
| Drivers | `DownloadClient.QBittorrent` (torrent), `DownloadClient.SABnzbd` (usenet) |
| Merged polling, per-slot connectivity | `Downloads.QueueMonitor`, `Downloads.QueueState` |
| Per-slot readiness gating | `MediaCentaur.Capabilities` (`client_ready?/1`; subjects `:download_client`, `:usenet_download_client`) |
| Client-neutral queue entry | `Downloads.QueueItem` (protocol tag, state enum, `failure_message`, `content_path`, SABnzbd's post-processing `stage_line`) |
| Phase projection | `Downloads.Phase` — a job's step on its protocol's ladder (usenet: fetch, download, verify, repair while it happens, unpack, move, done; torrent: metadata, download, done), the condition on it (queued, paused, stalled, failed) and the figure through the step; the one place the ladder is known. Pure, never stored. Every surface draws a job from it through `Components.Acquisition.DownloadStrip`. |

Config storage is flat keys in the Settings DB, set in-app only (never TOML —
credentials must not land in dotfiles or backups): `download_client_*` is the
torrent slot, `usenet_download_client_*` the usenet slot.

## The prowlarr-stack handoff

**The stack writes a file; Media Centaur reads it and a person accepts.**
Media Centaur exposes no setup API and never runs docker
([ADR-052](../decisions/architecture/2026-05-31-052-download-stack-control-plane.md),
amended 2026-11-19).

1. **Stack side** — at the end of every `./setup` run (install,
   `--reconfigure`, `./update`, `./restore`) `prowlarr-stack` writes the
   **wiring file**, `${XDG_STATE_HOME:-~/.local/state}/prowlarr-stack/wiring.json`,
   directory 700 and file 600: the Prowlarr address and key, both protocol
   slots with their credentials, and the completed directory, with
   `127.0.0.1` addresses and the published ports. The schema (format 1) is in
   the `MediaCentaur.Downloads.Wiring` moduledoc and in the stack's
   `docs/architecture.md`, "Wiring file".
2. **Media Centaur** — `Downloads.Wiring.proposal/0` reads the file and asks
   `Capabilities.integration_changes/2` what a save of its values would
   change. A difference is a `Wiring.Proposal`, drawn by
   `Components.Settings.WiringProposal` at the top of Settings → Acquisition
   and on the setup flow's Prowlarr step: the addresses, which fields change
   (never a credential), and whether the completed directory is inside a
   media directory.
3. **The person** — *Accept and test* saves Prowlarr and both slots through
   `Capabilities.save_integration/2` (the form's writer) and verifies each
   connection. *Decline* records the wiring's values as declined, so the card
   returns only when a value changes.

Rules the code holds:

* The wiring is taken whole or not at all. An unknown format, a missing
  field, a client type with no driver, or a file another user can write is
  stated on the card and changes nothing. A slot the file omits is left alone.
* Accept applies the file only while it still holds the values the card
  showed.
* There is no endpoint for wiring. Loopback is not a trusted address
  ([ADR-085](../decisions/architecture/2026-11-09-085-the-local-api-is-admitted-by-its-key.md)),
  so do not add a receiver under `/api` or anywhere else. Trust is file
  ownership.
* A showcase-mode instance reads no wiring; the test environment points the
  path (`:stack_wiring_path`) at a file that does not exist.
* The file is read when Settings → Acquisition or the setup step loads.
  Nothing watches it.

**Without the stack** (a person's own Prowlarr), the handoff is by hand:
Settings → Acquisition → *Detect from Prowlarr* reads Prowlarr's
`/api/v1/downloadclient` and pre-fills each detected client into its slot's
form (`ClientConfig.protocol_for_type/1` routes them). Prowlarr never returns
credentials and often reports Docker-internal hostnames, so the person reviews
the address, enters the credential, saves, and runs each slot's test.

**When either repo grows an integration surface (a new client, a new
credential, a new service), the wiring format, this section and the checklist
below are the places to update.** A new field the app must read is a new
format number; the app refuses a format it does not know.

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
      `Req.Test` tests (`test/media_centaur/downloads/download_client/`), the
      client's answers added to `conformance_test.exs` there (it fails until
      every module implementing the behaviour is listed), and an entry in
      `Dispatcher.module_for_type/1`. Export from the
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
- [ ] `prowlarr-stack`: the slot in the wiring file (`Downloads.Wiring`),
      service in the compose file, Prowlarr registration,
      completed dir inside MC's watched paths, VPN placement, `./setup`
      output + `.env` keys.
- [ ] Wiki: `Download-Clients.md` (table row + setup section),
      `Settings-Reference.md` (Acquisition subform), `Troubleshooting.md` if
      there's a new failure mode.
- [ ] This file, if the model itself changed.
- [ ] Live smoke test against the real client before calling it shipped.
