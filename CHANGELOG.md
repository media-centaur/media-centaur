# Changelog

User-facing release notes for Media Centarr. Internal refactors, test
changes, and dependency bumps with no user impact are omitted here —
see the git history for the full engineering trail.

## v0.29.1 — 2026-05-01

### Improved

- **Coming Up marquee polish.** Secondary tiles in the Coming Up section
  on the home page now anchor their show logos at the bottom-left with
  a diagonal scrim, so they stay legible on bright artwork instead of
  washing out. The redundant "Scheduled" badge that appeared on every
  tile is gone — the badge is reserved for states that actually mean
  something different, like Grabbed, Downloading, and Pending. When
  only one other show is upcoming alongside the hero, the tile no
  longer stretches to fill the full column height; it sits at a
  natural 16:9 with breathing room above and below.

## v0.29.0 — 2026-05-01

> **UI overhaul in progress this week.** A complete pass over the visual
> design is shipping in small increments — every release this week is a
> noticeable step up for mouse-driven use. Keyboard and gamepad navigation
> are paused while the UI settles and resume next week; if you drive Media
> Centarr from the couch, hold off on updating, or update and accept that
> some focus rings and shortcut behaviour will be temporarily off.

### Improved

- **Show logos in Coming Up.** The Coming Up marquee on the home page
  now displays each show's logo when one is on file, falling back to
  refined typography otherwise.

- **Show logos on Upcoming Active cards.** The Active section on the
  Upcoming page does the same — show logos lead the card, with the
  show name as the fallback.

- **Continue Watching breathing room.** Continue Watching cards on the
  home page now have a small extra gap between them so they're easier
  to scan, and the cards no longer scale-grow on hover.

- **Tighter Downloads activity.** Long groups in the Downloads activity
  list collapse when there are many entries, so a single noisy series
  no longer dominates the view.

- **Searches show file size.** The featured row in an acquisition
  search result now shows file size at a glance.

- **Post-grab Downloads UX.** The Downloads page tightens up after you
  pick a result and trigger a grab — fewer extra clicks to confirm
  what just happened.

- **Better stalled vs queued signal.** Acquisition shows a clearer
  difference between a download that's actively waiting in the queue
  and one that's gone quiet, so you know when to nudge it.

### Removed

- **Light theme and theme switcher removed.** Media Centarr is now
  dark-only. The theme picker in the sidebar is gone. The dark theme
  is genuinely good and tuned for couch-distance reading; a future
  light theme will return only if it can match that bar. If you were
  on light, you'll see dark on next launch — your other preferences
  are unchanged.

## v0.28.1 — 2026-05-01

### Improved

- **Faster initial page rendering.** Library, Home, Upcoming, History,
  Review, Settings, and Downloads now skip the duplicate data fetch
  that previously ran on the first paint — pages reach their
  interactive state with less redundant work, most noticeable on
  larger libraries.

## v0.28.0 — 2026-04-30

### New

- **Searches survive navigation.** Acquisition searches and their
  results now persist when you leave the page. Start a search,
  navigate anywhere else in the app, and when you come back the
  query, results, and selections are right where you left them.
  Searches reset only when the server restarts.

### Improved

- **Cinematic detail modal on the home page.** The home page detail
  panel now opens as a single-scroll cinematic surface — the
  same controls (Play, Mark watched, seasons, tracking) presented
  in a more immersive page-style layout.

- **Coming Up marquee on the home page.** A new cinematic marquee
  highlights upcoming releases on the home page, with sharper
  artwork rendering for hero and card images throughout the page.

## v0.27.5 — 2026-04-30

### Improved

- **Detail panel opens on the home page.** Clicking a card in
  Continue Watching or Recently Added now opens the title's
  detail panel right there on the home page — no more bounce to
  the Library page. Hit Play, mark watched, expand seasons,
  manage tracking; everything that worked in the Library detail
  panel works on the home page now.

- **Hero uses each title's logo when available.** The home page
  hero now displays the title's logo image when one is on file,
  with refined typography as the fallback for titles that don't
  have one.

- **Continue Watching card sizing tuned for distance.** Cards in
  the Continue Watching row are now sized for comfortable scanning
  from across the room.

- **Page-level atmosphere on the home page.** The backdrop fade and
  side dim now run the full length of the home page instead of
  ending at the hero, so the rows below sit on the same calm band.

### Fixed

- **Continue Watching no longer auto-plays on click.** Clicking a
  Continue Watching card now opens the detail panel and waits for
  you to hit Play — it was unexpectedly starting playback as soon
  as the panel appeared.

## v0.27.4 — 2026-04-29

### Fixed

- **Home page cards are clickable again.** Cards in the Continue
  Watching, Coming Up, and Recently Added rows on the Home page now
  open the title when you click them. Previously they rendered as
  static images that ignored clicks.

## v0.27.3 — 2026-04-29

### Changed

- **Hero backdrop top-aligned.** The Home page hero now anchors the
  backdrop image to the top of the card so faces and logos in the
  upper portion of the frame stay visible, instead of being pushed
  off the top by center-cropping. Card height is unchanged.

## v0.27.2 — 2026-04-29

### Changed

- **Home page row order.** Recently Added now sits above Coming Up.
  The new order is Hero → Continue Watching → Recently Added → Coming
  Up, putting "what's already on the box right now" before "what's
  coming later".

## v0.27.1 — 2026-04-29

### Fixed

- **Stranded files now self-recover.** A transient TMDB or network
  failure during ingestion used to drop affected files silently —
  the watcher had a row, but the file never reached the library and
  no review queue entry was created. The pipeline now re-emits these
  stranded files in two situations: on every BEAM start as part of
  the existing reconcile pass, and right after you save a new TMDB
  API key. Update a rejected key and stranded grabs reprocess on
  their own; no remsh required.

- **Rejected TMDB API keys are visible in the Console.** A 401 / 403
  from TMDB now logs at error level under the `:tmdb` component
  instead of being buried as a generic `:pipeline` warning, so a
  bad or expired key is immediately obvious in the Console drawer.

