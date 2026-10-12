---
status: in-progress
started: 2026-10-12
last_updated: 2026-10-12
---
# Download phases and app-owned grabs

## Glossary

Terms are defined here before use; the design spec carries the same
table and `docs/GLOSSARY.md` gets them at completion.

| Term | Meaning |
|---|---|
| **Job** | One entry in a download client: a torrent in qBittorrent, an NZO in SABnzbd. `Downloads.QueueItem`. Unchanged. |
| **Job id** | The client's durable key for a job: the infohash for a torrent, the `nzo_id` for usenet. Today `Target.torrent_hash`, which already holds nzo_ids and is renamed `download_id`. |
| **Step** | One rung of a protocol's ladder. Usenet: *fetch* (the client pulls the NZB), *download*, *verify*, *repair* (only while it happens), *unpack*, *move*, *done*. Torrent: *metadata*, *download*, *done*. |
| **Phase** | Where a job is on its protocol's ladder: the current step, the condition on it, and the figure. A pure projection (`Downloads.Phase`), never stored. |
| **Condition** | A qualifier on a step, not a step: *queued*, *paused*, *stalled*, *failed*, or none. Both of SABnzbd's "Queued" sources arrive as one `:queued` and draw on *download*. |
| **Stage line** | SABnzbd's `action_line` on a history slot, the live text of the post-processing stage ("Unpacking: 45%", "Verifying: 14/56"). Blank once the job completes. Not read today. |
| **Phase figure** | How far through the current phase the job is, 0–1, or nil when the client gives no figure: `progress` in *download*, parsed from the stage line in post-processing, nil in *fetch*. |
| **Download strip** | The one component that draws a job: phase ladder, phase word, figure bar, release name, size, client, telemetry age, cancel (`Components.Acquisition.DownloadStrip`). Today drawn three ways: the pursuit row's footer, the Other downloads row, the pursuit modal's activity block. |
| **Unnamed job** | A job the client lists before it has a name. SABnzbd names a *fetch*-phase job after the URL it is fetching (API key included); qBittorrent names a *metadata*-phase torrent after its hash. Never drawn by the client's name. |
| **Other downloads** | Jobs no pursuit claims. Unchanged meaning. |
| **Payload** | What the app hands a client: an NZB's bytes with a filename, a `.torrent`'s bytes, or a magnet URI (`DownloadClient.payload/0`). Fetched through Prowlarr's download link by `Acquisition.ReleasePayload`. |
| **Grab** | The app submitting a release to the protocol slot's client and recording the job id on the target (`Acquisition.Grab`, `DownloadClient.add/3`). Today the grab goes through Prowlarr's grab endpoint, which hands the release to Prowlarr's own client and tells the app nothing about the job. |
| **Category** | The label the app files a grab under at the client; the client's completed folder follows it, so it must sit inside a watched media directory. A field on each client slot in Settings, seeded by Detect from Prowlarr, default `prowlarr`. |
| **Hand-off availability** | `{:handoff, slot}` in `IntegrationAvailability`: whether a release can be handed to the slot's client. Today written from Prowlarr's answer about *its* client; becomes the driver's own answer (`Downloads.HandoffAvailability`). Name and consumers unchanged. |

## Goal

