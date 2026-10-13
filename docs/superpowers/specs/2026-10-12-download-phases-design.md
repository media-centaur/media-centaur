# Download phases — design

Status: approved 2026-10-12, the coherent path with both extensions below.
*Amended 2026-10-13:* only the strip (plan 1) shipped. The grab change
(plan 2, "identity at grab") was built in full on branch `app-owned-grabs`,
verified live, and withdrawn by the owner as too much re-engineering of
the grab path for a visual aim; see `campaigns/download-phases.md`
(Decisions made) for what was learned. The "cheap path" below is the one
in effect: Prowlarr grabs, pairing stays by title, and a fetching job is
hidden behind the "Fetching NZB…" placeholder.

Owner decisions (2026-10-12):

- **Both protocols grab directly.** The app owns every grab, routed by
  protocol inside `Acquisition`; Prowlarr is search only. Torrent grabs post
  the `.torrent` bytes (already fetched to derive the infohash) or the magnet
  to qBittorrent; usenet grabs fetch the NZB through Prowlarr's download link
  and post the bytes to SABnzbd (`addfile`, not `addurl`, so SABnzbd never has
  to reach Prowlarr's hostname and the job is named from its first sighting).
  Title-containment pairing retires.
- **Category is a field on each client slot**, beside Address and the
  credential in the Settings connection form, seeded by Detect from Prowlarr
  (both of the owner's Prowlarr clients use `prowlarr`), default `prowlarr`.
- Consequence accepted: grabs made by the app no longer appear in Prowlarr's
  History or indexer grab statistics.

The Incoming page draws a download beautifully while bytes move and falls
apart on either side of that: before the client has named the job (SABnzbd
fetching the NZB) and after the transfer (verify, repair, unpack, move). This
is the redesign of that slice from first principles, then reconciled with the
code.

## Glossary

- **Job** — one entry in a download client: a torrent in qBittorrent, an NZO in
  SABnzbd. Today `Downloads.QueueItem`. Unchanged.
- **Job id** — the client's durable key for a job: the infohash for a torrent,
  the `nzo_id` for usenet. Today stored on `Target.torrent_hash`, which already
  holds nzo_ids (cancel routing relies on it) and is misnamed for them.
- **Step** — one rung of a protocol's ladder. Usenet: *fetch* (the client
  is pulling the NZB), *download*, *verify*, *repair*, *unpack*, *move*,
  *done*. Torrent: *metadata*, *download*, *done*. (Added 2026-10-12 during
  Task 2: the code names the rungs steps and the position the phase.)
- **Phase** — where a job is on its protocol's ladder: the current step,
  the condition on it, and the figure. A pure projection of the job's state
  and protocol; never stored.
- **Condition** — a qualifier on a step, not a step: *queued*, *paused*,
  *stalled*, *failed*, or none. SABnzbd's queue "Paused" is *paused* on
  *download*. *Amended 2026-10-12:* SABnzbd's history "Queued" (waiting for
  post-processing) and its queue "Queued" both reach the driver as one
  `:queued` atom, so both draw as *queued* on *download*; the lit step is
  misplaced for the seconds a job waits for post-processing, and that is
  accepted. The earlier text placed it on *verify*; the strip therefore never
  says "Queued for unpacking".
- **Stage line** — SABnzbd's `action_line` on a history slot, the live text of
  the post-processing stage ("Unpacking: 45%", "Verifying: 12/56"). Empty once
  the job completes. Not read today.
- **Phase figure** — how far through the current phase the job is, 0–1, or nil
  when the client gives no figure. From `progress` in *download*, parsed from
  the stage line in the post-processing phases, nil in *fetch*.
- **Download strip** — the one component that draws a job: the phase ladder,
  the phase word, the figure bar, the release name, size, client, telemetry age
  and cancel. Today drawn three ways: the pursuit row's footer, the orphan row,
  and the pursuit modal's activity block.