## v0.27.0 — 2026-04-29

### Removed

- **Heavy Rotation row.** The home page no longer shows a "most
  rewatched" row of poster cards with `Nx` badges. Continue Watching,
  Coming Up, and Recently Added remain. Rewatch counts still appear as
  badges on the [Watch History](/history) page.

### Fixed

- **Update modal no longer goes silent during install/restart.** Once
  the updater hit the install-and-restart phase, the cancel button
  vanished and the footer was empty while the BEAM was actually
  restarting — easy to read as "stuck". The modal now shows a disabled
  "Installing…" button with a spinner for the rest of the run, so it's
  clear work is still in progress while the page reconnects.

## v0.26.2 — 2026-04-29

### Fixed

- **Console drawer now follows the tail of the logs reliably.** The
  systemd journal tab could end up scrolled away from the live edge
  when the drawer was reopened — new entries arrive at the bottom but
  the panel was sometimes left at the top. Opening the drawer now
  forces both the app log and the systemd journal back to their live
  edge, and stream resets (from tab or filter changes) re-pin too.

## v0.26.1 — 2026-04-29

### Improved

- **Search reliability under load.** Prowlarr searches now allow 60
  seconds to return (up from 30), so a slow indexer no longer trips
  the timeout on healthy hosts. The app also limits acquisition work
  to 3 concurrent searches at a time — batching a whole season used
  to fan out 10 simultaneous queries through one VPN tunnel, which
  cascaded into per-search timeouts. Whole-season grabs now finish
  reliably, just at a steadier pace.

## v0.26.0 — 2026-04-29

### New

- **Prowlarr search retry.** When a manual search times out on one or
  more indexers, each failed group now shows a per-group **Retry**
  link, and a footer **Retry N timeouts** button appears once all
  searches finish. The bulk button only retries true timeouts, so
  config errors (connection refused, 401, etc.) won't be silently
  re-thrown at the indexer.

- **Detail panel surfaces more from TMDB.** Movies and TV shows now
  show tagline, studio / network, original language, country of
  production, and vote count alongside the existing reception data.
  A new "reception" card groups score and votes for an at-a-glance
  read.

### Improved

- **Home page redesign.** The landing page is now full-bleed
  cinematic: a fluid 16:9 hero with a two-axis gradient and bottom
  fade, larger typography, and rows that scroll horizontally with
  snap. Cards lift, brighten, and pop forward on hover.

- **Continue Watching matches the Library's in-progress filter.**
  Earlier the home row dropped titles whose files had moved off disk
  and didn't include TV or movie series that still had episodes to
  watch. Both surfaces now show the same in-progress set.

- **Coming Up now shows the next 90 days, scrollable.** Up to 30
  upcoming items (was 8, was capped at this week). The row was
  renamed from "Coming Up This Week" to "Coming Up".

- **More content per row.** Continue Watching shows up to 24 (was 8),
  Recently Added 30 (was 16), and Heavy Rotation 30 (was 8).

## v0.25.0 — 2026-04-28

### New

- **The home page is now a cinematic landing.** Opening Media Centarr
  lands you on `/` — an assembled page with five rows: a rotating Hero,
  your in-progress Continue Watching, Coming Up This Week, Recently
  Added, and Heavy Rotation. Each row hides itself when there's nothing
  to show. Old `/?zone=continue` bookmarks redirect here.

- **Upcoming has its own page at `/upcoming`.** What used to live as a
  tab on the old Library is now a focused page combining the month
  calendar, tracked items, active shows, and a recent-changes feed. Old
  `/?zone=upcoming` bookmarks redirect.

- **Coming Up cards show live grab status.** Releases on the home page
  and the Upcoming page decorate themselves with a real-time badge —
  *Grabbed* (already acquired), *Searching* (Prowlarr is looking now),
  *Pending* (no acceptable release yet, will retry), or *Scheduled* (no
  grab armed yet). The badge updates automatically as the acquisition
  pipeline progresses.

- **Heavy Rotation row.** The home page surfaces the titles you actually
  rewatch. Each poster carries an `Nx` badge showing how many times
  you've finished it (`3×`, `5×`, …) — a more honest signal of what you
  love than a flat watched-recently feed.

- **Continue Watching, four cards plus "see all".** The home page row
  shows four backdrop cards with progress bars; "See all" opens the
  Library pre-filtered to in-progress titles via the new
  `/library?in_progress=1` deep-link.

- **Sidebar Watch / System groups.** The sidebar splits into **Watch**
  (Home, Library, Upcoming, History) at the top and **System**
  (Downloads, Status, Review, Settings) below — the cinematic surfaces
  visually separate from the operator surfaces.

### Improved

- **Library is now a single-purpose catalog browser.** Continue Watching
  and Upcoming, which used to share the Library as zone tabs, now have
  their own pages. `/library` is just the poster grid plus toolbar.

- **Faster page loads across the app.** Home, Library, Upcoming,
  History, and Downloads switched to targeted, section-specific
  reloaders. PubSub events that touch one row no longer trigger a
  full-page recompute, and broadcast bursts coalesce in a 200ms window.
  Hovering through the catalog feels snappier; arriving on `/history`
  with a long event log is materially quicker.

- **Watch history stats compute in SQL.** Hours Watched / Titles Watched
  / Current Streak and the 52-week heatmap now use database aggregates
  instead of streaming every event into Elixir — `/history` stays fast
  regardless of how much history you've built up.

- **Review page stays responsive while TMDB is slow.** Manual TMDB
  searches from the review queue run in a background task; the UI no
  longer locks up waiting for the API.

- **Library detail panel loads on demand.** Cast, crew, and file
  listings for a selected entity are fetched only when you open the
  panel, not on initial library page render — large libraries open
  noticeably faster.

### Fixed

- The library grid no longer comes up empty on initial mount in some
  setups — entries populate immediately on first connect.

