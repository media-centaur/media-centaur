# Changelog

User-facing release notes for Media Centaur. Internal refactors, test
changes, and dependency bumps with no user impact are omitted here —
see the git history for the full engineering trail.

## v0.85.0 — 2026-06-09

### Improved

**All preferences now live in Settings.** The configuration file
(`media-centaur.toml`) holds only the essentials the app needs before it
starts: the database location, the web port, and your initial watch
folders. Everything else — your TMDB key, download client, playback
paths, and so on — is managed in the app on the **Settings** page. If you
used to hand-edit the config file for those, your existing values are
already saved in the app and any leftover entries in the file are simply
ignored. There's nothing you need to do.

## v0.84.0 — 2026-06-08

### Fixed

**Multi-season box sets are matched automatically instead of piling up in
Review.** When a show was stored as a full-series pack — a folder named
something like "Show Name (2006) Season 1-7 S01-S07" with each season in its
own subfolder — the season-range text got tangled into the show's name. The
result didn't match anything online, so every episode landed in the Review
queue. These packs are now read correctly and matched on their own.

## v0.83.3 — 2026-06-08

### Fixed

**The TMDB search box on the Review page stays open.** When matching a file to
a movie or show, starting a search used to snap the search box shut the instant
you clicked Search (or pressed Enter), so its results never had a chance to
appear. The box now stays open and shows its matches so you can pick one.

## v0.83.2 — 2026-06-08

### Improved

**Download-client connection alerts are quieter and clear themselves.** A brief
network hiccup with your download client used to raise a cluster of duplicate
alerts on the Status page that lingered even after the connection was fine. Now
a momentary blip raises nothing at all, and a genuine outage shows a single
alert that clears itself automatically once the connection recovers.

## v0.83.1 — 2026-06-08

### Fixed

**Incident lookup by ID is reliable again.** Finding a specific incident by its
ID — the value in a `/status` incident link — could silently come up empty in
the troubleshooting tools. Those IDs now resolve correctly.

## v0.83.0 — 2026-06-08

### Improved

**Share a link straight to an issue.** When you open an issue from the Status
page, the address bar now points at that exact issue. Copy the link and a
bookmark or a paste into chat reopens the same detail view — already focused on
the problem — instead of dropping you on the generic Status page. The browser's
back button closes the issue and returns you to where you were.

## v0.82.5 — 2026-06-08

### Improved

**Faster diagnosis when something goes wrong.** When you report a problem, the
recorded incident now keeps a full snapshot of what was happening at the time —
the surrounding log lines, the health of each part of the app, and the details
the affected component reported. That picture survives restarts, so an issue
can be understood after the fact even once the live log has scrolled past it.

## v0.82.4 — 2026-06-08

### New

**Click an issue on the Status page to see what's going on.** When a subsystem
flags a problem, you can now click the issue to open a detail view — what that
part of Media Centaur does, when and how often the problem happened, and the
recent log lines — so you can understand it before deciding whether to report
it. The *Report this* button now lives inside that view, so reporting follows
reading the issue rather than coming first.

### Improved

**The problem-report wizard no longer closes if you click outside it or press
Escape.** While you're writing up a report, a stray click or keypress won't
discard what you've typed — close it deliberately with the buttons in the
dialog. Quick pop-up dialogs elsewhere in the app still close the easy way.

## v0.82.3 — 2026-06-08

### Improved

**Each subsystem panel on the Status page now opens with a plain-language
summary.** When you select a subsystem in the System Health board — Watcher,
Import, Metadata, Playback, Library, Downloads, Updates, or System — the panel
now leads with a short description of what that part of Media Centaur does and
what you'd notice if it stopped working, before showing its recent activity,
any issues, and technical logs. The panel reads top-to-bottom as an explanation
rather than just a status light.

### Fixed

**A manual update check no longer installs an update on its own.** Pressing
*Check for updates* now only tells you whether a new version is available;
installing stays a deliberate, separate step. Automatic installs (when you've
opted into them) are unaffected.

## v0.82.2 — 2026-06-08

### New

**The Updates panel now keeps a history of the versions you've run.** Open
**Updates** in the Status page's System Health board and you'll see the versions
Media Centaur has updated through, each with the date it started running — so you
can tell at a glance when you last updated and what you were on before. The list
starts building from this release onward.

## v0.82.1 — 2026-06-07

### Improved

**The "Your library" overview now lives inside the Library tile on the Status
page.** Instead of sitting at the top of the page, the library summary — counts
and size, recently added, pending work, completeness gaps, and storage outlook —
now appears when you select **Library** in the System Health board, fleshing out
that subsystem's panel alongside its technical logs.

## v0.82.0 — 2026-06-07

### New

**The Status page now opens with a "Your library" overview.** Above the usual
system-health board you'll find a quick read on the library itself: how many
movies, shows, and episodes you have and how much space they take up, a strip of
your most recently added titles, and three at-a-glance cards —

- **Pending work** — how many files are waiting for review and how many downloads
  are in progress, each linking straight to where you handle them.
- **Completeness gaps** — titles missing artwork or details, and series with gaps
  in their seasons, so you can spot what's worth tidying up.
- **Storage outlook** — free space on each drive, with a warning when files on an
  offline drive are at risk of being dropped from the library.

The overview updates on its own as your library changes.

## v0.81.0 — 2026-06-07

### Improved

**Opening Settings no longer kicks off its own update check.** Media Centaur
already checks for new releases on a regular schedule in the background, so the
extra check that fired every time you opened the Settings page was redundant
network traffic. The page now just shows the latest known result instantly, and
the **Check for updates** button is still there whenever you want to look right
now.

## v0.80.3 — 2026-06-07

### Fixed

**Dismissing an issue on the Status page now removes it for good.** Previously a
dismissed issue could quietly come back — most noticeably after a restart —
because it was only marked resolved rather than deleted. Dismissing now clears
the issue and its recorded history from Media Centaur entirely. (If the same
fault genuinely happens again, it'll surface as a fresh issue, so you're never
left in the dark about a live problem.)

## v0.80.2 — 2026-06-07

### Fixed

**"Check for updates" no longer gets stuck on "Checking…".** When you checked
for updates manually — or simply opened Settings — the card could stay on
"Checking…" indefinitely even though the check had already finished. It now
always shows the result: up to date, an available update, or a clear error.

## v0.80.1 — 2026-06-07

### New

**The Status page now shows an Updates tile.** Media Centaur's self-update has
joined the Status board: a calm tile that turns amber or red only if updating
itself runs into trouble — checks repeatedly failing to reach GitHub, checks
that have stalled, or an install that failed. Drill into the tile to see your
current version, when it last checked and when the next check is due, whether
automatic install is on, and a live progress bar while an update is applying. An
available update is shown as information, never flagged as a problem.

## v0.80.0 — 2026-06-07

### Fixed

**Automatic updates now work the way the settings describe.** If you choose how
often Media Centaur checks for updates, it now honours that interval — a short
setting like 15 minutes was previously stretched to roughly once an hour. And
when *Install updates automatically* is on, a new version now downloads and
installs on its own once it's found, instead of quietly waiting for you to press
*Update now*.

### New

**A short notice marks the pages that are still being built.** The Upcoming,
History, Downloads, and Status pages now show a small "work in progress" banner,
so it's clear what's finished and what's still on the way.

## v0.79.3 — 2026-06-07

### Improved

