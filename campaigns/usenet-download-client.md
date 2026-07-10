---
status: implemented (2026-07-10 — MC-side P1–P3 built & committed same day as the reconciliation; remaining = wiki page + live smoke test once the user enters the SABnzbd API key)
started: 2026-05-31
last_updated: 2026-07-10
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

## Reconciliation (2026-07-10 — live stack confirmed, before any code)

The user updated the Prowlarr stack: **SABnzbd is now added as a second
download client and is live.** Re-derived the whole design from scratch this
session (independent of this file) and it converged on the exact model below —
so the 2026-05-31 plan stands. Concrete facts learned by querying the *running*
dev node (`MediaCentaur.Search.Prowlarr.list_download_clients()` + raw
`GET /api/v1/downloadclient`), all resumable:

* **P0 is DONE.** Prowlarr now returns **two enabled clients**: `qBittorrent`
  (`type: "qbittorrent"`, `http://192.168.68.67:8080`) and **`SABnzbd`**
  (`type: "sabnzbd"`, `http://192.168.68.67:8085`, `username: nil`). MC could
  see and reach both. The stack-side service (download-stack-control-plane P1)
  is live; **only MC-side P1–P4 remain.**
* **SABnzbd's Prowlarr config contract** (`configContract: "SabnzbdSettings"`,
  `protocol: "usenet"`, `implementation: "Sabnzbd"`): fields =
  `["host","port","useSsl","urlBase","apiKey","username","password","category","priority"]`.
  **Auth is `apiKey`** (privacy `apiKey`, returned masked as `********`) — so
  like the qBit password today, MC can pre-fill URL from Detect but the **user
  must enter the API key** in Settings. The driver calls
  `GET {url}/api?apikey=KEY&mode=queue|history&output=json`.
* **`Prowlarr.list_download_clients` already normalizes `type: "sabnzbd"`**
  (`normalize_type/1` downcases any non-qBit implementation). No parse change
  needed for Detect — the Settings **type `<select>` just needs a `sabnzbd`
  option** (`acquisition_section.ex` currently offers only qBittorrent).
* **`SearchResult.from_prowlarr/1` discards Prowlarr's `protocol` field.**
  Prowlarr returns `"protocol": "torrent"|"usenet"` per result; MC drops it.
  `SearchResult` has no `:protocol` field. **This is the field the multi-client
  model needs** — first fix-now item.
* **`HealthHistory` is throughput-based** (`%{id => [{monotonic_us, size_left_bytes}]}`),
  **not** seeds/peers — so health classification is already protocol-agnostic.
  Lowers risk #4 to "map SAB status strings to the neutral `state` enum without
  reading `verifying/repairing` as stalled."
* **Import is already client-agnostic** — completed files land in a watched dir
  and import regardless of source (file watcher → Ingest → InboundListener).
  No import-side work.
* **Grab is already protocol-agnostic** — `Prowlarr.grab/1` posts guid+indexerId;
  Prowlarr routes usenet releases to SABnzbd on its own. No grab-side work.
* **Identity already tolerates usenet** — `Pursuits.Identity` "Strategy 4"
  (normalized release name) + `QueueMatcher`'s title fallback + `LibraryReconciler`
  content-path already pair hashless grabs. Confirms the "provisional identity"
  decision below is viable as-is for v1.
* **Owner decision (reaffirmed 2026-07-10):** **both clients monitored at once**
  (multi-client), not swap-only. Swap-only was named as the bolt-on and rejected —
  it makes one of the two live clients invisible in-app, which is exactly this
  user's setup.