- Orphaned entity records (left behind by partial deletions) are
  filtered out of the home page loaders, so they no longer crash
  Continue Watching or Recently Added when surfaced.

## v0.24.0 — 2026-04-26

### Improved

- **Downloads is now a single page.** What used to be split between the
  Download page (manual search) and the Auto-grabs page (background
  activity) has been collapsed into one. The sidebar now shows a single
  *Downloads* entry. Open it to see, top-to-bottom: what's transferring
  right now, every grab the system has tracked (auto and manual mixed),
  and the manual search form. Bookmarks to the old `/download/auto-grabs`
  URL redirect to the new page.

- **Manual grabs now show up in the activity timeline.** Previously,
  hitting *Grab* on a Prowlarr search result fired and forgot — there
  was no record of what you had asked for. Manual grabs are now tracked
  rows alongside auto-grabs, with a *manual* badge so you can tell them
  apart at a glance. The activity table also records the search query
  you typed so it's easier to recognise where each row came from.

- **Auto-acquisition defaults moved to a more sensible home.** The
  Settings → Release Tracking section used to host both the TMDB refresh
  interval *and* the auto-grab defaults (mode, quality, 4K patience).
  Auto-grab defaults now live next to the Prowlarr and download-client
  settings under Settings → Acquisition, where the rest of the
  acquisition behavior is configured. Release Tracking stays focused on
  what to track, not how to grab it.

## v0.23.0 — 2026-04-26

### New

- **Auto-grab releases as they become available.** When a movie or TV
  series you're tracking has a new release drop, Media Centarr can now
  search Prowlarr automatically and submit the best result to your
  download client — without you opening the Download page. Available
  whenever Prowlarr is connected. TV episodes are searched
  episode-by-episode (`Show Name S03E04`) with a season-pack fallback;
  movies use the title and release year.

- **Auto-grabs activity page.** A new **Auto-grabs** entry appears in
  the sidebar (next to Download) when Prowlarr is connected. It lists
  every active, snoozed, abandoned, or completed auto-grab with its
  attempt count, last outcome, and lifecycle status. Each row gives you
  a *Cancel* button while it's still searching, and *Re-arm* on grabs
  that gave up — useful when a release that was unfindable for a week
  finally seeds.

- **4K patience.** A new global preference (Settings → Release Tracking
  → *Auto-acquisition defaults*) lets you tell Media Centarr to wait
  for a 4K release to seed before falling back to 1080p. Default is
  48 hours — long enough to catch a slow 4K release without sitting on
  an unreplaceable episode forever. Set to 0 to grab whatever's
  available immediately.

- **Per-item auto-grab preferences.** Each tracked title now has its
  own override for mode (auto-grab on/off), minimum quality, maximum
  quality, 4K-patience hours, and a "prefer season packs" toggle for
  TV. The fields are wired through the Track and Item APIs today; a
  per-card UI gear icon will land in the next polish pass.

- **Configurable data directory.** Settings → Library now exposes a
  *Data directory* field that controls where Media Centarr stores
  caches that don't live in your watch directories — currently the
  poster and backdrop images for tracked titles. Defaults to the
  parent directory of the SQLite database. Files written by older
  versions still resolve via a legacy fallback, so flipping this
  doesn't strand existing images.

### Improved

- **Upcoming Releases broadcasts are now per-release.** When a tracked
  series has multiple newly-aired episodes in the same refresh cycle,
  each one is announced individually instead of one event per series.
  This is what enables episode-level auto-grab — and it also means the
  Upcoming Releases zone re-renders more precisely when only some of a
  show's pending episodes have aired.

- **Auto-grab retry strategy.** When a search comes back empty, the
  retry interval now grows exponentially (4h → 8h → 16h, capped at
  24h) instead of fixed 4-hour polls. Releases give up after 12 missed
  attempts (~one week at the cap) and surface as *Abandoned* on the
  Auto-grabs page with a *Re-arm* action — so a forgotten release
  doesn't poll Prowlarr forever, but you can revive it with one click
  if the situation changes.

- **Quieter Prowlarr-down behaviour.** When Prowlarr is unreachable
  during an auto-grab attempt, the failure no longer counts toward the
  abandonment budget. The grab snoozes for an hour and tries again,
  preserving its full retry allotment for the actual release-not-yet-
  seeded case.

- **Auto-grabs cancel themselves when their tracked title is removed.**
  Stop tracking a series and any in-flight auto-grabs for that series
  are cancelled with reason `item_removed`. No stray downloads after
  you change your mind about a show.

## v0.22.11 — 2026-04-26

### Fixed

- **Prowlarr *Test connection* now actually works on a healthy
  Prowlarr.** The previous test hit Prowlarr's `/api/v1/search`
  endpoint, which is not a connectivity probe — it's a live
  query that fans out to every configured indexer and routinely
  takes 20+ seconds to return on a perfectly healthy server. The
  short timeout introduced in v0.22.10 then made *every* test
  fail with a transport error, even when Prowlarr was reachable
  and the api key was correct. The button now hits
  `/api/v1/system/status` instead — a lightweight identity probe
  that returns 200 immediately when the URL is reachable and the
  key is valid, or 401 when the key is wrong, with a 5-second
  cap. Real searches and grabs use a more generous 30-second
  budget so slow indexers don't get clipped.

## v0.22.10 — 2026-04-26

### Fixed

- **Prowlarr *Test connection* gives up faster when the URL is wrong.**
  If you typed a Prowlarr URL that pointed nowhere reachable —
  wrong port, firewalled host, typo'd address — the Test button
  used to sit spinning for about a minute before reporting
  failure. The HTTP client retried three times by default, and
  each attempt waited the full 15-second timeout. The test now
  fails fast: a single attempt with a 5-second cap, no retries.
  Search and grab calls into Prowlarr inherit the same shorter
  budget, since Prowlarr is a local indexer that has no business
  taking that long to respond.

## v0.22.9 — 2026-04-26