**The Updates card now shows when the next check will happen.** Settings →
System tells you how often Media Centaur checks for updates and, roughly, when
the next check is due (for example, "every 6 hours — next check in about 2
hours"), or that automatic checks are off.

## v0.79.2 — 2026-06-07

### Improved

**Update settings now have their own place.** The "automatically check" and
"install automatically" options moved out of the System card into a dedicated
**Updates** section in Settings. The System card keeps the manual *Check for
updates* / *Update now* actions and now briefly explains how updating works.

## v0.79.1 — 2026-06-07

### Improved

**Tidied the update-frequency setting.** The "check every … minutes" field in
Settings → System → Updates now reads as a single plain sentence instead of an
all-caps label, matching the rest of the card.

## v0.79.0 — 2026-06-07

### New

**Media Centaur can now install updates on its own.** Turn on *Install updates
automatically* in Settings → System → Updates and new versions are downloaded and
installed without you lifting a finger. If something is playing when an update is
found, it waits until playback ends — your session is never interrupted by a
restart. It's off by default, so you stay in control unless you opt in.

### Improved

**You can choose how often Media Centaur checks for updates.** Settings → System →
Updates now lets you set how frequently the background check runs, or switch it off
entirely and only check when you press *Check for updates*. The card also shows
when it last checked. Checks use GitHub's public release feed, which has an hourly
limit per network, so the minimum is every 15 minutes — plenty, since new releases
are infrequent.

## v0.78.4 — 2026-06-06

### Improved

**The Status page is easier to work through.** The item you have selected is now
clearly highlighted, you can dismiss issues you have already dealt with, and you
can drill into the details of each area in a tabbed panel.

### Fixed

**The "Track New Releases" search box no longer loses focus while you type.** When
you opened the tracking dialog and clicked into the search field, it could
unexpectedly lose focus a second or two later as suggestions and results loaded —
kicking you out of the box mid-search. It now stays put so you can type and search
without interruption.

## v0.78.3 — 2026-06-05

### Improved

**A crisp new app icon that adapts to your browser theme.**
Media Centaur has a redesigned icon — a bold centaur archer that stays sharp in your browser tab, on
your home screen, and when you install Media Centaur as an app. It automatically switches between a
light and a dark version to match your system theme. The project website now uses the same icon.

## v0.78.2 — 2026-06-05

### Changed

**Reporting a problem now posts to GitHub, under your own account.**
When you report a problem, Media Centaur copies the report to your clipboard and opens a pre-filled
**GitHub issue** for you to post — so reports actually reach the developers and you can follow along as
they're worked on. Your report is still automatically scrubbed of file paths, keys, IP addresses, and
emails, and you review and edit the exact text first. One thing to know: the issue is **public**, so
give it a last glance before posting. No GitHub account? Use the **Copy** button and share the text
however you like. (Posting needs a free GitHub login.)

### Fixed

**Problem reports no longer silently fail to send.**
Reports previously tried to send in the background and could quietly fail with a "couldn't send
automatically" message. Reporting now goes through GitHub every time, so a report you take the time to
write actually gets through.

## v0.78.1 — 2026-06-05

### Fixed

**Updating no longer flashes a scary red "Not connected" error.**
While the app restarts to apply an update, you now see a calm "Applying update" notice instead of the
red connection error. The brief disconnect during an update is expected — and now it looks that way.

### Improved

**The Status board is cleaner and easier to navigate.**
The pending-review count has been removed from the board, and the subsystem card you're on now stands
out with a gold highlight when you navigate by keyboard or controller.

## v0.78.0 — 2026-06-05

### New

**You can now report a problem even when Media Centaur didn't catch it.**
The Status page has a new **Report a problem** button. Use it when something feels off but the app
hasn't flagged anything itself — Media Centaur attaches a snapshot of how the system is doing right
now, so your report still gives the developer useful context. As with every report, you review and
edit exactly what's included before it's sent, and if it can't be sent automatically you get the full
text to copy and share yourself.

**The Status icon flags problems you haven't seen yet.**
When Media Centaur detects something worth your attention, a small marker appears on the Status item
in the sidebar — so you'll notice from anywhere in the app, not only when you happen to open the
Status page. Opening the Status page clears it.

## v0.77.8 — 2026-06-05

### Fixed

**Media Centaur no longer fails to start after a background problem was recorded.**
If something went wrong in the background — for example a drive going offline — Media Centaur
quietly noted it so it could show you later. But once such a note had been saved, the app could
fail to start up at all, getting stuck in a restart loop. Startup now handles those saved notes
correctly, so the app opens normally every time.

### New

**A new Status page shows the health of each part of Media Centaur at a glance.**
The Status page now has a Subsystem Health Board: a tile for each part of the app — file watching,
the import pipeline, the movie database connection, and playback — coloured by how it's doing. Click
a tile to drill in and see recent activity and any problems for that area.

**You can now send a diagnostic report when something goes wrong, with full control over what's shared.**
When the Status page surfaces a problem, you can send a report to help get it fixed. A short,
step-by-step flow shows you exactly what will be included before anything leaves your machine, and
if sending isn't possible it falls back to copying the details so you can share them yourself.

### Improved

**The Status page is now focused on health and live activity.**
Less useful sections (recent changes, recently watched, the old error summary, and catalog counts)
were removed so the page concentrates on what's actually going on right now.

## v0.77.7 — 2026-06-01

### Fixed

**Installing an update no longer flashes a scary "not connected" error while the app restarts.**
When you install an update, Media Centaur briefly restarts itself to load the new version. During
that moment it used to show a red "Not connected to server" message — as if something had gone
wrong — even though the restart was perfectly normal. Now it shows a calm "Applying update" notice
instead, so you know the app is just finishing up and will be right back.

## v0.77.6 — 2026-05-31

### Fixed

**Movie collections no longer show up blank — they recover their artwork on their own.**
When a collection (like a film series or franchise) was first added, its poster and backdrop
occasionally failed to arrive — usually a brief hiccup talking to the movie database. The
collection then stayed blank no matter how many more films from it you added. Now, the next time
you add another film from the same collection, Media Centaur fills in the missing poster and
backdrop automatically.

### Improved

**Collections always show a poster and backdrop, even when the movie database has none for them.**
Some collections have no artwork of their own in the movie database. Rather than leave them blank,
Media Centaur now borrows a poster and backdrop from one of the films inside the collection, so
your library never has an empty-looking tile.

## v0.77.5 — 2026-05-31

### Fixed

**Pressing Enter on the Downloads page now reliably starts your search.**
If you typed a query and hit Enter quickly, the search box could lose focus without running the
search, leaving you to click the Search button instead. Enter now always searches.

## v0.77.4 — 2026-05-31

### Fixed

**Manual-search downloads now clear from your queue even when the download client drops the finished torrent.**
The previous release taught Media Centaur to recognise a download by its torrent fingerprint, but a
follow-on gap could still leave a request stuck: when a file finished and landed in your library
before Media Centaur recorded where it had downloaded to, the request stayed open showing
"Downloaded". Media Centaur now records that location as soon as the download appears, and also
recognises files whose release name includes the file type as a trailing word (for example a name
ending in "… x264-FS mkv"). Stuck requests like these now complete on their own.

**Deleting a library entry with many files no longer freezes the dialog.**
Removing an entry that tracked a large number of files could briefly lock up the confirmation
dialog while the files were cleared. That work now happens in the background, so the dialog stays
responsive.

## v0.77.3 — 2026-05-31

### Fixed

**Downloads you start from a manual search now reliably finish and clear from your queue.**
When you searched by hand and picked a release, the file could land in your library while its
download stayed stuck showing "Downloaded". This happened whenever the downloaded file's name
did not exactly match the result you picked — an added "LIMITED", "PROPER", or "REPACK" tag, a
tracker prefix, and the like. Media Centaur now identifies the download by its torrent
fingerprint rather than its name, so it recognises the file and completes the request no matter
how the name differs.

## v0.77.2 — 2026-05-30

### Fixed

**Your controller can no longer act on a Media Centaur window you can't see.**
If a Media Centaur page was left open in the background — hidden behind other
windows, on another desktop, or minimised — a connected gamepad could still
drive it, occasionally launching playback in a window you weren't even looking
at. Gamepad input is now accepted only by the Media Centaur window you actually
have in front of you.

## v0.77.1 — 2026-05-30

### New

**Moving your media to a new drive no longer empties your library.** Move your
files, then point Media Centaur at the new location in **Settings → Library →
Watch Directories**. On the next scan, files that simply moved — same folder
layout, same size — are recognised and re-linked to their existing entries, so
your watch history and details carry over instead of being re-imported as brand
new. (A file you *renamed* or re-encoded still comes in as new.)

### Improved

**There's now a "Scan now" button in Settings → Library**, right where you
manage your watch directories — so after moving or adding files you can pick
them up immediately instead of hunting through other screens.

### Fixed

**Clearing the database now fully resets.** Previously, using **Clear database**
in the Danger Zone could leave behind internal file records that made the next
scan skip your media — so the library stayed empty until you restarted the app.
A clear now rebuilds cleanly from what's on disk.

**Fixed a rare server error when a missing image was requested.** Missing
artwork now always falls back to the usual placeholder instead of erroring.

## v0.77.0 — 2026-05-29

### New

**You can now hide titles below posters for a clean wall-of-posters
view.** A new toggle under **Settings → Library → "Show titles below
posters"** suppresses the title and type/year line beneath each poster
card on the Library page. Leave it on for the default labelled grid,
turn it off when you want pure artwork.

## v0.76.0 — 2026-05-29

### Improved

**You can now drive the Library's tabs, sort, and filter with a keyboard or
gamepad.** After the Library page's recent redesign, its type tabs (All /
Movies / TV), the sort menu, and the name filter couldn't be reached without a
mouse. Press up from the poster grid to jump to the toolbar, move across it
with left/right, open the sort menu with Select (A on a gamepad), and type
straight into the filter.

### Fixed

**Returning to the Home hero no longer leaves it half cut off.** When you
navigate back up to the featured title with a keyboard or gamepad, the page now
scrolls to the top so the whole hero — including the Play and More info buttons
— is visible, instead of stopping partway with the top of the hero clipped.

## v0.75.0 — 2026-05-29

### Fixed

**Pages no longer flash empty "0" placeholders while loading.** Opening the
Library — or Home, History, Upcoming, Review, Downloads, or Settings — used to
briefly show blank counts and an empty page before your real content appeared.
Every page now renders your actual library the moment it opens.

### Improved

**The Library toolbar is cleaner and easier to scan.** The duplicate counts on
the All / Movies / TV tabs are gone (the same totals already sit in the header
just above), the selected tab has a subtler look, the sort and filter controls
now line up on a single row, and the search box stays tucked into a compact
icon until you click it.

## v0.74.1 — 2026-05-29

### Improved

**When an update is available, the release notes are visible right away.**
"What's new" now appears directly under the update instead of being tucked
behind a collapsible section, and a duplicate "View on GitHub" link was removed
for a cleaner layout.

## v0.74.0 — 2026-05-29

### Improved

**The "Recently Added" row on the home page now has a "See all" card at the
end.** Matching the "Continue Watching" row above it, you can jump straight to
your full library from the end of the row — with a keyboard, gamepad, or mouse.

## v0.73.6 — 2026-05-29

### Improved

**The keyboard and gamepad cursor holds its place across more of the app when
content refreshes in the background.** The previous release kept the Library
grid from losing your spot when new media arrived; the same protection now
extends to the home page rows and toolbars, so a background update never
bounces the highlight away from where you were.

## v0.73.5 — 2026-05-29

### Fixed

**The highlight no longer jumps away while you browse the Library and new media
arrives.** When you navigate the Library with a keyboard or gamepad and the
library refreshes in the background — for example, a finished download is added
— the cursor now stays on the item you were viewing. Previously the refresh
could drop the highlight, so your next press would snap back to the first item
or out to the sidebar menu.

## v0.73.4 — 2026-05-29

### Fixed

**A lone "Coming Up" release on the home page no longer stretches across the
whole row.** When only one upcoming release was scheduled, its artwork
ballooned to full width and looked out of place. It now keeps the same size
it would have alongside other releases, with a "See all" shortcut filling the
space beside it.

## v0.73.3 — 2026-05-28

### Fixed

**The Status page sections are now evenly spaced.** The "Errors" panel sat
flush against the cards above it instead of leaving the same gap as the
other sections. Spacing is now consistent all the way down the page.

## v0.73.2 — 2026-05-28

### Fixed

**Installing Media Centaur no longer stops you from logging in to your Linux
desktop.** On some desktops — most notably Ubuntu and other GNOME-based
systems — the background service set up during install could interfere with
the desktop session, leaving you stuck at the login screen. The service now
starts without touching desktop startup, so logging in works normally.

If you are currently locked out, switch to a text console (Ctrl+Alt+F3),
log in, and run `systemctl --user disable --now media-centaur.service` to
restore your desktop login — then update to this version, which fixes the
underlying cause.

## v0.73.1 — 2026-05-25

### Fixed

**The keyboard and controller highlight is no longer cut off on the first
title in each home page row.** When you moved the selection to the leftmost
card in Continue Watching or Recently Added, the highlight outline was
clipped along its left edge. It now draws fully around the first card.

## v0.73.0 — 2026-05-25

### New

**You can now drive the home page entirely with your keyboard or
controller.** The home page — the hero banner plus the Continue Watching,
Recently Added, and Coming Up rows — was previously the one screen you
couldn't navigate without a mouse. Now the arrow keys or d-pad move up and
down between the rows and left and right along each one, Select (Enter / A)
opens a title's details, Play (P / Start) starts playback, and Back
(Escape / B) returns you to the sidebar. When you close a title you opened
from a row, focus returns to exactly the card you came from.

### Fixed

**Keyboard and controller focus now settles correctly on the Watch
History page.** Opening Watch History could leave the cursor in an
unfocused state and skip restoring your place in the sidebar. Focus now
lands on the filter toolbar as intended.

## v0.72.18 — 2026-05-24

### Fixed

**Your gamepad no longer controls Media Centaur while you're playing
something else.** If you left Media Centaur open on one workspace (or a
second monitor) and switched away to a game, your controller could still
trigger actions in Media Centaur in the background — scrolling the
library or starting playback while you played. Media Centaur now responds
to the gamepad only while its own window has focus, so the controller
goes entirely to whatever you're actually using. Click back into the
Media Centaur window to hand the controller back to it.

## v0.72.17 — 2026-05-24

### Fixed

