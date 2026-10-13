---
status: in-progress
started: 2026-10-12
last_updated: 2026-10-13
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

**Plan 1 merged to `main` at `b0843f10` (2026-10-12), not yet shipped.
Plan 2 withdrawn by the owner on 2026-10-13: built in full on branch
`app-owned-grabs`, exercised live, then dropped unmerged.** Every surface
on Incoming draws a job through `download_strip/1` from `Downloads.Phase`;
the pursuit row's footer, the Other downloads badge row and the modal's
own bar are gone, as are `Logic.state_*` and `PursuitStatus.downloads_done`.
Live check 2026-10-12 (one 10.6 GB bare-MKV release): *Moving* with a
file name and no figure, then Completed; the strip matched the story.
Still unverified live: the Verifying/Repairing/Unpacking line formats.

Plan 2 was the "coherent path" of the spec: the app fetches the release
through Prowlarr's download link and submits it to SABnzbd/qBittorrent
itself, so the client's job id is known at grab. Building and running it
live showed what it costs: a Category setting per client, two
migrations and a backfill, the plan-unit fix the review found, and
Prowlarr's per-indexer **Redirect** setting must stay off or the link
answers a redirect instead of the release (following it would reach the
indexer from the app's host, outside Prowlarr's VPN/proxy/Byparr path,
so it was refused). The owner judged that re-engineering the grab path
for a visual aim, and the campaign's visible symptom — a usenet job
listed under Other downloads as "Fetching NZB…" for the seconds before
SABnzbd names it, plus title-match edge cases — is not worth it. Prowlarr
keeps grabbing; pairing stays by title; the branch, its wiki edits and
its two dev-database migrations were all reverted. Open: ship.

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
* `2026-10-12` — A rung of a ladder is a *step*; the *phase* is the
  job's position (step, condition, figure). Both SABnzbd "Queued"
  sources draw as *queued* on *download*; the spec's "on verify" was
  amended. (spec glossary, `54df0489`)
* `2026-10-12` — The cell vocabulary gains `:underway` and `:ahead` for
  the ladder; the strip's cancel event carries the release name when the
  host gives no title (the handler requires one). (`0de031bd`)
* `2026-10-12` — `PursuitStatus.downloads_done` removed: the modal's strip
  reads no count, and the count lives in the composite sentence.
  (`ccd84f72`)
* `2026-10-12` — SABnzbd's *Moving* stage line names the file, never a
  figure; the indeterminate bar is its drawing. Observed live, pinned in
  `phase_test.exs`.
* `2026-10-13` — **Plan 2 withdrawn.** The app-owned grab path was built
  on `app-owned-grabs` (identity at grab, category per client, hand-off
  availability in Downloads, plan units storing their release) and
  verified live against SABnzbd, then dropped unmerged on the owner's
  call: it re-engineers the grab path and adds owner-facing constraints
  (Category per client; Prowlarr's per-indexer Redirect must be off) to
  cure a few seconds of "Fetching NZB…" under Other downloads. Prowlarr
  keeps grabbing and pairing stays by title. Learned on the way, for
  whoever revisits it: Prowlarr records a hit on its download link as a
  grab in its History (so that cost never existed); Prowlarr does not
  expose the client's job id anywhere; an indexer with Redirect on
  answers `301` to its own NZB link; a job added by `addfile` is
  *Downloading* from its first poll, so SABnzbd's Grabbing state never
  occurs on that path. Branch deleted; wiki reverted to `5861974`;
  the two migrations rolled back on the dev database.

## Next steps

1. ✅ **Plan 1** — merged to `main` at `b0843f10`.
2. ✅ Live check done 2026-10-12 (see Status); the observed Moving line
   is pinned in `phase_test.exs`. Verify/Unpack formats stay unverified
   until a rar'd release passes through — extend `Phase.stage_figure/1`
   if the first one differs.
3. ✗ **Plan 2** — withdrawn 2026-10-13 (see Decisions made). The plan
   file stays under `docs/superpowers/plans/` as history, headed as
   withdrawn.
4. Ship (`/ship minor`), then retire this file. The scheduled follow-up
   from the spec (hand-off availability into Connectivity) falls with
   plan 2.

## Completion criteria

* A usenet job in any phase (fetch, download, verify, repair, unpack,
  move) and a torrent job in any phase render through `download_strip/1`
  on the pursuit row, Other downloads and the pursuit modal; no surface
  draws its own bar or state word; `Logic.state_label/1` and siblings
  are gone.
* No URL and no API key from a client's job name reaches a view-model;
  a `Grabbing` slot renders as "Fetching NZB…".
* ~~Every grab records `download_id` on the target before the first
  poll; pairing by id only; Category per client; hand-off availability
  written by the drivers; ADR for app-owned grabs~~ — plan 2, withdrawn
  2026-10-13.
* Wiki (the Incoming page) updated for the strip; `mix precommit` clean;
  shipped.

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
