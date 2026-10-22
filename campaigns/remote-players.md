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

**M1 built 2026-10-22 on branch `remote-players`** (worktree
`../media-centaur-app-remote-players`), `mix precommit` green; waiting
for the owner to merge. The wiki edits are committed locally in the wiki
repo and not pushed. Next: M2, the transport extraction, through the
milestone procedure.

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
* `2026-10-22` — The TV app ships `priv/mpv/scripts/media-centaur` in its assets and points libmpv at it; verified that the `dev.jdtech.mpv:libmpv` 1.0.0 artifact builds mpv 0.41 with Lua enabled. (spec, verified)

## Open decisions

1. **The credential on media requests.** (a) The TV app copies the
   session cookie into libmpv's `http-header-fields`, so the gate admits
   media requests like any other — one credential, but the device's
   whole identity travels on every byte-range request and lands in
   header logs. (b) The host signs a capability token over
   `{player_id, presence_id}` into each media URL it composes
   (`Phoenix.Token`, 12 h); the gate admits `/media/*` by that token
   alone — a second admission path, scoped to one file for one player.
   Recommendation: (b). Spec § Media delivery → Credential.
2. **Pushing the branch.** The owner asked for the work "in remote
   branch"; the branch exists locally only. Pushing `remote-players` to
   the public origin is outward-facing and waits for a yes.

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
3. **M3 — TV app skeleton** (`~/src/media-centaur/android-app`).
   Pairing screen, WebView shell, one libmpv instance on a surface, the
   bridge with reconnect, the bundled scripts in assets. Pairs, browses,
   plays one file, reports progress, auto-advances an episode on a real
   Chromecast with Google TV. Verification items below are answered here
   on hardware.
4. **M4 — Hardening.** Detach/reattach semantics end to end;
   host-restart recovery; sidecar subtitles over the media endpoint;
   HDR and audio passthrough options; Back-key and D-pad behaviour in
   the WebView; WebView rendering cost of the glass UI on the device;
   a removed player's channel closed at once.
5. **M5 — Release path and owner checks.** Signing in CI, Google Play
   internal testing track, wiki page for the TV app, ADR-080 (one
   session type over two transports), glossary elevated; the owner's
   walk through every page and the full viewing lifecycle on the TV.

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

## Pointers

* `docs/superpowers/specs/2026-10-22-remote-players-protocol-design.md`
  — the host–player contract: boundaries, the player channel, media
  delivery, host and TV app architecture, the verification record.
* `docs/playback.md`, `docs/mpv.md` — session internals, IPC protocol,
  launch flags, bundled scripts.
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