Net: the single real gap is still **multi-client queue monitoring** (P1+P3).
Everything else (grab, import, identity) is already neutral. Next session can
start writing code directly against P1.

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
* `2026-07-10` — **P0 confirmed live.** Prowlarr now has qBittorrent + SABnzbd both enabled (`sabnzbd`, `:8085`, `apiKey` auth). Stack side is done; MC-side P1–P4 remain. No design change — re-derived model matches.
* `2026-07-10` — **`ClientConfig` value type + `configured_clients/0` accessor** is the unification point. Storage stays **flat config keys** (existing generic `download_client_*` = torrent slot; add `usenet_download_client_*`), unified behind `Downloads.ClientConfig` / `Downloads.configured_clients/0`. *(Rejected: a nested `download_clients` map settings-blob — a bigger config-model migration + `@sensitive_keys` complications for no gain over two flat slots.)*
* `2026-07-10` — **Torrent-vocabulary rename is deferred, explicitly.** `Target.torrent_hash`, `DownloadStarted` `:infohash` payload key, and UI copy saying "torrent" all degrade correctly to nil/text for usenet. Renaming touches a schema column + an event contract, so it is a **scheduled follow-up vocabulary pass**, kept out of this monitoring feature (no migration smuggled in).
* `2026-07-10` — **`cancel_download/1` routes by the item's protocol.** With two clients, cancel must reach the *owning* driver: look the id up in the live merged `QueueState`, dispatch to that item's protocol driver (fallback: try each driver). `QueueItem` gains `:protocol` for this.
* `2026-07-10` — **Built (P1–P3, four commits).** Deviations & refinements vs. the plan, all recorded in moduledocs:
  * **Cancel fallback = id shape, not try-each.** Trying each driver was rejected mid-build: qBittorrent answers 200 to deletes of unknown hashes, so a wrong-client try reads as success and the real client never gets the cancel. SABnzbd ids are always `SABnzbd_nzo_…`, so the shape is deterministic.
  * **`test_connection` uses `mode=queue`, not `mode=version`.** `mode=version` is unkeyed — a wrong API key would pass the Settings test and then fail every poll. The keyed endpoint makes "Test connection" actually validate the key.
  * **Completed items now stay in `QueueState.items`** (excluded from health classification). Required for history-based completion: the `storage` path lives on the Completed history entry, and `DownloadIdentity` two-phase-captures it (title match pins the nzo_id into `Target.torrent_hash`, completion fills `content_path`) with **zero new identity code** — regression-tested in `download_identity_test.exs`.
  * **Terminal failure = Policy rule 3, no window:** `{:auto_cancel, :download_failed}`, gated on `failure_message` presence so qBittorrent's ambiguous `error`/`missingFiles` states stay out of the auto-pivot path. Rides the existing AutoCancel pivot (cancel + re-search, guid excluded).
  * **Per-slot capability tests.** `:usenet_download_client` is its own test subject; `download_client_ready?` = any slot configured+tested; `client_ready?/1` gates each slot's polling. One slot's test never vouches for the other.
  * **`QueueState.client_connectivity`** (per-slot grades) added next to the merged worst-grade `connectivity`, so one client's outage doesn't paint the healthy one. UI adoption of the per-slot detail is a follow-up.
  * **No new ADR.** ADR-035 (Prowlarr = integration point) survives intact by design; the two-slot model lives in the `ClientConfig`/`Dispatcher`/`QueueMonitor` moduledocs, per the moduledoc-over-ADR rule.

* `2026-07-10` — **First real payloads validated the identity design** (commit
  `af3b3dd0`): both live usenet pursuits reached `satisfied` end-to-end via
  title-match → nzo_id pin → name-match landing, with zero new identity code.
  Facts learned: **SABnzbd 5 nzo_ids are bare UUIDs** (no `SABnzbd_nzo_`
  prefix — cancel fallback now routes by 40-hex-infohash shape instead);
  Prowlarr's grab history carries **no client job id** (`grabTitle` only), so
  id-at-grab is impossible for usenet — first-sighting pinning stands as the
  design; history `storage` paths are container-internal, so `content_path`
  is only pinned when it exists on this host. Also `InfoHash.resolve/2` now
  skips usenet results (it was fetching whole NZBs just to fail parsing).
  Topology hardening shipped alongside: stack v1.1.0 stages SAB jobs in
  `completed/.staging` + atomic move-in; MC translates inotify renames and
  reserves `.staging` (commits `92a2753b`, stack `v1.1.0`).

## Next steps

Phased; each phase ships something real without depending on the harder logic
that follows.

1. **P0 · stack: add the SABnzbd service. ✅ DONE (confirmed live 2026-07-10).**
   *(Owned by [`download-stack-control-plane`](download-stack-control-plane.md).)*
   SABnzbd is registered as Prowlarr's second download client and reachable from
   MC (`type: "sabnzbd"`, `:8085`). This campaign keeps the **MC-side** work
   below (P1–P4).
2. **P1 · config & dispatcher. ✅ DONE 2026-07-10** (commits `b3d1ed4b`,
   `12338803`). `SearchResult.:protocol`; `usenet_download_client_*` slot;
   `Downloads.ClientConfig` + `configured_clients/0`; `Dispatcher.drivers/0` +
   `driver_for/1` (legacy `driver/0` deleted in P3 once caller-less); Settings
   Usenet Client form (SABnzbd type, URL, API key) with its own save/test;
   Detect routes Prowlarr's clients to both slots; per-slot capability tests.
3. **P2 · SABnzbd driver. ✅ DONE 2026-07-10** (commit `fde389e4`). Full-fetch
   `sync/1` (no RID equivalent — snapshot fingerprint for movement), history
   window limit 30, keyed `test_connection`, 200-with-error-body auth
   classification. `QueueItem`: `protocol`, `verifying/repairing/extracting`,
   `failure_message`, history-only `content_path`.
