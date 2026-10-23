---
status: in-progress
started: 2026-10-22
last_updated: 2026-10-23
---
# Remote players

## Goal

Make the Media Centaur UI and video playback available on a Google TV on
the same network as the host, with the fidelity the host has today: any
file in the library direct-plays, progress, completion, auto-advance and
the finish prompt all work, and the active profile is chosen on the TV.
This is the first feature of the roadmap's third era (streaming to the
user's other devices) and it sets the shape every later player follows:
the host's mpv becomes one player among several.

## Glossary

Defined before use; refine as the campaign proceeds, elevate to
`docs/GLOSSARY.md` at completion.

| Term | Meaning |
|---|---|
| **Player** | A machine that renders a viewing. Two kinds now: the **host player** (mpv spawned on the computer running the app, "this computer") and a **remote player** (the paired TV app). |
| **Pairing** | How a remote player joins the install: Settings → Players shows a one-time code (six digits, five minutes, five misses), the device offers the code with its name on the pairing page, and its browser session then holds the new player's id (`"player_id"`, beside ADR-078's `"profile_id"`). There is no separate token (ADR-079). |
| **Player channel** | The remote player's WebSocket to the host, carrying mpv IPC JSON in both directions. The remote equivalent of the Unix domain socket. |
| **Transport** | How a playback session reaches an mpv and how that mpv gets its file: Unix socket to a spawned process with a host path, or the player channel with a media URL. The one thing that varies per player kind. |
| **Playback session** | `Playback.MpvSession`: one profile watching one title chain on one player. Not the **browser session**, the signed cookie that holds the active profile (ADR-078). |
| **Media endpoint** | The HTTP route that serves a playable file by identity with Range support, admitted by the gate like every other request. |
| **TV app** | The Android TV application: a WebView shell showing the host's UI plus embedded libmpv bridged to the player channel. |
| **The gate** | One policy, `MediaCentaurWeb.RemoteAccess.admit/2` — loopback is the host player, any other address is admitted only as the paired player its session names — with two enforcement points: `Plugs.RemoteAccess` for HTTP (an unpaired `GET` goes to the pairing page, anything else is refused) and `Live.PlayerAware` for the LiveView socket. |

## Status

**Resumed 2026-10-23 (afternoon) after the context clear: reconciled,
nothing drifted; M7 opened at step 1 (scope recorded below) and its one
owner-free item done — the glossary elevated to `docs/GLOSSARY.md`.
M6's remainder and M7's calls are the owner's.** The earlier state:

**M6 nearly done: four batches built and verified on the Sony
2026-10-23; what is left is the owner's** (branch `remote-players`;
`android-app` rebuilt and installed with the audio buffer; UIDR-055).
Verified on the TV with zero dropped frames: the viewing's keys as
Controls bindings and a rebind on the TV's own Settings page; a removed
player's channel closed at once; a seek that never crosses the end;
sidecar subtitles over the media endpoint; a dropped channel reattaching
in a second; a host restart with the stream reconnecting and the viewing
recovered still playing; a clean audio start; the pair page's Code field
drawn and the page full height; the finish prompt after a 42-minute
file. The TV found faults fixed the same day: the sidecar URL's
percent-encoded name, the `file-loaded`/`path` order, the Controls page
one change behind (a desktop fault too), the stream ending early on a
host restart, the Code field's missing box, the page's 70% height, the
start-up underrun. Left for the owner: Back-key and D-pad polish
(nothing specific recorded — the owner's walk names it), and the earlier
calls: the Sound column's owner (9), the speed test (3), the application
id (1). Then M7. M5's OSD
check passed on the Sony 2026-10-22 (`mc-tv-flow osd tv`, record below): the layer
over native 4K video, the Skip Intro pill taken by SELECT, SELECT
pausing and resuming, arrows seeking, the track menu on MENU opening on
Subtitles, a subtitle picked and streaming, BACK closing the menu and
then stopping the viewing, the countdown pill, auto-advance to E02, the
finish prompt at the lab film's end — with zero dropped frames on both
episodes and the page patching once a second during a viewing, not at
all while idle. Five faults found and fixed on the way (the record lists
them). Open for the owner: decision 8 (which remote key opens the track
menu — MENU works when the remote has one). Owner's calls recorded
2026-10-22: direction 3, keys to the page, passthrough declined (stereo on
optical), no 4K UI (a slightly smaller TV UI scale wanted instead, M6).

## Design (unify pass, 2026-10-22)

**Core idea: the TV is mpv on another machine.** The TV app embeds
libmpv, and libmpv exposes the same property and command model that
mpv's JSON IPC already serialises. So the TV app speaks the *existing*
IPC protocol to the host over a WebSocket instead of a Unix socket.
`MpvSession` keeps its name and its observation logic, auto-advance
(ADR-062), track enforcement, completion and recovery semantics. The
only thing that varies per player is the transport. The bundled Lua
scripts (ADR-072) ride along if the libmpv build carries Lua.

One sentence: *a playback session is one profile watching one title on
one player, and the app observes it over mpv IPC whichever machine runs
the mpv.*

**Every browser session plays on the player it is on.** The TV app's
WebView session holds its player, so Play there starts a session on that
TV; a loopback browser plays on the host. No player picker in this
campaign. Casting from the host browser to a TV is a later feature with
its own picker. Per-device state stays browser-session state, per the
roadmap rule and ADR-078.

**A new context, `MediaCentaur.Players`**, owns the paired players and
their tokens: no deps, its own topic, modelled on `Profiles`. Playback
takes a player as a parameter and never depends on Players, the same way
it takes a profile id.

**Content for a remote player is a URL** served by the media endpoint;
the URL encodes the playable file's identity, not a host path.

**Rejected alternatives**, so they are not re-litigated: a sideloaded
browser on the TV (owner declined); browser HTML5 playback with ffmpeg
remux/transcode on the host (a media-server rebuild, loses fidelity);
a Chromecast Web Receiver (must be served over HTTPS from a trusted
certificate and then cannot reach a plain-HTTP LAN host; also makes the
TV a dumb screen driven from a phone).

### Incoherences found and their dispositions

1. **Transport is interleaved with observation in `MpvSession`** (Port
   spawn, socket retry, log file, `MpvExitClassifier`, `DisplayEnv`
   beside the IPC handlers). Fix in M2: lift the host transport behind
   one small interface. Not speculative: the second transport lands in
   M3.
2. **`content_url` is the file's identity.** `advance_to/2` compares
   mpv's reported `path` with the host path; a remote mpv reports the
   URL. Fix in M2: the transport maps a reported path back to the
   playable file and the session compares identities.
3. **`LaunchFlags` renders command-line strings.** libmpv takes the same
   options as structured pairs. Fix in M2: build option pairs, render
   CLI for the host and JSON for the player. One representation.
4. **`SessionRegistry` is keyed by entity id alone**, so "already
   playing" is install-wide; wrong with two players. Fix in M3: key by
   player and entity.
5. **`Playback.Events` name a profile but not a player.** Fix in M3,
   with item 4: every event about a viewing names its player, so the UI
   can say where it is playing.
6. **`SessionRecovery` scans a socket directory**, which is host
   recovery only. A remote player recovers by reconnecting its channel
   and the session reattaching; both are "a transport re-offers a live
   mpv". Fix in M3: recovery becomes per-transport, entity and profile
   resolution stays shared.
7. **No access layer exists**; the endpoint binds loopback with no
   authentication. Fix in M1: the bind address becomes a bootstrap TOML
   key defaulting to loopback, and the gate admits a
   non-loopback request only as the paired player its session holds.

### Seams that already fit

Typed `Playback.Events` structs (MC0012); `Resolver.play_params`; the
pure `WatchingTracker`, `Completion`, `NextEpisode`; the `ProfileAware`
on_mount pattern (for a `PlayerAware` sibling); the `ImageServer` plug
pattern (for the media endpoint); the bootstrap TOML tier in
`Settings.Config` (for the bind address); Boundary.

## Decisions made

* `2026-10-22` — The TV runs a native Android TV app, not a browser; the owner declined a sideloaded browser. (conversation)
* `2026-10-22` — The TV app embeds libmpv and speaks mpv's IPC protocol to the host over a WebSocket; `MpvSession` is the one session type for every player. (conversation; unify pass above)
* `2026-10-22` — The thing a viewing shows on is called a **player**. (conversation)
* `2026-10-22` — Each browser session plays on the player it is on; no picker, no casting, in this campaign. (conversation)
* `2026-10-22` — Distribution through Google Play's internal testing track, so installing on the TV is a Play Store install with no public listing. (conversation)
* `2026-10-22` — The TV app lives in a sibling repository, `~/src/media-centaur/android-app`: its own toolchain, signing and release cadence; the name holds if a phone launcher is ever added to the same Android project. (owner)
* `2026-10-22` — The bind address is a bootstrap TOML key, `bind`, default `127.0.0.1`, shown commented in `defaults/media-centaur.toml`; the endpoint listens before the database is reachable. (owner)
* `2026-10-22` — The media endpoint names a file by its `FilePresence` id (`/media/<id>`), the one row every playable file (`WatchedFile` or `ExtraFile`) references; the transport maps a reported URL back to the path through the same id. Rejected: `PlayableItem` id (progress identity, may own several files) and a signed token over the host path (a second identity for one idea). A presence row's id changes if the file leaves and returns, harmless for a URL that lives one session. (owner)
* `2026-10-22` — The whole campaign is built on branch `remote-players`, skeleton first: a full end-to-end slice (host transport, channel, media endpoint, TV app) before any hardening, then iteration; boundaries and transport are engineered as a real network interaction with high requirements. (owner)
* `2026-10-22` — The player channel is a raw WebSocket (`WebSockAdapter` on Bandit) carrying one mpv IPC JSON object per text frame, server pings for liveness, no compression, 1 MiB frame cap; not a Phoenix Channel, whose join/topic/heartbeat layer would wrap a protocol that already has framing and correlation. (spec)
* `2026-10-22` — A remote player runs one libmpv instance for the app's life, so it holds at most one viewing at a time; a second `play` on the same player replaces the first. `quit` on a remote player means stop and show the UI, not exit. (spec)
* `2026-10-22` — Media requests carry a capability token: the host signs `{player_id, presence_id}` (`Phoenix.Token`, 12 h) into each media URL it composes, and the gate admits `/media/*` by that token alone. Rejected: the session cookie in libmpv's HTTP headers (the device's whole identity on every byte-range request). (owner)
* `2026-10-22` — One branch, `remote-players`, for the whole campaign; nothing merges to main until the owner signs off at the campaign's end. The branch is not pushed. Main's M1 status in the index is therefore "built on the branch", not shipped. (owner)
* `2026-10-22` — The TV app ships `priv/mpv/scripts/media-centaur` in its assets and points libmpv at it; verified that the `dev.jdtech.mpv:libmpv` 1.0.0 artifact builds mpv 0.41 with Lua enabled. (spec, verified)
* `2026-10-22` — The Android toolchain is owned by the app repository's `mise.toml` (Temurin 21, `ANDROID_HOME=~/Android/Sdk`, SDK tools on `PATH`); `mc-tv` runs every tool through `mise -C <repo> exec`; nothing goes in a shell profile. SDK licences accepted on the owner's behalf. (M3 record; agent, owner absent)
* `2026-10-22` — The TV app targets compileSdk and targetSdk 36 on AGP 9.4.0 with built-in Kotlin, Gradle 9.6.0, minSdk 26. (M3 research)
* `2026-10-22` — The owner's TV is a Sony Bravia XR-42A90K at `192.168.68.63`: Android 12 (API 31), 32-bit only (`armeabi-v7a`), adb over the network on 5555 once ADB debugging is on. (M3 hardware checks)
* `2026-10-22` — The bridge's `set_property` keeps the JSON value's type (boolean, integer, double, string), as mpv's own JSON IPC does; a boolean sent as the string `"false"` is rejected by libmpv with error -4, which had left every viewing on the TV paused. (`android-app` `e46cd1b`)
* `2026-10-22` — Throughput needs no design work on this TV: measured 210–220 Mbit/s through the media endpoint over WiFi against a 95 Mbit/s ceiling in the owner's library; no transcode or remux path is opened. The speed test (open decision 3) remains a product question, not a rescue. (M5 measurement)
* `2026-10-22` — Full fidelity is the target of this software; the TV never drops picture quality to gain a feature. (owner)
* `2026-10-22` — The TV renders video on the native path (`vo=mediacodec_embed`: the decoder writes to the surface, the panel gets native resolution and HDR10); mpv draws nothing on the TV. PGS (bitmap) subtitles are unsupported on the TV rather than served through the GPU path at 1080p SDR. (owner; evidence in `android-app` `docs/playback-on-android.md`)
* `2026-10-22` — The host's page is the TV's OSD: it stays over the video, transparent, and the host renders the pills, track menu, finish prompt and text subtitles into it; the bundled Lua scripts stay the desktop mpv's. Verified on the panel that a transparent page over the native HDR video shows the video, both layers hardware-composited. (owner: "probably makes sense"; agent recommendation; `android-app` `c1ad83f` and after)
* `2026-10-22` — A viewing on a remote player carries its session options as per-file options on the `loadfile` (`replace` and the auto-advance `append` alike); nothing is set on the player's long-lived instance, so each viewing starts from the host's option set and mpv restores the instance at the file's end. Verified on desktop mpv 0.41 (M5 research R1). (open decision 5 → decided)
* `2026-10-22` — The viewing layer (the page as the TV's OSD) changes at most once a second and animates nothing continuously: on the Sony a 60 fps page animation over native 4K video ran at 26 % janky frames and doubled the app's CPU, while a 1 Hz bar and subtitle line cost nothing measurable (M5 research R6).
* `2026-10-22` — Audio passthrough is not offered: the owner's speakers are stereo on the TV's optical output with no surround decoder, so a bitstream would reach something that cannot decode it; the TV decodes every track itself and sends PCM, which is full fidelity for that chain. Revisit only if a decoder joins the setup. (owner; open decision 7 → declined)
* `2026-10-22` — The viewing layer's look is mockup direction 3, *scrim and seek bar*: a bottom gradient scrim, the title and episode line over a full-width seek bar with a handle and chapter ticks, the clock at both ends, a centre pause glyph for a moment, prompts at the top right, the track menu a centred two-column glass modal over a dimmed picture (`docs/superpowers/specs/2026-10-22-tv-viewing-layer-mockups/3-scrim-and-seek-bar`). (owner)
* `2026-10-22` — During a viewing every remote key goes to the page; the viewing layer's behaviour turns it into a playback command the host sends down the channel; `input.conf`, `RemoteKeys` and `keypress` leave the TV app. (owner, on the recommendation; open decision 6 → decided)
* `2026-10-22` — A debug build of the TV app bypasses the WebView's cache (`LOAD_NO_CACHE`): against a dev host the page script has no digest in its path and a rebuilt script never landed; a release host serves digested assets. (stage 4 finding)
* `2026-10-22` — A new viewing on a remote player replaces the one running (`Sessions.play/2` stops any other session on that player first): one libmpv, one viewing; two sessions on one channel observed each other's file. (stage 4 finding)
* `2026-10-22` — The remote transport drops an `end-file` that precedes its own file's `start-file`: a `loadfile … replace` on an mpv still holding a file ends that file first, and the bridge cannot know the reason. (stage 4 finding)
* `2026-10-22` — The page's input orchestrator re-detects its behaviour on every key: the viewing layer arrives by a server push, and a key after it must find the viewing behaviour whether or not a patch callback ran. The viewing keys (media keys, `ContextMenu`) live in a fallback map after the user's bindings, like the zone keys. (stage 4 finding)
* `2026-10-22` — A key the TV shell forwards to the page (Back as Escape, Menu as ContextMenu) is dispatched on the focused element, or `<body>`, never on the document: the page's keyboard source reads the event's target as an element, as every real key press has. (`android-app` `3df9251`)
* `2026-10-22` — An open overlay keeps the page's cursor: the cursor start never seeds the page beneath, a flat overlay whose one item arrives later (the OSD's prompt pill) gets it from the post-patch reconciler, and a named overlay's flat context is re-resolved until a region has items — one rule in `_ensureCursorStart`, replacing the branch in `_syncState`. (stage 4 finding)
* `2026-10-22` — The input system knows the active overlay by its navigation model name: a different name while the presentation stays "modal" is an overlay opening over, or closing back to, another, and is entered like any open. The track menu is nested in the OSD's overlay (`data-detail-nested`), so BACK closes the menu alone and the next BACK dismisses the OSD. (stage 4 finding)
* `2026-10-22` — The viewing's keys are Controls bindings (category *During playback on a TV*: play/pause, seek forward, seek back, audio & subtitles; defaults the remote's media keys and ContextMenu, no gamepad defaults), bound on the TV's own Settings page; the two fallback key maps behind the user's are gone, and a Play/Pause key outside a viewing is Play. Closes open decision 8: which key opens the track menu is the user's binding. (M6, the owner's question)
* `2026-10-23` — The TV's UI scale: a per-player scale factor (option (a) of open decision 10 — the Preferences stepper on a paired device writes the player's own factor, applied by the root layout for that device; the 0.7 auto-scale floor stays the desktop's). Not built in this campaign: the owner places it in a future campaign, *player operational status and settings*, to pursue once the more critical work is resolved; the TV stays at 1.4× until then. (owner's call)
* `2026-10-23` — A remote player's stream reconnects: every `loadfile` the remote transport sends carries FFmpeg's HTTP `reconnect` and `reconnect_on_network_error`, so a host restart or a network blip stalls the viewing and resumes it instead of ending the file early. (M6 fourth batch)
* `2026-10-23` — The TV app's audio buffer is 0.5 s (`Player.instanceOptions`): mpv's 0.2 s default underran once at every start on the Sony. (M6 fourth batch, `android-app`)
* `2026-10-23` — The TV app's application id is `app.mediacentaur.tv` and its display name "Media Centaur", for good. (owner; open decision 1 → decided)
* `2026-10-23` — The TV app ships first as a signed APK built in CI and attached to a GitHub release, which a user sideloads; the Google Play internal testing track is set up with the owner at the keyboard after the automation lands, since the Play Console account is theirs to open. (owner: "automate what we can before we do this")
* `2026-10-23` — The TV app's repository is named for its platform, not its form factor: `media-centaur-android`, public, beside the app repository — a phone or tablet variant shares its Gradle project and libmpv, and an iOS app would be `media-centaur-ios`. (owner's question; agent's name)
* `2026-10-23` — The TV app releases on its own cadence: its own tags and GitHub releases; `scripts/ship` tags the host only. The channel protocol is versioned by the spec, and a host release never waits on an app review. (owner)
* `2026-10-23` — The Back-key and D-pad polish is named by the owner's walk through the TV (M7's owner check); the Sound column (9) and the speed test (3) leave M7 and become milestones of their own afterwards if the owner wants them. (owner)
* `2026-10-22` — Every TV check prints the player's drop counters (`frame-drop-count`, `decoder-frame-drop-count`, `vo-delayed-frame-count`) after each viewing it drives — `DROPS:` lines in `mc-tv-flow osd`. A layer change that costs frames shows up there, not in a screenshot. (rig rule, owner's question)
* `2026-10-22` — No 4K UI on the TV: the Sony runs every app's UI at a 1080p override and the owner will not quadruple the WebView's load; a slightly smaller UI scale on the TV is wanted instead (M6). (owner)
* `2026-10-22` — The app's window, root layout and WebView carry no opaque background, and the WebView's transparency is set in code (`setBackgroundColor`), because any opaque paint above the player's surface hides the video. (`android-app`, the transparency commit)

## Open decisions

1. *Decided 2026-10-23 (Decisions made): kept.* **Application id and display name** — `app.mediacentaur.tv` and
   "Media Centaur" are provisional in the app repository. An id cannot
   change after the first Play upload, so the owner confirms both
   before M6. Recommendation: keep them.
2. **Playback performance on large, high-bitrate releases** — measured
   2026-10-22, see the M5 record; resolved as a decision (throughput
   is not a limit on this TV; no transcode path). What remains is
   open decision 4: the output path, which is a fidelity question, not
   a performance one. Still unmeasured: WiFi jitter over a full-length
   viewing (the two samples were 40 s each), and the TV's Ethernet
   port, which is present and unplugged.
4. **Output fidelity on the TV** (verified 2026-10-22). libmpv on the
   Sony decodes the original bitstream in hardware (`hwdec=mediacodec`,
   zero drops) but renders through `vo=gpu` into the app's
   `SurfaceView`, which on this panel is 1920×1080 because its Android
   UI runs at a 1080p override; the compositor then upscales to
   3840×2160. mpv's `video-target-params` while a 4K HDR remux played:
   1920×1080, bt.709, gamma 2.2, peak 1.0, so HDR (PQ/BT.2020) is
   tone-mapped to SDR on the GPU and the panel never enters HDR
   (SurfaceFlinger shows no HDR dataspace; the HWC reports hdr10, hlg
   and dv support). Audio: DTS-HD MA decoded to 16-bit PCM 5.1 over
   `audiotrack`, no bitstream passthrough. Dolby Vision profile 7's
   enhancement layer is not supported by mpv anywhere (host included);
   the HDR10 base layer plays. Options: (a) keep `vo=gpu` and fix the
   surface at the panel's physical size (`SurfaceHolder.setFixedSize`
   3840×2160) — restores resolution, costs a 4K tone-map on a 2022
   Mali every frame, and HDR output stays SDR unless mpv can present a
   10-bit HDR EGL surface on Android (research: it cannot as of
   mpv 0.41, to be confirmed); (b) `vo=mediacodec_embed` — the decoder
   writes straight to the surface, so the TV's own pipeline handles
   resolution, HDR10 and DV at near-zero GPU cost, but mpv then draws
   nothing: no OSD, no bundled pills, no track menu, no subtitles
   (subtitles would need a renderer of their own, or the WebView
   drawing them); (c) both, chosen per viewing: `mediacodec_embed` by
   default, `gpu` when a subtitle track is on. **Verified 2026-10-22**
   (`android-app` `docs/playback-on-android.md` has the evidence): (a)
   cannot give HDR — mpv's `--target-colorspace-hint` exists only for
   Wayland, D3D11 and winvk, the Android context is EGL, and this
   libmpv is built without Vulkan; (b) gives the compositor a native
   3840×2160 layer with dataspace `BT2020_ITU_PQ` and HDR metadata on
   both the DV remux and a plain HDR10 remux, zero dropped frames, `vo`
   switched at runtime over the channel; Dolby Vision is not signalled
   on either path (base layer, HDR10). Also verified, the owner
   watching the panel: a transparent page with a label over the native
   HDR video shows the video playing under it, both layers
   hardware-composited, once the app's three opaque backgrounds were
   removed (`android-app` `docs/playback-on-android.md`). **Owner's
   calls, 2026-10-22:** dropping quality is not acceptable, so there is
   no GPU-path fallback; PGS is unsupported on the TV; full fidelity is
   the target. Decision taken: (b) with the WebView as the OSD — the
   native path always, the host UI drawing the pills, track menu,
   finish prompt and text subtitles (`sub-text`) in the WebView, and
   PGS-only files saying so plainly. Audio: bitstream passthrough
   (`audio-spdif`) is the fidelity path; optical carries AC3 and the
   DTS core, eARC would carry DTS-HD MA and TrueHD; untested on the
   panel, an M5 item.
