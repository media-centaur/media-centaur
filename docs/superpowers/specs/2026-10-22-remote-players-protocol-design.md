# Remote players: the host–player contract

Campaign: `campaigns/remote-players.md`. Decision records: ADR-079 (admission), ADR-080 to follow (one session type over two transports). This document is the contract the two codebases agree on: `media-centaur-app` (the host) and `android-app` (the TV app). Everything a reader needs is defined before use.

## Glossary

| Term | Meaning |
|---|---|
| **Host** | The Phoenix application. Owns the library, identity, progress, every viewing decision, and observation of every viewing. |
| **Player** | A machine that renders a viewing. The **host player** is mpv spawned on the host (`:host`); a **remote player** is a paired device running the TV app (`Players.Player`). |
| **Viewing** | One profile watching one title chain on one player: a `Playback.MpvSession`. |
| **Transport** | How a session reaches an mpv and how that mpv gets its file. **Local**: Unix socket to a spawned process, host path. **Remote**: the player channel, media URL. |
| **Player channel** | The remote player's one long-lived WebSocket to the host, carrying mpv IPC JSON. Its remote end is the TV app's **bridge**; its host end is `Playback.Remote.Channel`. |
| **Bridge** | The TV app component that turns IPC JSON into libmpv calls and libmpv events into IPC JSON. |
| **Media endpoint** | `GET /media/:presence_id`: one playable file by its `FilePresence` id, served with HTTP Range. |
| **Media URL** | The URL of one file on the media endpoint, composed by the host, handed to the player over the channel. |
| **Attached / detached** | A remote session whose channel is up / down. Detached is a state, not an end. |

## Boundaries

The organising rule: **the host decides, the player renders, mpv is the shared vocabulary.**

| Concern | Owner | Why |
|---|---|---|
| What plays, from where, under which profile, which language policy | Host | The library, progress rows, profiles and preferences are the host's; the player has no copy of any of them. |
| Observation: position, pause, end, chapters, tracks; progress persistence; completion; auto-advance; the finish prompt | Host (`MpvSession`) | Already written against mpv's property model. Moving any of it to the player duplicates state and policy. |
| Rendering, decode path, HDR output, audio output, the surface | TV app | Hardware facts the host cannot know. |
| Local input (the remote's keys → mpv commands, the Back key) | TV app | Latency: a key press must not round-trip the LAN. mpv's own key bindings and the bundled Lua scripts run inside libmpv on the player, exactly as on the host. |
| Channel liveness, reconnect, backoff | TV app (initiates), host (tolerates) | The host's address is the one thing the device knows; the device dials. |
| Who the device is | Host (`Players`, the gate) | ADR-079. |
| Pairing UI | Both | Settings → Players on the host shows the code; the TV app's pairing screen collects address and code and loads the pairing page. |

What the TV app must **never** do: persist progress, decide the next episode, hold a copy of the library, or play a file the host did not name. What the host must **never** do: assume a player is reachable, block a LiveView on a channel round-trip, or hold player-side rendering settings.

## The player channel

### Transport

A raw WebSocket at `GET /players/channel`, upgraded from a plain Plug with `WebSockAdapter` on Bandit. Not a Phoenix Channel: mpv IPC already has its own framing (one JSON object per message, `request_id` correlation), and the Phoenix join/topic/heartbeat layer and its Kotlin client would wrap it for nothing. One connection per remote player; a second connection for the same player replaces the first (the device restarted or roamed).

| Property | Value | Why |
|---|---|---|
| Frame type | Text, one IPC object per frame, no trailing newline | WebSocket frames replace mpv's newline framing one for one. |
| Max frame size | 1 MiB (`websocket_options: [max_frame_size: ...]`) | The largest real payload is `track-list` for a disc remux, tens of KiB. |
| Compression | Off | Payloads are small; deflate costs CPU on the TV for nothing. |
| Liveness | Server WebSocket ping every 15 s; a connection with no pong in 30 s is dropped | Detects a TV that lost power or WiFi without waiting for TCP. Bandit answers client pings itself. |
| Direction | The device dials the host | The device knows the host's address from pairing; the host never needs the device's. |

### Admission

The upgrade request carries the device's session cookie (the WebView and the app's WebSocket client share one cookie jar on the device). The upgrade plug fetches the session and calls `RemoteAccess.admit/2`; only a paired player may open a channel. A connection whose player is removed is closed by the host at once (`PlayerRemoved`). An `Origin` header, when present, must match the host's origin (browsers on the LAN cannot open channels from other pages); an absent `Origin` is accepted, since a native client sends none.

### Protocol

mpv's JSON IPC, verbatim, in both directions:

