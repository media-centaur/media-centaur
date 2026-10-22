---
status: in-progress
started: 2026-10-22
last_updated: 2026-10-22
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

**M3 built and checked on hardware 2026-10-22 on branch
`remote-players`**: the Android rig (SDK, JDK pin, `mc-tv`, AVD, the
app repository's empty shell) builds, installs, launches, drives and
observes the app on the owner's Sony Bravia XR-42A90K
(`192.168.68.63`, Android 12, 32-bit). The emulator runs unaccelerated
(AMD-V is off in the BIOS); SVM Mode would make it fast. M1 and M2 are built
and verified against the simulator; nothing merges to main before the
owner's sign-off at the campaign's end; the wiki edits are committed
locally in the wiki repo and not pushed. Next: M4, the TV app skeleton —
scope, research, decisions and the design pass recorded; the plan and
execution follow the owner's word on the design.

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

## Open decisions

1. **Application id and display name** — `app.mediacentaur.tv` and
   "Media Centaur" are provisional in the app repository. An id cannot
   change after the first Play upload, so the owner confirms both
   before M6. Recommendation: keep them.

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
2. **M2 — Host side of the skeleton.** `Playback.Transport` seam with
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
4. **M4 — TV app skeleton** (`~/src/media-centaur/android-app`).
   Pairing screen, WebView shell, one libmpv instance on a surface, the
   bridge with reconnect and `time-pos` coalesced to 1 Hz, the bundled
   scripts in assets. Pairs, browses, plays one file, reports progress,
   auto-advances an episode on a real Chromecast with Google TV.
   Verification items below are answered here on hardware.
5. **M5 — Hardening.** Detach/reattach end to end on the device;
   host-restart recovery on the device; sidecar subtitles over the media
   endpoint; HDR and audio passthrough options; Back-key and D-pad
   behaviour in the WebView; WebView rendering cost of the glass UI on
   the device; a removed player's channel closed at once; Home's pinned
   "playing" rows filtered by player.
6. **M6 — Release path and owner checks.** Release signing in CI, Google
   Play internal testing track, wiki page for the TV app, glossary
   elevated to `docs/GLOSSARY.md`; the owner's walk through every page
   and the full viewing lifecycle on the TV.

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

Everything a cleared context needs, verified 2026-10-22. Reconcile
against `git log remote-players` first (the reconciliation rule).

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
* The TV app: `~/src/media-centaur/android-app`, first commit `98800d9`,
  no remote yet. Its toolchain is its `mise.toml`; the rig is
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

**Running the branch as a host (the end-to-end rig).**
* Scratch config: `/tmp/claude-1000/-home-shawn-src-media-centaur-media-centaur-app/4804e16b-c167-4c22-8eb8-6d5631bc6c6f/scratchpad/sim/media-centaur-sim.toml`
  — `bind = "0.0.0.0"`, port 4003, its own database and a media dir
  holding one generated 90 s MKV under `Sample Movie (2010)/`. The
  scratchpad is per session: a new session recreates it (ffmpeg
  `testsrc`/`sine` to make the file; `agent-mix ecto.create`/`ecto.migrate`
  under `MEDIA_CENTAUR_CONFIG_OVERRIDE`; the seed snippet is in the
  commit `7d2a74e7` conversation record below).
* Seed: `Library.Containers.create!(:movie, …)`, `Library.PlayableItems.find_or_create(:movie, id, 1)`,
  `Library.Files.link!(%{file_path, media_dir, playable_item_id})`,
  `Settings.Config.update(:setup_wizard_dismissed, true)`, run with
  `MEDIA_CENTAUR_CONFIG_OVERRIDE=<toml> agent-mix run -e '…'`.
* Server: from the worktree,
  `MEDIA_CENTAUR_CONFIG_OVERRIDE=<toml> MIX_BUILD_ROOT=~/.cache/agent-mix-build/media-centaur-app-remote-players mise exec -- elixir --sname mc_sim -S mix phx.server`,
  ready line "Running MediaCentaurWeb.Endpoint … 0.0.0.0:4003".
* Driving it: `elixir --sname probe_$$ --cookie "$(cat ~/.erlang.cookie)" --rpc-eval mc_sim@<short hostname> '<code>'`
  from a cwd outside the checkout (`uname -n | cut -d. -f1` is the host;
  `hostname` is not installed). `Players.start_pairing()`, `Players.list()`,
  `Playback.play(profile_id, uuid, player_id)`, `Sessions.stop/2`,
  `Sessions.list/0`, `Remote.PlayerRegistry.connected/0`.
* The device stand-in: `~/scripts/agents/mc-player-sim --host http://<LAN ip>:4003 --code <6 digits>`
  (or `--cookie <value>` once paired). It must dial the LAN address
  (`ip -4 -o addr show scope global`), never loopback, or the gate treats
  it as the host. It logs every frame (`>>` host→mpv, `<<` mpv→host) and
  maps `quit` to `stop`.
* Shut the host down with `spawn(fn -> Process.sleep(200); System.stop() end)`
  over RPC; the simulator's mpv keeps playing and recovery reattaches on
  the next start.

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