5. *Decided 2026-10-22 (Decisions made): per-file options on every `loadfile`.* **Per-viewing state on a long-lived libmpv** (found 2026-10-22). The
   host's mpv is a fresh process per viewing, so every option starts at
   its default; the TV's one libmpv keeps the previous viewing's
   state: `keep-open=yes` leaves `pause=yes` at the end of a file, and
   the next `loadfile` starts paused (seen on the Sony: the first
   viewing after an `eof` was paused from its first frame). The same
   applies to `sid`/`aid` enforcement, `script-opts` appended per
   viewing, and anything else the session sets. Options: (a) the host
   sends the viewing's whole option set as `loadfile` per-file options
   (`loadfile <url> replace -1 pause=no,start=…,keep-open=yes,…`), which
   mpv restores at the file's end — one representation of "this
   viewing's options" for both transports (`LaunchFlags` pairs render
   as CLI flags for the host and as the per-file list for a remote);
   (b) the bridge resets a known list on every `loadfile`, which puts
   session knowledge in the player. Recommendation: (a); the host owns
   what a viewing is.
6. *Decided 2026-10-22 (Decisions made): (a), the page.* **Who owns the remote's keys during a viewing** (M5, 2026-10-22).
   Today the TV app sends every key to libmpv as `keypress` while a file
   plays and `input.conf` on the player binds them. With the page as the
   OSD the pills, the track menu and the bar live in the page, so a key
   must reach the page to act on them. Options: (a) every key goes to the
   page always; the viewing layer's behaviour turns it into a playback
   command the host sends down the channel; `input.conf`, `RemoteKeys`
   and `keypress` leave the player. (b) keys go to libmpv unless the
   page "is up", which needs the shell to be told by the page or the
   host which state it is in — two owners and a race. Measured: the
   page → host → channel → mpv path is ≈10 ms (R6).
   Recommendation: (a).
7. *Declined 2026-10-22 (Decisions made): the owner has stereo speakers on the optical port and no surround decoder.* **Audio passthrough** (M5, 2026-10-22). `audio-spdif=dts` stalled
   playback on the Sony with its passthrough setting off (R6). Options:
   (a) the owner sets the TV's digital audio output to passthrough and
   the measurement is repeated; if the stream then reaches the optical
   receiver, passthrough becomes a per-player setting on Settings →
   Players (host-owned, sent as a per-file option); (b) never offer it.
   Recommendation: (a), after M5; nothing in M5 depends on it.
   *2026-10-22, owner:* the owner does not know the TV's setting and
   asked the agent to change it. *Attempt over adb, same day:* Android's
   Display & Sound → Advanced sound settings → Select formats is
   **Automatic** and lists every surround format under *Disabled* — the
   TV reports no encoded format for its current output, which is why
   mpv's IEC61937 track was refused. The Sony page that decides it
   (Settings → Display & Sound → Audio output, read through
   `uiautomator` because the activity draws over the protected TV
   input) shows *Speakers: TV speakers*, *eARC mode: Off*, **Digital
   audio out: PCM** and **Pass through mode: Off**, and the *Digital
   audio out* row is **disabled** (`enabled="false"` on its text; SELECT
   and RIGHT do nothing). On this Sony the row is enabled only when
   *Speakers* is set to *Audio system*, which also moves the TV's own
   sound to the external system. Nothing was changed. **Owner's call:**
   (a) switch *Speakers* to *Audio system* (the agent can do it over
   adb and revert), then *Digital audio out* to *Auto*, then retest;
   (b) force the Android side alone (*Select formats: Manual* with AC3,
   E-AC3, DTS, DTS-HD, settable with `settings put global
   encoded_surround_output 3` and reverted with `settings delete`), which
   makes Android accept the track but leaves Sony's digital output on
   PCM, so the optical receiver would still get PCM at best; (c) leave
   passthrough unoffered. Recommendation: (a), when the owner is at the
   TV to hear the result; nothing in M5 depends on it.
8. *Closed 2026-10-22 (Decisions made): the track menu's key is a Controls binding; MENU is its default.*
9. *Deferred 2026-10-23 (Decisions made): a milestone of its own after M7, if wanted.* **The Sound column's host-side owner** (M6, 2026-10-23). The desktop's
   track menu has a Sound column — night mode, dialogue boost, the
   limiter, the `n` key — whose per-folder memory and limiter rule live
   in Lua on the desktop player; the TV's menu has Audio and Subtitles
   only. Options: (a) the host owns the sound profile per folder
   (Settings rows, applied as mpv audio filters through the session on
   both transports; the Lua reads it back), (b) the TV goes without — the
   panel's own sound modes do the job, (c) a TV-only toggle without
   memory. Recommendation: (a), scoped as its own milestone after M7 if
   the owner wants it on the TV at all; (b) until then.
10. *Closed 2026-10-23 (Decisions made): a per-player scale factor, deferred to a future campaign.*
3. *Deferred 2026-10-23 (Decisions made): a milestone of its own after M7, if wanted.* **A "speed test" for the user** (owner, 2026-10-22): something that
   gives real clarity, practically and in plain terms, about what a
   player can play. Shape to design with the owner: Settings → Players
   (or the player's row) runs a timed transfer from the media endpoint
   to that player and reports a verdict in the user's terms — "this TV
   can play 1080p releases; 4K releases will buffer" — rather than a
   number alone, with the number beside it; a per-title hint before
   Play (the file's bitrate against the player's measured rate) is the
   natural follow-on. The measurement itself can be one channel
   command (the bridge fetches N MB of a known file and reports
   elapsed), or mpv's own `cache-speed` while playing. Which
   milestone: M5 if measurement shows a real limit, M6 otherwise.
   Recommendation: design it with the owner at the start of the next
   session, after the measurements of item 2.

## Next steps

Milestones in order; each lands on its own and leaves the host working.
Every milestone that changes an existing system runs the campaign
procedure (scope, research, decisions, `unify_design` on the design,
plan, `unify_design` on the plan, execution) and records each step here.

Restructured 2026-10-22 at the owner's direction: the whole campaign is
built on branch `remote-players`, and an end-to-end skeleton comes
first, then iteration. The contract both codebases follow is
`docs/superpowers/specs/2026-10-22-remote-players-protocol-design.md`.

1. ✅ **M1 — Reachable and closed.** Built 2026-10-22 (record below).
2. ✅ **M2 — Host side of the skeleton.** Built 2026-10-22 (record
   below; ADR-080). `Playback.Transport` seam with
   `Local` carrying today's behaviour (tests unchanged); `LaunchFlags`
   as option pairs; playable-file identity in place of `content_url`
   comparison; `Playback.Remote.Channel` + `MediaCentaurWeb.PlayerSocket`
   (raw WebSocket, mpv IPC frames, ping liveness); the media endpoint
   (Range, `sendfile`, 206/416, HEAD) with the chosen credential;
   `Playback.play/3` with the player; registry keyed by player and
   entity; `player` on every viewing event; `scripts/agents/mc-player-sim`
   driving a desktop mpv through the channel so the slice is verifiable
   with no Android code. Detach/reattach window and host-restart
   recovery over the channel are in scope here only as far as the sim
   proves them; hardening is M4.
3. ✅ **M3 — Android automation rig.** Built 2026-10-22 (record
   below): SDK, JDK pin, `mc-tv`, AVD, the app repository's empty
   shell, the debug APK; install, launch, log, screencap and a key
   press verified on the TV and on the emulator the same day; the
   emulator reaches the host as a device only via the LAN address.
   Left for M4: the WebView DevTools forward (needs a WebView).
4. ✅ **M4 — TV app skeleton.** Built 2026-10-22 (record below):
   `android-app` at `2ad7dda` — shell, player, bridge; pairs, browses,
   plays one file, reports progress, auto-advances an episode, ends on
   eof or Back, on the Sony Bravia. The finish prompt and a
   real-length file move to M5's first item.
5. ✅ **M5 — The native path and the page as OSD.** Built and verified
   on the Sony 2026-10-22 (record below; UIDR-055; the Sound column,
   sidecar subtitles and the stage-4 owner items went to M6). What the
   milestone had to deliver, from the decisions: the TV plays on `vo=mediacodec_embed` (native 4K
   HDR10; mpv draws nothing); the host's page stays over the video,
   transparent, and is the TV's OSD; everything the bundled scripts
   draw on the desktop exists on the TV as host UI in the page; text
   subtitles drawn by the page; PGS-only files say so plainly;
   per-viewing options sent so the long-lived libmpv starts clean
   (open decision 5); audio passthrough measured and, if the panel
   forwards it, offered. Inputs for step 1 (scope), gathered 2026-10-22:
   * *What the desktop scripts draw today* (`docs/mpv.md`,
     `priv/mpv/scripts/media-centaur/`): a Skip Intro pill on an intro
     chapter; a Next Episode pill during a credits chapter and an
     end-of-file countdown (ADR-062 auto-advance is the host's; the
     pill only shortens credits); the TAB track menu with the Sound
     column and `n` night mode; mpv's own OSD for seek/pause feedback.
     On the TV each becomes a host-rendered surface in the page or is
     dropped with a reason.
   * *What the host already knows per viewing* over the channel:
     `time-pos`, `duration`, `pause`, `eof-reached`, `track-list`,
     `aid`, `sid`, `chapter-list`, `playlist-count`, `playlist-pos`
     (`MpvSession`'s observe list); it does not yet observe `sub-text`
     (text subtitles for the page) or `chapter` (for the pills).
   * *What the page needs from the host*: to know it is on a TV player
     with a viewing in progress (the player id is in its session; the
     viewing events already name the player), the viewing's state, and
     commands back (seek, pause, track choice) which go host → channel
     → libmpv, never page → libmpv.
   * *What the TV app changes*: the WebView stays `VISIBLE` during a
     viewing (today `GONE` in `MainActivity.onViewingChanged`);
     `vo=mediacodec_embed` in `Player.instanceOptions` (the surface
     attach sequence is unchanged, `wid` already set); the remote's
     keys go to the page whenever the page shows an overlay and to
     mpv otherwise — today `dispatchKeyEvent` sends every key to mpv
     while `player.viewing`, so the routing rule needs an owner (the
     page tells the shell when it is "up", or the host does over the
     channel); Back while a file plays stays `stop`; the bundled
     scripts package and `input.conf` leave the TV build (nothing
     draws, `ENTER cycle pause` and the seeks move to host-driven
     commands or stay as `keypress` — decide in scope).
   * *Known costs to measure in research*: the WebView's rendering
     cost while idle and while animating over 4K video on the Mali;
     a transparent page's effect on the input system's focus rings;
     latency of host-rendered feedback (key → channel → LiveView →
     page) versus mpv's local OSD — the pause/seek feedback must feel
     immediate.
   * *Facts and evidence*: `android-app` `docs/playback-on-android.md`
     (render paths, HDR, transparency, audio, throughput, sampling);
     `mc-tv-flow perf --set vo=mediacodec_embed --overlay` reproduces
     the verified state.
   Deferred into M6 from the old hardening list: the finish prompt and
   a real-length viewing on the device (now part of the OSD work's
   verification); the pairing page's Code field size in the WebView;
   the WebView's 960×540 layout scale; the audio underrun at start;
   detach/reattach and host-restart recovery on the device; sidecar
   subtitles over the media endpoint; Back-key and D-pad polish; a
   removed player's channel closed at once; Home's pinned "playing"
   rows filtered by player; the speed test (open decision 3).
6. **M6 — Hardening.** The deferred list above, in the order the OSD
   work leaves them.
7. **M7 — Release path and owner checks.** Release signing in CI, Google
   Play internal testing track, wiki page for the TV app, glossary
   elevated to `docs/GLOSSARY.md` (✅ 2026-10-23); the owner's walk
   through every page and the full viewing lifecycle on the TV. Step 1
   recorded 2026-10-23 (record below); steps 2–7 wait on the owner's
   calls listed there.

### M7 — Release path and owner checks (procedure record, step 1)

**Step 1 — scope (2026-10-23).** In: (a) a home for `android-app` — a
GitHub repository (today it has no remote and no CI) — and a release
build signed in CI from a keystore held as a repository secret, one APK
per tag; (b) the Google Play internal testing track, the first upload
of which fixes the application id for good; (c) the path a user takes
to install the TV app on their own TV — Play's internal track (testers
the owner lists) or a sideloaded APK from the GitHub release; the wiki
page says which; (d) the wiki page for the TV app: requirements
(Android TV, the host on the same network), installing, then pointers
to pairing (`Settings-Reference#players`) and use (`Playback#on-a-paired-tv`,
`Keyboard-and-Gamepad`), which already exist; (e) the glossary
elevated to `docs/GLOSSARY.md` — **done 2026-10-23**: the Playback
section's stale *Player* row replaced by Player (host/remote), Pairing,
The gate, Transport, Player channel, Media endpoint, Playback session,
Viewing, Viewing layer and TV app, each row naming its module and
record; (f) the owner's walk through every page and the full viewing
lifecycle on the TV, with what it finds fixed under M6's Back-key and
D-pad item; (g) the merge of `remote-players` into main, the release
that carries it, and the five local wiki commits pushed with that
release; (h) campaign closure — the file deleted, the index paragraph
written, the per-player UI scale leftover (decision 10) re-homed there
under *player operational status and settings*. Dropped from M7: the
Sound column (decision 9) and the speed test (decision 3) — each is its
own milestone after M7 if the owner wants it, neither gates a release.
Not in scope: a Play production listing (store assets, a privacy
policy, content rating) — the internal track is the campaign's end
state, production is a later campaign.

*Owner's calls that gate step 2 onward:* decision 1 (the application id
`app.mediacentaur.tv` and the name "Media Centaur" — recommendation:
keep them); whether the TV app ships through Play at all for now or
only as a sideloaded APK (recommendation: build and sign in CI either
way; open the Play internal track only when the owner has a Play
Console account — it carries a one-time fee and an identity check, to
confirm in research); the repository's name and visibility
(recommendation: public, `media-centaur-tv`, beside the app
repository); and whether the host's `scripts/ship` should tag the TV
app too or the two release on their own cadence (recommendation: their
own cadence — the channel protocol is versioned by the spec, and a host
release must not wait on a Play review).

*Research list for step 2 (not yet run):* Play Console account
requirements and the internal track's tester limits as of 2026; Gradle
`signingConfigs` from CI environment variables with the keystore
base64-encoded in a secret; a GitHub Actions runner building the
`armeabi-v7a` debug and release variants against `dev.jdtech.mpv:libmpv`
1.0.0 with the `mise.toml` pins; whether the WebView version the Sony
runs (154) is the floor to document; the wiki's `Installation` page
structure, so the TV page sits beside it in `_Sidebar.md`.

**Step 2 — research (2026-10-23).** `android-app`: one Gradle module,
AGP 9.4, `compileSdk`/`targetSdk` 36, `minSdk` 26, `versionCode 1` and
`versionName "0.1.0"` as two hand-kept fields, no `signingConfigs`, no
remote, no CI, no CHANGELOG; `rootProject.name` is `media-centaur-tv`;
`mise.toml` pins Temurin 21 and points `ANDROID_HOME` at `~/Android/Sdk`
(absent on a CI runner; AGP reads `local.properties` `sdk.dir` first,
and the file is already gitignored). The debug APK is 107 MB and carries
libmpv for four ABIs (arm64-v8a, armeabi-v7a, x86, x86_64). Nothing
sensitive in the tree (a `192.168.1.5` placeholder in a hint string and
a doc; no keys, no home paths). `keytool` is on the mise JDK. `gh` is
logged in as the owner; the `media-centaur` organisation holds the app
repository and six others, all public but `shell`. The host's release
convention: `release.yml` on tag `v*`, the tag checked against the
version in the source, notes cut from `CHANGELOG.md`'s `## v<tag>`
section by `awk`, `SHA256SUMS`, `gh release create` with `github.token`;
`ci.yml` on push to main and pull requests. The wiki: `_Sidebar.md`
lists Getting Started → Installation; `Settings-Reference#players` says
"On the device, open that address"; the Pair card on Settings → Players
says "Open Media Centaur on it". Play Console requirements are left for
the sit-down (decided: Play after the automation).

**Step 3 — decisions (2026-10-23).** The owner's five calls (Decisions
made, 2026-10-23). Taken by the agent as routine: the release APK is
universal (one file for every TV and the emulator; Play takes an AAB
and splits it when that channel opens); `versionCode` is derived from
`versionName`; the keystore is generated now, held by the owner's
machine and backed up, and reaches CI as repository secrets.