**The Downloads page no longer shows the same release twice.** When your
torrent tracker prefixed a download's name (for example
`www.SomeTracker.org - …`), Media Centaur couldn't tell that the torrent
belonged to one of your active pursuits — so the release appeared both
under Active pursuits (wrongly labelled "Downloaded — no file has landed
in your library") and again under "Other downloads", as if it were
unrelated. Pursuits are now matched to their torrents by the download's
infohash, which the tracker can't mangle, so a download shows up in
exactly one place with its real, live status. Existing in-progress
downloads heal themselves the next time the page refreshes — no action
needed.

**Long release names no longer push the Downloads page sideways.** Very
long torrent names in Active pursuits and History could stretch the page
wider than the window and add a horizontal scrollbar. The names now
truncate cleanly within the page.

## v0.72.16 — 2026-05-24

### Improved

**The detail view makes better use of wide screens.** When you open a
series or movie on a full-width window, its network, rating, original
language, and genres now sit alongside the play button instead of
dropping below the description — closing the empty gap that used to open
up next to the buttons. Narrower and split-screen windows are unchanged.

## v0.72.15 — 2026-05-24

### Improved

**The Downloads page no longer implies your pursuits are stalled when
only the download client is.** The "Live" badge next to Active pursuits
actually tracked the connection to your download client — not whether
your pursuits were progressing — so it could read as if nothing was
happening when pursuits were searching, awaiting your decision, or
importing perfectly fine. The page now stays quiet while everything's
healthy and shows a clear, scoped warning ("Download client lagging" /
"offline") only when the client connection is actually degraded.
In-progress downloads also note "last seen Nm ago" when their figures
have gone stale, so a frozen progress bar can't be mistaken for a live
one.

## v0.72.14 — 2026-05-24

### Fixed

**Season and complete-series packs now correctly show as landed.** When
you grabbed a multi-episode pack from a manual search — one torrent
holding a whole season or an entire series — the pursuit could stay
stuck on "Downloaded — no file has landed in your library" indefinitely,
even though every episode was already imported. Media Centaur now
recognizes a pack by its release folder, so the pursuit completes as
soon as the files land, the same way single movies and TMDB-tracked
downloads already did.

## v0.72.13 — 2026-05-24

### Fixed

**Movie cast now appears the moment you refresh credits.** After using
**Settings → Library Maintenance → Refresh movie credits**, the cast
and crew now show up in a movie's **More info** panel right away —
including the cast grid and the "Directed by / Written by" line.
Previously the refresh updated the data behind the scenes, but an open
movie view kept showing the old, cast-less version until the app
restarted. (TV series were already unaffected.)

## v0.72.12 — 2026-05-24

### Fixed

**Artwork now appears on the open detail view the moment it downloads.**
When you opened a title that had no image and used **Refresh artwork**
(or artwork simply finished downloading in the background), the detail
view kept showing the placeholder until you reloaded the page. The
placeholder now flips to the real poster/backdrop on its own, no refresh
needed.

## v0.72.11 — 2026-05-24

### Fixed

**Refreshed artwork now updates instantly.** When you use **Refresh
artwork** on a title and it downloads a new or corrected poster,
backdrop, or logo, the new image appears right away in the detail view.
Previously a *replaced* image could keep showing the old one for up to
an hour, or until you reloaded the page.

## v0.72.10 — 2026-05-24

### New

**Refresh artwork for a single title.** Open a movie or show, go to its
**Manage** view, and click **Refresh artwork** to re-fetch its poster,
backdrop, and logo from the metadata service. Use it when a title is
missing its image or downloaded the wrong one — no need to refresh the
artwork for your whole library from Settings anymore.

## v0.72.9 — 2026-05-23

### Fixed

**Download progress no longer shows impossible percentages.** On the
Downloads page, a torrent that was (for example) 23% complete could
display "2330%". Progress now reads correctly between 0 and 100%.

## v0.72.8 — 2026-05-23

### Fixed

**Movies and TV episodes that had silently gone missing now appear in
your library.** If a file was added while the movie/TV metadata service
was briefly unreachable, Media Centaur would detect the file but could
quietly fail to import it — so it never showed up in your library *or* on
the review screen. Those files are now imported correctly. A new
safeguard also stops a single TV season from being recorded twice, a
situation that could previously block an entire show's episodes from
appearing. If you were missing content, it should fill in on its own.

## v0.72.7 — 2026-05-23

### Fixed

**A movie you own from a collection now opens its own page, not the
collection's.** When a film collection (like a series of related movies)
has only one movie in your library, opening it now shows that movie's
details — with a note that it's part of the collection — instead of
opening the whole collection. Collections where you own two or more
movies still open as a collection. The library grid and the detail page
now always agree on whether something is shown as a movie or a
collection.

## v0.72.6 — 2026-05-23

### Fixed

**The diagnostic console no longer flashes hidden log lines when it first
opens.** It now applies your active filters before showing any entries, so
log lines you've filtered out (for example, hidden components or lower
severity levels) don't briefly appear and then vanish.

## v0.72.5 — 2026-05-23

### Improved

**Language settings are now their own section, and much easier to set up.**
Settings → Language gives your audio and subtitle language preferences a
dedicated home (they were previously tucked under Playback). "Languages
you understand" is now a searchable, reorderable list — add a language by
name, order it by preference, remove it with a click — instead of a
comma-separated box of codes. It saves as you edit.

## v0.72.4 — 2026-05-23

### Improved