* Host → player: `{"command": [...], "request_id": N}`. The host sends only what `MpvSession` and `SessionRecovery` send today: `observe_property`, `get_property`, `set_property`, `loadfile`, `sub-add`, `quit`.
* Player → host: `{"event": "property-change", "id": N, "name": ..., "data": ...}` and the other events; `{"request_id": N, "error": "success" | ..., "data": ...}` replies.

The bridge implements the subset the host uses. libmpv's Kotlin surface (`dev.jdtech.mpv:libmpv` 1.0.0) is scalar: `command(Array<String>)`, `setOptionString`, `get/setProperty{String,Int,Double,Boolean}`, `observeProperty(name, format)` with events delivered through `EventObserver.eventProperty` overloads. Two consequences the bridge absorbs:

1. Node-valued properties (`track-list`, `chapter-list`, `playlist`) are observed as `MPV_FORMAT_STRING`; mpv renders them as JSON text, which the bridge parses and forwards as the `data` of a `property-change`. The host sees the same shape it sees from the Unix socket.
2. `command(Array<String>)` returns no error. The bridge replies `"success"` to a `command` it dispatched and an error string for one it refused (unknown command, malformed). `get_property` replies carry the value read synchronously.

`quit` on a remote player means *stop and show the UI again*, not *exit the process*: the bridge runs `stop` and releases the surface. mpv then reports `end-file` with reason `stop`, and the host's `Transport.Remote` treats an `end-file` whose reason is `stop` or `quit` as the end of the viewing (the session finalises and ends). The libmpv instance stays alive for the next viewing. Verified 2026-10-22 with `mc-player-sim` against a desktop mpv.

**Rate of `time-pos`.** mpv raises `property-change` for `time-pos` many times a second (358 events in about 15 s in the end-to-end run). The host needs one a second: the bridge coalesces `time-pos` to 1 Hz before it crosses the channel, forwarding the latest value. Every other property passes through as it changes.

### Launch

A viewing on a remote player is one `loadfile` with per-file options, preceded by the per-instance options that today are command-line flags. `Playback.LaunchFlags` becomes a list of `{option, value}` pairs rendered two ways: as `--option=value` for the host spawn and as `set_property`/`loadfile` options for the player. The bundled scripts (`--script=`) and the language policy are options like any other; the TV app ships the same `priv/mpv/scripts/media-centaur` package in its assets and points libmpv at it.

### Reconnect and recovery