- **Unnamed job** — a job the client lists before it has a name. SABnzbd names a
  *fetch*-phase job after the URL it is fetching (API key included);
  qBittorrent names a *metadata*-phase torrent after its hash. Never drawn by
  the client's name.
- **Other downloads** — jobs no pursuit claims. Unchanged meaning.

## Core idea

A download is one job moving through a short, protocol-specific ladder of
phases, and every surface draws the job as its phase. The transfer bar the
page already has is the *download* phase's drawing; the other phases get the
same treatment instead of the leftover fields.

## What is wrong today, by cause

1. **Identity arrives late for usenet.** The grab goes to Prowlarr, which hands
   the NZB URL to SABnzbd; the app never learns the `nzo_id`. Pairing falls
   back to title containment. While SABnzbd is fetching the NZB the job's name
   is the URL, so the title never matches, the job lands under Other downloads
   as a text dump that prints the indexer API key, then jumps into the pursuit
   card once the client renames it.
2. **Post-processing has no figure.** The driver reads SABnzbd's history slots
   for state only and discards the stage line. With no percent and no ETA the
   footer degenerates to a state word beside a release filename.
3. **The zero clock leaks.** `blank_to_nil` passes SABnzbd's `"0:00:00"`
   through as an ETA.
4. **Three drawings of one idea.** The pursuit footer (text state, 3px bar),
   the orphan row (badge state, no bar) and the modal's activity block (8px
   bar, its own transition) each re-draw the job and have drifted.

## Greenfield shape

### Identity at grab

Every grab records the job id on the target before the first poll. Torrents
already do (`InfoHash` at grab). Usenet cannot derive one, so the app submits
the NZB itself: `DownloadClient.add/3` on the SABnzbd driver calls
`mode=addurl` with the result's Prowlarr download URL and returns the
`nzo_ids`; the target stores it. Pairing is then exact by job id for both
protocols from the first sighting. The *fetch*-phase job pairs with its
pursuit and is drawn on the card at step one of the ladder.

`Target.torrent_hash` becomes `download_id`, since it already carries both
kinds of key. The title-containment fallback in `QueueMatcher` stays for
torrents whose indexer exposed no hash; it stops being the usenet path.

The category question comes with this: Prowlarr-initiated grabs land in the
category Prowlarr's download-client config names, and the SABnzbd completed
folder follows the category, which the file watcher depends on. The app reads
that category once from Prowlarr's `/api/v1/downloadclient` (the same endpoint
the bootstrap script reads) and passes it as `cat`. One source of truth, no
new setting.

### Phase as a projection

`Downloads.Phase.of(QueueItem.t()) :: %Phase{ladder, current, condition, figure}`.
One module, one test table. `QueueItem.state` stays the client's word, used by
cancel routing, health and the status sentence as today; `Phase` is derived
from `{protocol, state, progress, stage_line}` and is never stored, so it is a
projection, not a second representation.

Drivers supply what the projection needs and nothing else: SABnzbd's history
mapping adds `stage_line`; `"0:00:00"` becomes nil; the *fetch*-phase name
becomes the placeholder `"Fetching NZB…"`, the exact precedent the qBittorrent
driver sets for metadata downloads. The URL, and the key inside it, never
reach a view-model.

### One download strip

`Components.Acquisition.DownloadStrip.download_strip/1` takes a
`DownloadProgress` (which gains `phase`) plus the cancel wiring. It draws:

- the ladder: one small segment per phase in the existing `CellVocabulary`
  (done steps filled, the current step lit, later steps dim, *repair* only
  when it happens). The shape of completion, not a percentage, as the unit
  segments already do (UIDR-014);
- the phase word as plain colored text, the condition speaking before the
  step ("Paused", "Queued");
- the figure bar in the existing 3px slot: the known fraction when there is
  one, otherwise an indeterminate sliding highlight (transform-only, within
  the animation rules) so the row still reads alive;