4. **P3 · multi-client monitor + matching. ✅ DONE 2026-07-10** (commit
   `aca96185`). Merged per-slot polling with per-client bookmarks/items/
   connectivity; completed items kept in the snapshot; two-phase usenet
   identity confirmed against existing `DownloadIdentity` machinery;
   protocol-routed cancel; `{:auto_cancel, :download_failed}` policy rule.
5. **P4 · verify & document.** Stubs green; full suite green (2 pre-existing
   "Database busy" concurrency flakes, clean standalone). Remaining:
   * Wiki **Download Clients** page (SABnzbd setup) — drafted, push when the
     feature ships in a release.
   * **Live smoke test** — needs the user to enter the SABnzbd API key in
     Settings → Acquisition → Usenet Client (agent access to read the key out
     of the container was declined, correctly). Then: Test connection → green
     dot, Downloads page shows SAB queue, and a real usenet grab exercises
     history-completion + import.
   * The **richer status enum in the Downloads UI** shows raw SAB statuses via
     the existing state/status rendering; verify "Repairing…" copy reads well
     with real payloads (follow-up polish).

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

* **SABnzbd (live coordinates, 2026-07-10)** — `http://192.168.68.67:8085`,
  registered in Prowlarr as `SABnzbd` / `type: "sabnzbd"`. **JSON API** (all via
  `GET {url}/api?apikey=KEY&output=json&...`): `&mode=queue` (live slots:
  `nzo_id`, `filename`, `mb`, `mbleft`, `percentage`, `status`, `timeleft`),
  `&mode=history` (completed: `nzo_id`, `name`, `storage` ← **the `content_path`
  source**, `status`, `fail_message`), `&mode=version` (test_connection),
  delete = `&mode=queue&name=delete&value=NZO_ID&del_files=1`. **No RID delta**
  (unlike qBit) — `sync/1` fetches full queue+history each tick; `driver_state`
  holds the last snapshot for movement/summary. Verify the exact field names
  against SABnzbd's live `mode=queue` output before hardcoding (docs vs. build
  drift). API key: user-entered (Prowlarr masks it).
* **Download-client abstraction** — `lib/media_centaur/downloads/download_client.ex` (behaviour — 4 callbacks: `list_downloads/test_connection/sync/cancel_download`; moduledoc already names SABnzbd/usenet), `downloads/download_client/dispatcher.ex` (the seam to grow to `drivers()`), `downloads/download_client/qbittorrent.ex` (reference driver: auth, sync, list, cancel).
* **Queue monitoring** — `lib/media_centaur/downloads/queue_monitor.ex`, `downloads/queue_state.ex`, `downloads/queue_item.ex` (gains `protocol` + status enum), `downloads/download_client/qbittorrent/sync.ex` (qBit RID delta — SABnzbd has no equivalent; poll full queue+history).
* **Health** — `lib/media_centaur/downloads/health.ex`, `downloads/health_history.ex`.
* **Pursuit matching / identity** — `lib/media_centaur/acquisition/queue_matcher.ex` (infohash-first + title fallback), `acquisition/pursuits/download_identity.ex` (`content_path` capture), `acquisition/info_hash.ex`.
* **Grab flow** — `lib/media_centaur/acquisition/jobs/pursue_target.ex`, `search/prowlarr.ex` (the `POST /api/v1/search` grab), `search/search_result.ex` (no protocol field today).
* **Config** — `lib/media_centaur/config.ex` (`download_client_*` keys ~L48), `defaults/media-centaur.toml`, plus the Settings DB / UI for download-client config.
* **Lifecycle** — `lib/media_centaur/acquisition/pursuits/pursuit.ex`, `acquisition/target.ex`, `acquisition/pursuits/inbound_listener.ex` (file-landed → IdentityVerifier).
* **prowlarr-stack** — `~/src/media-centaur/prowlarr-stack/docker-compose.yml` (qBit + gluetun today), `README.md`, `defaults/`.
* [ADR-035](../decisions/architecture/2026-04-15-035-acquisition-prowlarr-integration.md) (Prowlarr integration), [ADR-037](../decisions/architecture/2026-04-16-037-acquisition-integration-scope.md) (integration scope / direct-driver relaxation), [ADR-043](../decisions/architecture/2026-05-10-043-acquisition-split.md) (Search/Downloads context split), [ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md) (campaign convention).
* **Sibling campaign** — media-search (complete 2026-06-10, in git history): the coverage planner that turns this infrastructure into the "user doesn't care" mixed grab.
