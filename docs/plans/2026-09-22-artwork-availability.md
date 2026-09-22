# Artwork availability — unification design

**Status:** implemented 2026-09-22 (decisions 8.1–8.3 taken as recommended; 4b revised the same day, §10; 4c and 4d remain scheduled)
**Trigger:** boot on 2026-09-22 15:36. Home rendered every poster, thumb and
logo as the image server's stand-in SVG because the browser fetched them 150 ms
before the NTFS media volume mounted. The server recovered two seconds later;
the open page never did.

## Glossary

| Term | Meaning |
|---|---|
| **media directory** | A configured root the watcher watches. Config key `media_dirs`. On this machine a symlink onto an NTFS volume mounted `nofail`, so boot does not wait for it. |
| **image cache** | `{media_dir}/.media-centaur/images`, one `{entity_id}/{role}.{ext}` file per `Library.Image` row. Owned by `Library.ImageCache`. It lives on the media directory's volume unless `images_dir` overrides it. |
| **availability** | Whether a media directory's volume is reachable right now. Live, per media directory, `:available` or `:unavailable`. Owner `Library.MediaFileAvailability`: `:persistent_term` for reads, a GenServer for writes, fed by the watcher's `watcher:state` broadcasts and republished as `{:availability_changed, dir, state}` on `library:availability`. Per-entity answer: `available_for_ids/1`, entity → watched file → media directory. |
| **presence** | Whether a file has been observed on disk. Durable, per file (`FilePresence`, ADR-045). `present?` on `DetailItem` and `SearchItem` means "at least one watched-file row". Not availability. This design does not touch it. |
| **projection** | An ETS read model rebuilt on source events and announced on `library:views` (ADR-041). All six library projections already treat `:availability_changed` as relevant. |
| **artwork URL** | `/media-images/<content_url>`, built by `ImageFiles.web_path/1`, served by `Plugs.ImageServer`. `?w=` selects a width derivative; `?v=` is the cache-buster that switches the response to `immutable`. |
| **disconnected render** | The HTML a LiveView returns to the initial HTTP request, before the WebSocket. The browser fetches every `<img src>` in it at once. |
| **connected render** | The render after the socket joins. LiveView patches the DOM by diff, so an unchanged `src` is never refetched. |
| **component placeholder** | The markup a component renders when its artwork URL is nil: the film icon in `library_cards` and `cinematic_shell`, the "storage not mounted" box on the Library card. |
| **image-server placeholder** | The 200 SVG `ImageServer` returns when the file is not on disk, sent `cache-control: no-store`. Retired by this design. |

## 1. Core idea

> **Whether an entry's artwork can be shown is decided once, in the read model,
> from the availability of the entry's media directory. Every artwork URL a page
> emits is servable at the moment it is emitted, and no layer below the read
> model re-decides it.**

Corollary: the disconnected render and the connected render are both pure
functions of the read model at their moment. If availability changed between
them, the DOM differs, and the browser fetches. No counter, no stream reset, no
HTTP-layer stand-in.

Why the incident follows from violating this: today the URL is emitted whether
or not the volume is up. The image server then decides "not servable" per
request and answers with a 200 stand-in. The browser records a successful load
of that URL. Nothing afterwards changes the URL, so nothing refetches.

## 2. Greenfield shape

**Availability model.** Unchanged. `MediaFileAvailability` is already the
single owner, already per entity, already broadcast. Its moduledoc says image
rendering consumes it; after this design that is true.

**Projections.** Every item that carries artwork carries `available?`, read
once per rebuild through `available_for_ids/1` (four bounded queries). Artwork
URLs on an unavailable item are nil. `DetailItem.available?` is set at build and
patched in place on `:availability_changed`, on the seam `reconcile_presence/0`
already provides for `present?`.

**Entity view.** `EntityView` carries `available?`. `LiveHelpers.image_url/2`
returns nil for an unavailable entity. That one function is where the detail,
status and shell components get a library artwork URL, so those sites change
nothing; they already have nil branches.