- the release name demoted to the secondary line, size, client, telemetry
  age, cancel, exactly as the transfer footer places them today.

The pursuit row (both doors), the orphan row and the modal's activity block
compose from it; none draws a bar or a state word of its own. The story
carries one variation per phase per protocol plus the conditions.

### The status sentence

`PursuitStatus.at_client_action/1` reads the phase figure so the modal's verb
line says "Unpacking · 45%" rather than "Post-processing at the download
client."; the next-step sentence is unchanged.

## Diff against the code, and each disposition

| Gap | Kind | Disposition |
|---|---|---|
| Usenet job id unknown until title pairing succeeds | wrong owner of identity | **Fix now**: `add/3` on the SABnzbd driver, grab dispatched by protocol, `nzo_id` stored at grab |
| `torrent_hash` holds nzo_ids | name lies about the type | **Fix now**: rename to `download_id` (migration, no compatibility path) |
| Stage line discarded; zero clock leaks; URL as a title | driver omits what the view needs | **Fix now** in `QueueItem.from_sabnzbd_*` |
| No phase concept; `state` mixes phases and conditions | missing projection | **Fix now**: `Downloads.Phase`; `state` kept as the client's word, explicitly not a second store |
| Three drawings of a job | duplicated surface | **Fix now**: one `download_strip`, three call sites |
| Badge in the orphan row vs text in the footer | two idioms | Resolved by the strip: plain text, the house rule for status labels |
| Modal bar is 8px with `transition-all` | drift | Resolved by the strip: the 3px `.progress-fill` bar everywhere |
| `matched_fetching_nzb` story asserts "no bar" | stale premise | Replaced by the ladder variations |
| Health judges only `:downloading` | out of scope | **Leave**: post-processing stalls are the client's to report; noted, not scheduled |
| Title-containment pairing | fallback that minted the edge cases | **Retire** (plan 2): every grab knows its job id; the torrent bytes or magnet the app submits carry the infohash, so no protocol needs it |
| `{:handoff, slot}` availability is written from Prowlarr's answer about *its* client | wrong writer once the app grabs | **Fix now** (plan 2): the driver's `add/3` answer writes it, the driver's `test_connection/1` probes it (`Downloads.HandoffAvailability`); name and consumers unchanged |
| `{:handoff, slot}` and `Downloads.Connectivity` then both measure the app's link to a client (submit path, poll path) | two representations of one fact | **Scheduled convergence**: fold the hand-off integration into Connectivity after plan 2 ships; until then the two agree by construction (same endpoint, same driver) |
| Grab-time transport | the NZB fetched by SABnzbd needs SABnzbd to reach Prowlarr's hostname | **Decided**: the app fetches the payload through Prowlarr's link and posts the bytes (`addfile`, `torrents/add`), so the only network paths are the two the app already has |

Plans: `docs/superpowers/plans/2026-10-12-download-phases.md` (phase projection, one download strip) and `docs/superpowers/plans/2026-10-12-app-owned-grabs.md` (identity at grab).

Nothing is left as a silent parallel path. If the owner declines the grab
change (below), the *fetch*-phase job is paired by elimination instead: one
Grabbing job and one handed-off usenet pursuit with no job pair; any
ambiguity leaves the job unlisted until it has a name. That is a heuristic
and is recorded here as such.

## Cost

The cheap path is the strip alone (items 2–4): a day's work, and it leaves
the usenet identity problem in place, patched by the placeholder name and the
elimination heuristic.

The coherent path adds the grab change: a driver callback, a protocol switch
at the one grab site, the category read from Prowlarr, the column rename and
the tests for each. Roughly a second day. What it buys is exact pairing from
the first poll for every usenet grab, an exact "never arrived" verdict, no
URL ever reaching a view-model, and the retirement of the usenet branch of
title matching, which is where the tracker-prefix and URL-name edge cases
have come from. Recommended.