**Step 4 — design unification (2026-10-23).** *Core idea:* a release of
the TV app is a tag, and everything downstream — the signed APK, the
checksum, the release page and its notes — is derived from that tag by
CI, as the host's is; nothing is built or installed by hand. *Greenfield
shape:* one version source (`versionName`; `versionCode` computed as
major × 10000 + minor × 100 + patch, so an upgrade install always
climbs); one toolchain source (`mise.toml`, read on CI by `mise-action`;
the SDK's location is the machine-local `local.properties`, written by
the workflow); signing as a property of the environment (the release
build type gains a signing config only when the keystore secrets are
present, so a contributor's `assembleRelease` yields an unsigned APK and
CI's a signed one — one build type, not two); the host's release
convention reused verbatim (tag check, CHANGELOG notes, SHA256SUMS,
`gh release`); a public repository named for the platform. *Diff
against the code:* (a) clean seams — the host's `release.yml` shape,
`local.properties`, `mise.toml`; (b) duplicated state — `versionCode`
beside `versionName` (derive it); the JDK version, which would be pinned
again in CI (read `mise.toml` instead); (c) incoherences — the README is
written for the author's rig (`mc-tv` lives in `~/scripts/agents`) and
a public repository needs the `gradlew` path first and the rig named as
the author's: fix now; `.gitignore` does not exclude a keystore: fix
now; the host's Pair card and the wiki tell the user to "open Media
Centaur" on the TV without saying where the app comes from — the
release page is where, so the card and `Settings-Reference` link it:
fix now (a host template line and a test on the branch). *Scope cost:*
the Pair card line is the one host change; everything else is in the
app repository and the wiki. Installing the signed APK on the Sony
replaces the debug build (a different signature cannot upgrade it), so
the TV loses its pairing once; the owner's walk starts by pairing.

**Step 5 — implementation plan (2026-10-23).** In the app repository:
`build.gradle.kts` (derived `versionCode`, environment-driven
`signingConfigs.release`), `.gitignore` (`*.jks`, `*.keystore`),
`CHANGELOG.md` (v0.1.0), `.github/workflows/ci.yml` (push and pull
request: `mise-action`, `local.properties`, `gradlew test assembleDebug`),
`.github/workflows/release.yml` (tag `v*`: version check, keystore from
secrets, `assembleRelease`, `media-centaur-tv-<version>.apk`,
`SHA256SUMS`, notes, `gh release create`), README (repository, the
release path, the secrets' names, `gradlew` first). On this machine: the
keystore under `~/.config/media-centaur-android/` with its passwords,
backed up through Fae, the four secrets set with `gh secret set`. Then
`gh repo create media-centaur/media-centaur-android --public` from the
checkout, push, watch CI; tag `v0.1.0`, watch the release, download the
APK, `apksigner verify`, install it on the Sony over adb (no TV window:
the TV is the owner's display while they are at the keyboard). Wiki:
`Android-TV-App.md` (requirements, install from the release page,
first run, updates, pointers), `_Sidebar.md` under Getting Started,
`Settings-Reference#players` naming the app; committed locally with the
other five. Host branch: the Pair card's line linking the release page,
its test, `mix precommit`. Record the outcome here.

**Step 6 — plan unification (2026-10-23).** Checked against the design:
no parallel path (there is no hand-built release to keep; `mc-tv build`
stays the debug rig); no copied constant (the JDK comes from `mise.toml`,
the version from `versionName`, the release URL appears once in the host
template and once in each wiki page as prose links, not a constant to
share); no shim (signing attaches to the one release build type); no
test stand-in encoding an old shape. One correction: the APK's name is
given by the Gradle build (`archivesName`), not renamed by the workflow,
so a local `assembleRelease` and CI produce the same file name.

### M6 — Hardening (procedure record, in progress)

**Step 1 — scope (2026-10-22), first item: the viewing's keys as
Controls bindings** (the owner's question: Media Centaur has control
configurations, why not use them). In: four catalog bindings in a new
category *During playback on a TV* — play/pause `MediaPlayPause`, seek
forward `MediaFastForward`, seek back `MediaRewind`, audio & subtitles
`ContextMenu`, no gamepad defaults; the JS id mapping; the two fallback
key maps deleted (`VIEWING_KEY_MAP`, and `ZONE_KEY_MAP`, a leftover
from before the catalog carried the zone keys); a Play/Pause key
outside a viewing meaning Play; UIDR-055 rule 3 amended; the wiki's
Keyboard & Gamepad page; open decision 8 closed. Out: per-device
bindings — bindings are install-wide, and the media keys and
ContextMenu exist on no desktop keyboard, so nothing collides; keys the
TV's operating system takes before the app (Sony's Info key during a
viewing), which cannot be captured — said in the wiki; gamepad defaults
for the four (none; bindable). The rest of M6's list is scoped when this
item lands.

**Step 2 — research.** `Controls.Catalog` is the compile-time list;
overrides are Settings rows; `Controls.get/0` resolves; the layout
embeds the resolved map as `data-input-bindings`; `index.js` builds the
key map by id (`actionForId`) and `controls:updated` hot-swaps it.
`KeyboardSource` consults the user's map, then `ZONE_KEY_MAP`, then
`VIEWING_KEY_MAP`. `DEFAULT_KEY_MAP` and `DEFAULT_BUTTON_MAP` are never
consulted by the app (an embedded empty map is still a map); they are
the test fixtures' defaults. The Controls page renders every category
from `Catalog.categories()` with `ControlsLogic.category_label/1`;
capture takes the next keydown on `window` in the capture phase, which
sees the shell's forwarded keys (bubbling synthetic events on the
focused element), so the TV can bind its own Menu key on its own
Settings page. The catalog's moduledoc says the wiki's tables are
generated from it; no such script exists. The focus machine answers
`PLAY` with `{type: "play"}` in every content context; `PLAY_PAUSE`
reaches it only outside a viewing and is ignored.

**Step 3 — decisions.** None for the owner: open decision 8 becomes the
user's binding, with `ContextMenu` as the default.

**Step 4 — design unification.** Core idea: *every key the app answers
to is a catalog binding; the page decides what the action means where
the cursor is.* Greenfield: one catalog, one resolved map, one
`keyToAction` over it; the viewing's four actions are bindings like the
rest; a Play/Pause key is Play when nothing is playing. Diff: (a) seams
— the catalog, the id mapping and the hot-swap, used as they are; (b)
duplicates — `VIEWING_KEY_MAP` and `ZONE_KEY_MAP` are second key→action
maps outside the user's: deleted, `keyToAction` reads one map; the two
`DEFAULT_*_MAP`s copy the catalog's defaults but are reachable only
from tests — kept as the fixtures' defaults, named as such, and given
the four so the fixture matches the catalog; (c) incoherences — the
catalog's moduledoc promises a wiki generator: corrected to "kept in
step by hand"; `PLAY_PAUSE` ignored on a page: the machine answers it
as `PLAY`. Coherence cost: none beyond the scope; no owner call.

**Step 5 — plan.** (1) `catalog_test`, `controls_logic_test`,
`controls_test` extended (14 bindings, the category, the label) →
catalog, `Binding.category`, the label. (2) `actions.test`: the
viewing's keys answer from the map only, a custom map without `]`
yields null → the two maps deleted, the fixture defaults extended.
(3) `index.test`: every catalog id maps to an action (the ids listed in
the test — the one copy of the list, a pin) → `actionForId` exported
and extended. (4) `focus_context.test`: `PLAY_PAUSE` on a grid is
`{type: "play"}` → `transition/1`. (5) UIDR-055 rule 3; the wiki's
Keyboard & Gamepad page (a defaults table under *In the browser UI*,
the TV section pointing at Controls); decision 8 to Decisions made.
(6) `bun test`, precommit, the OSD check on the TV.

**Step 6 — plan unification.** No old path kept: the fallback maps go
in the same change as the bindings. No constant copied: the defaults
live in the catalog; the fixtures' copy is named a fixture. Every
caller converts: `keyToAction` is one line. No shim. One stand-in
encoded the old shape — `actions.test`'s "zone keys still work with a
custom map" — and is rewritten to the new rule. The JS test that lists
the catalog's ids is a copy, accepted as a pin: a catalog id with no JS
action is otherwise silent.

**Step 7 — execution, first item (2026-10-23).** Commit `4bd5d6de`
(worktree), wiki `57560d0` (local, unpushed). Precommit green: ,
935 JS tests, zero warnings. Desk check on the headless simulator
(`mc-player-sim --headless`, new: mpv on null video and audio, so no
window on this computer, whose display is the TV): with E01 playing,
`ContextMenu` opens the track menu (context `viewing_subtitles`) and
closes it, `MediaFastForward` reaches the player as `seek 30 relative`,
`MediaPlayPause` as `cycle pause` — all from the embedded bindings, the
fallback maps gone. Found on the way: the sim host's resolved-bindings
cache (`:persistent_term`) was built at boot from the 10-binding catalog
and the code reloader did not refresh it, so the layout read a new id
as nil and the page answered 500 — a dev-only stale cache (a release
rebuilds it at boot), refreshed over RPC; and the rule itself seen
working by accident — a Play/Pause key with no viewing started the
focused shelf tile. **TV check pending** (the TV is the owner's gaming
screen and off tonight): `mc-tv-flow osd tv` with the bindings, and
binding Audio & subtitles to another key on the TV's own Settings page.

**Step 1 — scope, second batch (2026-10-23, the owner asleep, the TV
off).** The deferred list sorted by what can be verified on the desk
(the simulator, headless) and what needs the TV. *Desk items, in this
batch:* (a) a removed player's channel closed at once — today
`Players.remove/1` broadcasts `PlayerRemoved` and the channel never
hears it, so a revoked TV stays connected and its viewing keeps
streaming until the socket drops on its own; (b) Home's pinned
"playing" rows filtered by player — `HomeLive.Logic.continue_watching_items/2`
pins any entity with a live session on *any* player, so a viewing on
the desktop pins the row on the TV's Home and the reverse; (c) the
hidden bar patched at 1 Hz — the clock's assigns change every tick
whether the bar shows or not; (d) a relative seek past the end leaves
mpv paused on the last frame with no `eof-reached` (stage 4 finding;
reproduce on the desk, then clamp on the host or end on paused-at-end);
(e) sidecar subtitles over the media endpoint — the desktop mpv
auto-loads a sidecar next to the file, a remote player plays a URL and
cannot, so the host adds them with `sub-add` after `loadfile` from an
endpoint that serves the sidecar under the viewing's token; (f) the
unexplained burst (≈10 syncs/s for a second on Home with the finish
prompt open after SELECT on Delete, seen once) — reproduce or retire.
*Owner decisions, recorded under Open decisions and not taken here:*
the Sound column's host-side owner (night mode, dialogue boost, the
limiter; today Lua on the desktop player with per-folder memory); the
speed test (open decision 3); the application id (open decision 1).
*TV items, pending the TV being free:* the bindings on the Sony
(`mc-tv-flow osd tv`), the TV's UI scale a little smaller (the per-device
scale preference, set on the TV's own Settings page), the pairing
page's Code field in the WebView, the WebView's 960×540 layout scale,
the audio underrun at start, detach/reattach and host-restart recovery
on the device, Back-key and D-pad polish, the finish prompt after a
real-length viewing. *Dropped:* nothing yet.