**One-line install now works on macOS (Apple Silicon).** The
`curl … | sh` installer now detects Apple Silicon and installs the
experimental macOS build directly — no manual download. See the new
[macOS guide](https://github.com/media-centaur/media-centaur/wiki/macOS)
for what works, what's still rough, and how to report issues. macOS stays
experimental (Linux-developer-tested only); Linux is unchanged.

## v0.72.3 — 2026-05-23

### Improved

**Internal maintenance.** Repository housekeeping — completed planning
documents were pruned from the tree (their history is preserved in git).
No change to how Media Centaur behaves.

## v0.72.2 — 2026-05-23

### Changed

**The app is now called Media Centaur.** The misspelled "Centarr" is now
"Centaur" — across the app, the website (**media-centaur.net**), and the
project. How the app works is unchanged; only the name is different.

**Existing installs need a one-time manual switch.** The rename changes the
name of the release package, so an existing *Media Centarr* install can't
pick up this version through the in-app updater. To move to Media Centaur:

1. Stop the old service: `systemctl --user stop media-centarr.service`
2. Rename your data folder so the new app finds your library:
   `~/.local/share/media-centarr` → `~/.local/share/media-centaur`, and
   inside it rename `media-centarr.db` → `media-centaur.db`.
3. Install Media Centaur from **media-centaur.net** and start it.

Your library, settings, and watch history carry over. After this one-time
step, in-app updates work normally again.

## v0.72.1 — 2026-05-23

### Improved

**Internal maintenance.** Test-suite reliability work — the automated tests
now wait for results deterministically instead of on fixed timers, removing a
source of spurious failures — plus release-build housekeeping. No change to
how Media Centarr behaves day to day.

## v0.72.0 — 2026-05-22

### Improved

**Reliability hardening.** Internal safeguards and added test coverage so
the watch-progress and movie-collection display issues fixed in 0.71.2
can't quietly come back. No change to how Media Centarr behaves day to
day.

## v0.71.2 — 2026-05-22

### Fixed

**Watch progress updates live again.** When you finish (or make progress
on) an episode or movie, the detail screen now updates the progress bar
and the watched checkmark right away — you no longer have to close the
title and reopen it to see the new state.

**Movie collections no longer crash the detail screen.** Opening a movie
collection that contained a downloaded movie could crash its detail view.
It now opens normally.

**Playback tracking on files with many tracks.** Files carrying a lot of
audio or subtitle tracks could trigger internal errors that interfered
with playback tracking. These files are now handled correctly.

## v0.71.1 — 2026-05-22

### Improved

**Language names are spelled out.** A title's detail view now shows full
language names — *Japanese*, *English*, *Spanish* — instead of
three-letter codes, both on the *Remembered tracks* line and in the
Language detail.

## v0.71.0 — 2026-05-22

### Improved

**See and reset a title's remembered tracks.** When Media Centarr
remembers the audio or subtitle tracks for a show or movie — because you
changed them during playback — it now shows them on the title's **More
info** panel, on a *Remembered tracks* line (for example *"jpn audio ·
eng subtitles"*). A **Reset to default** button there forgets the
remembered choice so the title goes back to following your Settings →
Playback language preferences. The line appears the moment a choice is
captured, even while you're looking at the details.

## v0.70.0 — 2026-05-22

### New

**Language & subtitle preferences.** Set your preferred audio and
subtitle languages once in Settings → Playback, and Media Centarr applies
them automatically when you start something — choosing the matching audio
track and turning subtitles on or off to suit. You can also override the
choice for an individual show or movie when its needs differ from your
defaults.

**Manual downloads now finish on their own.** When you grab a release
from search, Media Centarr follows the file all the way into your library
and clears it from Active Pursuits once it lands — previously a manual
grab could sit there indefinitely showing "Not visible in your download
client." A download that finishes but never imports (for example, a
higher-quality copy of something you already have) now shows its real
stage — "Downloaded — not landed" or "In review" — instead of a confusing
message.

### Fixed

- Fixed a crash when opening a movie collection — clicking certain
  collection entries failed to load their details.
- Audio and subtitle tracks are now selected more reliably: language
  codes are matched consistently, including the "subtitles only when the
  audio isn't in your language" case.

## v0.69.0 — 2026-05-21

### New

Experimental macOS support. Media Centarr now ships a `darwin-arm64`
release alongside the Linux build, with a native macOS installer that
sets up autostart via launchd (the macOS analog of systemd) and the same
atomic install / upgrade flow Linux users have. The in-app
Settings → Overview → Update now path works on both platforms — once
installed, you upgrade the same way regardless of OS.

**macOS support is experimental in this release.** Try it on a
non-critical setup first, and report rough edges via the [macOS] issue
link on the docs site. We don't own a Mac, so first user reports are
how we'll discover what doesn't work yet.

### Improved

The README and docs site now carry visible status banners calling out
the in-progress UI overhaul and the experimental status of macOS
support, so you know what to expect at a glance.

## v0.68.1 — 2026-05-21

Internal maintenance release. No user-visible changes — the performance
baseline used to detect regressions has been refreshed against the
current code, and internal documentation was updated. See the git
history for details.

## v0.68.0 — 2026-05-20

### Improved

Navigation feels measurably snappier across the whole app. Several
sources of perceived latency on every page change have been
removed in a single sweep:

* The library page used to play a fade-and-slide-in animation on
  every card on every navigation. Cards now appear instantly.
* Posters and tiles in the home rows (Continue Watching, Coming
  Up, the upcoming marquee) now carry stable identities across
  renders, so the browser preserves the existing elements instead
  of tearing them down and rebuilding them on each refresh.
* The thin progress bar at the top of the page now only shows on
  genuinely slow operations. Fast navigations no longer briefly
  flash it.
* Modal panels open about 100ms faster.
* The sort-dropdown menu no longer plays a brief slide-in
  animation; it just appears when you open it.

Initial app load and reloads are also faster: hashed JavaScript
and CSS bundles are now served with a long-lived immutable cache
header, so the browser never re-checks them once they're cached.
A static default for input-method detection prevents a brief
focus-ring flicker on the very first paint.

## v0.67.4 — 2026-05-20

### Improved

Pages now switch without an artwork flash. Posters, backdrops, and
hero images used to render blank for a frame on every navigation
while the browser decoded the image off-thread — even when the
bytes were already in the local cache. In-flow artwork now fetches
eagerly and decodes synchronously, so each page paints with its
images already drawn. The hero and modal backdrops also claim
high fetch priority. Cast headshots and search-result thumbnails
remain lazy because they live behind reveals and can run into the
dozens.

## v0.67.3 — 2026-05-20

### Improved

Disabled the LiveView longpoll fallback. Previously, if the
WebSocket handshake didn't complete within 2.5 seconds, the page
would silently downgrade to HTTP long-polling — masking the real
connectivity problem and producing a degraded experience that
looked like a generally slow app. With the fallback off, transport
failures surface as a normal reconnect attempt instead of a hidden
slow path. On a healthy connection (essentially every connection)
nothing changes.

## v0.67.2 — 2026-05-20

### Improved

Posters, backdrops, and episode thumbnails now load instantly on
repeat visits. Image responses previously had no cache directives,
so the browser revalidated every artwork URL on each navigation —
adding a noticeable round-trip to every list, grid, and detail
view. The image server now returns local artwork with a one-hour
cache window plus a content fingerprint, and the home page's
version-busted URLs cache for a year. The first visit is unchanged;
every visit after is served from the local browser cache.

Patched two HTTP-server security advisories (Bandit chunked-encoding
DoS, Plug multipart-header DoS) by updating to upstream patched
releases. No user-visible behavior change beyond the fix itself.

## v0.67.1 — 2026-05-19

### Improved

Every page now paints instantly. Watch History, Acquisition, Review,
and Settings used to wait on a handful of database reads and capability
probes before the first paint — small individually, but the page was
frozen until the slowest one returned. Those reads now happen on a
supervised background task and stream into the page as they finish,
so the layout is up the moment you click. If a probe is slow (a
Prowlarr health check on a flaky network, for example) the page
appears with placeholders instead of stalling.

## v0.67.0 — 2026-05-18

### Improved

Modal opens are noticeably faster. Clicking into a title — from
anywhere in the app — used to do several database lookups to figure
out what kind of entity it was before the detail panel could render.
The detail projection now maintains a direct lookup index, so opening
a TV series, movie series, movie, or video object is a microsecond
cache hit instead of a multi-query probe.

Playback stays responsive while something is running. Every few
seconds during playback, the app broadcasts a progress update so the
modal's resume indicator and the Continue Watching row track in
real time. The broadcast used to re-load the whole entity from the
database on each tick — every episode, every image, every linked
file — and that cost was paid by every connected LiveView. The tick
now reads the same data from the in-memory projection. If you left
a video playing while browsing the library before and noticed the
UI getting sluggish, that's gone.

Opening the Files tab on a long-running show no longer freezes the
modal while the app sizes each file. File stats now run in parallel
on a supervised task; the modal paints immediately and sizes fill
in as they come back. A stale network mount can no longer stall the
whole modal — each stat now times out individually.

Clicking Play on a Continue Watching card or the Home hero responds
instantly. Previously the page paused briefly while the playback
handshake completed; now the URL updates immediately and the player
starts in the background.

The Upcoming page paints right away instead of holding the navigation
open while six release-tracking queries finished one after another.
The calendar, releases, tracked items, and grab statuses now load in
parallel and fill in as they arrive.

The Library grid also avoids a small per-refresh cost: re-sorting an
already-sorted view-projection list on every entity change. Not a
felt change on its own, but it adds up across the many small refreshes
the page receives.

## v0.66.2 — 2026-05-18

### Improved

The setup tour no longer makes you wait for TMDB to re-verify when
you reopen the wizard. Previously, if you'd already gotten TMDB
working in a prior session, Next was briefly disabled after every
restart while the app re-tested your saved key in the background.
Now the wizard trusts your saved configuration and advances; if the
re-test happens to fail, you'll see a flash and can step back to fix
it. New first-time users still need a successful test to move on
(an actually-failing test still blocks).

## v0.66.1 — 2026-05-18

### Fixed

A crash on startup if your library contained a movie collection where
some constituent movies were tracked in metadata but not yet on disk.
The Library projection layer assumed every collection child had a
file present and crashed when one didn't, taking the whole service
down with it. The projection now treats "no file yet" as a normal
state — the collection still appears, the missing children are
flagged as not-present in the detail view.

If you were on v0.66.0 and saw the service restarting in a loop,
this is the patch that unblocks it.

## v0.66.0 — 2026-05-18

### Improved

The Library page and the entity-detail modal both render from
in-memory projections instead of querying the database on every
open. You should notice snappier card grids on `/library`, faster
modal opens when you click into a title, and smoother updates when
new media gets added while you're browsing.

Continue Watching now refreshes itself when a watch drive comes
back online. Previously, if a drive disappeared and reappeared,
the row would stay in its stale state until you navigated away and
back — now it picks up the change automatically.

### Fixed

A small visual glitch where the "now playing" indicator could
appear on the wrong card immediately after starting playback (it
was matching against the wrong identifier in some paths). The
right card lights up now.

### Behind the scenes

This release ships the closure of two long-running architectural
campaigns:

- **Library Schema v2.** The internal data model has been rebuilt
  around a canonical "playable item" leaf — every supporting table
  (watched files, watch progress, subtitles, images, IDs) now keys
  to that one row. Invisible today, but it unblocks future features
  like multiple cuts of the same movie (theatrical + director's)
  and multi-part episodes as natural data shapes rather than
  workarounds. See decision record ADR-047.
- **Desktop rearchitecture.** Every read path consumed by a page in
  the UI now goes through an in-memory projection layer that
  rebuilds in the background as data changes. CI now enforces this
  with a per-page database-query budget so the pattern can't quietly
  regress.

## v0.65.1 — 2026-05-17

### Behind the scenes

Follow-up to the file-presence unification: cascading deletes are
now driven entirely by the application instead of the database. No
behaviour change for end users — the same deletion path runs in the
same order as before — but future schema work on SQLite no longer
needs to dance around foreign-key constraints. See
`decisions/architecture/2026-05-17-046-app-owned-cascading-deletes.md`.

## v0.65.0 — 2026-05-17

### Improved

File-tracking reliability. The library and the filesystem watcher
now share a single source of truth for "does this file exist on
disk." Two consequences you may notice over time:

- The class of bug where the ingest pipeline silently stalled with
  orphan rows (a file detected on disk but never matched to a
  library entry, even after a restart) is now structurally
  impossible. The previous recovery path — wiping the data directory
  — should never be needed again.
- When you delete a file from disk, the cleanup cascade through your
  library is more predictable: removing the file's presence record
  cleanly removes the linked library row in the same step, rather
  than relying on two separate tables agreeing.

### Behind the scenes

Multi-phase architectural refit (the "library-presence-unification"
campaign): file-presence tracking, TTL absence detection, and
pipeline dedup all moved from the Watcher context into the Library
context. The legacy `watcher_files` table is dropped; cascade-delete
via a foreign key enforces the entity↔presence invariant; pipeline
duplicate-event suppression now uses an in-memory ETS set rather
than a database upsert side-effect. No configuration changes.

## v0.64.1 — 2026-05-17

### Behind the scenes

Internal cleanup: prunes five no-longer-referenced exports from the
acquisition boundary, finishing the third and final phase of the
acquisition-split refactor begun in v0.62. No user-visible change.

## v0.64.0 — 2026-05-17

### Behind the scenes

Internal refit: the release-search machinery (Prowlarr client, query
building, title matching, quality bounds) moves into its own
`MediaCentarr.Search` module group, separate from the acquisition
flow that consumes it. No user-visible change in this release —
this is the structural groundwork that lets the next acquisition
features land without piling more responsibilities onto a single
sprawling context.

## v0.63.0 — 2026-05-17

### Fixed

If your library has previously gotten stuck — files on disk, watcher
running, but nothing ingesting — this upgrade unsticks it. A
migration finds files the watcher had recorded but the pipeline
never matched (typically because TMDB was misconfigured at the
time), forgets them, and lets the next scan dispatch them fresh.
Your library should populate within a few minutes of restart.

### Behind the scenes

This release lands the first two phases of a multi-release
architectural refit that moves file-presence ownership from the
watcher into the library, where it belongs. The visible behavior
above is the first user-facing benefit of the refit; subsequent
phases over the next few releases will eliminate the entire bug
class structurally.

## v0.62.3 — 2026-05-17

### New

The Library page now has a Scan button when your library is empty but
watch directories are configured. A line above it shows the live count
of files the pipeline is still ingesting, so the page reads as
"working on it" rather than "nothing here". The Setup Tour now lands
you on the Library page when you finish, so this signal is visible
from the moment your tour ends.

### Fixed

Add and Remove on the setup tour's watch-directories step now respond
on the first click. They used to need two clicks because Settings
writes were updating the database but leaving the in-memory cache
stale until an async refresh caught up; same-action reads after the
write now see the new value immediately.

## v0.62.2 — 2026-05-17

### Fixed

The setup tour no longer asks you to re-enter credentials you've
already saved. Clicking Next on a TMDB, Prowlarr, or download-client
step where the key was already configured used to refuse to advance
because the (intentionally empty) password input was required. Now an
empty submit means "no change, just continue".

Prowlarr and the download client no longer need a second Next click
after their connection test succeeds. The previous flow could verify
against a half-saved configuration and report a failure that the next
click would silently fix; verification now runs once, after all fields
are saved, and the tour advances as soon as the test passes.

## v0.62.1 — 2026-05-16

### Improved

The setup tour now verifies every integration before letting you
continue. The Next button on the TMDB, Prowlarr, and download-client
steps submits the form, tests the connection, and only advances when
the test succeeds — so a typo, an expired key, or a wrong port can't
slip through and silently break the rest of the app. Optional steps
(Prowlarr, download client, mpv, ffprobe) keep a Skip button alongside
Next so you can come back to them later. Critical steps (watch
directories and TMDB) hide Skip — you must configure them for Media
Centarr to do anything useful.

The library, dashboard, and detail pages render noticeably faster.
Library views now come from in-memory projections instead of querying
the database on every navigation.

### Fixed

Pressing Enter in the watch-directory input on the setup tour now adds
the directory. Previously you had to click the Add button twice.

Submitting the download-client password on the setup tour no longer
silently clears the field without testing — the connection is
verified, and the tour advances automatically when it succeeds.

## v0.61.7 — 2026-05-15

### Fixed

Media Centarr no longer downloads a second copy of a movie after the
first copy has already landed. When a pursuit completed, snoozed
acquisition jobs for the same movie could wake hours later and grab a
different release — leaving you with two copies of the same film. The
pursuit now closes out all related acquisition work the moment a file
lands, so duplicate downloads stop at the seam.

## v0.61.6 — 2026-05-15

### Fixed

Movie collections now show up in the library view again. Files for
movies that belong to a collection (a trilogy, anthology, or any TMDB
collection grouping) were being attached to the parent collection
instead of the individual movie, which caused both the collection and
the child movie to disappear from the grid. A one-time data fix runs
during this update to repair existing entries — after restarting, your
collections will be visible alongside your other movies.

## v0.61.5 — 2026-05-14

### Fixed

Pursuits no longer get stuck "active" after the file they were chasing
has already been added to your library. The completion path now has a
safety net — once every fifteen minutes, Media Centarr checks each
active pursuit against the library and closes it out if the matching
episode or movie is already on disk. The fast path (close the pursuit
the moment the file lands) is unchanged; this just catches the rare
cases where that notification was missed.

## v0.61.4 — 2026-05-14

### Improved

The "Coming up" row on Home no longer makes its secondary cards
taller when a release picks up a status like "Seeking" — the badge
now floats in the top-right corner of the card instead of stacking
under the title, so the row keeps a consistent height whether or not
the release has a status.

## v0.61.3 — 2026-05-14

### Fixed

Pursuits for a specific episode no longer pull in noisy results from a
too-broad "Season N" fallback search. Previously, if the
episode-specific search came up empty, Media Centarr would widen to a
"Show Season 2" query — which returned a pile of unrelated
season-tagged releases and made the detail view's query list
contradict its own header ("TV • S02E02" at the top, but a "Season 2"
query sat right below it). Episode pursuits now search only for the
specific episode. If you want a season pack to be acceptable, create a
season-level pursuit — those still search both forms as designed.

## v0.61.2 — 2026-05-14

### Fixed

Clicking a grouped pursuit row in the Active Pursuits list (e.g. a
show with multiple episodes in the same state, shown as "Sample Show
— 2 episodes — Searching") now expands the row to reveal the
individual episodes. The previous release had a wiring mismatch
between the group's expand state and the click handler, so clicks
fired but the row visually never opened. The chevron now flips and
the per-episode pursuits are listed underneath as intended.

## v0.61.1 — 2026-05-14

### Improved

Opening a pursuit's detail modal is now instant. Previously, when a
pursuit was sitting on a decision card waiting for you to pick a
release, clicking the pursuit to open the modal could take roughly
half a second to a couple of seconds — Media Centarr was asking
Prowlarr for the latest alternatives before drawing the modal, and
nothing rendered until the indexer answered. The modal now opens
immediately with the pursuit's status and timeline already filled in;
the alternatives list shows a "Searching for alternatives…" spinner
and populates as soon as Prowlarr responds. You no longer pay the
indexer's round-trip every time you peek at a pursuit.

## v0.61.0 — 2026-05-14

### Fixed

Pursuits no longer go silently dead after Media Centarr cancels a
torrent that's been sitting at zero seeders. Previously, when the
system decided a release was unsalvageable and cancelled it for you,
the pursuit could end up with no active target and just sit there —
you'd only notice by opening the pursuit and seeing it had nothing
running. The dead release now cancels AND a fresh search starts
automatically for a different release of the same episode or movie,
so pursuits keep chasing on their own until they succeed, exhaust
their attempts, or you cancel them yourself.

When a download finishes while a pursuit's decision card is open and
waiting on your pick, the pursuit now picks the landed file up
automatically instead of leaving the "pick a release" prompt hanging
until you click through it.

Picking an alternative release from a pursuit's decision card now
refreshes the pursuit modal immediately. Previously the modal sat
showing stale information after you picked, so it looked like nothing
had happened until you closed and reopened it.

Manual searches no longer add two phantom entries ("user decision
recorded", "fallback initiated") to the pursuit's timeline before
the actual pick. The timeline now shows a single, clean event for
each manual pick.

### Migration

This release applies one database migration on first launch that adds
an `awaiting_decision_at` column to the pursuits table and converts
existing "needs decision" pursuits to use it. The backfill is
idempotent and reversible, and the in-app updater handles the upgrade
— nothing for you to do.

## v0.60.2 — 2026-05-14

### Improved

The Downloads page now shows the exact Prowlarr query each pursuit is
using. Previously a pursuit could sit on "Searching Prowlarr" without
telling you what string was actually being searched — so when a search
quietly returned nothing useful, there was no way to tell whether the
problem was the query, your indexers, or the release simply not being
out there. The pursuit detail panel now lists the literal queries
under the title, repeats them next to the "Searching" status, and
shows them on the decision card so you can see what generated the
alternatives. For brace-expanded queries like `Sample Show
S01E{01,02,03}`, you see each expanded query as its own line. Future
timeline entries for "Searching Prowlarr" and "No acceptable release
found" will also name the query that was run.

## v0.60.1 — 2026-05-14

### Fixed

If your media drive is mounted slightly after Media Centarr starts —
typical on a fresh boot when the service comes up faster than the
filesystem — the library now appears as soon as the drive is online.
Previously the watcher could attach to the path before the drive was
ready and silently sit on a dead file-system watcher, leaving the
library empty and only Continue Watching and Coming Up showing stale
entries you couldn't click. The watcher now polls every couple of
seconds while it's waiting for the path to become accessible, then
re-attaches and restores the library automatically.

## v0.60.0 — 2026-05-13

### Improved

The Downloads page is faster across the board. With many active
pursuits, the list now pairs each pursuit with its live download in a
single pass instead of recomputing per render, and the pursuit detail
panel updates download progress without re-fetching the rest of the
panel on every tick. Manual search feels snappier — keystrokes no
longer pay for a second round-trip to the search session before the
preview updates.

Background acquisition work scales better. The periodic pursuit check
now does a constant number of database queries regardless of how many
pursuits are in flight (previously it scaled with the active count).
Removing a tracked show cancels all of its in-flight downloads in a
single step rather than one at a time.

## v0.59.1 — 2026-05-13

### Fixed

Release tracking for a movie now clears itself once the movie lands in
your library. Previously, an auto-acquired movie would leave its
tracking entry behind, cluttering your watchlist after its job was
already done. The tracking events log records the completion so you
can see what happened. TV series tracking is unaffected — episodic
shows keep tracking as before, since new episodes continue to release.

## v0.59.0 — 2026-05-13

### Improved

The Downloads page reads at a glance now. Active Pursuits and History
rows are dense single lines — title on the left, severity-colored
status on the right, no badge in the middle to draw the eye into empty
space.

When you have several episodes of the same show in the same state —
say seven *Sample Game May Weep* episodes all searching — they collapse into
one expandable container instead of stacking as seven near-identical
rows. Click the group to drill into the per-episode list; click an
episode to open its pursuit modal.

Pursuits now tell you **what to expect**. While a pursuit is between
attempts, the status reads *"Next attempt in 2h 15m (attempt 4)"*
instead of the timeless *"Looking for an acceptable release"*. The
countdown is minute-accurate and updates whenever the worker schedules
its next try.

## v0.58.0 — 2026-05-12

### Improved

Pursuit detail now opens as a **modal over the Downloads page** instead
of a separate page. Back closes it, refresh keeps it open, and the URL
is shareable. You can scan the Downloads page and dip into individual
pursuits without losing your place.

The **Decision needed** experience reads cleanly now. When a pursuit
is waiting on you, the modal shows a single card with the alternatives,
*Search Prowlarr again*, and *Cancel pursuit* sitting together in one
action row. Gone are the duplicate prompts and the floating Cancel
button.

The Downloads page **Activity** zone is now a proper **History** zone:
one row per pursuit (no more seven copies of *Sample Game May Weep* stacked
without season/episode), filtered by terminal state (**Failed**,
**Cancelled**, **Succeeded**, **All**). The default view shows Failed
— the bucket that actually wants your attention. Live pursuits live in
the *Active pursuits* zone above; History is unambiguously past-tense.

Picking an alternative release is **instant** now — no second round-
trip to Prowlarr to look the release up after you clicked it.

Modals adapt to viewport size more gracefully — always at least 100px
of breathing room from each edge, with the description column narrower
so other metadata can spread. Hero titles get a subtle drop shadow so
they stay legible over bright backdrops.

### Fixed

Clicking an alternative release on a pursuit started via brace-expanded
search (like `Sample Show S01E{01,02}`) no longer toasts *That release
is no longer available* — it actually submits the release.

Clicking **Search Prowlarr again** no longer freezes the Downloads page
or drops you into long-poll fallback when the indexer takes a few
seconds. The search runs in the background and the page stays live.

## v0.57.0 — 2026-05-12

### Improved

Pursuit cards on the Downloads page are no longer a wall of identical
rows. A TV pursuit now shows its episode in the title — *Sample Show Fifteen
S02E01*, *Sample Show Fifteen S02E02*, and so on — so you can scan a season at a
glance.

Each card now shows a single, severity-colored status sentence that
tells you what's actually happening — *Searching — Looking for an
acceptable release*, *Decision needed — pick a release below*, or the
live torrent state when a download is matched. The attempts/origin
metadata and the recent-events list are gone from the card; both
still live on the pursuit detail page.

The entire card is the link to that detail page now — no more
*Open full →* corner link.

## v0.56.1 — 2026-05-11

### Fixed

Opening a pursuit waiting for your decision (state: **Decision
needed**) no longer hammers Prowlarr in a loop and stop responding.
Alternatives are now fetched once when the decision card appears,
not on every queue tick.

Pursuits started from the manual-search box now load their
alternatives using the query you typed, not the messy release title of
your first pick — so the "Pick a different release" list is actually
populated.

## v0.56.0 — 2026-05-11

### New

You can now **change target** on any pursuit — whether it was started
automatically or by a manual search. The previous "Re-search" button is
gone; in its place, every pursuit (auto or manual) carries its search
recipe so it can abandon the current release attempt and look for a
different one without losing history. Manual picks that get stuck no
longer dead-end the way they did in v0.55.

### Improved

The Downloads page uses clearer status vocabulary throughout: targets
move through **Seeking → Acquired → Succeeded**, with **Failed** and
**Cancelled** as the terminal failure states. The old mix of
"grabbed", "abandoned", "snoozed" is retired.

The decision card ("Pick a different release") and the manual search
form now share one code path, so a release you pick from either
surface lands in your pursuit identically — including its history,
attempt count, and ability to change target again later.

### Fixed

A pursuit that "succeeded" but never had a matching file in the
download client now shows a clear *Waiting — not visible in your
download client* hint with **Change target** and **Cancel** actions,
instead of looking stuck.

## v0.55.1 — 2026-05-11

### Fixed

Clicking **Re-search** on a stuck **manual** pursuit (one you created
from the Downloads search box, not an auto-acquisition) silently
crash-looped the background search worker. It looked like the pursuit
was searching, but no progress was ever made — the worker raised the
same error on every retry until it gave up.

The **Re-search** button is no longer offered for manual pursuits.
Instead, you'll see **Pick a different release**, which opens fresh
Prowlarr results in the decision card so you can choose a new release
directly. If something else manages to trigger Re-search on a manual
pursuit anyway, you'll now see a clear inline message pointing you at
**Pick a different release** rather than a silent retry loop.

## v0.55.0 — 2026-05-11

### Improved

Downloads and pursuits are now visually connected on the **Downloads**
page. Previously, the page showed three separate stacked lists — an
"Active queue" of torrents at the top, a list of active pursuits in
the middle, and the activity table at the bottom. You had to mentally
pair which torrent was for which pursuit.

Now each pursuit card grows a footer showing its matched live torrent
(state, progress, ETA, download client) with the cancel button right
there. Pursuits with no matching torrent show a status hint instead —
*Searching*, *Snoozed*, *Waiting — not visible in your download
client*, or *Stopped* — so you can see at a glance what's happening
without opening the detail page.

A small **Other downloads** section appears below the activity table
if you have torrents in your download client that don't pair with any
tracked pursuit (sideloaded manually, or a title-match miss).

## v0.54.0 — 2026-05-11

### Fixed

If a download appeared stuck in the **Waiting / Not visible in your
download client** state — the file was sent to the download client but
never showed up in its queue — clicking **Re-search** on the pursuit
detail page would refuse with *"This pursuit can't be re-searched right
now."* The only recovery was to cancel the whole pursuit and start
over.

Re-search now works for this state. The stuck grab is reset and a
fresh search begins immediately, just like for snoozed, abandoned, or
cancelled grabs.

## v0.53.1 — 2026-05-11

### Fixed

The **Downloads** section in the sidebar would disappear after every
update, and the only way to bring it back was to visit Settings →
Acquisition, click *Test* on the download client, save the
auto-acquisition defaults, and refresh the browser. The Downloads
nav now appears reliably as soon as both Prowlarr and the download
client are configured and their connection tests pass — no manual
test, no reload.

### Improved

The Downloads nav now appears and disappears **in real time** when
the underlying connection state changes. If you save Prowlarr or
download-client settings and run *Test*, the sidebar updates the
moment the test result comes back. Previously, the nav only refreshed
on the next page load or user interaction.

**Behavior change.** The Downloads section is now visible only when
**both** Prowlarr **and** your download client are configured and
have a passing test result. Earlier releases gated only on Prowlarr,
which meant the section could appear with no download client wired
up — a state in which the queue page had nothing to show. If you
had Prowlarr but no download client and were relying on this, open
Settings → Acquisition and finish wiring your download client; the
Downloads section will reappear automatically.

## v0.53.0 — 2026-05-11

### New

The pursuit detail page (`/download/:id`) has been redesigned around
what's actually happening to a pursuit right now, instead of the
static counters that used to sit there. The page now leads with a
live status card — "Downloading", "Snoozed", "Stalled", "Queued",
"Verifying", "Waiting" — plus a one-line description of what's
expected to happen next automatically. When the download client is
reporting progress, a progress bar shows up.

You can now act on a stuck pursuit without cancelling it. New buttons
appear on the activity card when they make sense:

- **Re-search** — for snoozed, stalled, abandoned, or
  cancelled-grab pursuits, this kicks off a fresh Prowlarr search
  right now. Snoozed pursuits keep their attempt count;
  abandoned/cancelled grabs are re-armed from a clean slate.
- **Pick a different release** — switches the pursuit into
  decision mode so you can browse alternatives in the existing
  picker.
- **Cancel pursuit** — unchanged in behaviour, but now lives in
  the activity card next to the other actions.

Pursuits that haven't seen activity in over 24 hours now surface a
"Last activity: 2d ago" footnote in red, so silently-stuck pursuits
stop looking healthy.

### Improved

The pursuit detail header is now identity-only — title, type
(Movie / TV with season and episode), year, and quality criteria.
The noisy `Attempts`, `Tried releases`, `Started`, and `Origin`
counters moved into the live activity card, where they only show
up when relevant. The bottom of the page is now labelled "History"
to make clear that it's the past, while the activity card is the
present.

## v0.52.1 — 2026-05-11

### Fixed

Republishes v0.52.0 after a release-build regression. No user-visible
behaviour changes versus v0.52.0 — the display-environment resilience
and mpv log-file capture from that release ship intact. The v0.52.0
tag never produced a downloadable build.

## v0.52.0 — 2026-05-11

### Fixed

Playback no longer fails silently with “mpv exited (status 1) before
playback started” when Media Centarr was started before your desktop
session was ready. The app now finds your Wayland or X11 session
automatically and hands it to mpv, so the player can open its window
even when the service was launched at boot. If no desktop session is
reachable at all, the flash message now tells you to sign in or
restart Media Centarr after login instead of giving you a cryptic
exit code.

The shipped systemd unit also waits for `graphical-session.target` and
imports the relevant environment variables before launch, so fresh
installs get this behaviour out of the box. Existing installs benefit
the moment they update.

### Improved

When mpv does fail to start, the cause now appears in the journal and
Console drawer — mpv's own log is captured to a per-session file and
the exit classifier summarises it. Previously, `--no-terminal` meant
mpv's error message never reached the backend, leaving only a generic
line about a silent exit.

## v0.51.3 — 2026-05-09

### Fixed

Freshly grabbed downloads briefly showed a long string of letters and
numbers as their title — qBittorrent's placeholder before it has
fetched the torrent's real name. The Downloads page now says
“Fetching torrent details…” in that window instead, then swaps in
the actual title once it's available.

## v0.51.2 — 2026-05-09

### Fixed

Cancelling a download from the Downloads page now removes the row you
clicked. The previous version sometimes appeared to delete the wrong
row visually — the actual cancellation was correct, but the UI showed
a different row disappearing until the page was reloaded.

### Improved

The app stays more responsive while it scans your library for changes.
Background work that updates pursuit health, refreshes images, and
reconciles file presence no longer holds up the live UI, and disk
health checks run in parallel so the upcoming-shows screen feels
snappier on libraries with many entries.

## v0.51.1 — 2026-05-09

Internal quality follow-ups on the v0.51.0 data-migrations mechanism —
regression tests for the runner, tightened authoring rules, no
user-visible behavior change.

## v0.51.0 — 2026-05-09

### Fixed

Active downloads that started before the pursuit feature shipped now
show up correctly on the Downloads page after this update. Previously,
an in-flight grab created on an older version could remain invisible to
the pursuit-tracking UI — its timeline, alternative-release decisions,
and detail page were all gated on a pursuit row that didn't exist. This
release backfills a pursuit for every still-active grab during the
update, so the Downloads page sees them all the moment the app
restarts. Closed-out grabs (already grabbed, abandoned, or cancelled)
are intentionally left alone.

## v0.50.0 — 2026-05-08

### New

The Downloads page now shows a freshness pill next to the active-queue
header. Green "Live" with a quiet pulse means the queue you're seeing
is current. Amber "Updated Ns ago" means the data is starting to lag.
Red "Offline" / "Auth failed" with a Reconfigure link tells you the
connection broke — no more guessing why the numbers stopped moving.

### Improved

The Downloads page feels as live as qBittorrent's own web UI. Under
the hood, Media Centarr now talks to qBittorrent through its native
incremental sync API instead of refetching the full torrent list
every poll, matching the cadence the qBittorrent web UI uses (1.5 s
when you're watching the page).

### Fixed

When qBittorrent's stored credentials stop working — typically after
the user changes the qBittorrent password without updating Media
Centarr's settings — the system no longer hammers qBittorrent once
per 1.5 s with bad credentials. It backs off to one attempt every 30
seconds and surfaces the auth failure right on the Downloads page,
instead of silently leaving you with a stale-looking queue.

## v0.49.1 — 2026-05-08

### Fixed

Aired episodes now reach your downloads page on time. Previously, the
system could go more than a day without checking for episodes that had
just aired — every restart of the app reset its 24-hour timer, so a
recent update could push the next check almost a full day into the
future. The release-tracking system now sweeps every 15 minutes for
episodes whose air date has just passed, while the heavier metadata
refresh runs every 6 hours instead of 24. The schedule survives
restarts: when the app comes back up, it picks up where it left off
rather than starting the timer over.

The Downloads page no longer feels stale on first open. New
subscribers (you opening `/download`, the upcoming zone in the
Library) now receive the current queue immediately on connect,
instead of waiting up to 5 seconds for the next poll tick.

## v0.49.0 — 2026-05-08

### New

The TV series detail panel now shows upcoming episodes inline with
the season list. Open any tracked show and you'll see scheduled
episodes interleaved among the ones you already have on disk — each
upcoming row carries the air date, formatted as "in 7d" for the near
future, "aired 3d ago" for episodes that aired but haven't landed in
your library yet, or the bare month/day for further-out releases.

When TMDB knows about a future season that doesn't have any local
files yet, that whole season appears as its own collapsible block at
the bottom of the list, so you can see what's coming next even
before the first file arrives. Untracked shows render exactly as
before — no extra rows, no empty headers.

The upcoming rows are deliberately quiet: muted, no thumbnail, no
watched toggle. They're informational, not actionable.

## v0.48.0 — 2026-05-08

### Fixed

When you pick an alternative release on a stalled pursuit, the next
search now correctly skips releases you've already tried. Previously
the system could return to the same release the user had just
rejected, since the user's pick was recorded on the pursuit but never
reached the search worker. The pursuit aggregate is now the single
source of truth for tried releases, and the search worker reads from
it directly.

## v0.47.1 — 2026-05-08

### Improved

The pursuit timeline now tells the full story of a download. Earlier
versions showed the start ("Release picked") and the eventual outcome
("Stall confirmed", "Pursuit satisfied") but nothing in between. With
this release, every state change observed by the watcher — the torrent
arriving in the queue, transitioning from queued to downloading, going
slow, stalling out, recovering, completing — is recorded as its own
entry on the pursuit's timeline.

The practical effect: when a download is sitting at "grabbed" and you
open its detail page, you now see the actual status. A torrent stuck
fetching metadata reads as "Download started — queued" instead of
silence. A download that briefly stalled and recovered reads its
ups and downs in order. The timeline stays clean — heartbeat ticks
where nothing changed are not recorded, only real transitions.

## v0.47.0 — 2026-05-08

### New

Pursuits now react to download trouble on their own. When a
torrent stalls for a sustained window, the pursuit moves to
**needs your input** so you can pick an alternative release
without having to babysit the queue. When a torrent goes a
long stretch with no peers — the strongest "this release is
dead" signal we have — Media Centarr cancels it automatically
and the pursuit stays open for fallback.

Files that arrive on disk are now matched back to the pursuit
that asked for them. If the filename matches the release that
was grabbed, the pursuit closes successfully. If a misnamed
torrent slips through and the filename is wrong for what was
expected, the pursuit cancels itself with an identity mismatch
note, and the file is left in place for you to handle through
the existing review surface.

### Improved

Stall and zero-seeder detection windows are now configurable.
The defaults (a long stall window before asking you, a shorter
one before auto-cancelling clearly dead torrents) match what
felt right in testing, but the underlying values are
settings-backed so they can be tuned without a release.

## v0.46.0 — 2026-05-08

### New

Downloads now track each acquisition goal as a **pursuit** —
a single thread that follows the goal from search through
arrival, surviving cancellations and retries. The Downloads
page shows an **Active pursuits** section above the existing
activity list, and clicking **Open full →** on any pursuit
opens a detail page with the complete event timeline:
every search, release pick, decision, and outcome appears
as a labelled entry you can scan top to bottom.

A new detail page at `/download/<pursuit-id>` shows the full
state of one pursuit — origin, attempt count, criteria,
tried-releases count, and a vertical timeline of everything
that's happened. From this page you can cancel the pursuit
at any time.

### Improved

Cancelling a download and trying again no longer leaves two
unrelated rows in the activity list — the new pursuit is
recorded alongside the original attempts under one timeline,
so you can see the full history of what was tried in one
place.

Pursuits give up gracefully. After enough failed attempts
over enough time, a pursuit marks itself **exhausted** and
stops retrying — dead releases no longer churn in the
background forever.

## v0.45.3 — 2026-05-07

### Fixed

Updated the Bandit web server to 1.11.0 to pick up upstream
fixes for three memory-exhaustion vulnerabilities reachable
via crafted WebSocket / HTTP/2 traffic. No exploit was observed
against Media Centarr — the upgrade is precautionary.

## v0.45.2 — 2026-05-07

### Fixed

The Setup Tour pages now fill the full window. Previously, on
short pages like the Welcome step, the dark gradient backdrop
stopped partway down and revealed a flat strip below.

Setup Tour forms look right at a glance. The **Re-check** and
**Test connection** buttons used to render as bare text — now
they have a visible outline so they read as buttons. The text
inputs also size correctly next to their buttons, instead of
sitting noticeably taller and forcing the buttons to stretch.

## v0.45.1 — 2026-05-07

### Improved

Setup Tour forms are easier to read at a glance. The submit
button now reads **Save** when a field is empty and **Update**
when you're changing an existing value — no more wondering
whether your previous TMDB key is still in there. Every
**Test connection** button now sits inline with its Save button
instead of dangling on its own line below the form.

The TMDB step links you straight to themoviedb.org for signup
and to the API settings page for your token, and makes it
clear that TMDB API access is **free**. The mpv step's
**Re-check** button moves inline with Save so the layout stops
breaking awkwardly. The ffprobe step now spells out that
sidecar subtitle files (e.g. `movie.en.srt`) work without
ffprobe — only embedded tracks need it. The download client
step now shows a proper select box with qBittorrent as the
single supported option, instead of a confusing free-text
field.

## v0.45.0 — 2026-05-06

### Improved

The Setup Tour you saw in v0.44.0 is now a full eight-step
walkthrough. It opens with a Welcome page that introduces the
process and outlines what you're about to configure. Every step
in the middle now carries three short blocks: **What this is**
(what the dependency does), **Why it matters** (what breaks
without it), and **What you'll need** (a concrete bullet list of
prerequisites — install commands, URLs, credentials).

A prominent color-coded callout above each form makes the current
state impossible to miss — green "This step is configured", amber
"Partially configured", red "This step needs attention", or grey
"Not yet configured". The compact pill in the header stays for
at-a-glance scanning.

The tour now ends with a **Summary** screen listing every
component with a status glyph (✓ / ! / ✗ / —), a *Required* badge
on the components the app can't function without, and an Edit
link that jumps you straight back to any step that needs more
work. Required-step counts in the headline copy adapt to your
actual progress.

### Fixed

If you finished or skipped the Setup Tour with critical pieces
still broken (no TMDB key, no watch directories), Settings →
Overview now shows a dismissible red banner so the situation
doesn't quietly persist.

## v0.44.0 — 2026-05-06

### New

Media Centarr now opens with a guided **Setup Tour** the first time
you launch after upgrading. It walks you through configuring
everything the app needs — your watch directories, TMDB API key,
mpv, ffprobe, Prowlarr, and your download client. Each step shows
what's currently configured, auto-detects binaries on common
Linux/macOS paths (`/usr/bin`, `/usr/local/bin`, `/opt/homebrew/bin`,
`/snap/bin`, `~/.local/bin`), and lets you skip any step you'd
rather come back to later.

Once you finish or skip the tour, it stays out of the way — but you
can re-run it anytime from **Settings → Overview → Run setup tour**.

The tour also surfaces a previously-hidden setting: **the path to
your `ffprobe` binary**. Earlier releases shelled out to bare
`ffprobe` from `$PATH`; if it wasn't there, embedded-subtitle
detection silently fell back to sidecar-only without telling you
why. You can now point Media Centarr explicitly at
`/usr/local/bin/ffprobe` (or wherever yours lives) — from the tour
or under **Settings → Playback**.

## v0.43.0 — 2026-05-06

### New

The movie detail panel now shows what subtitles are actually available
on the file, so you can decide whether to play it without launching mpv
first. Two sources are detected:

- **Embedded tracks** in the video container (MKV/MP4) — read from the
  file's stream metadata via `ffprobe`. Each track's language is shown
  as its ISO code (`en`, `es`, `fr`, …).
- **Sidecar files** in the same directory — `Movie.en.srt`,
  `Movie.spa.srt`, etc. Languages are inferred from the filename
  suffix; sidecars without a recognisable language code surface as
  `external` so you know they're there but not what they are.

If `ffprobe` isn't installed, the feature gracefully degrades to
sidecar-only detection — nothing crashes, nothing complains beyond a
single boot-time log line.

A new **Refresh movie subtitles** button in Settings → Library
backfills tracks for movies imported before this release. Safe to
re-run; it skips files that already have detected tracks.

TV series are out of scope for this release — per-episode aggregation
needs a different display story and will land separately.

## v0.42.2 — 2026-05-05

### Fixed

Modal dialogs (the update-progress modal, service-action confirmations,
the watch-history delete prompt, the upcoming "track new show" picker,
and others) no longer leave a thin un-dimmed strip at the bottom of the
page. The backdrop now covers the full viewport.

Canceling a download from the Downloads page no longer appears to
remove a different download from the list. The queue now matches each
row by identity instead of position, so cancellations update the
correct entry without needing a page reload.

### Improved

The cast filter on a TV show's **More info** panel is narrower and now
clearly reads as a search input — it has a leading magnifying-glass
icon and a subtle field background, instead of spanning the full panel
width.

## v0.42.1 — 2026-05-05

### Improved

The TV credits panel no longer falls over on long-running shows. Series
like *The Simpsons* return hundreds of cast members from TMDB across
their full run, which made the **More info** panel scroll forever. The
grid is now capped at 24 cards (the show's regulars + main recurring
cast, by TMDB billing order) and surfaces an inline filter input above
the grid whenever the underlying cast exceeds that count. Type to
filter the visible 24 in real time — the visible count stays capped
even as you narrow, so the panel never blooms.

Cast under 24 entries (movies, short-run series) is unchanged — no
filter input, all entries visible.

## v0.42.0 — 2026-05-05

### New

TV series detail panels now have a **More info** button between Play
and Manage that opens a credits view, mirroring the one movies got in
v0.40.0. The series credits view shows **Created by** at the top
(creators pulled from TMDB), an aggregate cast grid covering the
whole show (not per-season), and a meta block with network, first
aired, status, country and language. Names link to TMDB person pages,
and the panel ends with external links to TMDB and IMDb when known.

### Improved

Settings → Library Maintenance has a new **Refresh series credits**
button next to the existing Refresh movie credits one. One click
backfills creators, aggregate cast, and IMDb ids for any TV series
imported before those fields existed. Safe to re-run; series that
already have credits are skipped.

## v0.41.0 — 2026-05-05

### Fixed

Your library is now safe when a drive stays unmounted. Previously, if
a watched drive was offline for more than 30 days, the cleanup pass
would treat every file on it as "missing too long" and silently delete
the corresponding entries — including entire shows and movies whose
files all lived on that drive. The cleanup now refuses to remove
anything until the drive is back online and confirmed visible. When a
drive does come back, every absent file gets a fresh 30-day grace
window starting from the moment the drive reappears, giving you time
to verify state on a now-visible disk.

The Status page's storage section now surfaces drives that are
offline with files at risk: file count, drive name, and projected
purge date. If a drive disappears unexpectedly, you see it before the
clock runs out.

### Improved

Hero artwork and continue-watching thumbnails on the Home page now
repopulate as soon as a drive comes back online. Previously only the
small "Recently Added" posters refreshed after a remount; the larger
hero and continue-watching tiles kept showing stale placeholder art
until the page was reloaded by hand.

## v0.40.2 — 2026-05-04

### Improved

Buttons across the app now read clearly. The soft-tinted variants
(secondary blue, action green, info cyan, risky amber, danger red)
previously used a same-colour label on a same-colour tinted
background, which made them hard to read. Labels now use the theme's
default foreground colour so the tint still signals intent without
sacrificing legibility.

## v0.40.1 — 2026-05-04

### Fixed

The new **More info** button on movie detail panels did nothing when
clicked. The credits view never opened because the modal URL was
silently dropping the new view state. Now it works as intended.

## v0.40.0 — 2026-05-04

### New

Movie detail panels now have a **More info** button between Play and
Manage that opens a credits view with the director, writers, and full
cast laid out as a grid (no more horizontal scroll). Names link to
their TMDB person pages where available, and the panel ends with
external links to TMDB and IMDb (when known).

### Improved

The Settings → Danger Zone refresh button is now **Refresh movie
credits** — one click backfills cast, crew (director, writers,
composer, etc.), and IMDb ids together for any movies imported before
those fields existed. Safe to re-run; movies that already have
credits are skipped.

## v0.39.1 — 2026-05-04

### Improved

Finished the v0.39.0 TMDB-id migration: the redundant rows in the
internal external-id table that had been left behind for safety
during the transition are now removed automatically when you
upgrade. No user action required.

## v0.39.0 — 2026-05-04

### Fixed

The cast strip on a standalone movie's detail panel was always
empty, even after running **Refresh movie cast**. The internal
cause was that standalone movies didn't carry their TMDB id on the
movie record itself — so the backfill job had nothing to look up.
Existing libraries are migrated automatically: every movie, TV
series, movie series, and video object now records its TMDB id
directly. Re-run **Settings → Danger Zone → Refresh movie cast**
to populate cast for any standalone movie that's still empty.

## v0.38.1 — 2026-05-04

### Fixed

The cast strip introduced in v0.38.0 didn't actually appear on movie
detail pages. The cast data was correctly fetched from TMDB and
stored in the database, but a normalisation step in the library
loader silently dropped the field on the way to the UI. Cast now
shows up as intended after running **Refresh movie cast** in
Settings.

## v0.38.0 — 2026-05-04

### New

The movie detail panel now shows a **Cast** strip at the bottom — a
horizontally scrollable row of poster-style cards, one per actor.
Each card carries the actor's photo, their name, and the character
they played. Click any card to open the actor's TMDB page in a new
tab. Cast members without a profile photo on TMDB get a silhouette
icon so the layout stays steady.

### Improved

Settings → Library Maintenance now has a **Refresh movie cast**
button. Use it once to backfill cast data for movies that were
imported before this release; new movies pick up cast automatically
on import. The action is safe to re-run — it skips movies that
already have cast.

## v0.37.5 — 2026-05-04

### Improved

The Manage view's delete confirmations are now *inline* — no more
modal-on-modal. Click the prominent danger button once and it flips
to "Click again to confirm — Delete all files (size)" with a Cancel
link beside it; click it again to commit. Per-folder and per-file
delete buttons follow the same pattern (text changes to "Click again
to confirm" / "Click to confirm", with the file row picking up a
tinted background to mark which row is armed). This matches how
Rematch already worked in the same view, and removes the secondary
overlay that was making the modal feel cluttered. Switching to a
different delete button re-targets the pending confirmation; only
one is armed at a time.

## v0.37.4 — 2026-05-04

### Improved

The Manage view now leads with a prominent "Delete all files" danger
button (or "Delete this file" when there's only one) showing the total
size up front, so wiping a title from disk no longer requires hunting
for a hidden affordance. Per-folder and per-file delete buttons are
also always visible now instead of appearing only on hover — useful
for movie collections that sit loose at the root, and for trimming a
single stray file out of a TV series folder. The single watch root
itself never gets a delete button (deleting the watch dir would be
catastrophic), but everything inside it does.

## v0.37.3 — 2026-05-04

### Improved

The "More info" toggle inside the detail modal is now called "Manage"
with a cog icon — because the entry's main view already shows the
synopsis, genres, director, rating, and runtime, the secondary view is
really for managing what's behind it: files, identifiers, and
rematching. Inside, the redundant Metadata block (which just repeated
the hero row) is gone. External IDs collapse to one tight row per
source instead of duplicating the TMDB url and id on separate lines,
with the entity UUID demoted to a quiet footer chip — still copyable
for support, no longer competing with real metadata.

Each media file in the Manage view now also shows the technical badges
parsed from its filename — 4K, HDR, WEB, H265 and so on — plus an
"added on" date so you can see at a glance what kind of release each
file is and when it landed in your library. HDR rides a blue chip; the
rest are quiet ghost badges so the row stays scannable.

## v0.37.2 — 2026-05-04

### Improved

When the metadata sidebar of the detail panel has an odd number of
facets, the trailing one (typically Genres) now spans both columns
instead of squeezing into a single column with dead space beside it.
For movies showing only Director, Rating, and Genres, that means
Genres lays out on a single line where it used to wrap.

## v0.37.1 — 2026-05-04

### Improved

The detail panel reads more naturally now. Rating sits next to Director
on the metadata sidebar instead of dropping to its own row, so the
two most-asked-for fields share a line and the eye doesn't have to
zig-zag. The full file path no longer takes up space on the main
detail view either — it lived inside a labelled box that competed for
attention with synopsis and metadata. File details (paths, sizes,
delete affordances) are still one click away in the "More info" view,
which is where the rest of the per-file controls already live.

## v0.37.0 — 2026-05-04

### Fixed

Cancelling a download on the Downloads page now actually removes the
row and keeps it gone. Previously the row would vanish for a moment and
then reappear when the download client's next status snapshot arrived —
because the cancellation hadn't fully propagated client-side yet, so the
snapshot still listed the torrent. The page now remembers your in-flight
cancels and filters those rows out of incoming snapshots for a short
grace window, while also asking the queue monitor to refresh
immediately. If the cancel actually fails, the row reappears after the
grace window so you can see something went wrong instead of staring at
a silent empty list.

## v0.36.1 — 2026-05-03

### Fixed

Auto-grab now verifies that each search result actually matches the
show or movie you're tracking. Previously, tracking an item with a
short or common name (e.g. "Sample Show Fifteen") could trigger downloads of
unrelated releases — other shows whose name contained the word, or
even episodes of completely different shows whose episode title
happened to be "Sample Show Fifteen". The system trusted the indexer's relevance
ranking and accepted any acceptable-quality result; now it rejects
results that don't parse to the requested title and season/episode (or
movie + year) and keeps searching for a real match.

## v0.36.0 — 2026-05-03

### New

The Downloads page now flags downloads that are stuck or making little
progress, even when your download client still thinks they're
downloading. A torrent that's been crawling along at a few KB/s for an
hour, or hasn't moved at all in 10 minutes, gets a clear secondary
label below the title — "Less than 100 MB in past hour", "No progress
in 10 minutes", "Fetching metadata for over 5 min — magnet may be
dead", or "Queued for over 30 minutes". Stuck downloads also bubble to
the top of the list so they're immediately visible.

Upcoming cards across the rest of the app pick up the same signal
quietly: a download that's stuck shows its arrow icon in warning
yellow with a "Stuck" tooltip instead of the usual blue, so you can
spot a problem without having to open the Downloads page.

## v0.35.0 — 2026-05-03

### Improved

The detail panel — the modal that opens when you click a card — now
reflows on wide displays. On 4K and other high-resolution monitors,
the synopsis sits on the left at a comfortable reading width, while
director, genres, rating, network, and similar metadata stack into a
compact 2-column grid on the right instead of running edge to edge in
a long, hard-to-track line. On standard-width displays the layout is
unchanged.

## v0.34.1 — 2026-05-03

### Improved

The home page hero now rotates every 7 hours instead of once a day, so
the featured title at the top of Home changes more often. The 7-hour
interval is chosen so that even if you only open the app at a
consistent time each evening, you'll still cycle through your full pool
of eligible heroes over a few days rather than landing on the same one
repeatedly.

## v0.34.0 — 2026-05-03

### New

Settings → Services has a new **Auto-grab** toggle, alongside the
existing Watchers, Pipeline, and Image Pipeline switches. When off,
the system stops searching for tracked episodes as they air, and any
snoozed searches pause until you turn it back on. Manual grabs from
the Downloads search box keep working regardless. Useful if you run a
second instance for testing or want to take auto-grab quiet without
clearing your tracked items. Defaults to on.

## v0.33.1 — 2026-05-03

### Fixed

TV episodes auto-armed from the Upcoming tracker sometimes sat in the
Downloads list forever, showing "Attempts: 0" and "Last attempt: never"
even when the system was busy retrying behind the scenes. Searches for
those episodes now run as expected. Existing stuck rows heal
automatically the first time you launch this version — affected
downloads will start showing real attempt activity within minutes.

## v0.33.0 — 2026-05-03

Version-marker release. No code or user-visible changes since v0.32.4
— the minor bump tags the close of the multi-week component-contract
migration (see the v0.32.1 → v0.32.4 entries) as a single milestone.

## v0.32.4 — 2026-05-03

Maintenance release. No user-visible changes — closes the internal
component-contract migration: every Phoenix function-component
attribute in the app now carries a typed module or a documented
waiver, and a Credo check (`TypedComponentAttrs`) is now active to
prevent regression. Future contributors who add a `attr :foo, :map`
without explaining what it accepts will get a build-time nudge to
either tighten the type or document why it's loose.

## v0.32.3 — 2026-05-03

Maintenance release. No user-visible changes — Phase 5 of the internal
component-contract migration: the entity detail panel (the modal that
opens when you click a card) and the modal shell that wraps it now
document every attribute they accept and tighten the season-expansion
state to a typed `MapSet`. No behaviour changes; the contracts make
future regressions in the detail UI easier to catch in tests.

## v0.32.2 — 2026-05-03

Maintenance release. No user-visible changes — Phase 3 of the internal
component-contract migration: the Library poster cards/toolbar and the
entire Upcoming releases zone (calendar, day detail, active shows,
tracked items, episode rows) now declare prose contracts on every
loose attribute and a typed struct for the "currently tracking" row,
so future regressions that omit a required field surface in tests
instead of in your browser.

## v0.32.1 — 2026-05-03

Maintenance release. No user-visible changes — Phase 4 of the internal
component-contract migration: the Track New Releases modal, the
Downloads Activity table, and the diagnostic Console drawer now pass
typed structs and documented contracts to their components instead of
plain maps, so a future regression that omits a required field crashes
at the data layer (where it's catchable in tests) instead of silently
rendering broken UI.

## v0.32.0 — 2026-05-03

### Improved

- **Movies that belong to a TMDB collection now appear as the movie itself
  in your Library and on Home — not wrapped in a collection container —
  when you only own one movie from that collection.** Adding a single
  film from a multi-film franchise (for example, one *Super Mario* movie
  out of a TMDB-listed *Sample Mascot Collection*) used to surface as a
  one-item "collection" tile, which forced an extra click and didn't
  match the mental model. Single-movie cases now show as a regular
  movie tile across the Library, Home → Recently added, Home → Continue
  watching, and the Home hero. If you later add a second movie from the
  same collection, the two group back together as a multi-movie
  collection.

- **Continue watching now reflects what you're actually watching, even
  when a file is temporarily unavailable.** If you unmount a drive or
  move a file mid-session, the show or movie stays in your Continue
  watching list — your progress isn't erased by a transient file
  change. Movies, episodes, and standalone videos all behave the same
  way on this surface.

### Fixed

- **Clicking a single-movie collection tile now opens the movie's detail,
  not a collection wrapper.** Previously, even when the Library tile
  visually represented "the movie," clicking it opened the collection
  page (which contained one item). The tile and detail now agree on
  what's behind it.

## v0.31.1 — 2026-05-03

### Fixed

- **The detail modal on the Home page now stays in sync with playback.**
  If you opened a show or movie's detail card from the Home page, watched
  it, and closed the player, the modal still showed the pre-watch state —
  no updated play position, no "watched" indication, no "Watch again"
  button. Closing and reopening the modal worked around it. The modal
  now refreshes from playback events the same way it always did on the
  Library page.

## v0.31.0 — 2026-05-03

### Improved

- **Show titles on the Upcoming page now use the official logo where
  available.** Previously, only shows whose logo had already been
  fetched for the main Library card showed it on Upcoming — anything
  else fell back to plain typography, leading to a mixed look. The
  logo is now fetched and stored alongside the rest of the metadata
  when a tracked show or movie refreshes, so the visual treatment is
  consistent across pages.

### Fixed

- **"Queue all" on the Upcoming page now re-arms grabs that were
  previously cancelled or marked as failed.** Before, any release that
  had a terminal grab on record was silently treated as "already in
  progress," so a cancelled or abandoned download couldn't be retried
  from the Queue All button — the toast claimed success while nothing
  actually happened. The action now distinguishes between in-flight
  searches, completed grabs, and terminal states, re-queues the
  terminal ones, and reports an accurate summary (e.g. "Queued 2,
  re-armed 1, 3 already grabbed").

## v0.30.3 — 2026-05-02

Maintenance release. No user-visible changes — closes out the internal
component catalog (Phoenix Storybook) initiative: every component is
now either covered, deliberately skipped with a reason, or has a
static-example placeholder. Three rendering bugs surfaced during the
final review were fixed (a crashing list variation, a collapsed
poster-row layout in the catalog sandbox, and a modal that escaped
its preview block). The completed roadmap and design doc were
removed.

## v0.30.2 — 2026-05-02

Maintenance release. No user-visible changes — Phase 5 of the internal
component catalog (Phoenix Storybook) added stories for the library
poster card, toolbar, the home-page poster row, the upcoming-releases
zone, and the entity detail panel. Each story documents the
contract observations a future typed-attr migration will act on.

## v0.30.1 — 2026-05-02

Maintenance release. No user-visible changes — internal developer
catalog (Phoenix Storybook) was expanded with foundation pages,
deepened component stories, and a Credo check that prevents coverage
drift. A production build issue introduced by the catalog work was
fixed so future releases continue to ship cleanly.

## v0.30.0 — 2026-05-02

### Improved

- **Editing the image directory for a watched library now takes effect
  immediately.** When a watch entry's image directory lives on a
  separate drive, Media Centarr runs a small health monitor that
  watches that mount. Previously the monitor was started once at boot
  and would keep watching the old path until the next app restart if
  you edited it from Settings. Changing the image directory is now
  reconciled live alongside the watch directory itself — start a new
  monitor for the new path, stop the one for the old.

### Fixed

- **Library lookups by nil identifiers no longer match the wrong row.**
  Several internal helpers that look up entities by key didn't guard
  against a `nil` key, which can happen when a record's optional FK is
  unset. The default Ecto behaviour for that case treats `nil` as a
  match against any nullable column, which could quietly load an
  unrelated record. The helpers now refuse `nil` keys and return
  not-found, eliminating a class of silent corruption that mostly
  hadn't been observed but could surface during cleanup cascades or
  bulk operations.

## v0.29.2 — 2026-05-01

### Fixed

- **Drives mounted after Media Centarr starts are now picked up
  automatically.** If your media drive came online after Media Centarr
  had already booted — typical after a reboot, where the app starts
  before an external or network drive finishes mounting — the
  watcher would attach to the empty mountpoint and never notice when
  the real filesystem appeared on top of it. The library would stay
  in placeholder mode until you restarted the app or hit "Scan
  directories" by hand. The watcher now detects when the filesystem
  under a watched directory has changed and re-attaches on its own,
  which also re-resolves artwork for every entity on the drive.

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