Every surface on Incoming draws a download-client job as its phase on a
short protocol-specific ladder, from one component, so the NZB-fetch and
post-processing states stop rendering as text dumps (the owner's
complaint, 2026-10-12: "the during-download states are fantastic, but
these are just text dumps"). The root of the worst row is that usenet
identity arrives late — the app never learns the job id at grab — so the
app takes over every grab and records the id on the spot. Prowlarr
becomes search only.

## Status

**Designed and planned, nothing built.** The spec is approved by the
owner with both extensions (both protocols grab directly; category is a
field on each client slot). Two implementation plans are written, each
task with its tests, code and commit. Execution has not started; the
owner was asked subagent-driven vs inline and deferred to a new context.
Working tree: the spec, the two plans and this file, committed together.

## Principles

1. One representation per idea: one `Phase` projection, one download
   strip, one grab path, one job id column. No surface draws a bar or a
   state word of its own.
2. Identity is known at grab, never inferred from a name. Title matching
   retires rather than remaining as a fallback (CLAUDE.md: no
   compatibility paths).
3. Status labels are plain colored text, never a badge; only
   `transform`/`opacity` animate.
4. `mix` runs only as `~/scripts/agents/agent-mix`; test-first; every
   public function component gets a story.

## Decisions made

* `2026-10-12` — The phase ladder, not the fields, is what every surface
  draws; `QueueItem.state` stays the client's word and `Downloads.Phase`
  is a derived projection, not a second store. (spec)
* `2026-10-12` — The app owns every grab, both protocols; Prowlarr is
  search only. Owner chose this over usenet-only. (spec, owner)
* `2026-10-12` — Category lives on each client slot in Settings, seeded
  by Detect from Prowlarr, default `prowlarr`; not read from Prowlarr
  at grab time. (spec, owner)
* `2026-10-12` — Payload transport: the app fetches the release through
  Prowlarr's link and posts the bytes (`addfile`, `torrents/add`), so
  SABnzbd never needs to reach Prowlarr's hostname and the job is named
  from its first sighting. (spec)
* `2026-10-12` — `Target.torrent_hash` is renamed `download_id`; it
  already held nzo_ids. (plan 2)
* `2026-10-12` — Hand-off availability keeps its name and consumers;
  its writer and probe move to the driver's answers. Folding it into
  `Downloads.Connectivity` is a scheduled follow-up, not this campaign.
  (spec)
* `2026-10-12` — Accepted: grabs made by the app no longer appear in
  Prowlarr's History or indexer statistics. (owner)
* `2026-10-12` — Accepted hazard: targets grabbed before plan 2 ships
  carry no job id and stop pairing; the file still imports through the
  watcher. The CHANGELOG entry says so. (owner informed, not vetoed)

## Next steps

Execute the two plans in order, each on its own branch from `main`,
test-first, one commit per task, `mix precommit` clean before the
plan's last task. Subagent-driven development was recommended
(a fresh subagent per task, review between tasks); inline execution
is the alternative. Verified facts the plans rest on: Prowlarr's two
download clients both use category `prowlarr`; SABnzbd history slots
carry `action_line`, `postproc_time`, `nzo_id`, `url` (empty
`action_line` on completed jobs; the live format is unverified until a
job is mid-process — plan 1 Task 10 checks it).

1. **Plan 1** — `docs/superpowers/plans/2026-10-12-download-phases.md`,
   10 tasks, branch `download-phases`: driver facts (stage line, zero
   clock, placeholder name) → `Downloads.Phase` → `DownloadProgress.phase`
   → `:underway` cell state → `download_strip/1` + CSS + story → pursuit
   row composes it → Other downloads composes it (and `Logic.state_*`
   deleted) → modal activity composes it → status sentence carries the
   figure → precommit, docs, wiki.
2. Owner looks at Incoming with a usenet download in flight; confirm the
   stage-line format and extend `Phase.stage_figure/1` if it differs.
3. **Plan 2** — `docs/superpowers/plans/2026-10-12-app-owned-grabs.md`,
   9 tasks, branch `app-owned-grabs`: `Downloads.InfoHash` → `add/3` on
   both drivers → category on the slot → Settings field + Detect seeds it
   → `Downloads.HandoffAvailability` (Boundary cycle check inside) →
   `Acquisition.ReleasePayload` → `Acquisition.Grab` + the two jobs →
   column rename + id-only pairing → copy, ADR, wiki, CHANGELOG note.
4. Ship (`/ship minor`), then retire this file and open the scheduled
   follow-up (hand-off into Connectivity) only if it still qualifies as a
   campaign; otherwise do it as one change.

## Completion criteria

* A usenet job in any phase (fetch, download, verify, repair, unpack,
  move) and a torrent job in any phase render through `download_strip/1`
  on the pursuit row, Other downloads and the pursuit modal; no surface
  draws its own bar or state word; `Logic.state_label/1` and siblings
  are gone.
* No URL and no API key from a client's job name reaches a view-model;
  a `Grabbing` slot renders as "Fetching NZB…".
* Every grab (auto and manual, both protocols) records `download_id` on
  the target before the first poll; `QueueMatcher` has no title path;
  `QueueItem.normalized_title` is gone.
* Category is a field on both client forms, seeded by Detect, sent with
  every grab.
* `{:handoff, slot}` is written by `Downloads.HandoffAvailability` from
  the driver's answers; `Prowlarr.grab/2`, `grab_outage?/1`,
  `download_client_unavailable?/1`, `test_download_clients/1` are gone.
* ADR for app-owned grabs indexed; wiki (`Prowlarr-Integration.md`,
  `Download-Clients.md`, `Settings-Reference.md`, the Incoming page)
  updated; `mix precommit` clean; shipped.

## Pointers

* Spec (glossary, greenfield shape, incoherence table with
  dispositions): `docs/superpowers/specs/2026-10-12-download-phases-design.md`
* Plans: `docs/superpowers/plans/2026-10-12-download-phases.md`,
  `docs/superpowers/plans/2026-10-12-app-owned-grabs.md`
* Today's drawings of a job: `lib/media_centaur_web/components/acquisition/pursuit_row.ex`
  (`download_footer/1`), `lib/media_centaur_web/live/incoming_live/orphan_queue.ex`,
  `lib/media_centaur_web/components/acquisition/pursuit_activity.ex`
* Driver facts: `lib/media_centaur/downloads/queue_item.ex`
  (`from_sabnzbd_queue/1`, `from_sabnzbd_history/1`)
* Pairing today: `lib/media_centaur/acquisition/queue_matcher.ex`,
  `lib/media_centaur/acquisition/pursuits/observations.ex`
* Grab sites today: `lib/media_centaur/acquisition/jobs/grab_target.ex`
  (`hand_off/2`), `lib/media_centaur/acquisition/jobs/pursue_target.ex`
  (`grab_found/5`), `lib/media_centaur/search/prowlarr.ex` (`grab/2`)
* Hand-off availability today: `lib/media_centaur/search/prowlarr_availability.ex`,
  `lib/media_centaur/search/probe_job.ex`, `lib/media_centaur/integration_availability.ex`
* Cell vocabulary (UIDR-014): `lib/media_centaur_web/components/acquisition/cell_vocabulary.ex`
* Live SABnzbd and Prowlarr can be read from the dev node with the
  Tidewave `project_eval` tool (`MediaCentaur.Downloads.configured_clients/0`,
  `MediaCentaur.Secret.expose/1`, `MediaCentaur.Search.Prowlarr.default_client/0`).