| Event | Host behaviour |
|---|---|
| Channel drops mid-viewing | The session goes **detached**: no progress writes, no state broadcast beyond `:detached` if the UI wants it. A 60 s reattach window. |
| Same player reconnects within the window | The channel re-offers the live mpv: the host re-sends `observe_property` for its set, reads `path`, `time-pos`, `script-opts`, and continues. Same mechanism as `SessionRecovery` reading a socket back. |
| Window expires | The session finalises as a stop, with the last persisted position. |
| Host restarts | On reconnect the channel finds no session for the player; `SessionRecovery` queries the player as it queries a socket (`path`, `time-pos`, `script-opts`'s profile id) and starts a reconnecting session. The media URL's presence id resolves the entity. |
| TV app dies mid-viewing | The channel closes without `end-file`; the viewing ends when the window expires. A restarted app reconnects with an idle libmpv and reports no `path`, so nothing is recovered. |

### Backpressure and volume

At most a few messages per second per player (`time-pos` once a second; a burst of `track-list`, `chapter-list`, `playlist-*` at file load). No flow control is needed beyond the frame-size cap. The host's channel process is a plain `GenServer` per player; the session process sends to it and never waits for a reply, so a slow TV cannot block a session or a LiveView.

## Media delivery

### Endpoint

`GET /media/:presence_id`, a plug in the endpoint behind the gate beside `ImageServer`, not a router route: no session fetch, no CSRF, no layouts.

| Aspect | Behaviour |
|---|---|
| Identity | The `FilePresence` id. The plug reads the row, checks the path lies under a configured media directory, stats the file. |
| Body | `Plug.Conn.send_file(conn, status, path, offset, length)`. Bandit hands it to the kernel (`sendfile`), zero-copy; the BEAM never touches the bytes. |
| Range | A single `bytes=start-end` or `bytes=start-` → `206` with `Content-Range`, `Content-Length`, `Accept-Ranges: bytes`. No Range → `200` whole file. Multi-range or unsatisfiable → `416`. ffmpeg's HTTP demuxer uses single open-ended ranges and reopens on seek, so this is the whole surface. |
| Headers | `Content-Type` from the extension (`video/x-matroska`, `video/mp4`, …), `Last-Modified` and `ETag` from mtime and size so a reopen can be `304`-validated, `Cache-Control: private, no-store` (the TV never caches media). |
| `HEAD` | Answered with the headers and no body. |
| Errors | Unknown id or path outside every media directory → `404`. Unmounted drive → `503` so the player reports a transient failure rather than a missing file. |

### Why not transcode, remux or mount

Direct play keeps fidelity and keeps the host idle. libmpv on the device decodes with MediaCodec and renders with gpu-next; no server-side ffmpeg pipeline, no second copy of the file, no quality ladder. A network share on the device was rejected: an Android TV app cannot mount one, and it would move file identity out of the host.

### Throughput budget

| Source | Bitrate | LAN need |
|---|---|---|
| 1080p remux | 25–40 Mbit/s | Any wired or 5 GHz WiFi link. |
| 4K HDR remux | 60–100 Mbit/s | Gigabit wire, or 5 GHz WiFi 5/6 with a clean channel. |

Sequential `sendfile` from an SSD saturates these without effort; the limit is the device's WiFi. Player-side cache options (`cache=yes`, `demuxer-max-bytes` around 150 MiB, `demuxer-readahead-secs` 20) ride out WiFi jitter and are the TV app's instance options, not the host's.

### Credential for media requests

An open decision, recorded in the campaign. The two coherent options:

1. **Session cookie.** The TV app copies the WebView's session cookie into libmpv's `http-header-fields` so every media request is admitted by the gate as the paired player. One credential, no new code on the host. Cost: the session cookie, which also admits the UI, travels on every media request and lands in any log that captures headers; libmpv needs the cookie plumbed at every launch.
2. **Capability URL.** The host signs a short-lived token over `{player_id, presence_id}` (`Phoenix.Token`, 12 h, the endpoint's key) into the media URL it composes. The gate admits a `/media/*` request by that token alone. Cost: a second admission path, scoped to one file, one player, one window; the token is only ever minted by the host for a session it started.

Recommendation: the capability URL. The media request is made by a native media stack, not a browser; it should carry a capability for one file, not the device's whole identity.

### Sidecar subtitles

`--sub-auto` finds nothing over HTTP. The host knows a file's sidecar subtitles (`Subtitles`) and adds each as `sub-add <media URL of the sidecar>` after `loadfile`. Sidecars are `FilePresence` rows too, so the media endpoint serves them unchanged. Not in the skeleton; first hardening item.

## Host-side architecture

```
Playback.play(profile_id, uuid, player)        player :: :host | player_id
  └─ Resolver → play_params
  └─ Sessions.play(play_params, player)
       └─ MpvSession (unchanged observer)
            └─ Transport (behaviour): connect/1, send/2, reattach/1, close/1
                 ├─ Transport.Local   Port spawn + Unix socket (today's code, moved)
                 └─ Transport.Remote  Playback.Remote.Channel for the player
Playback.Remote.Channel                        one per connected remote player
  ├─ started by MediaCentaurWeb.PlayerSocket (the WebSock handler) on upgrade
  ├─ registry by player_id; the socket process forwards frames to it
  └─ fans events to the attached MpvSession; queues nothing when none
SessionRegistry                                keyed by {player, entity_id}
```

Boundary rules: `Playback` takes a player as a value and never depends on `Players`, as it takes a profile id and never depends on `Profiles`. The web layer owns the WebSocket handler and the media plug and already depends on `Playback`. `Playback.Events` gain a `player` field so the UI can say where a viewing is.

## TV app architecture

Kotlin, Android TV (Leanback launcher intent), minSdk 26 from the libmpv artifact.

| Module | Owns |
|---|---|
| `pairing` | First-run screen: host address, name, code; loads the host's pairing page in the WebView and detects success (the session cookie now admits `/`). Stores the host address. |
| `shell` | The `WebView` showing the host's UI. D-pad events reach the page; Back is intercepted natively and pushed to the page as a `BACK` input-system action, so the page's own back semantics hold (UIDR-028). |
| `player` | One `MPVLib` instance for the app's life, a `SurfaceView`, instance options (hwdec `mediacodec`, `vo=gpu-next`, `gpu-context=android`, the cache options, `script=` the bundled package). Shown over the WebView while a file plays; hidden on `quit`. |
| `bridge` | The WebSocket client (OkHttp), IPC JSON ⇄ `MPVLib`, the observer that re-emits property changes as events, reconnect with exponential backoff (1 s → 30 s), identity by the shared cookie jar. |

The app has no model of titles, profiles or progress. Its persistent state is the host address and the cookie jar.

## Security summary

* Admission is ADR-079's for every surface: pages, images, the channel, media. The only addition is the media capability token if chosen.
* The channel is the host's command path into a device: it is opened only by a paired player's session, carries only mpv commands the host composes, and is closed when the player is removed.
* Media URLs name a presence id, never a path; the plug confines every path to the configured media directories.
* No TLS on the LAN in this campaign. The threat model is a household network; the install already trusts it for the UI once `bind` opens. Named as a known gap.

## Verification record

| Claim | Status |
|---|---|
| `dev.jdtech.mpv:libmpv` 1.0.0 builds mpv 0.41 with Lua enabled (`-Dlua=enabled` in its `mpv.sh`) | Verified 2026-10-22 |
| Its Kotlin API is instance-based with scalar property observation only | Verified 2026-10-22 (`MPVLib.kt`) |
| minSdk 26, MIT | Verified 2026-10-22 (`build.gradle.kts`) |
| Bandit 1.13 does `sendfile` with offset and length through ThousandIsland; WebSockAdapter upgrades from a plain Plug; `max_frame_size` configurable | Verified 2026-10-22 (deps source, hexdocs) |
| mpv IPC: one JSON object per message, `request_id` correlation, events may interleave with replies | Verified 2026-10-22 (`DOCS/man/ipc.rst`) |
| D-pad focus into an Android System WebView on Google TV; Back key dispatch order | Open; first thing the TV skeleton tests on hardware |
| HDR passthrough and multichannel audio passthrough through libmpv on a Chromecast with Google TV | Open; hardening milestone |
| `script-opts` readable back from libmpv for recovery | Verified 2026-10-22 on the Sony: the bridge answers `get_property script-opts` as a map parsed from libmpv's `k=v,…` string (amendment below) |
| D-pad focus into the WebView on the Sony; Back reaches the app first | Verified 2026-10-22: arrow keys move the page's focus; the activity intercepts Back before the WebView |
| libmpv plays over the media endpoint on a 32-bit Sony Bravia (Android 12) | Verified 2026-10-22: `hwdec=mediacodec`, `vo=gpu`, full screen |
| The session cookie survives the app's process restarts | Verified 2026-10-22: paired across three reinstalls |

## Amendments

**2026-10-22 — the `end-file` reason.** `dev.jdtech.mpv:libmpv` 1.0.0
forwards only the event id for `MPV_EVENT_END_FILE` (`event.cpp`), not
`mpv_event_end_file.reason`. The bridge supplies the reason: `stop`
when a stop was asked for since the last `loadfile` (the host's `quit`,
or Back on the remote), `eof` otherwise. `error` is never sent; mpv
does not set `eof-reached` when it moves straight into the next
playlist entry, and the host treats every reason but `stop`/`quit`
alike. The sentence "mpv then reports `end-file` with reason `stop`"
above holds of mpv, not of the binding.

**2026-10-22 — rendering rules.** "Node-valued properties observed as
`MPV_FORMAT_STRING` and parsed" is one case of a table in the bridge
(`PropertyFormat`): JSON-text properties (`track-list`, `chapter-list`,
`playlist`, …) are parsed; key-value lists (`script-opts`) become an
object, which recovery requires; `yes`/`no` and numerals become their
scalars (`aid`, `sid`); `time-pos`, `duration` are observed as doubles,
`pause`, `eof-reached` as flags, `playlist-count`, `playlist-pos` as
integers.

**2026-10-22 — the page is the OSD (M5, UIDR-055).** Three rows above
no longer hold. *Local input* (Boundaries): the remote's keys go to the
page, not to mpv; the page's viewing behaviour turns them into
`Playback.Command`s the host renders to IPC and sends down the channel
(page → host → channel → mpv ≈10 ms, measured on the Sony). No
`input.conf`, no `keypress`, no bundled scripts on the player. *The
`player` row* (TV app architecture): `script=` is gone and `vo=gpu-next`
is `vo=mediacodec_embed` — the decoder writes straight to the surface for
native 3840×2160 HDR10 and mpv draws nothing; the WebView stays visible
over the surface for the whole viewing. *Launch*: every `loadfile`
carries the session options as per-file options (ADR-080's amendment),
the language policy and the profile included, and the TV app ships no
scripts package. The host keeps a per-player **viewing stream**
(`Playback.subscribe_viewing/1`: the viewing on attach, on every
discrete change, position once a second) from which the page draws the
layer; `sub-text` and `chapter` join the observed set. The shell forwards
Back and Menu to the page as `Escape` and `ContextMenu` keydowns on the
focused element — never on the document, whose target the page's
keyboard source cannot read; every other key the WebView delivers as is.

## The end-to-end skeleton

The smallest vertical slice that exercises every boundary, built before anything is hardened:

1. Host: `Transport` seam with `Local` carrying today's behaviour (tests unchanged).
2. Host: `Playback.Remote.Channel` + `PlayerSocket` + the media endpoint + `play/3`, verifiable from the host alone with a desktop mpv driven through a small script that speaks the channel (`scripts/agents/mc-player-sim`).
3. TV app: pairing screen, WebView shell, libmpv surface, bridge. Pairs, browses, plays one file, reports progress, auto-advances an episode.

Then iterate: detach/reattach window, host-restart recovery, sidecar subtitles, HDR and audio output, Back-key and D-pad polish, Play internal track.