### Fixed

- **Connection-test buttons no longer wipe your form.** Typing a
  Prowlarr URL, a download-client URL, or a TMDB API key into
  Settings → Acquisition or Settings → TMDB and clicking
  *Test connection* used to discard whatever you typed if the test
  came back unsuccessful — the form would silently revert to the
  previously-saved values. The Test button now saves your inputs
  *first*, then runs the test against them. Whether the test passes
  or fails, your typed values are kept. Saving never required a
  passing test, and still doesn't.

## v0.22.8 — 2026-04-25

### New

- **Repair missing images.** Settings → Library maintenance now
  detects artwork files that are missing from disk and re-downloads
  them from TMDB on demand. A badge in the section header shows
  the count; one button drains the queue. Until now, recovery from
  a partial image-cache loss meant rebuilding the whole library;
  this is the surgical alternative — works for any entity whose
  TMDB id is known (movies, TV series, episodes, movie series,
  video objects).

### Improved

- **Marketing screenshots restored at full 4K.** Click-through
  shots on [media-centarr.net](https://media-centarr.net/), the
  README, and the wiki are back. The 4K versions now live in a
  separate `media-centarr-assets` repo and load through jsDelivr's
  global CDN, so they render fast worldwide and the main repo
  stops accumulating multi-megabyte PNGs every release.

- **Showcase seeder is more robust.** Image-download failures
  during `mix seed.showcase` are now logged with the queue entry
  preserved, instead of silently leaving a broken row in the
  database. If a download fails at seed time, the new Repair
  button drains it without a re-seed.

## v0.22.7 — 2026-04-25

### Fixed

- **Marketing site screenshots restored to a working set.** The 4K
  click-through variants published in v0.22.5 were captured from a
  showcase instance whose TMDB data had been lost, so they were
  shipping as broken-image tiles on
  [media-centarr.net](https://media-centarr.net/). The v0.22.4
  screenshots are back in place; the 4K click-through feature is
  paused until a clean recapture lands.

- **Dev server no longer inherits production config.** Running
  `iex -S mix phx.server` or `mix phx.server` from a dev checkout
  now picks up `~/.config/media-centarr/media-centarr-dev.toml` (or
  falls back to dev defaults) instead of silently reading the
  installed production TOML — which was causing the dev instance to
  bind port 2160 and share the prod database. Only affects people
  running the app from source.

## v0.22.6 — 2026-04-25

### Improved

- **Missing image artwork now degrades gracefully.** When a poster,
  backdrop, logo, or episode thumbnail isn't on disk — partial
  download, unmounted storage, mid-flight cleanup — the UI shows a
  subtle dark tile shaped to the correct aspect ratio (2:3 for
  posters, 16:9 for backdrops/thumbnails, 4:1 for logos) instead of
  the browser's native broken-image glyph. Your library grid stays
  aligned through any transient image-cache state.

## v0.22.5 — 2026-04-24

Documentation / marketing release — no code changes affect the
installed app's behavior.

### Improved

- **Screenshots on the landing page, README, and wiki now link to
  4K-resolution versions.** Click any screenshot to open a crisp
  3840-pixel-wide capture of the same view in a new tab. A small
  "4K" badge appears on hover on the marketing site to confirm the
  linkout. The screenshot tour (`scripts/screenshot-tour`) now
  dual-renders both variants in a single run.

## v0.22.4 — 2026-04-24

Documentation / marketing release — no code changes affect the
installed app's behavior.

### Improved

- **Release Tracking screenshot now shows a populated calendar.**
  The landing-page Release Tracking tile captures `/?zone=upcoming`
  with thumbnails placed on multiple days across the current month —
  the visual pattern a user with actively-airing tracked shows sees
  in practice — instead of the near-empty calendar that real TMDB
  air dates (mostly months in the future) produced.

## v0.22.3 — 2026-04-24

Documentation / marketing release — no code changes affect the installed
app's behavior.

### Improved

- **Landing page and wiki now showcase the Upcoming zone and the
  Download page properly.** The Release Tracking screenshot on the
  project site and wiki now captures `/?zone=upcoming` with a real
  calendar of announced upcoming films and TV instead of a
  Recent-Changes proxy. The Download screenshot shows
  a live queue of downloads and the search screenshot shows results
  for a public-domain title.

## v0.22.2 — 2026-04-24

### Improved

- **Faster startup and image pipeline.** Three N+1 query loops are now
  batched into single `WHERE IN` queries. Config loading at app start
  goes from ~12 SELECTs to 1; image-download batch completions go from
  20 UPDATEs per batch to 1; image-download failure handling collapses
  to at most 2 queries regardless of batch size. No behaviour change —
  just less database chatter on every startup and every image batch.

## v0.22.1 — 2026-04-24

### Improved

- **Settings page sections can be deep-linked via URL.** Opening
  `/settings?section=acquisition` jumps straight to the Acquisition
  tab; appending `#settings-prowlarr` or `#settings-download-client`
  scrolls to the specific form. Useful for bookmarks and for
  documentation that points at a specific setting.
- **Project website and wiki show the product on every major page.**
  The marketing site and the GitHub wiki now include screenshots of
  the library grid, movie/TV detail, review queue, status, watch
  history, download, console, and every major settings section —
  replacing broken image links and empty documentation pages.

## v0.22.0 — 2026-04-24

### New

- **The Status page now summarises recent errors, and you can
  report them to the developer in one click.** Instead of a
  long list of every failed file, you see a count of errors in
  the last hour grouped by what actually went wrong (rate
  limits, permission denied, etc.) — at most the top three
  groups, so the page stays scannable. A **Report errors**
  button opens a modal that shows exactly what will be sent
  as a GitHub issue: an environment block (app version, OS,
  uptime), a fingerprint, a count, and up to five recent log
  lines. Paths, UUIDs, API keys, IP addresses, emails, and
  any URLs you've configured (Prowlarr, download clients) are
  automatically scrubbed before the preview is shown. Nothing
  is sent until you click **Confirm & open GitHub** — at
  which point a new browser tab opens on the Media Centarr
  repo with the title and body already filled in. Two users
  hitting the same bug will produce matching issue titles, so
  GitHub's duplicate detection can collapse them.

## v0.21.0 — 2026-04-24

### Fixed

- **The file watcher no longer crashes when you create
  or modify an excluded directory.** If you had an
  excluded folder (for example, a Captures dir) inside
  a watch directory, creating or touching that folder
  could silently kill the watcher so new media files
  stopped being detected until the app restarted. The
  watcher now handles those events cleanly.

### Improved

- **Changes to your excluded-directory list take effect
  immediately.** Adding or removing an entry in
  Settings → Library no longer requires a restart —
  the watcher picks up the change as soon as you save.

## v0.20.2 — 2026-04-22

### Improved

- **Text fields behave like ordinary text fields again.**
  Backspace now deletes the character to the left of the
  cursor instead of wiping the whole field, and Escape takes
  two presses before it clears what you typed — the first
  press just exits editing so you don't lose your work.
  Focused text fields also show a brighter ring while you're
  actively typing, so it's clear whether arrow keys will
  move the cursor or navigate the page.
- **No more misleading Prowlarr / download-client URL
  suggestions.** Those fields used to show
  `http://localhost:…` as placeholder text, which didn't
  apply to most setups and led to accidental copy-paste.
  The placeholders are gone — the fields are blank until
  you fill them.

### Fixed

- **Settings → Controls is keyboard- and gamepad-navigable.**
  The remap and clear buttons for every binding, the Reset
  options, and the Xbox/PlayStation glyph toggles are all
  reachable with arrow keys and the D-pad.
- **Settings → Library watch and excluded directory lists
  are navigable without a mouse.** The Add, Edit, Delete
  (and Confirm/Cancel) buttons on those lists are
  focusable, and the excluded-path input is part of the
  focus order.
- **Upcoming → Tracking rows accept keyboard and controller
  input.** Each tracked show or movie can be focused
  individually; press Enter (or A on the gamepad) to open
  the stop-tracking confirmation instead of hovering the
  row and clicking the X.

## v0.20.1 — 2026-04-22

### Fixed

- **Startup failures now report the real cause.** If something went
  wrong while Media Centarr was booting — a port collision, a missing
  config, a child that couldn't start — the log would often show a
  misleading "could not lookup Ecto repo" error instead of the
  underlying problem. The real failure is now the first (and only)
  error you see in the journal.

## v0.20.0 — 2026-04-22

### Improved

- **The play button turns into an "Offline" indicator when the file's
  storage isn't mounted.** Before, you could click play on content
  whose drive was offline and the click would silently fail. The
  button now disappears in favour of a muted pill the moment a watch
  directory goes unavailable, matching the way images already become
  placeholders for offline content. When the drive reconnects, the
  play button returns automatically.

### Fixed

- **Playback failures now tell you what went wrong.** Clicking play
  on a file mpv couldn't open — bad codec, stale mount, unreadable
  file — used to silently do nothing: no window, no error. You now
  get a flash message with the specific reason ("Failed to recognize
  file format.", "Error opening input file", etc.), and when the
  error looks like a missing file, a hint to check that your media
  drive is mounted. mpv's own diagnostic output is also captured into
  the Console drawer and the systemd journal, so playback issues are
  now diagnosable after the fact without re-running.

## v0.19.0 — 2026-04-22

### New

- **Watch History page is now keyboard- and gamepad-navigable.** The
  filter pills, search input, date badge, event list, and pagination
  all respond to arrow keys and the gamepad d-pad. The per-event
  delete button reveals itself when its row takes focus, so you no
  longer need a mouse to prune a mis-recorded watch.

### Improved

- **Clearing the library filter now returns focus to the grid.**
  Pressing Y (gamepad) or Backspace (keyboard) to clear the filter
  used to leave you sitting in the toolbar — you had to press Down
  to see your unfiltered library. Focus now follows the clear
  straight back into the grid.
- **The gamepad hint bar shows Play inside a detail modal.** When
  you have a movie or episode open, the bottom hint bar now reminds
  you that the Start button plays it, matching the hint you see in
  the grid.

## v0.18.1 — 2026-04-21

### Improved

- **TV series detail loads faster.** The first time you open a show
  with many seasons and episodes, the page now renders in a fraction
  of the previous time — the database layer was missing two indexes
  that made every show open trigger a full-table scan.
- **Library grid stays responsive during playback.** Progress updates
  while you're watching an episode no longer rebuild the entire grid
  behind the scenes; only the affected poster is refreshed. Libraries
  with hundreds of entries feel noticeably smoother.
- **Status page opens without hanging.** The /status page used to
  stall on first paint while it gathered stats, history, and storage
  measurements. Those now load in the background so the page renders
  immediately and fills in as the numbers arrive.
- **Track New Show modal opens faster.** The list of suggested shows
  is built from a single database query instead of loading everything
  into memory first.
- **Review page handles bulk approvals better.** Approving or
  dismissing many files in a row no longer rebuilds internal
  bookkeeping from scratch on every action.
- **Console drawer opens faster on big buffers.** If you've bumped the
  console buffer size above the default, opening the Console no
  longer copies the entire buffer up-front — only what you'll see,
  with the rest arriving live as new logs come in.
- **Releases refresh contends less with SQLite.** The periodic refresh
  of tracked shows now fans out only the TMDB fetches in parallel;
  the database writes happen one at a time, avoiding the occasional
  lock contention on slower disks.
- **Image backfill keeps TMDB busier.** The background image pipeline
  went from 4 to 8 concurrent workers, which cuts the time to
  populate artwork for a freshly-imported library nearly in half.
- **Acquisition queue processes more jobs at once.** The Oban
  acquisition queue went from 5 to 10 concurrent jobs for faster
  throughput when grabbing multiple releases.

## v0.18.0 — 2026-04-21

### Added

- **Capability gating on external integrations.** UI surfaces that depend
  on TMDB, Prowlarr, or the download client now only appear once you've
  explicitly tested that connection in Settings and it came back green.
  The Download sidebar entry stays hidden until Prowlarr tests green;
  the downloads queue panel hides (with a pointer to Settings) until
  the download client tests green; Track New Releases, the Rematch
  button in detail view, and Review's Search TMDB stay hidden until
  TMDB tests green. Tests are cleared automatically when you save new
  credentials, so changing a URL or key immediately re-hides the
  dependent features until you re-test.
- **TMDB "Test connection" button** on the Settings → TMDB page,
  matching the existing Prowlarr and download client pattern. Result
  persists with a relative-age display ("Connected · 3 min ago") and
  is cleared when the API key is saved.

## v0.17.0 — 2026-04-21

### Fixed

- **Detail view no longer closes when you click inside the Console
  drawer.** The dismiss-on-outside-click behavior is now scoped to
  the modal's backdrop rather than listening globally — clicks
  inside sibling overlays (Console, future popovers) stay
  self-contained. Applies to every modal: movie/show detail, Track
  New Show, delete confirmations, stop-tracking, cancel-download.

## v0.16.2 — 2026-04-21

Maintenance release — no user-visible changes. Restores a green CI
baseline (test isolation fix for systemd-supervised runners) and
renames an internal dev-only dependency.

## v0.16.1 — 2026-04-20

### Fixed

- **Detail view backdrop** now anchors to the top of the hero image
  instead of centering. When the source image is taller than the 21:9
  hero, the bottom crops away and the top of the composition is
  preserved — important for posters and title treatments that live near
  the top of the frame.

## v0.16.0 — 2026-04-20

### Added

- **Settings → Controls.** Remap every keyboard and gamepad binding.
  Each row has separate KEY and PAD columns; click the pencil to
  listen for a new key or pad button, clear to unset. Choose Xbox or
  PlayStation glyph styles. Reset per-category or all at once. New
  bindings take effect immediately without reload.

### Improved

- **Console component chips** now use a deliberate per-component color
  palette instead of randomly-assigned daisyUI semantic classes.
  Routine library logs no longer look like warnings, and faded-to-
  invisible chips are gone — every chip is distinct and readable in
  both themes.
- **Console → Systemd tab** now tails the live edge the way
  `journalctl -f` does: oldest entries at the top, newest at the
  bottom, scroll pinned to the bottom. Scroll up to read history;
  scroll back down and tail-follow resumes.

### Fixed

- **Settings → Controls column alignment.** KEY and PAD stay firmly
  aligned across every row in a category via a shared subgrid — longer
  keycaps ("Backspace") no longer push the surrounding columns around.

## v0.15.2 — 2026-04-19

### Improved

- **Documentation refreshed for the DB-managed-config world.** The
  README, GitHub Pages landing, contributor `docs/configuration.md`, and
  the public wiki (*Configuration File*, *Adding Your Library*,
  *Settings Reference*, *Prowlarr Integration*, *Download Clients*,
  *First Run*, *Troubleshooting*, *FAQ*) all now describe the current
  app-managed configuration flow. The shipped `defaults/media-centarr.toml`
  is documented as containing only `port` and `database_path`; every
  other setting is edited in *Settings* and persisted to the database.

## v0.15.1 — 2026-04-19

### Fixed

- **Settings → Library layout.** Watch-directory and excluded-directory
  rows no longer right-align paths or render the same path twice, and the
  images-directory line is hidden when it would just restate the
  default `{dir}/.media-centarr/images` location. Edit is now a pencil
  icon for visual parity with the trash icon next to it.
- **System → Storage path truncation.** The Database row stopped
  hard-cutting at 48 characters with a leading ellipsis — long paths now
  display in full and only collapse to a trailing CSS ellipsis when the
  viewport is genuinely too narrow.
- **System → "Watch directories" row** now opens *Settings → Library*
  instead of looping back to *System*.

### Improved

- **Settings sidebar url for System** is now `?section=system` (was
  `?section=overview`). Old bookmarks still work — a one-line redirect
  catches `?section=overview` and routes to `?section=system`.
- **System → Integrations** (was "Configuration") — the label now matches
  what the group actually contains: external-service readiness (TMDB,
  Prowlarr, Download Client, MPV).
- **System page** dropped the now-obsolete "Configuration" card whose
  subtitle claimed watch directories required editing `media-centarr.toml`
  and restarting. Watch directories are managed in the Library section.
- **Services → "Scan now"** uses the success tone per UIDR-003 (it
  sits alongside other action buttons like "Detect from Prowlarr").
- **TMDB → API Key** now includes a "get one at themoviedb.org" link
  below the input for first-time users.

## v0.15.0 — 2026-04-19

### New

- **Excluded directories are now managed in the app.** A new *Excluded
  Directories* card lives next to *Watch Directories* under *Settings →
  Library*. Add a path to skip a sub-tree inside one of your watch
  directories — handy for downloads-cache folders, trash bins, or any
  area with transient files you don't want indexed. Changes take effect
  immediately; no restart.

### Improved

- **All runtime configuration lives in the database.** Every setting
  that has a UI (TMDB key, Prowlarr, download client, MPV paths, extras
  and skip directory names, file-absence TTL, auto-approve threshold,
  release-tracking cadence, and excluded directories) is now edited
  exclusively in *Settings*. Your existing `~/.config/media-centarr/`
  TOML values are imported automatically on first boot, after which
  the TOML is no longer consulted for those keys — the DB is the
  single source of truth. Editing the TOML post-upgrade is a no-op;
  use the UI.
- **Tighter `media-centarr.toml`.** The shipped default config now
  contains only the two keys that genuinely have to live outside the
  database: the HTTP `port` and the `database_path` itself. Every
  other key was either migrated to the DB or deleted as unused
  (`recently_watched_count`, legacy `media_dir` fallback).

## v0.14.0 — 2026-04-19

### New

- **Watch directories are now managed in the app.** Open *Settings →
  Library → Watch Directories* to add, edit, or remove watch directories
  from the UI. No more editing the TOML config file or restarting the
  app — changes take effect immediately, starting or stopping the file
  watcher per directory. The dialog validates paths live (exists, is
  readable, not duplicated, not nested inside another configured
  directory) and previews how many video files and subdirectories it
  found. Each entry supports an optional display name and an advanced
  *images directory* override for putting the artwork cache on a
  separate (e.g. SSD) volume. Existing `watch_dirs` entries in your
  `media-centarr.toml` are imported automatically on first boot, after
  which the UI is the source of truth.

### Improved

- **Library scrolls all the way to the top when you reach the zone
  tabs.** Keyboard and gamepad up-navigation from the library grid now
  scrolls the page fully to the top when focus lands on the Continue
  Watching / Library / Upcoming tabs, instead of stopping flush with
  the tab row.

### Fixed

- **Dev builds no longer check GitHub for updates.** Development
  instances (running via `mix phx.server` or the dev systemd unit) skip
  the boot update check and the periodic six-hour check, and hide the
  Updates card in Settings. The in-app updater targets production
  binaries; dev builds update by rebuilding from source.

## v0.13.1 — 2026-04-19

### Improved

- **Clearer message when GitHub rate-limits update checks.** The
  anonymous GitHub API has a 60-requests-per-hour-per-IP cap; when we
  hit it the System page was showing a cryptic *"Update check error:
  HTTP 403"*. The updater now detects the rate-limit response (via
  `x-ratelimit-remaining`) and surfaces the friendlier *"GitHub rate
  limit reached. Try again after HH:MM UTC."* using the reset
  timestamp GitHub returns.
- **Last-known release stays visible during transient errors.** A
  failed check no longer clobbers the `latest_release` displayed on
  the card — the "See what's new" disclosure and the tag+date line
  now remain populated from the last successful check, with the error
  message shown alongside. No more brief "blank card" flash during a
  stale-to-fresh transition either.

## v0.13.0 — 2026-04-19

### New

- **Service card on Settings > System.** A new *Service* card shows the
  current systemd state (running / stopped / not installed / not
  running under systemd) as a coloured badge, and — when systemd is
  available — offers **Restart** and **Stop** actions with a
  confirmation dialog. Both actions use `systemctl --user --no-block`
  so they return immediately and the restart cycle completes
  asynchronously; the browser reconnects on its own when the BEAM is
  back.
- **Service details disclosure.** A *Show service details* toggle on
  the card reveals the full `systemctl --user status` output in a
  scrollable monospace panel — useful when triaging a failed restart
  or checking recent activity without leaving the page.

### Fixed

- **Image-downloader test flake.** `ImagesTest` and
  `ImageProcessorTest` both stubbed `Application.put_env(:media_centarr,
  :image_http_client, …)` globally. Under `async: true` their setups
  raced, causing the 404 test (and others) to occasionally see a
  stub from a neighbour — showing `{:image_open_failed, "Failed to
  find load buffer"}` instead of `{:http_error, 404, _}`. The
  override now lives in the process dict (per-process, auto-cleans on
  test exit) and sibling test files can no longer stomp on each
  other.

## v0.12.6 — 2026-04-19

### Fixed

- **Update-progress modal now covers the full page.** The modal was
  nested inside the Settings page's content grid, where its
  `position: fixed` backdrop was constrained by the surrounding flex
  layout. Moved it to the layout root — the same placement the rest
  of the app's modals use (`ModalShell.modal_shell`, `TrackModal`) —
  so the backdrop covers the entire viewport regardless of which
  settings section is active or how the page is scrolled.
- **Auto-restart at the end of an update now actually restarts the
  service.** The detached handoff shell runs under `env -i` for
  hygiene, which was stripping `XDG_RUNTIME_DIR` and
  `DBUS_SESSION_BUS_ADDRESS` — two variables `systemctl --user`
  needs to reach the user's systemd instance. Without them, the
  installer's `has_systemd_user` probe returned false, the unit
  never got reinstalled, and the service was never told to restart.
  The new release was staged correctly on disk, but the running BEAM
  kept serving the old version. The handoff now passes these vars
  through explicitly.

## v0.12.5 — 2026-04-19

### Improved

- **Status check-marks no longer look oversized.** The green ✓ and
  amber ⚠ indicators on the System page (Configuration card) and the
  update-progress modal are now the lighter `-mini` heroicon variants
  sized to match their adjacent text, instead of chunky `-solid`
  glyphs that sat visually above the baseline. Applied across every
  place these indicators show up.

## v0.12.4 — 2026-04-19

### Improved

- **Stuck-restart warning shows up faster.** The modal now waits
  6 seconds after the handoff fires before surfacing the diagnostic
  panel (was 30 seconds). A healthy restart completes in 2–3 seconds,
  so 6 is a comfortable buffer without making you stare at a dead
  spinner for half a minute.

## v0.12.3 — 2026-04-19

### Improved

- **Update progress modal shows the full checklist.** The apply dialog
  used to show one line that replaced itself on every phase transition.
  It now renders every step — *Downloading release*, *Extracting files*,
  *Installing and restarting* — as a persistent row that lights up and
  checks off as progress happens, so you can see where you are in the
  process at a glance.
- **Modal styling is correct.** The backdrop now covers the full
  viewport instead of leaving the page visible at the edges, and the
  panel uses the app's standard modal design (centered, clear dark
  backdrop with blur, scale-in animation).

### Fixed

- **"Restarting the service…" no longer hangs silently.** If the BEAM
  doesn't die within 30 seconds of the handoff being fired, the modal
  switches to a warning state showing the exact `systemctl --user
  restart media-centarr` command to run manually, with a copy button.
- **Handoff script now writes a diagnostic log.** The shell redirects
  its own stdout+stderr to `~/.cache/media-centarr/upgrade-staging/
  <version>-<random>/handoff.log` from its first instruction, so when
  an update doesn't finish cleanly you can see exactly how far the
  chain got. The redundant `nohup` wrapper was also removed —
  `setsid --fork` already creates a new session, and `nohup`'s stdio
  reopening was interfering with our redirect.

## v0.12.2 — 2026-04-19

### Fixed

- **Settings > System stuck showing an ancient release.** Manual and
  on-view update checks refreshed only the in-memory cache, while the
  durable `Settings.Entry` row kept whatever the scheduled cron last
  wrote. On every restart the old row re-hydrated the cache for 5
  minutes, so the "latest known" version could drift weeks behind
  reality. All check paths now dual-write — the two storage layers
  stay in sync — and the boot-time check fires unconditionally (the
  job's uniqueness constraint prevents piling on the cron).

## v0.12.1 — 2026-04-19

### Fixed

- **Download progress bar sat at 0% then jumped to 100%.** The updater
  now streams the release tarball and reports progress at every 1%, so
  the bar moves smoothly as the download proceeds. A short CSS
  transition on the bar itself (150ms ease-out) smooths the motion
  between percentage ticks.
- **"Update staged. Restarting the service…" got stuck forever.** The
  detached shell that hands control to the staged installer was losing
  its stdio to the closing Erlang port, which SIGPIPE'd the installer
  before `systemctl restart` fired. Fix: the handoff script redirects
  its own output to a log file in the staging directory, and the
  spawner now passes `:nouse_stdio` plus `setsid --fork` so the chain
  is fully detached before the port closes.

## v0.12.0 — 2026-04-19

### New

- **See what's new shows the full release notes.** The disclosure on
  the System card no longer truncates at 500 characters — it now
  renders the full release body in a contained, scrollable panel with
  smaller type so longer changelogs don't overwhelm the page.

### Improved

- **Settings sidebar.** The *Overview* page is now called *System*,
  matching what the card actually covers (version, updates, release
  notes). URLs and bookmarks are unchanged.
- **App card identity.** The tagline on the Media Centarr card has
  been replaced with the license and copyright line
  (*MIT License · © 2026 Shawn McCool*).

## v0.11.0 — 2026-04-19

### New

- **Escape hatches for when *Update now* fails.** The Updates card on
  Settings > Overview has a new *Prefer the terminal?* disclosure with
  three copy-button commands covering the common recovery paths
  (standard update, force-reinstall current version, full bootstrap).
  The failure dialog also shows the same fallback command inline so you
  can recover with a single copy-paste rather than hunting for docs.
- **`--force` on the CLI updater.** `media-centarr-install --update
  --force` reinstalls the current latest tag even when the version
  matches — useful when a previous in-app apply left partial state and
  you want to re-extract and re-migrate cleanly without bumping to a
  new release.
- **Troubleshooting section in the README.** A *When auto-update fails*
  block documents the recovery ladder (service restart → CLI update
  → `--force` → bootstrap reinstaller) so users who reach the README
  before the UI still find the fallback commands immediately.

## v0.10.2 — 2026-04-19

### Fixed

- **Retry after a failed update.** If *Update now* failed (network blip,
  bad checksum, anything), the next click reported *"an update is
  already in progress"* and stayed stuck until the service restarted.
  Retries now work correctly — a new attempt blows through the previous
  failure. The failure dialog also gains an explicit **Retry** button so
  you don't need to close and re-open.

## v0.10.1 — 2026-04-19

### Fixed

- **In-app updater failure.** *Update now* crashed with `Tarball
  rejected: tar_error ... :enoent` because the extractor was clearing
  its own staging directory — including the tarball it was about to
  read. The extractor now leaves the downloaded file in place and
  only tightens the directory permissions.

## v0.10.0 — 2026-04-19

### New

- **See what's new, right in Settings.** The Updates card on Settings >
  Overview now has a *See what's new* disclosure that expands to show
  the release notes for the latest version — no need to click through
  to GitHub to find out what changed.
- **Rich release notes on GitHub.** The release workflow now uses the
  real `CHANGELOG.md` entry as the GitHub release body, so the notes
  you see in-app and on GitHub are the same user-facing copy. No more
  generic "Linux x86_64 release" placeholders.

## v0.9.1 — 2026-04-19

### Fixed

- **Post-install URL.** The installer's success message showed the dev
  server's URL (`http://localhost:1080`) instead of the real production
  URL. It now prints `http://localhost:2160`, and honors a custom
  `port = NNNN` if you've set one in your `media-centarr.toml`.

## v0.9.0 — 2026-04-19

No user-facing changes in this release. Internal build-tooling cleanup
that completes the transition to in-app updates as the only supported
update path — the old `scripts/install` is gone, and the local release
script has been renamed to `scripts/preflight` to reflect its true role
as a pre-tag build check.

## v0.8.0 — 2026-04-19

### New

- **One-click updates.** Settings > Overview now has an *Update now* button
  that downloads, verifies, and installs the latest release. A progress
  modal shows what's happening, and the service restarts automatically
  when it's done.
- **Background update checks.** Media Centarr now checks for new releases
  every 6 hours and shows a notice on Settings > Overview when one is
  available — no need to click *Check for updates* to see if you're
  behind.
- **First-run prompts.** On a fresh install, the Library page links you
  straight to the *Configure library* settings when no watch folders
  are set up, and Settings > Overview reminds you to add a TMDB API key
  so artwork and metadata load.
- **Installer: autostart is now optional.** Pass `--no-service` to skip
  systemd setup, and use `media-centarr-install service install` or
  `service remove` to add or remove autostart later. Systems without
  a working systemd user session (WSL2 without systemd, some containers)
  install cleanly and print the manual start command.
- **Installer: clearer output.** Every install, update, and uninstall now
  prints what was changed on disk and how to undo it — no more hunting
  through docs for the right path to delete.