**Components.** `available?` arrives on the item, never through a per-page map.
One offline treatment on every surface, the one the Library card already has:
unavailable → the offline placeholder ("storage not mounted"), the entry's name,
and no Play; available with a URL → the image; otherwise the quiet placeholder.
Home's continue-watching and recently-added cards adopt it; today they would
fall through to the quiet placeholder, which reads as "no artwork" rather than
"offline".

**Hero.** `HeroCandidates` excludes unavailable entries. The rotation picks by
position in the candidate list, and a hero with no backdrop is not a hero. An
entry returns to the pool when its drive returns.

**Image server.** A file server. A file that is not on disk is a 404. The only
way a page reaches that is a data defect (file missing while the volume is up),
which `ImageHealth` and image repair own and Status shows.

**LiveViews.** Pages subscribe to `library:views` for artwork and nothing else.
A drive mounting reaches a page as `library_view_updated` after the projections
rebuild, the same path every other library change takes.

**Boot.** Unchanged. Watchers run their first check before the endpoint listens,
so a request cannot arrive during `:initializing` on a normal boot. The
optimistic `:initializing` bias stays: a request that does arrive then, on an
absent volume, yields 404s that heal on the next availability transition,
because the DOM changes.

What the design deliberately does not do: no dependence on fstab or systemd
ordering (the app must be right for every user's mount), no client-side retry,
no delaying the endpoint until drives mount.

## 3. Diff against reality

The idea "this entry's storage is reachable, so show its artwork" currently has
four representations.

| Where | Mechanism | Input | Covers | Fails |
|---|---|---|---|---|
| `Plugs.ImageServer` | 200 SVG stand-in, `no-store` | `File.regular?` per request | any page, any time | the page that already painted it |
| `HomeLive` | `:image_version` counter folded into `?v=` by `Logic.with_image_version/2` on `:availability_changed` (commit efc52fd5, 2026-05-05) | availability topic | a Home that is alive at remount | a Home mounted after the remount, which is this incident: both renders start at version 0 and emit identical URLs |
| `LibraryLive` | `availability_map` + `dir_status` + `unavailable_count` assigns, `available` attr on the card, grid stream reset on `:watching` | `available_for_ids/1` per page | Library, both cases | nothing on its own page; the rule is trapped in one LiveView and Home does not have it |
| `Views.Detail` | `present?` patched in place | watched-file rows | presence | not availability, not artwork |

The Library page is the surface that already implements the core idea, per
page: it suppresses the `<img>` server-side when the entry is unavailable, so
its disconnected render before a mount and its connected render after differ,
and the browser fetches. The design promotes that rule from one LiveView into
the read model and deletes the per-page plumbing everywhere.

Also present: `HomeLive` assigns `availability_map: %{}` and never fills it, a
half-adoption of the Library approach next to the counter.

## 4. Incoherences and dispositions

| # | Incoherence | Disposition |
|---|---|---|
| a | ADR-041 says consumers enrich per-row with availability from their own LiveView state. The projections already rebuild on `:availability_changed` and Detail already carries presence, so the principle is breached for identity but kept for artwork. | **Fix now.** Dated amendment to ADR-041: availability is projection data. Progress and playback stay per-page. |
| b | The image server answers "not here" with a 200 body, a presentation decision made at the HTTP layer with a different input than the read model. | **Fix now.** Remove `send_placeholder/2`; missing file → 404. The visual result of a 404 on the rare defect image must be checked in a real browser during implementation (`alt` text and Chromium's broken-image glyph), not assumed. |
| c | Five builders of the artwork URL (`Views.Browse`, `Library.Images`, `Library.Posters`, `Library.HomeFeed` ×2, `LiveHelpers.image_url/2`); only the last appends `?v=updated_at`, so the same file has two URL forms with different cache lifetimes. | **Schedule.** One builder in `Library.Images` used by every projection and by `image_url/2`. Convergence point: the commit immediately after this slice, on its own, because it changes the grid's cache lifetime and `ArtworkWarmup`'s byte-identical URL test is the forcing function. |
| d | An `Image` row does not record which media directory's cache holds its file. `ImageCache.resolve_path/1` searches every cache, and image availability is inferred through the entity's watched files. | **Schedule.** Add `media_dir` to `library_images`, paired migration and idempotent backfill. Convergence point: the next release that carries a migration. Not needed for this fix: the pipeline writes an image into the entity's own media directory cache, so entity availability equals image availability by construction. |
| e | `present?` (durable, per file) and `available?` (live, per media directory) are two words for two ideas. | **Not an incoherence.** Record both in `docs/GLOSSARY.md` so they are never merged. |
| f | `MediaFileAvailability` moduledoc claims image rendering consumes it; no artwork path does. | **Fix now.** Falls out of the design; update the moduledoc. |
| g | `MediaCentaurWeb.MediaFileAvailability` (web helper) and `Logic.with_image_version/2` exist only to serve the per-page mechanisms. | **Fix now.** Delete with their callers. |

## 5. Scope cost

Touched, roughly twenty files.

- **Read models.** `BrowseItem`, `ContinueWatchingItem`, `HeroCandidatesItem`,
  `RecentlyAddedItem`, `DetailItem` gain `available?`; each projection makes one
  bulk availability call per rebuild; Detail's in-place reconcile also patches
  `available?`. `SearchItem` has no artwork and is untouched.
- **Entity view.** One field on `EntityView`, set by both adapters
  (`DetailItem.to_entity_view/1`, `EntityShape.to_entity_view/2`); one guard in
  `image_url/2`.
- **Deletions.** Home's `:image_version` and `Logic.with_image_version/2`;
  Library's `availability_map`, `dir_status`, `unavailable_count`, the stream
  reset, and the web `MediaFileAvailability` helper; `library_half.available?/1`
  (one DB read per render, replaced by the projection field); the image-server
  placeholder branch and its fifteen assertions, replaced by 404 assertions.
  Home's and Logic's `image_version` tests go with the mechanism; the scenario
  they pinned, artwork repopulates after a remount, is re-asserted against the
  new mechanism. ADR-027 scopes append-only to parser and pipeline suites.
- **Components and stories.** `library_cards` reads `entry.available?`;
  `continue_watching_row` and the recently-added card gain the offline
  treatment from `item.available?`; `hero_card` needs nothing because
  unavailable entries never reach it. Story variation matrices gain the
  offline state on each of those (MC0009).
- **Records.** ADR-041 amendment; `docs/GLOSSARY.md` entries for availability,
  presence, artwork URL; `MediaFileAvailability` moduledoc.
- **Wiki.** Troubleshooting: an entry whose storage is offline shows the offline
  placeholder on every page, and its artwork appears when the drive mounts,
  without a reload.

## 6. Verification (test-first)

1. **Projection.** An entity whose media directory is `:unavailable` projects
   with `available?: false` and nil artwork URLs; flipping availability and
   rebuilding restores them. One test per projection that carries artwork.
2. **The boot race, as a LiveView test.** With the directory unavailable, the
   disconnected render of Home contains no `/media-images/` `src`. Mark the
   directory available, let the projections rebuild, and the connected render
   contains them. This is the incident, reduced to the two renders.
3. **Alive at remount.** A connected Home and a connected Library re-render
   with artwork after `library_view_updated` follows `:availability_changed`.
4. **Image server.** Missing file → 404; present file unchanged.
5. **Real browser.** Stop the app, unmount `/mnt/videos`, start the app, open
   Home, mount the volume. Artwork appears without a reload. Then the same with
   the Library page open and with a detail modal open.

## 7. Walkthrough: three media directories, one drive offline

Three media directories on three drives; the third is a USB drive that is not
plugged in when Home loads.

- **Load.** The watcher for the third directory failed its first check and is
  polling the path every 2 s. The availability model holds it `:unavailable`.
  Every projection was built with that. Home's hero comes from the first two
  drives. Continue Watching and Recently Added show the third drive's entries
  with the offline placeholder, their name, and no Play; the rest render
  normally. The disconnected render and the connected render agree, so nothing
  is fetched that cannot be served. Library shows the same offline cards. A
  detail opened on one of them shows the quiet backdrop, the offline Play
  state, and its episode list, since presence rows are untouched. Status's
  storage tile shows the drive offline.
- **Plug the drive in.** The OS mounts it at the configured path. Within 2 s
  the watcher's poll sees the device, starts inotify, and broadcasts
  `:available`. The availability model flips the directory and republishes.
  The five artwork projections rebuild and Detail patches `available?` in
  place; each announces on `library:views`. Every open page re-reads: offline
  cards become artwork cards, Play returns, the hero pool regains the third
  drive's candidates at the next rotation, the storage tile shows online. No
  reload, no cache-buster. In parallel, the watcher's recovery scan imports
  anything added to the drive while it was away, the absence sweeper resets
  the presence clock for that directory so nothing is purged for having been
  unseen, and the hoist rule re-presents collections whose child counts
  changed.
- **Unplug it again.** inotify reports the unmount at once; the watcher
  broadcasts `:unavailable`; the same chain runs the other way and the cards
  go offline. Presence rows are kept: the absence sweeper never purges files
  on an unavailable directory.

One limit worth stating: an entity's availability is that of its *first*
watched file's directory. Two renditions of one title on two drives, one of
them the USB drive, resolve to whichever file comes first. Rare with three
separate libraries; exact once (4d) lands.

## 8. Decisions for the owner

1. Approve the ADR-041 amendment (4a).
2. 404 for a missing file, no stand-in response (4b). Recommended.
3. Keep (4c) and (4d) scheduled as stated, or pull either into this slice.
   Recommended: scheduled. Both are exact improvements; neither is needed to
   make the core idea hold.

## 9. Verification results (2026-09-22)

Headless Chromium against the dev server, media-library symlink removed
before a service restart, one page held open, symlink restored while it
stayed open (`~/scripts/agents/mc-bootrace`). The watcher noticed the
directory within its 2 s poll; the projections rebuilt; the page changed
with no navigation entry added.

| Page | Before the mount | After the mount | Elapsed |
|---|---|---|---|
| Home | 44 offline blocks, no library artwork, no hero | 0 offline blocks, 63 loaded artwork images, hero back | 2.2 s |
| Library | 39 offline blocks, no artwork | 0 offline blocks, 39 loaded posters | 1.6 s |
| Home with a detail open | modal: 0 artwork images | modal: 2 loaded artwork images | 2.7 s |

Test suite: `mix precommit` green (7678 ExUnit, 830 bun).

## 10. Revision: the read model checks the file (2026-09-22)

The 404 of 4b left one visual the owner rejected: a file that vanished
after it landed (a wiped or damaged image cache) reached the page as the
browser's broken-image glyph — the browser deciding what a missing file
looks like, which is a second decider by another name. Options weighed:
a stand-in response for the defect case only (the shape 4b removed), hiding
the glyph with empty `alt` (per-site, one browser's behaviour), a durable
presence flag with a sweep job (the long-run shape, with 4d), or the read
model checking the file. The last keeps the one rule.

Renderable now means the directory is available **and** the file is on
disk, evaluated where the read model takes artwork in:

- `Views.ItemAvailability.resolve/2` also nils an artwork URL whose file
  `ImageCache.resolve_path/1` — the lookup the image server serves from —
  does not find; only for available directories, so an unmounted path is
  never touched.
- `Library.Image` gains a virtual `present?`, set by
  `Library.Images.with_presence/1` on every row the detail projection takes
  in (the entity's own, its episodes', its collection members'), and
  re-checked in place on the availability event once per entity payload.
  `LiveHelpers.image_url/2` withholds the URL of a row whose file is
  missing.
- Hero candidates need their backdrop on disk, not just a backdrop row.
- The image server, on a miss for a library path, reports the fact
  (`Library.report_missing_artwork_file/1`): the owner's container — the
  series for an episode thumb — is broadcast as changed, every projection
  re-checks, and the page swaps the broken image for its placeholder.
  Reporting is not deciding.

Cost: one file stat per artwork URL per rebuild, skipped for unavailable
directories. Test fixtures changed to match: a test that expects a served
URL now registers a media directory and writes the file
(`TestFactory.register_media_dir/1`, `create_image_with_file/2`).

Verified against the dev server: a poster file moved out of the cache
while the drive was up, Library opened cold with the projection still
carrying the URL. 388 ms after the page connected the card showed the quiet
placeholder and no broken image remained on the page.

A file restored by hand shows the placeholder until the next rebuild; the
repair path bumps the row and rebuilds, so the artwork returns on its own.