**Step 2 — research, second batch (2026-10-23).** (a) `Players.remove/1`
deletes the row and broadcasts `PlayerRemoved` on `players:updates`;
`PlayerAware` sends a removed player's page to `/pair`; the channel
(`PlayerSocket` → `Remote.Channel`) never hears it, stays registered and
keeps streaming a live viewing; the device is re-admitted per HTTP
request only. A channel that closes detaches its session, which waits
the 60 s reattach window before ending. (b) `LiveHelpers.load_playback_sessions/0`
snapshots every session keyed by entity id — one key per entity
whatever the player — and `apply_playback_change/5` ignores the event's
`player`; users: Home (pins), Library (the card's playing dot), the title
detail host (`title_playback`, guards delete), Status (every session —
an admin board). `PlaybackStateChanged.player` is `:host | player_id`;
`PlayerAware` gives every socket `player`. (c) The bar hides by
`opacity: 0` with a 200 ms transition on `data-bar`, its DOM kept so a
show never reflows; `Logic.update` replaces the viewing each tick and
the clock, fill and handle re-render: ≈8 mutations/s, 0 drops on the
Sony. (d) Reproduced on the headless simulator (desktop mpv 0.41): with
a successor queued, `seek 200 relative` → `end-file reason=eof` → mpv
advances, right; with none, mpv lands on `time-pos = duration`, emits
`pause=true` and never `eof-reached=true` (mpv sets it only when playback
runs into the end), and the session sits `paused pos=90.0` for good —
the desktop too, where the user quits the window. The session's
`{:seek, n}` goes out as `seek n relative`; the session holds `position`
and `duration`. (e) `Subtitles.Track` (`kind: :sidecar`, `source` the
path, `language`, `watched_file_id`) is detected at import
(`Library.Inbound` → `Detector.Sidecar`) and listed by
`Subtitles.list_tracks_for_file/1`; `WatchedFile.file_presence_id` ties
a file to its presence; the media endpoint serves `/media/:presence_id`
by a token over `{player_id, presence_id}`; the desktop mpv auto-loads
sidecars itself (`sub-auto`), so only the remote transport lacks them;
`Transport.Remote` holds the locators and sees every mpv event
(`start-file`, `file-loaded`, `path`); mpv's `sub-add <url> auto <title>
<lang>` loads an external track from a URL and fires `track-list`, which
the session already re-resolves ("external sub file" anticipated).
Boundaries: Playback depends on Library, not Subtitles; Library and the
web layer depend on Subtitles. The simulator's library has no sidecar
(0 tracks) — one goes into `mc-sim-host setup`. (f) Not reproduced yet;
step 7 tries with the finish prompt on Home. (g) *New, found in (d):*
after an auto-advance `reset_for_file` sets `current_sid: nil`; mpv
reports an observed property only when it changes, and `sid`, set by
`set_property`, keeps its value across files, so the new file brings an
`aid` event (auto → 1) and no `sid` event; the capture then reads "no
subtitle" and persists `subtitles_off: true` for the series — the sim
host's log shows it; the desktop advances the same way.

**Step 3 — decisions, second batch.** (a) A removed player's channel
closes at once (`:removed`), after telling the device's mpv `stop`; its
viewing ends at once, no reattach window — the player is not coming
back. (b) A page's playback map holds its own player's sessions (the
roadmap's rule: per-device state is session state); Status keeps every
session. (c) *Dropped:* the hidden bar's 1 Hz patch is ≈8 text and
attribute mutations a second at zero measured cost, and freezing the
clock would keep a second copy of the position; nothing to fix. (d) A
relative seek never crosses the end: the host clamps it to one second
before the duration, so the file plays out and ends the way it always
does (the prompt, the successor) — one rule for both transports, no
state-matching on mpv's pause. (e) The remote transport adds the file's
sidecars with `sub-add … auto` once mpv reports `file-loaded`, from
`/media/:presence_id/subtitles/:basename` under the viewing's token; the
sidecars of a presence are one query in Subtitles, used by the plug and
the transport; Playback gains Subtitles as a dependency. (g) An observed
property persists across files: `reset_for_file` keeps `current_aid`
and `current_sid`. Owner's calls, not taken: the Sound column's owner,
the speed test, the application id (Open decisions).

**Step 4 — design unification, second batch (`unify_design`).** Core
idea: *a remote player is a peer of the host's own mpv — the same
session through a transport; what its mpv cannot do for itself (find
the file, find the file's companions, outlive its pairing) the transport
does for it; and what belongs to one device (its viewing, its playing
rows) never shows on another.* Greenfield: (a) the pairing is the
channel's admission, so the channel ends when the pairing does — it
listens on `players:updates`, tells the device's mpv `stop` and closes
`:removed`; a detach is for a channel that may come back, a removal is
final, so the transport turns `channel_down :removed` into the session's
end. (b) "what is playing here" is the device's sessions: the page's map
is loaded and updated for its player, with Status the one board over
every player. (d) the session owns position and duration, so it bounds
a command: `Command.within/3` shortens a seek that would cross the end
to stop one second short and drops one with nothing left; the command
type is unchanged (relative stays relative). (e) a file's companions
are fetched the way the file is — `/media/:presence_id/subtitles/:basename`
under the file's token (the token names the file; its sidecars are part
of it); the sidecars of a presence are one Subtitles query; the remote
transport, standing in for mpv's own autoload, adds them with `sub-add`
when mpv reports `file-loaded` for the presence it saw in `path`; the
session stays unaware, as it is of the desktop's autoload. (g) observed
properties persist across files. Diff: seams used as they are —
`MediaServer.serve/3`, `MediaToken`, `PlayerChannel.locators` (one more
closure, `locate_subtitle`), `Transport.Remote.handle_message`, the
session's re-resolution on `track-list`, `PlayerAware`'s `player`,
`PlaybackStateChanged.player`. Duplicates: `apply_playback_change/5`
has every caller destructure the event — it takes the event and the
page's player instead, one rule for "is this mine". Incoherences: Status
keys sessions by entity across players (two players on one title
collide) — pre-existing, scheduled: *Status keyed by {player, entity}*,
M6 third batch; Playback gains Subtitles as a dependency — a new
crossing, recorded in `docs/context-map.md`. Coherence cost: within the
batch; no owner call.

**Step 5 — plan, second batch.** Test-first, in this order. (1) (g)
`mpv_session_test`: `reset_for_file/4` keeps `current_aid`/`current_sid`.
(2) (d) `command_test`: `Command.within/3`; `mpv_session_transport_test`:
a seek past the end goes out shortened, one with nothing left is not
sent. (3) (b) `live_helpers_test`: `load_playback_sessions/1` by player
(`:host`, an id, `:all`) and `apply_playback_change/3,4` with the event
and the player; Home, Library, the title detail host and Status
converted; `home_live_test`: another player's session does not pin.
(4) (a) `channel_test`: `connect/2` subscribes; `{:player_removed, own}`
→ `{:stop, :removed, {1000, "removed"}, [stop frame], state}`; another
player's removal unhandled; `PlayerSocket.reply` maps the five-tuple;
`remote_test`: `channel_down :removed` → `{:closed, {:ok, :ended}}`.
(5) (e) `subtitles_test`: `sidecars_for_presence/1`; `media_server_test`:
the subtitles route (200 with the file, 404 for a basename not among
the file's sidecars, 403 for another file's token); `player_channel_test`:
`locate_subtitle`; `remote_test`: `path` then `file-loaded` pushes one
`sub-add url auto title lang` per sidecar; Playback's `use Boundary`;
the context map; `mc-sim-host setup` writes a sidecar beside E01 and
detects its tracks. (6) Docs: `docs/playback.md`, `MediaToken` and
`MediaServer` moduledocs, the protocol spec, wiki `Playback.md` and
`Troubleshooting.md` where they say sidecars are missing on a TV.
(7) Desk checks on the headless simulator: removal closes the channel
and stops the file; a seek past the end plays out to the prompt; the
sidecar appears in the track menu; Home pins only the page's player's
viewing. (8) (f) reproduce the burst with the finish prompt.

**Step 6 — plan unification, second batch.** No old path kept:
`apply_playback_change/5` goes, every caller converts in the same
change (Home, Library, the detail host, Status). No constant copied: the
subtitles URL is composed in one place (`PlayerChannel.locators`) and
parsed in one (`MediaServer`). No shim: the transport's `file-loaded`
rule replaces nothing. Test stand-ins: tests calling
`apply_playback_change/5` are rewritten to the event form, not wrapped.
The sim fixture is a fixture, not a copy of production data.

**Step 7 — execution, second batch (2026-10-23).** Every item built
test-first, the unit tests green, precommit green (8702 Elixir, 935 JS,
zero warnings), each item verified on the headless simulator
(`scratchpad` scripts; `mc-sim-host sidecars` is new: a sidecar beside E01
and every file's tracks detected). (a) `Players.remove/1` → the channel
pushes `stop` and closes `{:shutdown, :removed}` (a deliberate close is a
shutdown, `:replaced` too — the first cut's `:removed` landed in the error
log as a crash); the channel tells its session itself (`closed/2`'s
reason is Bandit's to wrap: it arrived as `{:error, …}`); the viewing was
gone within a second, the simulator's reconnect refused (1002). (b)
`LiveHelpers.load_playback_sessions/1` and `apply_playback_change/4` take
the page's scope (`:host`, a player id, `:all`); the title detail host
loads its set at mount for `PlayerAware.playback_player/1` and filters
events by it; Home's own `:playback` snapshot (loaded once, never
updated) and Library's dead `playback:` assign are gone — one playing set
per page; Status keeps `:all`. Checked: the movie playing on the
simulated device pulses on the device's Library card and not on the
host's. (c) dropped, as decided. (d) `Command.within/3`: a seek that
would cross the end becomes `{:seek_to, duration − 1}`, a new vocabulary
entry rendered `seek … absolute+exact` — the first cut shortened the
relative seek, and a keyframe seek that close to the end snapped onto it
(the simulator's files keyframe every 10 s), so the viewing still sat
paused; exact, the file plays its last second, `eof-reached` fires and
the session ends. (e) `Subtitles.sidecars_for_presence/1`;
`/media/:presence_id/subtitles/:basename` under the file's token
(`MediaServer.admit/3`, one admission for the file and its companions);
`locators.locate_subtitle`; `Transport.Remote` remembers the presence
from `path` and pushes `sub-add <url> auto <name> [<lang>]` on
`file-loaded`; Playback depends on Subtitles. Checked: the sidecar is
track 1 (`eng`), the resolver enforces it, its lines stream to the page.
The spec's claim that sidecars are presence rows was wrong (the watcher
stamps video files only) — amended. (f) not reproduced: with the finish
prompt open on the device page after the lab film's end, SELECT on Delete
caused one sync (the confirm state), not ten; retired. Found on the way:
completion needs continuous watching into the end (the tracker's 10 s
rule), so a seek into the last second ends the viewing without
completing it — the desktop's rule too, left as is. (g) `reset_for_file`
keeps `current_aid`/`current_sid`; the simulator's series had the
poisoned override from before the fix, cleared by hand.

**Third batch (2026-10-23), steps 1–7.** *Scope:* Status keyed by
`{player, entity}` — two players on one title collided in the board's
map (scheduled by the second batch's design pass); the TV list waits.
*Research:* Status built its own map (`build_playback_state`, keyed by
entity, carrying `started_at`), updated it through the shared
`apply_playback_change` with the `:all` scope the second batch added, and
its widget already draws one block per session; `derive_playback` reads
values only; `entity_progress_updated` found the one entry by entity.
*Decisions:* none for the owner. *Design pass:* the board over every
player and a page's playing set are two ideas — one is keyed by player
and title, the other by title alone — so the `:all` scope was a flag
hiding a different key: gone; Status owns its map
(`StatusHelpers.apply_session_change/2`, one entry per player and title,
`started_at` kept from first sight) and the helper's scope is `:host |
player_id` only; progress moves every player's bar on that title (per
profile and title, not per player). *Plan:* `status_helpers_test`
(two players on one title, the stop that keeps the other, `started_at`),
`status_live_test` (two sessions "2 active", one stopped "1 active"),
`live_helpers_test` (the `:all` case removed) → the helper, Status's
three handlers, docs. *Plan pass:* no `:all` left anywhere; the helper's
arity drops to 3 and both callers (the detail host, the tests) follow; no
shim. *Execution:* done, 212 tests green across the four files;
precommit green, commit `8ff8cb81`.

**TV checks of the three batches (2026-10-23, the TV free again).**
Three windows on the Sony (`scratchpad` scripts `m6tv`, `m6tv-b`,
`m6tv-c`), zero dropped frames in every viewing. Passed: the media keys
through the bindings (Play/Pause pauses and resumes, Fast forward and
Rewind seek ±30 s), MENU opening and BACK closing the track menu, BACK
stopping the viewing; a rebind on the TV's own Settings page — the Seek
back row clicked, the Menu key the shell forwards captured as
`ContextMenu`, Audio & subtitles given Rewind by the auto-swap, and in
the next viewing Rewind opened the menu and Menu seeked back; a seek
past the end — on E01 it landed on 89 s and the chain advanced to E02,
on the movie the file played out (`seek 89.023 absolute+exact`,
`eof-reached`, `end-file stop`), the viewing ended and the page came
back with no prompt; removal while playing — `stop` pushed, the socket
closed `1000 removed`, the viewing gone within a second, the app on
`/pair` (run twice; the Sony paired again each time, now `9586a9fc`,
the two stale desk players removed); the sidecar beside E01 — mpv's
track 2, external, titled by its name, its own entry in the menu,
picked (sid 2), its line on the page. Three faults the TV found, each
fixed test-first: (1) the media endpoint answered 404 for the sidecar —
`MediaServer` runs ahead of the router, which is what decodes path
segments, so a basename with spaces arrived percent-encoded and matched
no track; the plug decodes it (`media_server_test`, an encoded name).
(2) On the second run the `sub-add` never left the host — libmpv
delivered `file-loaded` before the `path` property (the first run had
the opposite order) and the transport pushed only on `file-loaded` with
a presence already known; it now pushes once both are known, in either
order, once per file, and `start-file` forgets both (`remote_test`).
(3) The Controls page rendered the bindings one change behind after a
bind — `Controls.broadcast/0` published `get/0`, the `:persistent_term`
cache that the Cache worker refreshes only on receiving that very
broadcast, so the broadcast and the writer's own return carried the
state before the write; the desktop has the same fault, masked in tests
where no worker runs and `get/0` resolves live. The writer refreshes
the cache before it broadcasts (`controls_test`, with the cache warm).
Docs: `docs/playback.md` and the spec amendment say "in either order".
Precommit green; commit `e606061b`.

**Fourth batch (2026-10-23, the TV free), steps 1–7.** *Scope:* the
TV-only list, measured before anything was designed: (a) the pairing
page's Code field; (b) the WebView's 960×540 layout and the UI scale "a
little smaller" — one question; (c) the audio underrun at start; (d)
detach/reattach and host-restart recovery; (e) the finish prompt after a
real-length viewing; (f) Back-key and D-pad polish — nothing specific is
recorded; waits on the owner naming what they saw. *Research (TV window
d, `scratchpad/m6tv-d`):* the WebView reports 960×540 CSS px at a device
pixel ratio of 2 (Android TV's 1080p is xhdpi by convention), so
`--auto-scale` computes 0.5 and the stylesheet's 0.7 floor clamps it: the
TV draws the design at 1.4× its 1:1 size — (b) has one cause. The Code
field had no box on the desk either (`page-shot` at 960×540): the kit's
`.input` takes a caller's class in place of its own, and the code's
`font-mono tracking-widest` had replaced `w-full input`; the page's
background stopped at 70% of the screen — `min-h-screen` under the 0.7
zoom, the `--pvh` case `app.css` documents. A dropped channel reconnects
in 1 s and the viewing reattaches, zero drops. A host restart killed the
stream: FFmpeg's HTTP reader took the short read for the file's end, mpv
sat on `eof-reached` at 84 s of 2543 (keep-open), and the recovered
session ended the viewing at once. The TV's mpv is FFmpeg n8.1, whose
HTTP `reconnect` and `reconnect_on_network_error` resume the Range with
backoff (caps: 120 s a try, 256 s in all); mpv ignores a `stream-lavf-o`
key a build lacks; the media token lives 12 h. `audio-buffer=0.5` set on
the instance before a play: no underrun, where every earlier start logged
one at mpv's 0.2 s default. The rig: `mc-sim-host stop` returned before
the old node had gone and the next `start` never came up (an empty log) —
it waits now. *Decisions:* (b) is the owner's — open decision 10.
*Design pass:* the stream is the transport's delivery, so its options
ride on each file beside the session's: `Transport.Remote`'s one
`loadfile` helper (open and queue) leads with
`stream-lavf-o=reconnect=1,reconnect_on_network_error=1` — not on the TV
app's instance (the host owns delivery) and not in `LaunchFlags` (the
desktop's local file has no stream). The AO buffer belongs with the TV
app's AO, decoder and cache options (`Player.instanceOptions`). The Code
field and the page height are fixes at the callers, not the kit. *Plan:*
`remote_test` (both loadfile expectations) → the helper;
`pairing_controller_test` (both inputs drawn as the kit's, LazyHTML) →
the class; `min-h-screen` → `calc(100 * var(--pvh))`; `audio-buffer` in
the TV app and its doc; the rig's stop waits; docs: the transport
moduledoc, `docs/playback.md`, the spec amendment; TV window e. *Plan
pass:* the stream options live in the transport only; every loadfile goes
through the helper; no shim. *Execution (TV window e, `m6tv-e`):* the
Code field 279×28 CSS px, drawn; `audio-buffer` 0.5 → no underrun; the
host stopped (16 s) and started (2 s): FFmpeg reconnected with backoff
("Will reconnect … in 3 second(s)", then 7), the channel came back in
1 s, the recovered session kept playing (45 → 51 s, not paused for
cache), zero drops; a seek into the last 30 s of the 42-minute file
played out to the finish prompt (completed: Delete this file / Done /
Watch again). Precommit and commit: see Status; the TV app's build with
the buffer (`android-app`): see Status.

### M5 — The native path and the page as OSD (procedure record)

**Measurements (2026-10-22), before any M5 design.** Two real releases
from the owner's library were linked into the simulated host as
symlinks (`mc-sim-host stage`): the heaviest 4K file (a 2160p UHD
remux, HEVC, DV profile 7 FEL over HDR10, DTS-HD MA 5.1, 77 GiB,
95 Mbit/s average) and the heaviest 1080p file (H.264, DTS-HD MA 5.1,
21 Mbit/s). The owner's dev server was not touched: its `bind` stays
loopback.
* **Link ceiling, no TV window.** The TV's shell has no curl or wget
  but toybox `nc` and `dd`: 1 GiB fetched from the media endpoint over
  the TV's WiFi in 38.7 s (≈27.8 MB/s, ≈220 Mbit/s); a 20 s timed fetch
  gave 208 Mbit/s; an `adb push` ran at 158 Mbit/s. The TV's `eth0` is
  present with no carrier. Ad-hoc LAN servers from the agent shell are
  refused by the permission classifier; the simulated host on 4003 is
  the one LAN-exposed path, which is why `stage` exists.
* **First window: every viewing paused.** `pause=true` from the first
  frame of both files, and the host's `set_property pause false`
  answered by libmpv with `-4` (bad option value): the bridge
  stringified JSON booleans. Fixed (`android-app` `e46cd1b`, a unit
  test on the typed set). The initial pause was the long-lived
  instance keeping `keep-open`'s pause from M4's last `eof` (open
  decision 5).
* **Second window, both files playing** (`mc-tv-flow perf`): 4K —
  `hwdec=mediacodec`, `time-pos` advancing in real time over 26 s,
  `cache-speed` 10–12.6 MB/s (mpv throttles to the file's rate once
  the 150 MiB cache is full: `demuxer-cache-duration` 13.4–13.8 s),
  `paused-for-cache` never, `frame-drop-count` 0, `decoder-frame-drop-count` 0,
  `vo-delayed-frame-count` 0, `avsync` 0.00003; 1080p — the same with
  56 s cached. No mpv warnings or errors beyond "Dolby Vision
  enhancement-layer playback is not supported".
* **Output path** (`video-target-params` during the 4K file): 1920×1080,
  bt.709, gamma 2.2, sig-peak 1.0, rgba16f; `osd-dimensions` 1920×1080;
  `android-surface-size` 1920×1080 at surface creation; SurfaceFlinger:
  `displayFrame [0 0 3840 2160]`, `sourceCrop 1920×1080`, dataspace
  UNKNOWN, HWC supports hdr10, hlg, dv. Audio out `s16`, 6 ch, 48 kHz,
  `audiotrack`. Open decision 4 carries the options.
* **Third window, `vo=mediacodec_embed`** (set over the channel before
  `loadfile`, no app change): SurfaceFlinger shows the app's layer at
  `size=(3840,2160)`, `sourceCrop 3840×2160`, `dataspace=BT2020_ITU_PQ`,
  `hdr metadata types=3`, on both the DV profile 7 remux and a plain
  HDR10 remux; the MediaTek decoder logs HDR metadata reads; zero
  dropped frames, real time; `video-target-params` unavailable (no
  mpv renderer); screencap still captures the frame. No DV signalling
  on either path. The GPU path's HDR ceiling is the manual's:
  `--target-colorspace-hint` is Wayland/D3D11/winvk only, Android's
  context is EGL, and the build has no Vulkan. Full evidence in
  `android-app` `docs/playback-on-android.md` (`1ffa3b1`).
* **Rig additions.** `mc-sim-host stage <file> <name> <year>`;
  `mc-tv-flow perf <tv|emu> <movie-id>[:seek]...` (two property samples
  25 s apart, screenshot, the SurfaceFlinger dataspace lines, mpv
  warnings, Back, `hdmi`). Staged in the sim host this session:
  MOVIE `1bb10bdd-cbda-48b4-b59d-263425a31c40` (4K, 95 Mbit/s),
  `f506e315-80b0-40a3-a2a1-9a5696d47fd8` (1080p) and
  `1e2de1ec-6f9f-4109-b821-728f1a77f239` (a second 4K remux, 65 Mbit/s,
  HDR10 without DV).

* **Overlay windows (four, the owner watching the panel).** A
  transparent page with a label over the native HDR video showed black
  three times; each time one opaque paint was removed: the root
  layout's and the WebView's XML black backgrounds, the theme's window
  background, and Chromium's base colour (set only by
  `WebView.setBackgroundColor` in code — the dark grey of the app's
  dark theme in the capture gave it away). The fourth showed the video
  under the label on the panel and in `screencap`, both layers
  `DEVICE`-composited, the video layer `BT2020_ITU_PQ`
  (`android-app` `6e2ea71`).
* **Audio research.** mpv's `ao_audiotrack` opens an `IEC61937` track
  for spdif formats; `--audio-spdif` takes `ac3, dts, dts-hd, eac3,
  truehd`; optical carries PCM 2.0, AC3 and the DTS core only; the
  owner's speakers are on optical. Untested on the panel.
* **Decisions taken with the owner** (Decisions made, 2026-10-22):
  full fidelity, native path, page as OSD, PGS unsupported.

**Step 1 — scope (2026-10-22, resumed session).** What the milestone
contains, with each desktop OSD feature's fate on the TV:

*In scope.*
1. **The native path.** `vo=mediacodec_embed` is the TV app's instance
   option; the surface callbacks set `vo` to it, never to `gpu`; mpv draws
   nothing on the TV. `input.conf`, the `keypress` door, `RemoteKeys` and
   the bundled scripts leave the TV build: nothing on the player reads a
   key or draws a pixel.
2. **The page stays over the video** during a viewing (`VISIBLE`,
   transparent, already verified) and the host's UI is the TV's OSD: a
   **viewing layer** rendered by the host into every page of a remote
   player's session, over a hidden app shell, while that player has a
   session. The host player never shows it: its mpv window draws its own
   OSD and covers the browser.
3. **The viewing layer's contents** — each a host-rendered surface fed by
   the host's own observation of the viewing:
   * *The bar* (replaces mpv's seek/pause OSD): title and episode line,
     position, duration, a progress bar, the paused state; shown while
     paused and for a few seconds after any key, hidden otherwise so the
     video is unobstructed.
   * *Skip Intro* (replaces `skip_intro.lua`): the same chapter-title rule
     (Intro, Opening, OP, Prologue; a next chapter exists), a pill
     bottom-right while the chapter plays; SELECT seeks to the next
     chapter.
   * *Next Episode* (replaces `next_episode.lua`): skip mode during a
     credits chapter at or after 80% with a successor queued, countdown
     mode in the last 20 s with a successor queued; SELECT is
     `playlist-next`. Auto-advance itself is unchanged (ADR-062, the
     host's).
   * *The track menu* (replaces `track_menu.lua`'s Audio and Subtitles
     columns): the viewing's audio and subtitle tracks from `track-list`,
     the active ones marked, "None" for subtitles; choosing sets `aid`/
     `sid` over the channel, which `OverrideCapture` already records as
     the profile's divergence. Bitmap subtitle tracks (PGS, VobSub, DVB)
     are listed as not supported on this TV and cannot be chosen; a file
     whose only subtitles are bitmap says so in the menu.
   * *Text subtitles* (new: mpv drew them on the desktop): the host
     observes `sub-text` and the page draws the current line at the
     bottom, plain text.
4. **Keys during a viewing** go to the page, never to libmpv: the page's
   input system handles them, the viewing layer's behaviour turns them
   into **playback commands** the host sends down the channel (pause,
   seek by ±10 s and ±60 s, next episode, track choice, stop). One
   routing rule, one owner; feedback is the bar re-rendered from the
   host's observation, with the pressed command reflected at once. Back
   closes the track menu when it is open, otherwise stops the viewing,
   as M4 verified.
5. **Per-viewing options on the long-lived libmpv** (open decision 5): the
   remote transport sends the viewing's session options with the
   `loadfile`, so each viewing starts from the host's option set and the
   player's instance carries nothing over; the appended successor carries
   the same set. Which options can ride on `loadfile` (`pause`,
   `keep-open`, the language policy, `script-opts`) is research item R1.
6. **The finish prompt and a real-length viewing on the TV**, deferred by
   M4, are this milestone's verification: the WebView now stays up, so the
   prompt simply renders when the session ends.
7. **Audio passthrough**: measured in research (R6); whether it is offered,
   and where, is a decision for the owner after the measurement.

*Dropped, with reasons.*
* mpv's volume OSD and `volume`: the TV's remote changes the system
  volume, which Android applies to the app's AudioTrack; mpv stays at 100.
* The Sound column (night mode, dialogue boost, the limiter, the `n` key)
  → **M6**: its per-folder memory and the limiter rule live in Lua on the
  desktop player and need a host-side owner before the TV can have them;
  nothing else in M5 depends on it.
* The pills' mouse hover and click: the TV has no pointer.
* The OSC: never enabled under the app.
* `osd-dimensions`-based scaling: the page's CSS scales the layer.

*Moved.* Sidecar subtitles (`sub-add` over the media endpoint) stay in
M6; the page's subtitle line renders them unchanged when they arrive.
The speed test stays open decision 3, M6. The WebView's 960×540 layout
scale and the pairing page's Code field stay M6, though the viewing
layer is designed at that scale from the start.

**Step 2 — research.** Items, each answered before the design pass:
* R1 per-file `loadfile` options on a long-lived mpv (desktop mpv 0.41
  over IPC): does `pause=no` unpause an instance `keep-open` left paused;
  is `keep-open=yes` as a per-file option still in force when
  `eof-reached` fires; do `alang`/`slang`/`sid` apply per file; is
  `script-opts` settable whole (replace) so recovery reads one profile id.
* R2 `sub-text` with no renderer: observe it on a desktop mpv with
  `vo=null` playing a file with a text track (proxy for
  `mediacodec_embed`), and whether `sid` changes still select tracks.
* R3 the session's door for commands: `Sessions` has `play`, `resume`,
  `stop`; the page needs pause, seek, next, track choice through the
  session so the transport stays the only IPC writer.
* R4 what the page can know: `PlaybackStateChanged` carries
  `now_playing`; the layer needs position, duration, pause, chapter
  state, tracks, `sub-text` at 1 Hz for one player — a per-player topic.
* R5 the input system's overlay model for the layer (flat MODAL vs
  `data-nav-overlay` regions), where the layer mounts (the root layout,
  since a viewing outlives any one page), and the media keys the WebView
  delivers (`MediaPlayPause`, `MediaFastForward`, …).
* R6 on the TV, one window: the WebView's cost over native 4K video
  (`dumpsys gfxinfo`, CPU), the LiveView round trip from the WebView and
  the channel round trip (the two halves of key-to-feedback latency), and
  `audio-spdif=ac3,dts` over the channel (`audio-out-params`, the
  `spdif passthrough not supported` log line).
* R7 the bridge's `PropertyFormat` table: `sub-text` is a string and
  `chapter` an integer, both already covered by its defaults.

**Step 2 — research record (2026-10-22).**
* R1 **answered, decision 5 (a) holds.** Desktop mpv 0.41 over IPC
  (`--idle --keep-open=yes`, a 14 s MKV with a text track and titled
  chapters): `loadfile <f> replace -1 pause=no,keep-open=yes,slang=eng,alang=eng,script-opts=media_centaur_session-profile_id=abc`
  starts unpaused on an instance `keep-open` left paused at the previous
  file's end; `keep-open` reads `yes` when `eof-reached` fires; `slang`,
  `script-opts` (whole, one key, readable for recovery) and `sid` apply
  while the file plays and are restored at `stop` (`slang []`,
  `script-opts {}`, `pause false`). An appended entry with its own
  per-file options plays them after `playlist-next`. So the remote
  transport sends every session option as per-file options on both the
  `replace` and the `append` `loadfile`, and nothing is set on the
  instance.
* R2 **answered.** With `vo=null` (no renderer, the desktop proxy for
  `mediacodec_embed`) `sub-text` property-change events carry each line
  as it is due and `""` between lines; `sid=no` makes it unavailable
  (a property-change with no `data`), `sid=1` resumes it. The bridge's
  `emitPropertyChange` already forwards a null `data`.
* R3 the session's only command doors are `play`, `resume`, `stop`; the
  observer sends `set_property sid` (enforcement), `loadfile … append`
  (auto-advance) and `quit`. The page's commands need one typed door
  through `Sessions` so the transport stays the only IPC writer; design
  item.
* R4 `PlaybackStateChanged` carries `now_playing` (names, position,
  duration) on the install-wide `playback:events` topic at state changes
  only; the layer needs a 1 Hz stream for one player. Design item: a
  per-player viewing topic.
* R5 the input system: a flat MODAL overlay is `[data-detail-mode='modal'] [data-nav-item]`
  from `Components.Modal` (always in the DOM, `data-state`), BACK pushes
  its `data-dismiss-event`; regions need `data-nav-overlay` and a
  `config.overlays` entry. The page's key map is `keyboard.js`'s
  `keyToAction`; the WebView delivers media keys as DOM keys
  (`MediaPlayPause`, `MediaFastForward`, `MediaRewind`), which the key
  map does not know yet. The layer mounts once in the root layout, as
  the gamepad hint bar does, so it outlives page navigation.
* R6 **measured on the Sony, three windows** (`mc-tv` + `mc-sim-host`,
  the 4K DV remux on `mediacodec_embed`):
  * Round trips: host → channel → libmpv → host 2.7–7.4 ms (eight
    `get_property` requests); the WebView's LiveView socket heartbeat
    2.0–4.4 ms. A key's path page → host → channel → mpv → host → page is
    therefore ≈10 ms plus render; no local shortcut is needed.
  * The WebView's cost over playing native 4K HDR video, `dumpsys gfxinfo`
    and `top` over 10 s each: page cleared, **app 35 % CPU** (mpv's decode
    and the bridge), SurfaceFlinger 6 %; a static OSD bar, 0 page frames,
    app 30 %, SF 7 %; the bar ticking at 1 Hz with a subtitle line
    changing every 2 s, 10 page frames at 8–9 ms, app 33 %, SF 7 %; a
    continuous 60 fps transform animation, 487 frames, **26 % janky at
    48 ms**, app 65 %, SF 19 %. `frame-drop-count` stayed 0 in every
    phase: the video never suffers, the page does. Rule for the design:
    the layer changes at most once a second and animates nothing
    continuously (a short opacity fade is the ceiling).
  * `audio-spdif=ac3,dts` set before `loadfile` of the DTS-HD MA file:
    mpv selected `spdif_dts` and **playback stalled** (`time-pos` fixed
    at the resume position for 90 s, `current-ao` and
    `audio-out-params` unavailable, no video advance); the TV's own log
    said `PassThroughMode = Off`. The binding logs nothing from the AO,
    so the refusal is inferred. Without the option: `audiotrack`, `s16`,
    6 channels. Owner item: set the Sony's digital audio output to
    passthrough/auto and retest; until then passthrough is not offered.
  * The long-lived instance kept `audio-spdif` across `Sessions.stop`
    and a second `play` (the second window froze the same way until
    the process was restarted): a `set_property` over the channel is
    install-wide for the player's life. Decision 5 (a) covers the
    session's options; the rig's `--set` must be used knowing this.
  * `mc-tv launch` on a running app does not reload the page (window 2
    carried window 1's injected elements); `mc-tv stop` first for a
    clean page.
* R7 confirmed from `PropertyFormat.kt`: `chapter` is in `longs`,
  `sub-text` falls to the string default.
* App change made for the measurement and kept: `MainActivity.onViewingChanged`
  no longer hides the WebView (`android-app`, this session's commit).

**Step 3 — decisions.** Taken here with the scope's reasoning, each
reversible at the plan:
* Keys during a viewing go to the page (scope item 4). Measured cost
  ≈10 ms; one owner. → open decision 6 for the owner's confirmation,
  recommendation: the page.
* Decision 5: (a), per-file options on every `loadfile`, confirmed by
  R1. Moved to Decisions made.
* The Sound column and sidecar subtitles stay M6; audio passthrough is
  not offered until the owner's retest (R6). → open decision 7.
* The viewing layer renders only for a remote player's session (scope
  item 2); the host player's page never shows it.
* The layer changes state at most once a second and does not animate
  continuously (R6).

**Step 4 — design unification (2026-10-22, `unify_design`).**

*Core idea, one sentence.* **A viewing is observed and commanded by the
host through one session, and a player that draws nothing gets its
on-screen state drawn by the host's page from that same session** — the
page is one more reader of the session, never a second controller.

*Greenfield shape.*
1. **`Playback.Viewing`** — one value type, the state of one viewing as
   a reader needs it: `player`, `entity_id`, `profile_id`, the title
   words (`entity_name`, `season_number`, `episode_number`,
   `episode_name`), `content_url`, `position_seconds`,
   `duration_seconds`, `paused?`, `chapters` and the current `chapter`
   index, `audio_tracks` and `subtitle_tracks` (each with `id`, `lang`,
   `title`, `codec`, `bitmap?`), `aid`, `sid`, `successor_queued?`,
   `subtitle_text`, `state` (`:playing | :paused | :detached`) and the
   derived **prompt**: `nil`, `:skip_intro`, `:next_episode` or
   `{:next_episode_in, seconds}`. Built by `MpvSession` from its state
   (`Viewing.from_session/1`); the prompt rules are pure
   (`Viewing.prompt/1` over `Playback.Completion`'s credits words and a
   new `Playback.IntroChapter` with the intro words).
2. **The viewing stream** — `Playback.subscribe_viewing(player)` on topic
   `playback:viewing:<player>`, message `{:viewing, %Viewing{}}` on
   every discrete change (pause, chapter, tracks, subtitle line,
   prompt) and on position at most once a second; `{:viewing_ended,
   player}` when the session finalises. Uniform for both players; the
   host player's stream simply has no subscriber today.
3. **`Playback.Command`** — the typed vocabulary a reader sends back:
   `:toggle_pause`, `{:seek, ±seconds}`, `:activate_prompt` (the
   prompt's action, judged by the session: a seek to the chapter after
   the intro, or `playlist-next`), `{:select_track, :audio | :subtitle,
   id | :none}`, `:stop`. Door: `Playback.command(player, entity_id,
   command)` → `Sessions.command/3` → the session, which renders the
   IPC and sends it through its transport. The page never composes IPC.
4. **The transport owns how its mpv loads a file**: `Transport.loadfile/4`
   (`locator`, `start`, `:replace | :append`) returns the command.
   `Local` renders today's forms (`--{ --start=N url --}` at launch,
   `loadfile url append -1 start=N` for the successor; the process
   carries the session options). `Remote` renders every session option
   plus `start` as per-file options on both forms, as one `%n%`-quoted
   key-value string (`LaunchFlags.per_file_options/2`; the bridge can
   only pass strings, R1/lab 2). `Transport.draws_subtitles?/1`: `Local`
   true, `Remote` false. `LaunchFlags.session_options/1` gains
   `{"pause", "no"}`; `script-opts-append` renders per file as
   `script-opts=<value>` on a remote (no user config to append to).
5. **The viewing layer** — `MediaCentaurWeb.Live.ViewingAware`, an
   `on_mount` in `live_session :default` after `PlayerAware`: for a
   remote player it subscribes to that player's viewing stream and
   assigns `:viewing` (nil or the struct) and the layer's own UI state
   (`:viewing_bar` shown-until, `:viewing_menu` open?), attaching
   `handle_info` and `handle_event` hooks; `Layouts.app` renders
   `Components.ViewingLayer` from those assigns on every page, so a
   viewing recovered while the page is on Settings still has its OSD.
   The host player gets no assign and no layer. The layer's root carries
   `data-viewing`; CSS hides the app shell beneath it and makes the body
   transparent (`body:has([data-viewing])`).
6. **Components.ViewingLayer** (function components with stories):
   `viewing_bar/1` (title and episode line, position, duration, the
   progress bar from the kit's recipe, the paused glyph), `viewing_prompt/1`
   (the pill: a `<.button variant="primary">` with its label and the
   SELECT hint, bottom-right), `viewing_subtitle/1` (the line, plain
   text, `.text-on-image`), `viewing_track_menu/1` (a glass panel of
   two `GlassMenu.menu_list` columns, Audio and Subtitles, the active
   entry a `menuitemradio`, bitmap tracks disabled with "Not supported
   on this TV", "None" first in Subtitles). The bar is shown while
   paused and for 4 s after any command (a LiveView timer); prompts and
   the subtitle line whenever their condition holds; nothing animates
   continuously (decision, R6).
7. **Keys** — the input system is the one pipeline. The layer is the
   active overlay (`data-detail-mode="modal"`, `data-dismiss-event="viewing_back"`);
   the track menu, when open, is a second overlay rendered first in DOM
   order with `data-dismiss-event="viewing_menu_close"` and the regions
   `viewing_audio` / `viewing_subtitles` (`data-nav-overlay="viewing_menu"`,
   MENU contexts with left/right edges). A **viewing behaviour**
   (`viewing_behavior.js`) composed over the page's behaviour while
   `[data-viewing]` is present — the `withWipNotice` decorator is the
   precedent — maps actions in the bar state: LEFT/RIGHT → `{:seek, ∓10}`,
   UP/DOWN → `{:seek, ±60}`, SELECT → `:activate_prompt` when a prompt
   is focused (the pill is the modal's one nav item, so the orchestrator's
   activate does it), else `:toggle_pause`; the media keys the WebView
   delivers (`MediaPlayPause`, `MediaPlay`, `MediaPause`,
   `MediaFastForward`, `MediaRewind`, `ContextMenu`) join the key map as
   actions (`PLAY_PAUSE`, `SEEK_FORWARD`, `SEEK_BACK`, `MENU`). With the
   menu open the behaviour steps aside and MODAL navigation runs. BACK
   is containment as always: the menu closes, else `viewing_back` stops
   the viewing. The hook's `pushEvent` is the behaviour's door (as
   `play` is today). Gamepad works for free.
8. **The TV app**: `vo=mediacodec_embed` as the instance option and in
   `surfaceCreated`; `android-surface-size` dropped (GPU path only);
   `input-conf`, the scripts package and `Assets.sync`, `RemoteKeys`,
   `keypress` and the viewing branch of `dispatchKeyEvent` removed —
   every key reaches the WebView, Back is `shell.back()` always, and
   `Player.stop()` is called only by the bridge's `quit`.

*Diff against reality.*
* (a) Seams used as they are: `Transport` (two callbacks added),
  `Playback.Events` and MC0012, `Subscriptions`, the `PlayerAware`
  on_mount pattern, `Components.Modal`'s overlay contract, the
  behaviour decorator, `LaunchFlags` pairs, `OverrideCapture` (a track
  chosen in the menu arrives as a `sid` change and is captured as a
  keypress would be), `TrackResolver` enforcement.
* (b) Unified: `PlaybackStateChanged.now_playing` (a loose map built by
  `build_now_playing/1`) and the new viewing state are one idea →
  `now_playing` becomes a `%Viewing{}`, map-matched by its three readers
  (Status's playback widget, `StatusHelpers`, `LiveHelpers.apply_playback_change`)
  under the same keys. The TV's `input.conf` and the page's key map
  were two owners of one key → the player's bindings go. The intro and
  credits chapter words exist in Lua (`skip_intro.lua`,
  `next_episode.lua`) for the desktop mpv and in Elixir for the host
  (`Completion` today, `IntroChapter` new): the Lua must stay (it runs
  inside the desktop's mpv), so this is a **deliberate duplication**
  held equal by a test that reads both Lua pattern lists and asserts
  them against the Elixir words.
* (c) Decided: `NextEpisode.loadfile_command/1` composes IPC for one
  transport → replaced by `Transport.loadfile/4` (fix now). `Transport.Remote.open/2`
  sends `set_property` per option onto the long-lived instance →
  per-file options (fix now; ADR-080, `docs/mpv.md`, `docs/playback.md`
  and the protocol spec say `set_property` and are amended in the
  plan). The spec's boundary row "Local input: TV app" and "the bundled
  scripts ride along" → amended: keys go to the page, the TV build
  ships no scripts. `MpvSession` sends `quit` on `eof-reached` → stays
  (on a remote it is stop). `sid` enforcement may pick a bitmap track on
  a player that cannot draw it → `TrackResolver` receives only the
  tracks the transport can draw (fix now).

*Coherence cost, named.* Promoting `now_playing` to `Viewing` touches
three readers and their tests; the viewing behaviour, two overlay
regions and four key-map actions are new input-system surface with
their bun tests; the Lua-pattern sync test is small. No part of this is
owner-gated; the owner's calls are open decisions 6 and 7.

**Step 5 — implementation plan (2026-10-22).** Five stages, each
leaving the host working and `agent-mix precommit` green; test-first
throughout (`automated-testing`); stories land with their components
(`storybook`). Nothing merges; the branch stays unpushed.

*Stage 1 — host: the viewing type, the stream, the commands, the
transport's loadfile.* Files: `lib/media_centaur/playback/viewing.ex`
(struct, `from_session/1`, `prompt/1`, `@bitmap_codecs`),
`intro_chapter.ex` (the intro words, `skip_target/2`), `command.ex`
(the typed vocabulary), `playback.ex` (`command/3`,
`subscribe_viewing/1`), `sessions.ex` (`command/3`), `events.ex`
(`now_playing` typed as `Viewing.t()`; the viewing stream's two
messages documented under MC0012), `mpv_session.ex` (observe
`sub-text` 12 and `chapter` 13; fold `subtitle_text` and `chapter`;
`Viewing.from_session/1` in place of `build_now_playing/1`; the 1 Hz
position throttle `last_viewing_at`; `handle_cast({:command, _})`
rendering IPC; `handle_track_list_update` hands `TrackResolver` only
the tracks the transport draws; `queue_next` through
`Transport.loadfile/4`), `transport.ex` (`loadfile/4`,
`draws_subtitles?/1`), `transport/local.ex` and `transport/remote.ex`
(their renderings; `Remote.open/2` sends one `loadfile` with per-file
options and no `set_property`), `launch_flags.ex`
(`per_file_options/2` with `%n%` quoting, `{"pause", "no"}` in
`session_options/1`), `next_episode.ex` (`loadfile_command/1`
removed). Readers of `now_playing` move from `[:key]` to `.key`
(`components/status_widgets/playback.ex`, `live/status_helpers.ex`,
`live/status_live.ex`). Tests: `viewing_test.exs`,
`intro_chapter_test.exs`, `command_test.exs`,
`chapter_words_lua_sync_test.exs` (parses `skip_intro.lua` and
`next_episode.lua` pattern tables, asserts the Elixir words),
`launch_flags_test.exs` (per-file string, quoting, `pause=no`),
`transport/remote_test.exs` and `local_test.exs` (`loadfile/4`),
`mpv_session_test.exs` with the fake transport (commands → IPC, the
stream's cadence, bitmap tracks never enforced on a remote, the
`append` with options), the `now_playing` readers' tests. Check:
`mc-player-sim` end to end on the sim host — a viewing starts
unpaused after a previous `eof`, `script-opts` reads back one profile
id, `Playback.command/3` pauses, seeks and switches a track.

*Stage 2 — web: the viewing layer.* Files: `live/viewing_aware.ex`
(on_mount after `PlayerAware` in `router.ex`'s `live_session :default`:
assigns `:viewing`, `:viewing_bar_until`, `:viewing_menu`; `handle_info`
for `{:viewing, _}`, `{:viewing_ended, _}`, `:viewing_bar_hide`;
`handle_event` for `viewing_command` (`command`, `seconds`),
`viewing_prompt`, `viewing_track` (`kind`, `id`), `viewing_menu_open`,
`viewing_menu_close`, `viewing_back`), `components/viewing_layer.ex`
(`viewing_layer/1` composing `viewing_bar/1`, `viewing_prompt/1`,
`viewing_subtitle/1`, `viewing_track_menu/1`; the bar's progress from
the kit's recipe, the pill a `<.button variant="primary">`, the menu two
`GlassMenu.menu_list`s), `storybook/viewing_layer.story.exs` (playing,
paused, each prompt, a subtitle line, the menu with a bitmap track
disabled, a PGS-only file), `components/layouts.ex` (`attr :viewing`,
rendered after the overlays slot) and the fourteen `<Layouts.app>`
call sites passing `viewing={@viewing}` beside `profile`, `app.css`
(`.viewing-layer`, `body:has([data-viewing])` transparent, the shell
hidden). Input system: `core/actions.js` (`PLAY_PAUSE`,
`SEEK_FORWARD`, `SEEK_BACK`, `MENU`; `MediaPlayPause`, `MediaPlay`,
`MediaPause`, `MediaFastForward`, `MediaRewind`, `ContextMenu`),
`viewing_behavior.js` (`withViewing(behavior, {pushEvent})`: bar-state
mapping, steps aside while `[data-nav-overlay="viewing_menu"]` is
present), `page_behavior.js` (the registry wraps when the reader sees
`[data-viewing]`; `_detectBehavior`'s key becomes name plus the
viewing flag so the wrap attaches and detaches with the layer),
`config.js` (`overlays.viewing_menu` with `viewing_audio` /
`viewing_subtitles` MENU regions, their selectors, start priority),
`core/dom_adapter.js` (`hasViewing()`). Tests: `viewing_behavior.test.js`,
`config_coverage.test.js`, nav-graph region tests, `viewing_aware_test.exs`
(a device socket with a viewing renders the layer, the host socket
never; each event reaches `Playback.command/3`; BACK with the menu
open closes it, else stops), `layouts_test` for the attr, the story in
`storybook_render_test`. Check on the desk, no TV: pair a headless
Chromium with the sim host from the LAN address (`mc-sim-host pairing`
→ the code typed on `/pair`), bridge a desktop mpv with
`mc-player-sim` for that player, `Playback.play/3`, then `mc-nav-trace`
and `page-shot` against the paired page: the layer over a transparent
body, arrows seek, SELECT pauses, the prompt appears on the lab MKV's
intro chapter and SELECT skips it, MENU opens the menu and BACK closes
it, BACK stops.

*Stage 3 — the TV app.* Files: `player/Player.kt` (`vo` →
`mediacodec_embed` in the instance options and `surfaceCreated`;
`android-surface-size`, `input-conf`, `script` and the assets sync
removed; `keypress` removed), `player/RemoteKeys.kt` and
`player/Assets.kt` and `assets/mpv/` deleted, `shell/MainActivity.kt`
(`dispatchKeyEvent`: Back → `shell.back()` when the page is shown,
everything else to the WebView; the viewing branch removed),
`README.md` and `docs/playback-on-android.md` (the key path, the
native path as the default). Tests: the JUnit set unchanged in intent;
any test of `RemoteKeys` goes with it. Check: `mc-tv build`,
`mc-tv install`.

*Stage 4 — verification on the TV* (`mc-tv-flow osd`, new; each a
short window ending with `mc-tv hdmi`), after the sim host's E01/E02
are regenerated with titled chapters (Intro, Story, Credits), a text
track and, for one file, a `dvdsub` bitmap track, and the library
rescanned: (1) play E01 — the bar appears paused/on key and hides, LEFT
seeks, SELECT pauses and resumes, the subtitle line renders; (2) the
Skip Intro pill at the intro chapter and SELECT skipping it; (3) the
Next Episode countdown in E01's last 20 s, SELECT advancing, then
auto-advance to E02 without a key; (4) the track menu on MENU, a
subtitle chosen, the bitmap track disabled with its words, BACK
closing the menu; (5) BACK stopping the viewing with the page
restored; (6) the finish prompt at the chain's end; (7) the real-length
check, one longer window agreed with the owner: the 4K remux seeked
to its last minutes, left to end, the finish prompt opening.

*Stage 5 — records and docs.* ADR-080 amended (per-file options on a
remote, the command door, `Transport.loadfile/4`); a new UIDR, *A
remote player's OSD is the host's page* (the layer, its contents, the
1 Hz rule, the key path, bitmap subtitles unsupported); the protocol
spec amended (keys to the page, no scripts on the player, per-file
options, the viewing stream); `docs/playback.md`, `docs/mpv.md`
(the remote rendering of each row); wiki `Playback.md` (a section for
the TV), `Keyboard-and-Gamepad.md` (the remote's keys during a
viewing), `Troubleshooting.md` (bitmap subtitles on the TV; audio
passthrough off), committed locally, unpushed; `decisions/README.md`
regenerated. Open decisions 6 and 7 stay listed for the owner.

**Step 6 — plan unification (2026-10-22, `unify_design` on the plan).**
Checked against the ways plans fail: no old path is kept — `set_property`
per option, `NextEpisode.loadfile_command/1`, the TV's `input.conf`,
`RemoteKeys` and `keypress` all leave in the stage that replaces them;
no constant is copied — the intro and credits words have one Elixir
home each and the Lua lists are held equal by a test; every caller
converts — all three `now_playing` readers in stage 1, all fourteen
`<Layouts.app>` sites in stage 2 (the same idiom `profile` already
uses, so no new mechanism); no shim — the fake transport gains
`loadfile/4` like the real ones; no stand-in encodes the old shape —
`mpv_session_test` asserts the per-file `loadfile`, not a
`set_property` sequence. One finding: `SessionRecovery.recover_player/1`
reads `script-opts` for the profile, which per-file options make
readable only while a file plays — exactly when recovery runs (R1), so
no change. **Amendment from the owner (this session): the layer's
layout and controls are not settled by the plan — they go to the owner
as a mockup round before stage 2 is executed**, and stage 2's component
list follows what the owner picks. Execution has not started.

**Step 7 — execution.**
* *Stage 1 (host) — built 2026-10-22, evening.* `Playback.Viewing`
  (one shape for `now_playing` and the stream, with the prompt judged by
  `Viewing.prompt/1`), `Playback.IntroChapter`, `Playback.Command` and
  the door `Playback.command/3` → `Sessions.command/3` →
  `MpvSession.command/2` (a cast, rendered against the current prompt);
  the per-player viewing stream (`Playback.subscribe_viewing/1`,
  `Topics.playback_viewing/1`, `Events.broadcast_viewing/1`,
  `Events.ViewingEnded`), streamed on attach, on each discrete property
  and on position once a second; `sub-text` and `chapter` observed;
  `Transport.queue/3` and `Transport.draws_subtitles?/1` (Local: the
  old append, true; Remote: the same per-file options, false);
  `LaunchFlags.per_file_options/2` with `%n%` quoting and
  `script-opts-append` → `script-opts`, `{"pause", "no"}` in the
  session options; `Transport.Remote.open/2` sends one `loadfile` and no
  `set_property`; `NextEpisode.loadfile_command/1` removed; the
  resolver sees only drawable subtitle tracks and a bitmap-only file
  gets `sid=no`; `Track.codec`; the three `now_playing` readers read
  with `Map.get`. Tests: `viewing_test`, `intro_chapter_test`,
  `command_test`, `chapter_words_lua_sync_test` (parses both Lua
  tables, the floor and the window), `launch_flags_test`,
  `transport/remote_test`, `mpv_session_transport_test` (commands,
  the stream's cadence, bitmap enforcement), `sessions_test` updated;
  the `next_episode_test` cases for the removed function went with it.
  Records: ADR-080 amended (3a, 8–10), `docs/playback.md`,
  `docs/mpv.md`. **End to end on the sim host with `mc-player-sim`
  (a headless desktop mpv):** the prompt reads `{:skip_intro, 4.0}` on
  the lab file's intro chapter and `:activate_prompt` seeks past it;
  `:toggle_pause` pauses and resumes; `script-opts` reads back one
  profile key; the subtitle line streams; the file's end ends the
  session and the instance's `pause` reads false after it; a second
  viewing starts playing on the same long-lived mpv. Found on the way,
  for M6: a relative seek past the end leaves mpv paused on the last
  frame with no `eof-reached`, so the viewing does not end until Back —
  the host should clamp a seek to the duration, or treat paused-at-end
  as the end.
* *Stage 2 (web) — built 2026-10-22, evening.* `Live.ViewingAware`
  (on_mount after `PlayerAware`; subscribes to the player's stream through
  `Subscriptions`, which now takes `{module, function, args}`; seeds the
  layer from `Sessions.list/0`; hooks for the stream and the layer's six
  events; a 4 s bar timer), `Live.ViewingAware.Logic` (the layer's state
  transitions, the payload parsers), `Components.ViewingLayer`
  (direction 3: scrim, title and episode line, seek bar with chapter
  ticks and handle, clocks, the paused state and centre glyph, the prompt
  pill as the one nav item, the subtitle line, the track menu as two
  `GlassMenu.menu_list` columns in a centred glass modal rendered before
  the OSD so it is the active overlay while open; `menu_list` gained a
  `disabled` item), its story (nine states at 960×540) and index,
  `Layouts.app`'s `viewing_layer` attr on all fourteen pages, the CSS
  (the html and body transparent and the shell hidden under a viewing;
  only opacity transitions), the input system (`PLAY_PAUSE`,
  `SEEK_FORWARD`, `SEEK_BACK`, `MENU` and the WebView's media keys;
  `viewing_behavior.js` wrapping the page's behaviour while
  `[data-viewing]` is present, keyed in `_detectBehavior`; the reader's
  `hasViewing`/`isViewingMenuOpen`; the `viewing_menu` overlay regions
  as MENUs). Tests: `viewing_aware_test` (the host never draws it; a
  device draws, updates from the stream, hides at the end; commands
  reach the player as IPC; the menu opens and Back closes it first, then
  stops), `viewing_aware/logic_test`, `viewing_behavior.test.js`, the
  menu-list story's disabled variation. **Checked on the desk, no TV:**
  `_cdp.js` learned `MC_COOKIE` (a paired device's session cookie, the
  value `mc-player-sim` prints), so `page-shot` and `mc-nav-trace` see
  the page as the device: over a transparent body the layer showed the
  Skip Intro pill with its focus ring, the pause glyph, the subtitle
  line lifted above the bar, and the bar with the title, PAUSED, the
  amber fill, chapter ticks and both clocks; Left, Right and Enter
  arrived at the simulator's mpv as `seek -10`, `seek 10` and
  `cycle pause`; Escape (Back) arrived as `quit` and the session ended.
  The menu's keys are covered by the behaviour's unit tests only until
  the TV check.
* *Stage 3 (the TV app) — built 2026-10-22, evening* (`android-app`
  `8ca4f32`, then `066bf70`): `vo=mediacodec_embed`
  as the instance option and on surface creation, `android-surface-size`
  dropped, `input-conf`, the scripts package, `Assets.sync`, `RemoteKeys`,
  `keypress` and the `CopyBundledScripts` Gradle task removed, every key
  to the WebView, Back forwarded as Escape; then (`066bf70`) `Shell.kt`
  forwards Menu as `ContextMenu`, a debug build sets `LOAD_NO_CACHE`, and
  `MainActivity.dispatchKeyEvent` routes Back and Menu. Built and
  installed on the Sony.
* *Stage 4 (the TV) — done 2026-10-22, evening, in two sittings.*
  Rig: `mc-tv-flow osd tv [out-dir]` (resets progress, plays E01 from
  the start, screenshots each state, prints the player's drop counters
  after each viewing; E01/E02 in the sim host carry chapters Intro
  0–8 s, Story, End Credits 75–90 s and an English SRT track; the lab
  film `Sample Lab Film` is staged, 14 s, intro/story/credits, SRT);
  `mc-tv ui` reads a screen as text; `mc-tv eval` answers in 0.2 s now
  (`_cdp.js` kept node alive for the full 30 s request timeout after
  every answer, so each evaluation cost 30 s of the owner's screen).
  *First sitting* verified the layer over native video (both layers
  `DEVICE`-composited), the Skip Intro pill and the subtitle line, the
  bar with the title, episode line, chapter ticks and clocks hidden
  after 4 s with the opacity fade, LEFT as `seek -10`, auto-advance
  E01 → E02 with the page staying up, the finish prompt at the lab
  film's end; and found the first five faults, fixed between sittings:
  (1) the WebView cached the dev host's `app.js` → `LOAD_NO_CACHE` in
  debug builds; (2) a second `play` on the player ran two sessions over
  one channel → `Sessions.play/2` replaces the running viewing; (3)
  `loadfile replace` on a loaded file reported the old file's `end-file`
  as `eof` → `Transport.Remote` drops an end-file before its own
  `start-file`; (4) the orchestrator never attached the viewing
  behaviour when the layer arrived by push → `_detectBehavior` on every
  source action; (5) the user's key bindings hid the media and menu keys
  → `VIEWING_KEY_MAP` fallback. *Second sitting* (a resumed session)
  ran the check with those fixes: arrows and DOWN seeked, SELECT, MENU
  and BACK did nothing. Traced on the TV page with a capturing keydown
  recorder, a `window.onerror` hook and the input system's debug trace
  (`mc-tv eval` installs them; the page keeps them across LiveView
  patches), five more faults, each with a failing test first: (6) the
  shell dispatched Back and Menu on the document, whose target has no
  `closest` → the keyboard source threw before the key was seen →
  the shell targets the focused element (`android-app` `3df9251`); (7)
  `createPageBehavior` handed `withViewing` no `hasPrompt` → SELECT threw
  `deps.hasPrompt is not a function` → the factory passes every dep
  (`page_behavior.test.js`, new); (8) the cursor start seeded the page
  beneath the layer when the modal was empty (the pill streams in after
  the layer) and the context stayed on Home's shelf → an open overlay
  keeps the cursor, the reconciler focuses a flat overlay's item when it
  appears; (9) the track menu opening over the OSD was no presentation
  change, so its entry never resolved and the cursor fell on the active
  audio track → the active overlay is known by name and a change of name
  is an open; (10) closing the menu took the flat dismiss path, which
  expects no overlay at all and blinded the sync while the OSD stayed
  → the menu is `data-detail-nested` in the OSD's overlay. Then the
  flow itself was wrong once: after a seek back to 0 the pill returns
  and SELECT takes it (by design), so the pause check seeks forward.
  **Verified on the Sony, the whole check green** (captures in the
  session's scratch `osd3/`, gone with it; the facts stand): play →
  pill; SELECT skips to 8 s; SELECT pauses (PAUSED, centre glyph, amber
  fill); RIGHT seeks to 18 s paused; SELECT resumes; MENU opens the menu
  on Subtitles/None with its focus ring; DOWN, SELECT picks English
  (`sid=1`, the subtitle line streams "Sample line at 24 s"); BACK closes
  the menu; the countdown pill at 80 s with the subtitle line lifted;
  auto-advance to E02 at 7 s with E02's own pill; BACK ends the session
  and the page is back; the lab film plays to its end and the finish
  prompt opens. `DROPS:` after E01 and E02: `frame-drop-count=0
  decoder-frame-drop-count=0 vo-delayed-frame-count=0`; the lab film's
  read came back `?` at 11.4 s of 14 (the request raced the file's end;
  read earlier next time). Patch rate measured with a `MutationObserver`
  over 4 s windows: Home idle 0, viewing ≈1 batch/s of ≈8 mutations (the
  1 Hz tick, bar shown or hidden), after the viewing 0. One unexplained
  burst seen once in a probe: ≈10 syncs/s for a second on Home with the
  finish prompt open after a SELECT on its Delete button; not
  reproduced, noted for M6. **Owner items for M6:** the TV's UI scale a
  little smaller (per-device, the existing scale preference); a seek
  past the end leaves mpv paused on the last frame with no `eof-reached`
  (clamp the seek to the duration, or end on paused-at-end); the lab
  film must play ≥10 s continuously for completion (the tracker's rule),
  which the finish check now does; the bar's DOM is patched at 1 Hz
  while hidden (cheap, but the hidden bar could skip its clock).
* *Stage 5 (records and docs) — done 2026-10-22.* UIDR-055, *A remote
  player's OSD is the host's page* (the layer and its parts, the 1 Hz
  rule, keys to the page, the menu as the page's and nested, text
  subtitles only; anti-patterns), `decisions/README.md` regenerated;
  the protocol spec amended (the Boundaries row for local input, the
  `player` row, launch, the viewing stream, the shell's forwarded keys);
  `docs/mpv.md` says for each of the three scripts what the remote
  player shows instead; `docs/playback.md` already carried the viewing
  and the command door from stage 1; the input-system doc and skill
  carry the overlay rules from stage 4. Wiki, committed locally and
  unpushed (`de4868e`, after M1's `9df804c`): `Playback.md` *On a
  paired TV*, `Keyboard-and-Gamepad.md` *On a paired TV (during
  playback)* with the remote's keys as they stand (open decision 8 may
  change the menu key), `Troubleshooting.md` *Playback on a TV* (image
  subtitles, no surround passthrough). ADR-080 was amended in stage 1.

### M4 — TV app skeleton (procedure record)

**1. Scope (2026-10-22).** In, all in `~/src/media-centaur/android-app`:
the host-address screen (the one native screen: the app knows nothing
until it has an address); the WebView shell loading the host, which
sends an unpaired device to its own pairing page and home after a
match; the cookie jar shared between the WebView and the channel; one
libmpv instance on a `SurfaceView` for the app's life, shown while a
file plays; the bridge (OkHttp WebSocket ⇄ `MPVLib`): IPC JSON in,
typed libmpv calls out, property events and replies back, `time-pos`
at 1 Hz, reconnect with backoff; the remote's keys routed to whichever
is on screen (the page, or mpv as `keypress`); the TV's own
`input.conf`; the host's bundled scripts package in assets; logging
under `MediaCentaur` and `mpv`; `mc-tv webview`. Exit: on the Sony,
pair, browse, play one file, see progress on the host, auto-advance an
episode, stop from the finish prompt. Dropped: an error page for an
unreachable host beyond a retry (M5 polish). Moved to M5: sidecar
subtitles, HDR and audio passthrough options, detach/reattach and
host-restart on the device, Back-key and D-pad polish, WebView cost,
removed-player close, Home's rows by player. To M6: release signing,
Play, the wiki page, the glossary, the app icon and banner art.

**2. Research (2026-10-22), against the host branch and the libraries.**
* The host sends a remote player, in order: `set_property` for each
  session option (`keep-open=yes`, `resume-playback=no`, the language
  options), `change-list script-opts append media_centaur_session-profile_id=<id>`,
  then `loadfile <media url> replace [-1 start=<s>]`; then
  `observe_property` ids 1–10 for `time-pos`, `duration`, `pause`,
  `eof-reached`, `track-list`, `aid`, `sid`, `chapter-list`,
  `playlist-count`, `playlist-pos`; `quit` to end a viewing; recovery
  asks `get_property` `path`, `time-pos`, `script-opts` with a
  `request_id` and expects `script-opts` **as a map** (`session_profile/1`
  rejects anything else). `Transport.Remote` ends the viewing on
  `end-file` whose `reason` is `stop` or `quit`; `MpvSession` sends
  `quit` on `eof-reached=true` and finalises on any `end-file`.
* `MPVLib` 1.0.0 (verified from `MPVLib.kt` and `event.cpp`): instance
  API; `command(Array<String>)` returns nothing; typed get/set;
  `observeProperty(name, format)` with no id; property events arrive
  as `eventProperty(name)` (NONE), `(name, Long)`, `(name, Double)`,
  `(name, Boolean)`, `(name, String)`; any other format is dropped in
  the JNI layer. **`event(eventId)` carries only the id: the `end-file`
  reason is not forwarded.** Log messages arrive through `LogObserver`.
* mpv renders node properties (`track-list`, `chapter-list`) as JSON
  text when read as a string, and key-value lists (`script-opts`) as
  `k=v,k=v`. The bridge therefore needs per-property rendering rules:
  JSON text → parsed JSON; `script-opts` → object; scalars typed.
* mpv-android's `BaseMPVView` (the libmpv reference): before `init`:
  `config=yes`, `config-dir`, `force-window=no`, `idle=once`; `vo` set
  separately (`gpu` or `gpu-next`); `surfaceCreated` → `attachSurface`,
  `force-window=yes`, `vo` restored; `surfaceChanged` →
  `android-surface-size=WxH`; `surfaceDestroyed` → `vo=null`,
  `force-window=no`, `detachSurface`. `MPVView.initOptions`:
  `gpu-context=android`, `opengl-es=yes`, `hwdec=mediacodec,mediacodec-copy`,
  `hwdec-codecs=h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1`,
  `ao=audiotrack,opensles`, `input-default-bindings=yes`,
  `demuxer-max-bytes`, `demuxer-max-back-bytes`.
* The bundled scripts bind keys: a visible pill forces `enter`
  (activate) and the track menu offers `TAB` (open) and `n` (night
  mode), overridable by `input.conf`. Keys reach libmpv only as
  `keypress <name>` commands the app sends, so the app owns the
  remote-to-mpv mapping. mpv's own default binds `ENTER` to
  `playlist-next`, which a remote's centre button must not do.
* The input system maps `Escape` to `BACK` (`actions.js`) and runs the
  page's back semantics from it (UIDR-028), so a native Back becomes a
  synthetic `Escape` keydown in the page. The WebView delivers D-pad
  keys as arrow keys and `Enter`; verified on the Sony at the start of
  execution (the spec's open item).
* The pairing flow needs nothing native: `GET /` on an unpaired device
  is a 302 to `/pair`, the form posts `pairing[name]`, `pairing[code]`
  with a CSRF token, and a match redirects to `/` with the session
  cookie `_media_centaur_key` carrying `player_id`. The cookie jar is
  `android.webkit.CookieManager`; OkHttp reads it through a `CookieJar`.
* The Sony is 32-bit (`armeabi-v7a`); libmpv 1.0.0 ships that ABI;
  `hwdec=mediacodec` is the decode path on it.

**3. Decisions (2026-10-22).**
* Three packages under `app.mediacentaur.tv`, after the spec's modules
  with `pairing` folded into the shell: `shell` (the activity, the
  host-address screen, the WebView, key routing), `player` (the one
  `MPVLib`, the surface, instance options, the local input policy),
  `bridge` (the channel: WebSocket, IPC ⇄ libmpv, rendering rules,
  reconnect). The app's state is the host address (`SharedPreferences`)
  and the cookie jar; nothing else persists.
* The bridge synthesises the `end-file` reason the binding drops:
  `stop` when the bridge itself issued `stop` since the last `loadfile`
  (the host's `quit`, or Back on the remote), `eof` when `eof-reached`
  was true, `error` otherwise. Spec amendment recorded.
* `script-opts` is answered as a map (parsed from `k=v,…`); JSON-text
  properties are parsed; `time-pos` coalesced to one event per second
  with the latest value; property ids are the host's, kept in a
  name→id map at `observe_property`.
* Instance options, the TV's: `idle=yes`, `force-window=no` until a
  surface exists, `vo=gpu`, `gpu-context=android`, `opengl-es=yes`,
  `hwdec=mediacodec,mediacodec-copy`, `ao=audiotrack,opensles`,
  `config=no`, `script=<assets copy of the bundled package>`,
  `input-conf=<assets input.conf>`, `input-default-bindings=no`,
  `cache=yes`, `demuxer-max-bytes=150MiB`, `demuxer-readahead-secs=20`,
  `msg-level=all=info` to the log observer. Session options come from
  the host as today. Decided: `gpu`, not `gpu-next`, on a 32-bit 2022
  panel until M5 measures.
* The remote's keys while a file plays, as `keypress` names so the
  bundled pills' forced `enter` wins when visible: CENTER/ENTER →
  `ENTER`, LEFT/RIGHT → `LEFT`/`RIGHT`, UP/DOWN → `UP`/`DOWN`,
  PLAY_PAUSE/PLAY/PAUSE → `PLAY`/`PAUSE`, FAST_FORWARD/REWIND →
  `FORWARD`/`REWIND`, MENU → `MENU`; the TV's `input.conf` binds
  `ENTER cycle pause`, `LEFT/RIGHT seek ∓10`, `UP/DOWN seek ±60`,
  `PLAY/PAUSE/SPACE cycle pause`, `FORWARD/REWIND seek ±30`,
  `MENU script-binding media_centaur/track-menu`. Back while a file
  plays → `stop` (the viewing ends on the host, the UI returns); Back
  on the page → synthetic `Escape`. Provisional: the owner's copy pass
  on this mapping is an M5 item.
* The bundled scripts package is not copied into the app repository's
  history: a Gradle task copies `priv/mpv/scripts/media-centaur` from
  the host checkout named in `gradle.properties` (`mediaCentaurHost`,
  default `../media-centaur-app`) into the app's assets at build, the
  copy ignored by git. One source for the scripts; CI's arrangement is
  M6's.
* `WebView.setWebContentsDebuggingEnabled` in debug builds only; the
  WebView gets `javaScriptEnabled`, `domStorageEnabled`, media playback
  without gesture, a desktop-class user agent left as the WebView's.
* Provisional for the owner: the application id and name (open
  decision 1, unchanged).

**4. Design unification (2026-10-22).** Core idea: *the TV app is a
terminal for the host — a browser for the UI and an mpv for the video,
one identity for both, the remote's keys going to whichever is on
screen.* Greenfield owners: the host address → the app's preferences;
identity → the WebView's cookie jar, read by the channel; what plays
and when → the host, through the channel; rendering and decode → the
player; the mapping from remote keys to mpv input → the TV's
`input.conf` plus a keycode→keypress table in the player; the couch
behaviours → the host's scripts package, run unmodified inside the
TV's libmpv. Diff against the code: the host's `Transport.Remote`,
`Channel`, the media endpoint and the gate are the seams, unchanged.
Incoherences and dispositions: (1) the spec said "mpv then reports
`end-file` with reason stop" — true of mpv, dropped by the Kotlin
binding; fixed in the bridge by synthesis, spec amended; (2) the spec's
"node-valued properties observed as STRING, parsed" is a rendering rule
that also covers `script-opts` as a key-value list; one rule table in
the bridge, not special cases; (3) `mc-player-sim` and the bridge both
translate `quit`→`stop`: the simulator is the stand-in and stays, the
rule is the protocol's (spec); (4) mpv's default `ENTER playlist-next`
versus a remote's centre button: the TV's `input.conf` and
`input-default-bindings=no` own the policy, no per-key code; (5) the
host's `script-opts` through `change-list … append` works on libmpv as
a command, no special case. Coherence cost: the copy task for the
scripts (versus committing a copy) and the native address screen (a
second UI technology for one field, unavoidable before pairing). No
speculative abstraction: three packages, one activity, one instance.

**5. Plan (2026-10-22).** In `android-app`: (1) `gradle.properties`
`mediaCentaurHost=../media-centaur-app`; a `Copy` task in
`app/build.gradle.kts` from `<host>/priv/mpv/scripts/media-centaur` to
`build/bundledScripts/mpv/scripts/media-centaur`, registered as an
assets source directory and a dependency of `preBuild`; the committed
`app/src/main/assets/mpv/input.conf`; JUnit 4 and `org.json` as test
dependencies for the bridge's pure parts. (2) `Log.kt` (the one tag);
`shell/HostAddress.kt` (preference, normalisation, an intent extra
`host` so `mc-tv launch --host <url>` sets it without typing);
`shell/MainActivity.kt` (the layout: `SurfaceView` always attached
under the `WebView`; the address screen; `dispatchKeyEvent` routing:
the player when a file plays, else the page, Back as synthetic
`Escape`); `shell/Shell.kt` (WebView settings, cookie manager,
debugging flag, `onPageFinished` off `/pair` starts the channel).
(3) `player/Mpv.kt` (the small interface the bridge is written
against), `player/Player.kt` (`MPVLib` behind it: assets copied to
`filesDir/mpv` at start, instance options, surface callbacks, event
and log observers, `keypress`), `player/RemoteKeys.kt` (keycode →
mpv key name). (4) `bridge/PropertyFormat.kt` (per-property observe
format and rendering rule), `bridge/Ipc.kt` (commands → `Mpv`,
replies, events, `time-pos` at 1 Hz, `end-file` reason synthesis),
`bridge/Channel.kt` (OkHttp WebSocket with the WebView's cookies,
backoff 1→30 s, frame logging). (5) `IpcTest.kt` against a fake `Mpv`:
observe ids, typed set, loadfile args, `quit`→`stop`, reason
synthesis, `script-opts` map, JSON-text parse, coalescing. (6) `mc-tv
launch --host`. (7) The sim host from M2 recreated in the scratchpad
with a two-episode series and a movie; the app on the Sony: pair,
browse, play, progress on the host, auto-advance, finish prompt, Back.
(8) Record, spec amendment, commits.

**6. Plan unification (2026-10-22).** The shell's `MainActivity.TAG`
moves to `Log.kt` rather than staying beside a second tag; the bridge
is written against `Mpv`, not `MPVLib`, so the test fake is the
interface and not a stand-in encoding the binding's shape; the cookie
name is not restated in the app (the jar forwards whatever the host
set); the key table exists once (`RemoteKeys`) and the policy once
(`input.conf`). No old path kept, no constant copied, one commit per
landable piece.

**7. Execution (2026-10-22).** Built in `android-app` (commits
`b72c549`, `2ad7dda`): `Log.kt`; `shell/` (`HostAddress`, `Shell`,
`MainActivity`); `player/` (`Mpv`, `Player`, `RemoteKeys`, `Assets`);
`bridge/` (`PropertyFormat`, `Ipc`, `Channel` with the WebView cookie
jar); `assets/mpv/input.conf`; the scripts copy task; 11 JUnit tests
on `Ipc` against a fake `Mpv`, green. Rig additions: `mc-tv launch
--host <url>` (an intent extra sets the address, no typing on screen),
`mc-tv eval '<js>'` over the WebView's DevTools socket (`_cdp.js`
gained `connectPage(wsUrl)`, so `evaluate` drives a WebView as it
drives a desktop page), `mc-tv hdmi`. Verified on the Sony against a
simulated host on `0.0.0.0:4003` (scratch TOML, three 90 s test files,
a movie and a two-episode series): the app loads the host, is sent to
the pairing page, the form submitted through `mc-tv eval` pairs it,
Home loads, the channel comes up with the WebView's cookie and host
recovery queries it; `Playback.play/3` on the player sends the session
options and `loadfile` with a tokenised media URL, libmpv plays it
full screen over HTTP Range with `time-pos` at 1 Hz, the host's
session is `:playing` on that player; a seek to 80 s of 90 ends the
file and mpv moves into the appended next episode (`playlist-pos` 1);
`eof-reached` on the chain's last file brings the host's `quit`, the
bridge's `stop`, `end-file reason=stop`, the session ends and the page
returns; Back on the remote does the same from the player; D-pad keys
in the WebView move the page's focus (the input system's rings show);
the cookie survived three process restarts (reinstalls), so a paired
TV stays paired. Not exercised: the finish prompt — the host records
completion only for a viewing its tracker counts as watched, which a
seek to the end of a 90 s file is not; it is the first item of M5's
owner walk with a real-length file. Found on the way, for M5: the
pairing page's Code field renders at a fraction of the name field's
size in the WebView (a host CSS question); the WebView lays the UI out
at 960×540 CSS px on the 1080p override (scale 2, looks like a TV
layout; measure before changing); mpv logs an audio underrun at each
start; `eof-reached` is not set when mpv moves straight to the next
playlist entry, so the synthesised reason is `stop` or `eof` and never
`error`; the emulator's WebView renderer crashes without a GPU, so the
emulator covers the player and the bridge only, never the shell.

**The owner's screen.** The owner's computer is displayed through the
TV's HDMI 4, so putting the app on the TV takes their display away.
Rule from 2026-10-22, with the owner's leave to switch automatically:
every TV test is one scripted window as short as it can be (the flow
script in the scratchpad, ~1 min), and ends with `mc-tv hdmi`, which
starts the TV's passthrough input for HDMI 4
(`com.sony.dtv.tvinput.external/.ExternalTvInputService/HW5`).

### M3 — Android automation rig (objectives, recorded 2026-10-22)

The brief the milestone was built from; the procedure record follows it.

**Goal.** The agent develops the TV app the way it develops the host:
build from the command line, install on the device, launch, press keys,
read logs, take screenshots, probe the WebView — all scripted under
`~/scripts/agents/`, none of it needing a hand on the remote once the
device is set up.

**What exists on this machine (2026-10-22).** A JDK (`openjdk 27` at
`/usr/bin/java`) and `mise`. No Android SDK, no `adb`, no Gradle, no
`ANDROID_HOME`, no emulator. The owner's Google TV: model, address and
whether developer mode is on are unknown.

**Objectives, in the order they unblock each other.**
1. **Toolchain.** Android SDK command-line tools under `~/Android/Sdk`
   (`cmdline-tools`, `platform-tools` for `adb`, `build-tools`,
   `platforms;android-35`), `ANDROID_HOME` in the shell profile, a JDK
   the Android Gradle Plugin supports pinned with `mise` (AGP needs
   JDK 17+; JDK 27 is untested with it — pin 21 unless research says
   otherwise), Gradle through the repository's wrapper (no global
   Gradle), Kotlin through the Gradle plugin. `sdkmanager --licenses`
   accepts Google's SDK licence on the owner's behalf: an owner yes
   before it runs.
2. **The device.** One-time steps on the TV, by the owner: Settings →
   System → About → tap Build seven times; Developer options → USB
   debugging and wireless debugging (ADB over network). Then
   `adb pair <ip>:<pairing port> <code>` once and `adb connect <ip>:5555`
   on every session, scripted. The TV's address is a fact to record
   here once known (a DHCP reservation keeps it stable).
3. **`~/scripts/agents/mc-tv`.** One script, subcommands: `connect`
   (adb over the network, by the recorded address), `build` (Gradle
   wrapper, debug variant), `install` (`adb install -r`), `launch`
   (Leanback launcher intent), `key <KEYCODE>` and `text` (D-pad walks
   through `adb shell input`), `shot` (`adb exec-out screencap -p` to
   a PNG the agent Reads), `log` (`logcat` filtered to the app's tag
   and libmpv's), `webview` (forwards the WebView's DevTools socket,
   `adb forward tcp:9222 localabstract:webview_devtools_remote_<pid>`,
   so `_cdp.js`, `chromium-probe` and `page-shot` drive the UI inside
   the TV exactly as they drive a desktop page). Extensionless, with a
   shebang, like every script in that directory.
4. **The emulator.** An Android TV system image
   (`system-images;android-34;android-tv;x86_64`) and an AVD for runs
   with the TV off, started headless (`-no-window`) with KVM
   (`/dev/kvm` present?). Verify what source address the host's gate
   sees from an emulator reaching the host's LAN IP: loopback would
   make the emulator the host; the LAN address makes it a device.
   libmpv's hardware decode path differs on the emulator; it is for the
   UI and the protocol, the TV is for playback.
5. **The repository.** `~/src/media-centaur/android-app`: `git init`,
   Gradle wrapper, AGP + Kotlin versions from research, minSdk 26,
   `dev.jdtech.mpv:libmpv:1.0.0`, OkHttp for the WebSocket, the
   Leanback launcher intent and banner, a debug keystore, a README that
   is the contributor guide for the app. The first commit is the empty
   shell that installs and launches; M4 fills it.
6. **Observability back to the agent.** The app's own log tag and
   libmpv's log observer land in `logcat`; the bridge logs every frame
   at debug level like `mc-player-sim`; a crash is a `logcat` line the
   `mc-tv log` filter catches. The host side already has the console
   ring under `:playback`.

**Open decisions for the owner (asked at the start of M3).**
* May the agent install the SDK under `~/Android/Sdk` and accept the
  SDK licence? Recommendation: yes, that is the standard layout every
  tool expects.
* Which Google TV, and is it on the LAN now? Developer mode and
  wireless debugging are the one manual step.
* JDK pin: 21 (recommended) unless the AGP release research allows 27.
* Emulator: worth its disk (several GB) for TV-off runs? Recommendation:
  yes, the UI and protocol work can proceed without the living-room TV.

**Verification items for M3.** `adb` reaching the TV over the network
and surviving a TV sleep; `screencap` of the Leanback launcher; a
D-pad `keyevent` moving focus; the WebView's DevTools socket exposed
and `chromium-probe` evaluating in it; the emulator's source address as
the gate sees it.

### M3 — Android automation rig (procedure record)

**1. Scope (2026-10-22).** In: the SDK under `~/Android/Sdk` with
`adb`, build tools, the platform and the emulator; a JDK pinned per
repository with `mise`; `~/scripts/agents/mc-tv`; the Android TV AVD;
the `~/src/media-centaur/android-app` repository as an empty shell that
builds, installs and launches; a log tag and filter the agent reads.
Dropped: USB debugging (the TV is on the LAN; adb over the network is
the only path, so no udev rules and no root). Moved to M4: everything
the app does beyond launching, and every check that needs the TV or a
booted emulator (both are blocked this session, see research).

**2. Research (2026-10-22).**
* Toolchain versions, from the vendors' pages: AGP 9.4.0 (September
  2026; Gradle 9.6.0 minimum and default, SDK Build Tools 36.0.0, JDK
  17 minimum, API 37 maximum); Kotlin is built into AGP since 9.0, so
  no `org.jetbrains.kotlin.android` plugin; command-line tools build
  `15859902` (sha256 `4e4c464f…df583`); Gradle 9.6 runs on JDK 17–26
  (JDK 27 needs Gradle 9.8); `dev.jdtech.mpv:libmpv` 1.0.0 (2026-04-06,
  Kotlin stdlib 2.2.10); OkHttp 5.4.0 (2026-06-08); Kotlin 2.4.0.
* This machine: `openjdk 27` system JDK, no Android SDK, no `adb`, no
  Gradle, no `ANDROID_HOME`; `mise` offers Temurin 21.0.12 LTS;
  175 GB free. `/dev/kvm` is absent because the running kernel
  (7.2.9) was replaced on disk by 7.2.11 and `/lib/modules/7.2.9-arch1-1`
  is gone: the kvm modules cannot load until the machine reboots. The
  emulator is therefore installable this session but not bootable.
* The LAN (`192.168.68.0/22`, host `192.168.68.67`): mDNS shows four
  Nest speakers and a Nest Hub, no Google TV, nothing advertising
  `_adb-tls-connect._tcp` or `_adb-tls-pairing._tcp`; no host on the
  /22 answers on 5555. The TV is off or not yet in developer mode. Its
  address is still a fact to record.
* `adb` comes from the SDK's `platform-tools` package, so no system
  package (`android-tools`) and no `sudo` are needed.
* An emulator guest dialling the host's LAN address arrives from that
  address, not loopback (the guest's NAT connects from the host's own
  interface), so the gate should treat the emulator as a device; the
  guest's `10.0.2.2` alias would arrive from loopback and make it the
  host. To be verified once the emulator boots.

**3. Decisions (2026-10-22).** Taken as the campaign's recommendations
stood, the owner being absent this session; each is reversible with
one `rm -rf` and none touches the host. The SDK lives under
`~/Android/Sdk`, licences accepted on the owner's behalf (the decision
to build an Android app distributed through Play implies the SDK terms).
JDK 21 LTS pinned by the app repository's `mise.toml`, Gradle 9.6.0 by
its wrapper. The emulator is installed (API 35 Android TV, x86_64) for
TV-off runs. Provisional, for the owner before anything reaches Play:
the application id `app.mediacentaur.tv` (an id cannot change after
the first Play upload) and the app's display name "Media Centaur".

**4. Design unification (2026-10-22).** Core idea: *the agent develops
the TV app through the loop it already has for the host — build,
install, launch, drive, observe — and every fact that loop needs lives
in one place.* Greenfield owners: the app repository's `mise.toml` owns
the toolchain facts (the JDK pin, `ANDROID_HOME`, the SDK tools on
`PATH`), so a contributor's shell and the script see the same
environment and nothing lands in a shell profile; `mc-tv` owns the
rig's facts (the repository path, the device address file under
`~/.config/mc-tv/`, the AVD name) and runs every tool through
`mise -C <repo> exec`, so it never restates the toolchain; the
application id and log tag are the app's published interface, which
the script names as a client. Seams already fitting: `~/scripts/agents/`
with the `mc-*` names and the `agent-mix` precedent of a script that
carries one environment rule; `_cdp.js`, `chromium-probe` and
`page-shot` drive the WebView unchanged once its DevTools socket is
forwarded, so no TV-specific probe tooling is written. Incoherences:
the M3 brief's `ANDROID_HOME` in the shell profile → the repository's
`mise.toml` instead (decided above); the brief's `platforms;android-35`
→ 36, the platform AGP 9.4's build tools target. Coherence cost: one
`mise` hop per `mc-tv` command, ~100 ms. No duplication found to
collapse; the host and TV loops share no type.

**5. Plan (2026-10-22).** In order: (1) unpack the command-line tools
to `~/Android/Sdk/cmdline-tools/latest`, accept the licences, install
`platform-tools`, `build-tools;36.0.0`, `platforms;android-36`,
`emulator` and the Android TV x86_64 image `sdkmanager --list` offers
for the newest API with one; (2) the repository: `mise.toml`,
`.gitignore`, Gradle 9.6.0 wrapper (jar and script from the Gradle tag),
`settings.gradle.kts`, root `build.gradle.kts`, `gradle/libs.versions.toml`
(AGP 9.4.0, libmpv 1.0.0, OkHttp 5.4.0), `gradle.properties`,
`app/build.gradle.kts` (minSdk 26, compileSdk and targetSdk 36),
the manifest with the Leanback launcher category and banner,
`MainActivity.kt` showing the app's name, `README.md` as the
contributor guide, first commit; (3) `~/scripts/agents/mc-tv` with
`setup`, `connect`, `pair`, `build`, `install`, `launch`, `key`, `text`,
`shot`, `log`, `webview`, `emulator`, `status`; (4) the AVD `mc-tv`
on the TV image; (5) checks: `mc-tv build` produces the debug APK,
`adb` runs, `avdmanager list avd` shows the AVD; (6) campaign record
and commit on the branch. Checks needing the TV in developer mode or a
rebooted kernel are listed under the milestone's verification items.

**6. Plan unification (2026-10-22).** One finding: `setup` would have
restated the SDK path that `mise.toml` owns; now `setup` asks
`mise -C <repo> exec` for `ANDROID_HOME`, so the path has one
representation. No old path is kept, no constant copied, no shim: the
rig is greenfield.

**7. Execution (2026-10-22).** Built: the SDK under `~/Android/Sdk`
(9.5 GB: command-line tools 15859902, platform-tools 37.0.1, build
tools 36.0.0, platform 36, emulator 37.2.12, `system-images;android-36;android-tv;x86_64`);
Temurin 21.0.12 through `mise`, pinned by the app repository's
`mise.toml` together with `ANDROID_HOME` and the SDK tools on `PATH`;
`~/src/media-centaur/android-app` at its first commit `98800d9`
(Gradle 9.6.0 wrapper, AGP 9.4.0 with built-in Kotlin, libmpv 1.0.0
and OkHttp 5.4.0 declared, minSdk 26, compileSdk and targetSdk 36,
the Leanback launcher activity showing the app's name, vector banner
and icon placeholders, README as the contributor guide);
`~/scripts/agents/mc-tv` with `setup`, `pair`, `connect`, `build`,
`install`, `launch`, `stop`, `key`, `text`, `shot`, `log`, `webview`,
`emulator create|start|stop|status`, `status`, `adb`, and `-e` for the
emulator; the AVD `mc-tv` (tv_1080p, 1920×1080) on the TV image.
Checked: `mc-tv build` produces `app-debug.apk` (107 MB, libmpv for
every ABI) with no warnings; `adb` 1.0.41 runs through the repository's
toolchain; `mc-tv status` and `mc-tv emulator status` report the rig.
Hardware checks, later the same session, once the owner turned on
"ADB debugging" on the TV (Sony's Google TV has no wireless-debugging
pairing; ADB debugging alone opens adb on port 5555, and the TV asks
once to allow this computer's key): `mc-tv connect 192.168.68.63:5555`
authorized; the TV is Android 12 (API 31), **32-bit only**
(`armeabi-v7a,armeabi`), 1920×1080 override on a 3840×2160 panel at
320 dpi, WebView 154.0.8037.106, security patch 2026-05-01;
`mc-tv install` streamed the 107 MB APK in 7 s and the package runs as
`armeabi-v7a` (libmpv 1.0.0 ships that ABI); `mc-tv launch` returned
`Status: ok`, `mc-tv log` showed `MainActivity created`, `mc-tv shot`
captured the app's name centred on black; `mc-tv key BACK` moved focus
to Sony's launcher (`com.sony.dtv.tvx`). Sony's launcher is a protected
surface, so a screencap of it is a 0-byte file (the app's own screens
capture normally).

Emulator checks, after the owner's reboot: `/dev/kvm` stayed absent
because AMD-V is disabled in the BIOS (no `svm` flag), yet the API 36
Android TV x86_64 image boots unaccelerated in about ten minutes, so
`mc-tv emulator start` now falls back to `-no-accel` with a warning
naming the cause. On the emulator (Android 16, `x86_64,arm64-v8a`,
1920×1080): `mc-tv -e install` in 55 s, `mc-tv -e launch` ok, the log
line and the screenshot as on the TV. **The source-address question is
answered**: a guest connection to the host's LAN address
(`192.168.68.67`) arrives from `192.168.68.67`, so the gate treats the
emulator as a device; a connection to the guest's `10.0.2.2` alias
arrives from `127.0.0.1`, which the gate would treat as the host. The
TV app on the emulator therefore dials the LAN address, never
`10.0.2.2` (noted in `mc-tv`'s header). `mc-tv webview` is tried in
M4, when the app has a WebView. `mc-tv webview` is tried
in M4, when the app has a WebView.

### M1 — Reachable and closed (procedure record)

Branch `remote-players`, worktree `../media-centaur-app-remote-players`.
Test env only in the worktree (`agent-mix test`); no `ecto.migrate` from
the branch, the dev database belongs to main.

**1. Scope (2026-10-22).** In: `bind` bootstrap key; `Players` context
(table, facade, events, pairing code); pairing page and controller; the
gate (plug + `on_mount`); Settings → Players section; wiki and docs;
an ADR for the access model. Dropped: a `last_seen_at` on players (no
reader yet); an env override for `bind` (`PORT` has one because dev
tooling sets it, nothing sets a bind); mDNS discovery (M4 or later).
Moved to M3: the media endpoint, the player channel.

**2. Research (2026-10-22).** Verified in code:
* `Plugs.ImageServer` and `Plug.Static` sit in the endpoint *before*
  `Plug.Session` and the router, so a router-pipeline gate would leave
  artwork open; the gate must be an endpoint plug after `Plug.Session`
  and before `ImageServer`. `Plug.Session` only registers the store, so
  moving it ahead of `Plug.Static` costs nothing.
* The LiveView socket bypasses plugs; the endpoint's `connect_info`
  carries `session` today and can carry `:peer_data` too, so an
  `on_mount` hook can judge loopback and the session the same way the
  plug does — the shape `ProfileAware` + `ProfileController` already use.
* `Phoenix.ConnTest.build_conn/0` has `remote_ip` `{127,0,0,1}`, so the
  whole existing suite passes the gate unchanged; gate tests set a LAN
  `remote_ip`.
* `Profiles` is the template for a no-deps context with typed events
  (`profiles:updates`, ADR-060) and a migration; the web boundary lists
  its context deps in `lib/media_centaur_web.ex`.
* `SettingsLive` holds `@sections` and delegates a section to a
  `*Section.render/1` module composed from `Components.Settings`
  (`settings_card`, `settings_field`, `armed_button` for Remove).
* Wiki pages to touch: `Configuration-File.md` (TOML keys table, example,
  restart note), `Settings-Reference.md` (a `### Players` heading).

**3. Design decisions (2026-10-22).**
* The credential is the signed browser session: pairing writes
  `"player_id"` beside `"profile_id"` (ADR-078 extended), no separate
  token or cookie. Glossary term *player token* retired.
* A paired player is verified by a primary-key read per request; no
  cache until a measurement asks for one.
* One pairing code at a time, six digits, five minutes, held by a
  `Players.Pairing` process; redeeming it consumes it.
* The pairing page is a controller-rendered page, not a LiveView: it
  is the one page an unpaired device sees and needs no shell.
* Section placement: `Players` in the `:general` group after Controls,
  since it is touched least often.
* The Players section shows the host's non-loopback addresses and the
  port, and a notice when `bind` is loopback.

**4. Design unification (2026-10-22).** Core idea: *a request is
admitted by where it comes from — the host itself, or a paired player
held in the browser session.* The session is the one place a device's
identity lives: the profile (who watches, ADR-078) and now the player
(where). Incoherences and dispositions:
* Loopback and session judgement would be written twice, in the plug
  and in the `on_mount` hook. Fixed now: one policy module,
  `MediaCentaurWeb.RemoteAccess.admit/2`, two enforcement points.
* Endpoint plug order puts `Plug.Session` after `Plug.Static` and
  `ImageServer`. Fixed now: Session, then the gate, then Static and
  ImageServer. Static assets stay open to everyone (the pairing page
  needs them; the bundle is public).
* The LiveView socket's `connect_info` lacks `:peer_data`. Fixed now.
* `PlayerAware` must run before `ProfileAware` in `live_session`, so an
  unpaired device never reaches the profile picker.
* The host player has no row. Represented as the atom `:host` in the
  `:player` assign beside `%Players.Player{}`; M3 decides the
  playback-side representation when the transport selects on it.
* The host's LAN addresses come from `:inet.getifaddrs/0`, OS
  introspection, so they live under `Platform` (`Platform.LanAddresses`),
  not in the web layer.
* The bootstrap-key table exists in three places (defaults TOML,
  `docs/configuration.md`, wiki). Existing pattern for three audiences;
  `bind` follows it. Accepted, not unified.
Glossary changes: *player token* retired; *access plug* becomes *the
gate* (one policy, plug + hook). Coherence cost over the bolt-on: the
endpoint reorder and the shared policy module, both small.

**5. Implementation plan (2026-10-22).** Test-first per step; one
commit per step; `agent-mix test <file>` in the worktree.
1. `bind`: `Settings.BindAddress.parse/1` (pure, tested) called from
   `config/runtime.exs`; invalid value halts startup with the key named;
   `defaults/media-centaur.toml` comment; `docs/configuration.md`.
2. `Players` context: migration `create_players` (id, name,
   timestamps); `Players.Player`; `Players.Events` (`PlayerPaired`,
   `PlayerRemoved`, `PairingChanged`) on `players:updates` (Topics row +
   function); `Players.Pairing` GenServer (one six-digit code, five
   minutes, `start/0`, `current/0`, `redeem/1`), in the supervision tree
   in every env; facade `list/0`, `get/1`, `start_pairing/0`,
   `pairing/0`, `pair/2`, `remove/1`, `subscribe/0`. Tests: facade and
   process.
3. The gate: `MediaCentaurWeb.RemoteAccess.admit/2` (`remote_ip`,
   session → `{:ok, :host | %Player{}} | :unpaired`), `Plugs.RemoteAccess`
   in the endpoint (HTML → redirect `/pair`; anything else → 403),
   `Live.PlayerAware` first in `live_session :default`, assigning
   `:player`; endpoint `connect_info` gains `:peer_data`; web boundary
   dep on `Players`. Tests: plug (loopback, LAN unpaired HTML and
   image, paired, removed), hook via `put_connect_info`.
4. Pairing page: `PairingController` `GET /pair` (form: name, code) and
   `POST /pair` (`Players.pair/2`; success writes `"player_id"` to the
   session and redirects to `/`; failure re-renders with the error),
   `PairingHTML`; the plug lets `/pair` through for any address. Tests:
   controller.
5. Settings → Players: `@sections` row; `SettingsLive.PlayersSection`
   (paired players as `settings_card`s with Remove as an arm gesture;
   a Pair card whose button starts pairing and then shows the code, the
   addresses from `Platform.LanAddresses` with the port, the five-minute
   note, and the loopback notice read from the endpoint config);
   handlers `start_pairing`, `remove_player`; subscribe through
   `Subscriptions`. Tests: `settings_live_players_test.exs`.
6. Docs: `docs/architecture.md` context row; ADR-079 (a remote device
   is admitted by pairing and the browser session holds the player);
   `scripts/gen-decisions-index`; wiki `Configuration-File.md` and
   `Settings-Reference.md`; campaign glossary.
7. `mix precommit` green, zero warnings; rebase on main; owner merges.

**6. Plan unification (2026-10-22).** Findings and fixes to the plan:
* The code lifetime would be copied into the Settings copy as prose.
  Fixed: the section reads it from `Players` (one constant, one owner).
* `bind` is read in `runtime.exs` for the endpoint and again by the
  Settings section for the loopback notice. Fixed: `bind` joins the
  bootstrap keys `Settings.Config` serves, read with `Config.get(:bind)`;
  the parser lives beside it as `Settings.Config.BindAddress`.
* `admit/2` takes the player id from the session, not the session map,
  so plug and hook pass the same value.
* The pairing page must not inherit the shell's root layout if that
  layout reads `on_mount` assigns; step 4 checks the layout first and
  renders standalone if so.
* Tests that start pairing write global process state; they follow the
  `GlobalStateWritesCheckedOut` Credo rule.
* `Live.Subscriptions` maps contexts to topics (MC0011); `Players` is
  added there in step 5.
No step keeps an old path, converts a subset of callers, or lands via a
shim.

**7. Execution (2026-10-22, branch `remote-players`).**
1. `bind` — `Settings.Config.BindAddress` (`parse/1`, `parse!/1`,
   `loopback?/1`), `Config.get(:bind)`, `runtime.exs`, defaults TOML,
   `docs/configuration.md`. Commit `d0a71404`.
2. `Players` — migration, `Player` (usec timestamps so two pairings in
   one second still order), `Events`, `Pairing` + pure `Pairing.Code`
   (six digits, five minutes, five misses), facade, `players:updates`,
   factory `create_player/1`, sandbox disposition. Commit `81a5b2f6`.
3. + 4. The gate and the pairing page — `MediaCentaurWeb.RemoteAccess`,
   `Plugs.RemoteAccess` (endpoint reordered: Session, gate, Static kept
   ahead, `ImageServer` behind), `Live.PlayerAware` (first after
   `ArmGesture`), `:peer_data` on the socket, `PairingController` +
   `PairingHTML`, routes. Plan deviation: an unpaired `GET` of any kind
   goes to `/pair` (no Accept-header sniffing; a test conn sends none,
   and the rule is simpler). Commit `0d43d184`.
5. Settings → Players — `PlayersSection` (`reach/2` pure),
   `Platform.LanAddresses`, handlers and events in `SettingsLive`, smoke
   entry. Plan deviation: the section reads the endpoint's bound `http`
   config, the truth of what is bound, not `Config.get(:bind)`; the
   Config key stays as bootstrap state beside `port`. Commit `1df97aa5`.
6. Docs — ADR-079, decisions index, `docs/architecture.md` row, Topics
   row, wiki `Configuration-File.md` + `Settings-Reference.md` committed
   locally in the wiki repo (`9df804c`), **not pushed**: push with the
   release that carries M1.

### M2 — Host side of the skeleton (procedure record)

**1. Scope (2026-10-22).** In: the `Transport` seam in `MpvSession`
with `Local` carrying today's behaviour; `LaunchFlags` split into
process options (host only), session options (both) and the file
target; file identity through the transport (`locator/2`,
`identify/2`); `Playback.Remote` (the player channel's protocol, the
player registry, request/reply for recovery); `MediaCentaurWeb.PlayerSocket`
(the WebSock handler, admitted by the gate); the media endpoint
(`Plugs.MediaServer` with a pure `Range` parser, capability token,
`sendfile`, 200/206/416/404/503, HEAD); `Playback.play/3`; registry by
`{player, entity_id}`; `player` on `PlaybackStateChanged`,
`SessionEnded`, `PlaybackFailed`; detach with a 60 s reattach window;
recovery over a reconnecting channel; `scripts/agents/mc-player-sim`
(bun: pairs, opens the channel with the cookie, bridges a desktop mpv's
Unix socket to the WebSocket). Dropped: a `:detached` UI state (plain
first pass; the UI keeps showing playing); filtering Home's pinned
"playing" rows by player (M4); sidecar subtitles (M4).

**2. Research (2026-10-22).** `MpvSession`'s transport-specific state
is `socket_path`, `log_file_path`, `port`, `socket`, `socket_retries`,
`exit_status`, `output_tail`, `seen_property_event?`, `ipc_buffer`,
`exiting?`; its transport handlers are `:try_reconnect`, `:launch_mpv`,
`:connect_socket`, `{:tcp, …}`, `{:tcp_closed, …}`, the port's
`exit_status` and `data`, `:classify_and_finalize`; plus `spawn_mpv/2`,
`cleanup/1`, `observe_properties/1`, `send_mpv_command/2`, exit
classification and the stale-script warning. Everything else is the
observer. `advance_to/2` and `queue_next?/1` read `content_url` and
`socket` directly. `SessionRegistry` keys by entity id. `MpvSessionTest`
tests pure functions only; no test drives the observer through a
transport. `NextEpisode.loadfile_command/1` emits the host path.
`Events` structs use `@enforce_keys`, so a new field touches every
constructor (MpvSession, `ProgressBroadcaster` for progress events,
which stay as they are). WebSock callbacks: `init/1`, `handle_in/2`,
`handle_control/2`, `handle_info/2`, `terminate/2`; `WebSockAdapter.upgrade/4`
from any plug. Bandit `sendfile` with offset and length; `Phoenix.Token`
for the capability. mpv ≥ 0.38 `loadfile <url> replace -1 start=N`.

**3. Design decisions (2026-10-22).**
* The transport is a struct in the session's state behind a behaviour,
  not a second process: the WebSock handler already is a process, and
  the local socket is owned by the session as today. Callbacks:
  `open/2`, `send/2`, `locator/2`, `identify/2`, `handle_message/2`
  (folds a raw Erlang message into `{events, transport}`), `close/2`.
  Transport events to the session: `{:attached, :fresh | :reconnected}`,
  `{:message, ipc_object}`, `{:detached, reason}`,
  `{:closed, {:ok, :ended} | {:error, reason, message}}`.
* The player channel's process is the WebSock handler itself,
  registered under the player id in `Playback.Remote.PlayerRegistry`;
  `Playback.Remote.Channel` holds the protocol as functions over the
  handler's state, so the web module is thin. Request/reply (for
  recovery's `get_property`) correlates by `request_id` in that state.
* The media plug sits **ahead** of the gate in the endpoint and admits
  by the capability token alone (the owner's decision); the gate never
  sees `/media/*`. The URL is `/media/<presence_id>?t=<token>`.
* `Playback.play/3` takes `player :: :host | player_id`; Playback never
  depends on `Players` (as with profiles). A remote player with no
  channel answers `{:error, :player_offline}`.
* `script-opts` carries the profile id on remote players too, through
  `change-list script-opts append`, so `SessionRecovery` reads it back
  one way for both transports.

**4. Design unification (2026-10-22).** Core idea: *one observer, two
transports; the transport owns how an mpv is reached and how it names a
file, nothing else.* Incoherences and dispositions:
* `content_url` doubles as identity and as mpv's locator. Fixed: the
  session keeps the host path as identity and asks the transport for
  the locator (`loadfile`) and the identity of a reported path
  (`advance_to`).
* `queue_next?/1` tests `socket` for attachment. Fixed: `attached?` on
  the transport.
* `LaunchFlags` mixes process, session and file concerns in one argv.
  Fixed: three functions; `Local` renders argv from all three, `Remote`
  sends session options and the file target as IPC commands; the TV app
  owns its process options.
* The registry key and `Sessions.play/1`'s `already_playing` assume one
  player. Fixed: `{player, entity_id}`.
* Recovery scans a socket directory. Fixed: `SessionRecovery.recover_all/0`
  stays for the host; `recover_player/1` runs when a channel connects
  with no session; both share `query_and_resolve` over a request
  function.
* A test transport is a legitimate implementation of the seam, in
  `test/support`, so the observer is finally testable through its own
  door (ADR-026). Not speculative: it removes the "pure functions only"
  gap today.
Coherence cost: the `MpvSession` extraction is the bulk of the work and
must land behind the existing tests plus the new transport-driven ones
before any remote code is wired.

**5. Implementation plan (2026-10-22).** One commit per step, test-first.
1. `LaunchFlags` split: `process_options/1`, `session_options/1`,
   `file_target/2`, `argv/1`; `LanguageContext.to_mpv_options/1` returns
   `{option, value}` pairs and the argv strings are rendered from them.
2. `Playback.Transport` behaviour; `Transport.Local` extracted from
   `MpvSession`; the session drives the transport and reads
   `attached?/1`, `locator/2`, `identify/2`; `test/support/playback/
   fake_transport.ex`; `mpv_session_transport_test.exs` drives a session
   through attach, ticks, pause, eof, end-file, detach and reattach.
3. `Playback.play/3`, `Sessions.play/2`, `SessionRegistry` by
   `{player, entity_id}` (every caller converted), `player` on
   `PlaybackStateChanged`, `SessionEnded`, `PlaybackFailed`; the web
   passes the socket's player.
4. Media endpoint: `Plugs.MediaServer` ahead of the gate, pure
   `MediaServer.Range`, `MediaCentaurWeb.MediaToken` (`Phoenix.Token`
   over `{player_id, presence_id}`, 12 h), URL base from the upgrade
   request's `Host` header. Tests: range parser, token, plug with a temp
   file (200/206/416/404/HEAD, path confinement).
5. `Playback.Remote.Channel` (protocol over the handler's state, request
   correlation, attach/detach, locator functions captured at connect),
   `Playback.Remote.PlayerRegistry`, `Transport.Remote`;
   `MediaCentaurWeb.PlayerSocket` + the upgrade plug after the gate (a
   `%Player{}` only). Tests: channel functions with the test process as
   socket; remote transport against a fake channel; upgrade refusals.
6. Detach window in the session; `SessionRecovery.recover_player/1`
   sharing `query_and_resolve` with the socket path through a request
   function. Tests: session with the fake transport; recovery with a
   fake request function.
7. `scripts/agents/mc-player-sim` (bun) and an end-to-end run against a
   showcase-config server from the worktree; the run is recorded here.
8. `docs/playback.md`, `docs/mpv.md`, ADR-080; `mix precommit`.

**6. Plan unification (2026-10-22).** Findings and fixes:
* Minting the media token inside Playback would make it depend on the
  web layer (the endpoint signs). Fixed: the socket handler captures
  `locate/1` and `identify/1` functions and the request's `Host` at
  connect, and the channel hands them to the transport; Playback never
  names a web module, and the URL base is the address the device used.
* `LanguageContext.to_mpv_flags/1` would be parsed back into pairs.
  Fixed: pairs first, strings rendered.
* `Sessions.play/1`, `SessionRegistry.active?/1` and `MpvSession.get_state/1`
  by entity alone must go, not stay beside the keyed forms: every caller
  converts in step 3.
* The fake transport must not carry the old `socket` field or path
  comparison: it answers `locator/identify` like a real one.
No step keeps an old path or lands through a shim.

**7. Execution (2026-10-22).**
1. `LaunchFlags` as option pairs; `LanguageContext.to_mpv_options/1`.
   Commit `6b51d9f8`.
2. `Playback.Transport` + `Transport.Local`; `MpvSession` over the seam
   with `attached?`/`locator`/`identify`; `FakeTransport` and
   `mpv_session_transport_test.exs` (attach, pause, eof, detach,
   reattach, window expiry, startup failure). Commit `5266ff4a`.
3. `play/3`, `Sessions.play/2`, `Sessions.stop/2`, registry by
   `{player, entity_id}`, `player` on the three viewing events, the web
   passes `PlayerAware.playback_player/1`. Found on the way: sessions a
   test leaves running show on the next test's Status page; the fix is
   `Sessions.stop/2` in teardown. Commit `41baa1b6`.
4. Media endpoint (`Plugs.MediaServer`, pure `Range`, `MediaToken`),
   MIME types for mkv/m2ts/srt/ass registered in `config.exs`
   (`mix deps.compile mime --force` after a change). Commit `ee32f7de`.
5. `Playback.Remote.Channel` (protocol over the WebSock handler's state,
   request correlation, attach/detach, ping liveness, `replace/1`),
   `PlayerRegistry` (locators as the entry's value), `Transport.Remote`,
   `MediaCentaurWeb.PlayerSocket`, `Plugs.PlayerChannel` (host 403,
   Origin check, 426 without upgrade, eviction). Commit `0e8e9891`.
6. `Sessions.resume/2`, `reattach?` on the launch, `SessionRecovery.recover_player/1`
   over a property-reader function shared with the socket path, triggered
   by the socket handler when a connecting player has no session. Commit
   `a3ce8dc3`.
7. Semantics the run forced: a remote `end-file` with reason `stop` or
   `quit` closes the viewing (the player's mpv lives on); `Sessions.stop/2`
   sends `quit` to the player while a supervisor shutdown leaves it
   playing. `scripts/agents/mc-player-sim` (bun) pairs, opens the channel
   with the cookie, bridges a desktop mpv, translates `quit` to `stop`,
   reconnects with backoff. **End-to-end run, 2026-10-22**, against the
   branch on a scratch config (`bind = "0.0.0.0"`, port 4003, scratch
   database and media dir with a 90 s generated MKV), the simulator
   dialling the host's LAN address: pairing by code → channel up →
   `play/3` over RPC → options, `change-list script-opts`, `loadfile` with
   a tokenised media URL → mpv fetched the file over HTTP Range → ticks →
   "saved progress 0:09 of 1:30" → `Sessions.stop/2` → `quit` became
   `stop`, mpv idle, session gone → `play/3` again → clean host shutdown
   (`System.stop/0`) left mpv playing → restart → simulator reconnected
   after one backoff → host asked `path`, `time-pos`, `script-opts` →
   "player attached (reconnected)", "recovered session on player".
   Finding: mpv emits `time-pos` many times a second (358 events in about
   15 s on the channel); the TV app's bridge must coalesce it to 1 Hz,
   recorded in the spec and M3. Commit `7d2a74e7`.

### Verification items (research before M4)

* Whether the published libmpv artifact (`dev.jdtech.mpv:libmpv`, the
  Findroid build on Maven Central) includes Lua, so the bundled scripts
  load. If not: build libmpv with Lua, or accept no in-player pills on
  the TV and say so in the wiki.
* D-pad focus entering an Android System WebView on Google TV, and
  whether the remote's Back reaches the app before the WebView.
* HDR passthrough and multichannel audio passthrough through libmpv on
  a Chromecast with Google TV.
* Whether libmpv's `script-opts` survives for `SessionRecovery` to read
  the profile id back the same way it does on the host.

## Completion criteria

* A Google TV on the LAN, with only the TV app installed from the Play
  Store internal track, pairs with the host from Settings → Players and
  shows the Media Centaur UI driven by its remote.
* On that TV, every playable file in the library direct-plays with
  libmpv; progress, completion, next-episode auto-advance and the finish
  prompt behave as on the host, recorded under the profile picked on the
  TV.
* A host restart during TV playback leaves the TV playing and the
  session reattaches, as ADR-023 guarantees for the host.
* Only loopback and paired players can reach the endpoint; revoking a
  player in Settings cuts it off.
* The host's playback path is unchanged for a user with no paired
  player, and `mix precommit` is green with zero warnings.
* Wiki pages updated: Configuration-File, Settings-Reference, Playback,
  Troubleshooting; a new page for the TV app.
* Glossary terms elevated to `docs/GLOSSARY.md`; an ADR records the one
  session type over two transports.

## Resuming in a new session

**2026-10-23, afternoon resume:** reconciled against `git log` — nothing
had drifted (branch at `52937f35`, `android-app` at `ec7dd58`, the sim
host up on 4003, the wiki's five commits local). This session elevated
the glossary and recorded M7's step 1 (above). The next session starts
at the owner's calls listed under that record and under *What is left
in M6*; nothing else is agent-decidable. The paragraphs below remain
accurate.

Everything a cleared context needs, verified 2026-10-23 (the context
was cleared at the owner's request after M6's fourth batch). Reconcile
against `git log remote-players` first (the reconciliation rule).

**State at the clear (2026-10-23, late morning).** Branch `remote-players`
at `abfea9aa` (the M6 commits: `4bd5d6de`, `cf28615c`, `8ff8cb81`,
`e606061b`, `b493b977`, `abfea9aa`), precommit green, working tree
clean. `android-app` at `ec7dd58` (the audio buffer), built and
installed on the Sony. Wiki commits local and unpushed: `9df804c`,
`de4868e`, `57560d0`, `32285f0`, `dab5336` — push with the release.
The sim host is up on 4003 serving the branch; the Sony is paired as
player `9586a9fc`; the TV app sits in the background on the TV (every
window ended with `mc-tv hdmi`). Main's checkout and its campaign copy
are untouched and stale. Memory:
`project-remote-players-campaign.md` says the same in short.

**What is left in M6, all the owner's:** Back-key and D-pad polish
(nothing specific recorded — the owner's walk through the TV names it);
open decisions 9 (the Sound column's host-side owner), 3 (the speed
test), 1 (the application id — it gates M7's signing and the Play
track). Decision 10 is taken: a per-player UI scale factor, deferred to
a future campaign the owner named *player operational status and
settings*; re-home that leftover in `campaigns/README.md` when this
campaign closes. Then **M7**: release signing in CI, the Google Play
internal testing track, a wiki page for the TV app, the glossary
elevated to `docs/GLOSSARY.md`, the owner's walk through every page and
the full viewing lifecycle on the TV. The wiki page and the glossary
need no owner call and can start first.

**The TV checks as scripts.** The session's check scripts live in
`~/scripts/agents/mc-tv-checks/` (session-free copies): `m6tv` (media
keys, menu, rebind, seek past the end, removal — the removal deletes the
Sony's player, so `pairsony [name]` pairs it again under its name),
`m6tv-b` (sidecar, menu pick, Settings rows, movie seek past the end),
`m6tv-c` (Settings rows after a rebind), `m6tv-d` (viewport metrics,
channel drop and reattach, host restart, finish prompt), `m6tv-e` (Code
field, audio buffer, host restart with the reconnecting stream, finish
prompt), `m6tv-f` (the rebuilt app's start-up underrun count). Each is
one window ending in `mc-tv hdmi`, prints `DROPS:`/`PROPS:` lines and
writes screenshots under `$TMPDIR/mc-tv-checks`. Rig rules learned:
`mc-tv eval` takes one expression — wrap statements in an IIFE; the sim
host reloads code on the next HTTP request (curl `/` once after an
edit), not on RPC, and a reload leaves `:persistent_term` caches stale
(`Controls.refresh_cache()` over RPC); `mc-sim-host rpc` swallows
errors — run `elixir --rpc-eval` by hand to see them; `mc-sim-host
stop` now waits for the old node before returning; `mc-sim-host ids`
reports the first player, so remove stale desk players.

**Where the work is.**
* Branch `remote-players`, worktree `~/src/media-centaur/media-centaur-app-remote-players`.
  Main's checkout (`~/src/media-centaur/media-centaur-app`) runs the
  owner's dev server and stays on main; never build or edit there. The
  branch is not pushed; nothing merges until the owner signs off at the
  campaign's end.
* `mix precommit` is green on the branch (8644 tests, 2026-10-22). Run
  everything through `~/scripts/agents/agent-mix` from the worktree.
  Test env only for `mix` tasks that touch a database: the dev TOML's
  database is the owner's.
* Wiki edits for M1 are committed locally in `~/src/media-centaur/media-centaur.wiki`
  (`9df804c`), not pushed; push with the release that carries the campaign.
* The TV app: `~/src/media-centaur/android-app` at `ec7dd58` (shell,
  player, bridge; transparent over the player's surface; the native
  output path; Back and Menu forwarded to the page), no remote yet. Each session: `mc-tv
  connect`, `mc-tv build`, `mc-tv install`; `mc-tv launch --host
  http://<LAN ip>:<port>` points it at a host; `mc-tv eval` drives the
  WebView; every TV window ends with `mc-tv hdmi` (the owner's screen). Its toolchain is its `mise.toml`; the rig is
  `~/scripts/agents/mc-tv` (run it with no arguments for usage).

**The TV (as of 2026-10-22).** Sony Bravia XR-42A90K at
`192.168.68.63` (mDNS `_androidtvremote2._tcp`, port 6466). Done the same day: the owner
turned on Developer options → ADB debugging (Sony's Google TV has no
wireless-debugging pairing step), `mc-tv connect 192.168.68.63:5555`
was authorized on the TV, and the address is remembered under
`~/.config/mc-tv/device`; every session starts with `mc-tv connect`.
The TV is Android 12 (API 31), 32-bit only (`armeabi-v7a`), 1080p
override on a 4K panel, WebView 154. The machine was rebooted the
same day (kernel 7.2.11) and `/dev/kvm` is still absent: the Ryzen 5
5600X exposes no `svm` flag (`/proc/cpuinfo` has only `svm_lock`), so
AMD-V is disabled in the BIOS and `kvm_amd` cannot load. The emulator boots
anyway, unaccelerated, in about ten minutes (`mc-tv emulator start`
warns and falls back); enabling SVM Mode in the BIOS (typically
Advanced → CPU Configuration) is optional and makes it fast. The
source-address check is done: an app on the emulator must dial the
host's LAN address, never `10.0.2.2`.

**Running the branch as a host (the end-to-end rig).** Two scripts
replace the per-session recipe: `~/scripts/agents/mc-sim-host`
(`setup` once — media, TOML, database, seed under `~/.cache/mc-sim-host`;
`start`, `stop`, `status`, `rpc '<elixir>'`, `ids`, `pairing`; bound
to every address on 4003, a device dials the LAN URL `status` prints)
and `~/scripts/agents/mc-tv-flow` (`pair`, `play`, `finish`, each one
short TV window ending with `mc-tv hdmi`; reads ids from
`mc-sim-host ids`). The simulated host's database was recreated on
2026-10-22 when the script was written, so **the TV must pair again**
(`mc-tv-flow pair tv`) before `play` or `finish`. `mc-player-sim`
remains the desktop stand-in for host-side work. Run every `mix`
through `agent-mix`; the dev TOML's database is the owner's.

**The owner's screen.** The owner's computer is displayed through the
TV's HDMI 4. Any TV window takes it away; the owner has allowed
automatic switching, asking that screen time be minimised: batch, keep
each window to a minute, always end with `mc-tv hdmi`. The TV is also
the owner's gaming screen: when the owner says it is in use, take no TV
window at all until they say it is free — verify on the desk with
`mc-player-sim` and record the TV check as pending.

**The next session's agenda: the owner's calls, then M7.** Four M6
batches are verified on the Sony (2026-10-23, records above; wiki commits
local, unpushed). Nothing is left that an agent can decide alone: decision 10 is taken
(a per-player scale factor, deferred to a future campaign — *player
operational status and settings* — to be re-homed in the campaigns
index when this one closes), Back-key and D-pad polish (the owner's walk through the TV names what to
fix), and the older calls 9 (the Sound column), 3 (the speed test), 1
(the application id). When the owner answers, run the chosen items
through the procedure, then M7 (release path and owner checks). The
Sony's player is `9586a9fc` (paired again after the removal checks); the
installed TV build carries the audio buffer. For any TV window: `mc-sim-host start` (it serves the branch and rebuilds
`app.js` on change — confirm a changed symbol with `grep` in
`priv/static/assets/js/app.js`), `mc-tv connect`, wake the TV if needed
(`mc-tv adb shell input keyevent KEYCODE_WAKEUP`); the installed build is
`ec7dd58` (the audio buffer), rebuild only after a change; `mc-tv-flow osd tv <dir>` is
the whole check and every TV check prints `DROPS:` lines. The older
checkpoint text below is kept for its facts.

**The earlier agenda (the owner's checkpoint on M5, then stage 1 —
done 2026-10-22).** Steps 1–6 ran on 2026-10-22; nothing of M5 is built except
the WebView staying up (`android-app` `f2ca2b2`). Waiting on the
owner: (1) a pick, or a mix, from the viewing layer's mockup round in
`docs/superpowers/specs/2026-10-22-tv-viewing-layer-mockups/`
(1 hairline, 2 lower-third card, 3 scrim and seek bar; each page shows
the same seven states at the TV page's 960×540); the chosen look
fixes stage 2's components and may add a measurement (direction 2's
blur over the video); (2) open decision 6, keys to the page; (3) open
decision 7, passthrough after the TV's audio setting is changed. Then
execute the plan stage by stage, recording each stage's outcome in the
M5 record. Everything below this paragraph is the older agenda, kept
for its facts.

*Older agenda (2026-10-22, morning):* The owner asked for a plan before implementation
(2026-10-22). Run the milestone procedure on "the native path and the
page as OSD": (1) scope — from the inputs listed under M5 in Next
steps, decide what each desktop OSD feature becomes on the TV, who
owns key routing, what happens to `input.conf` and the scripts
package on the TV, and what is dropped with a reason; (2) research —
read `MpvSession`'s observe list and `Transport.Remote`, the LiveView
surfaces that already react to viewing events by player, the TV
shell's key routing, and measure the WebView's cost over 4K video and
the key-to-feedback latency; (3) decisions — open decision 5 (per-file
`loadfile` options, recommended) and the key-routing owner go to the
owner with recommendations; (4) `unify_design`; (5) plan; (6)
`unify_design` on the plan; (7) execute. Read first: this file's
Decisions made and the M5 inputs; `android-app`
`docs/playback-on-android.md`; `docs/mpv.md` for the desktop OSD;
`docs/superpowers/specs/2026-10-22-remote-players-protocol-design.md`
for the channel contract (it will need an amendment: the TV draws
nothing, the page is the OSD). The staged real files and
`mc-tv-flow perf [--set vo=mediacodec_embed] [--overlay]` make every
measurement one command; the TV's paired player on the sim host is
`b8ef08c8` (re-pair with `mc-tv-flow pair tv` if `mc-sim-host ids`
shows none); `mc-sim-host start` now returns when the server is up.

**What is proven end to end** (2026-10-22, M2 record step 7): pairing by
code; channel up; `play/3`; options and `loadfile` with a tokenised media
URL; mpv fetching over HTTP Range; progress saved; `Sessions.stop/2`
quitting the player as a stop and ending the session; a second viewing;
clean host shutdown leaving the player playing; reconnect with backoff;
recovery of the viewing with its position and profile.

**What is not yet proven**: anything on a real device — D-pad and Back in a
WebView, libmpv rendering, HDR and audio passthrough, `script-opts` read
back from libmpv, the WebView's cost on a Chromecast with Google TV.

## Pointers

* `docs/superpowers/specs/2026-10-22-remote-players-protocol-design.md`
  — the host–player contract: boundaries, the player channel, media
  delivery, host and TV app architecture, the verification record.
* `docs/playback.md`, `docs/mpv.md` — session internals, IPC protocol,
  launch flags, bundled scripts.
* `~/scripts/agents/mc-player-sim` — the device stand-in: pairs, opens the
  channel, bridges a desktop mpv; the end-to-end check for any host-side
  change.
* `~/scripts/agents/mc-sim-host`, `~/scripts/agents/mc-tv-flow`,
  `~/scripts/agents/mc-tv` — the simulated host, the TV verification
  windows, the device rig (run each with no arguments for usage).
* `~/src/media-centaur/android-app` — the TV app: `README.md` is its
  contributor guide; `bridge/Ipc.kt` and `player/Player.kt` carry the
  protocol decisions in their docs.
* `dev.jdtech.mpv:libmpv` 1.0.0 (Maven Central; source
  <https://github.com/jarnedemeulemeester/libmpv-android>, `MPVLib.kt`)
  — the libmpv the TV app embeds.
* `lib/media_centaur/playback/mpv_session.ex`, `launch_flags.ex`,
  `session_recovery.ex`, `events.ex`, `resolver.ex`, `sessions.ex`.
* `lib/media_centaur_web/live/profile_aware.ex` — the on_mount pattern
  the player equivalent follows.
* `lib/media_centaur_web/plugs/image_server.ex` — the file-serving plug
  pattern.
* `lib/media_centaur/settings/config.ex` — the bootstrap/runtime split
  the bind address joins.
* ADR-023 (durable process design), ADR-062 (playlist auto-advance),
  ADR-072 (bundled mpv scripts), ADR-075 (context naming), ADR-078
  (profile held by the browser session).
* mpv JSON IPC: <https://mpv.io/manual/stable/#json-ipc>; libmpv client
  API: `libmpv/client.h` in the mpv repository.
* mpv-android: <https://github.com/mpv-android/mpv-android>; Findroid's
  libmpv artifact: <https://github.com/jarnedemeulemeester/findroid>.
