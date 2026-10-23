# The player model: an engineering quality pass

Campaign: `campaigns/remote-players.md` (M8). Written 2026-10-23 against
branch `remote-players` at `4638956a`, after M1–M7 were built by rapid
prototyping. This is the `unify_design` pass over everything the campaign
built for playing on more than one player: the affected slice designed
again from first principles, laid over the code, and every gap decided.
Nothing here is implemented; the owner approves the trade first.

## Glossary

Assumes the campaign's glossary (player, host player, remote player,
pairing, the gate, transport, player channel, media endpoint, playback
session, viewing, viewing layer). Terms this document adds:

| Term | Meaning |
|---|---|
| **Player id** | The value that names a player everywhere in the host: `:host` for the host player, the `players` row's id for a remote player. The one representation of "which player". |
| **Kind** | Which of the two a player is, host or remote. Chosen from the player id in one place; it decides the transport and nothing else directly. Every other difference between the two is a question the transport answers. |
| **Connected player** | A remote player with a channel open to the host right now (`Playback.Remote.PlayerRegistry`). A paired player may be connected or not. The host is never "connected": its mpv is spawned. |
| **Locators** | The three functions the web layer hands a channel at connect: compose a presence's media URL, compose the URL of a sidecar beside it, read a presence id back from a media URL. How Playback names a file to a remote mpv without composing a URL itself. |
| **Enforcement point** | A surface that carries the gate's verdict and acts on a player's removal: the HTTP plug, the LiveView socket hook, the player channel's socket. ADR-079 named the first two. |
| **Entry** (proposed name) | One file of a viewing chain with its library identity and resume position: the shape that `Resolver.play_params`, `NextEpisode.queue_item`, `NextEpisode.identify/2`, `SessionRecovery.build_params/3` and the session's own fields each spell today. |
| **Property mirror** (proposed name) | The session's copy of what mpv last reported for each observed property. |

## 1. The core idea

Unchanged from ADR-080: *a playback session is one profile watching one
title chain on one player, observed over mpv IPC whichever machine runs
the mpv; the transport is the one thing that varies per player.*

The pass did not find a wrong idea. It found an idea without one
representation. "Player" is held four ways on the branch: as
`:host | String.t()` in Playback, spelled nine times (once as a typespec
that resolves to no module); as `:host | %Players.Player{}` on the
socket, converted to the first form by a helper, with nothing reading
the struct's fields; as a `{pid, locators}` registry entry; and as a
kind decided by `is_binary/1` in more than one function. The boundary
ADR-080 states, that Playback takes a player as a value and never
depends on Players, is crossed by one alias. And the observer the
transport seam was cut out of is still one process of 1,122 lines
holding six concerns in a struct of 39 fields.

## 2. The greenfield shape

### 2.1 Three owners

| Owner | Owns | Does not own |
|---|---|---|
| `MediaCentaur.Players` | The set of paired players: rows, names, the pairing code, `players:updates`. | Whether a player is connected; what plays on it; who a request is from. |
| `MediaCentaurWeb` | Admission (`RemoteAccess.admit/2`) and its enforcement on every surface; URL composition (locators, `MediaToken`); the media endpoint; the viewing layer; Settings → Players. | mpv, sessions, the channel protocol. |
| `MediaCentaur.Playback` | Viewings: sessions keyed by `{player, entity_id}`, the two transports, the channel protocol and the connected set, recovery, the viewing stream, commands. | Players rows and events; URLs; admission. |

Dependencies: Web → Players, Web → Playback; Playback → Library,
Settings, Subtitles; Players → nothing. Playback → Players is not a
dependency. Playback reacts to a player's removal only as a transport
fact (its channel closed for good), never by reading a Players event.

### 2.2 One representation per idea

| Idea | Representation | Defined once in |
|---|---|---|
| Which player | `:host \| Ecto.UUID.t()` | `Players.Player.id/0`; `Playback.player/0` is its name inside Playback and for the web layer. Every other spelling references one of the two. |
| The player a request or socket is on | its player id, in `:player` | `RemoteAccess.admit/2` returns it; `PlayerAware` assigns it. |
| A player's kind | chosen from the id | `Sessions.transport_for/2`, the one `:host`-or-binary dispatch in Playback. |
| What differs between the kinds beyond reachability | transport properties | `Playback.Transport`: `draws_subtitles?/1`, a new "holds one viewing at a time", and recovery (§2.3). |
| A connected remote player | its channel's registry entry | `Playback.Remote.PlayerRegistry`. |
| The host's standing | a sentinel, not a row | `:host`, admitted by address (ADR-079). |
| The file a chain is on | one struct | Entry (§2.4). |

**The host stays a sentinel.** Considered and declined: a `players` row
for the host, seeded at install. It would make every player a row and
any future per-player setting uniform, at the price of a bootstrap row
that must never be deleted, and a UUID for a player whose identity is
its address. The host is different in kind: admitted by address, never
paired, never removed, its mpv spawned. The sentinel says so. A future
per-player setting for a remote player is a row keyed by its UUID; the
host's equivalent is the install's Setting it already has, which is
where decision 10 of the campaign placed the desktop's scale floor.

### 2.3 Where each question about a player is answered

| Question | Answered by |
|---|---|
| Is this request or socket the host, or a paired player? | Web: `RemoteAccess.admit/2`, from the address and the session. |
| Which player does Play start on? | Web: the socket's `:player`, passed to `Playback.play/3`. |
| How is this player's mpv reached? | Playback: `Sessions.transport_for/2` → `Transport.Local` or `Transport.Remote`. |
| Can it hold two viewings? | The transport. |
| Does it draw subtitles? | The transport (`draws_subtitles?/1`). |
| What does `quit` mean to it? | The transport (Local: exit; Remote: stop). |
| What is it told to load, and what did it load? | The transport (`locator/2`, `identify/2`). |
| Which of its mpvs outlived their session? | The transport finds them and reads their properties; `SessionRecovery` turns the readings into reattach params; `Sessions.recover/1` is the one door, keyed by player. |
| Is it connected? | Playback: `PlayerRegistry.lookup/1`. |
| What happens when it is removed? | Web, at every enforcement point: the plug on the next request, the LiveView hook at once, the channel socket at once; the media endpoint on the next range request. |
| Whose viewings does a page show? | Web: its own player's; Status shows every player's. |

### 2.4 The session's shape

The observer becomes a thin GenServer over pure modules, each testable
without a process:

* `MpvSession` keeps the lifecycle only: open the transport, fold
  transport events, the reattach window, finalise, terminate.
* **Entry**: what plays now. The file, its library identity (entity id
  and name; episode, movie, extra or video-object id; season and episode
  numbers and name) and resume position. One struct where five map
  shapes are today. Built by `Resolver` and `NextEpisode`, read back by
  `SessionRecovery`, re-pointed by an advance.
* **Property mirror**: what mpv last reported. Position, duration, pause,
  path, chapters and the current chapter, the tracks and `aid`/`sid`,
  playlist count and position, the subtitle line, eof. One function folds
  a `property-change` in; `Viewing` reads from it and from the Entry.
* The chain (ADR-062): the queue test, the append, the advance, over an
  Entry and the mirror.
* Progress persistence: the Library writes that run in tasks today, as a
  module taking an Entry, a position and a completion verdict.
* Track policy: `LanguageContext` takes the orchestration that the
  session's track-list, enforcement and capture handlers do, and answers
  with the IPC commands to send.
* The viewing stream: unchanged, reading the Entry and the mirror.

`Transport`, `Viewing`, `Command`, `Events` and `LaunchFlags` stay as
they are.

### 2.5 Layout

The directory says which transport a file belongs to:

```
lib/media_centaur/players/                 identity and pairing: rows, the code, events
lib/media_centaur/playback.ex              facade: play/3, command/3, the subscribe doors, player/0
lib/media_centaur/playback/
  sessions.ex session_registry.ex session_supervisor.ex supervisor.ex
  session_recovery.ex                      the shared half of recovery
  mpv_session.ex                           (+ after M9: entry, the mirror, the chain, persistence)
  transport.ex
  transport/local.ex                       the host player
  transport/local/{ipc_framing,exit_classifier,log_reader,user_config}.ex
  transport/remote.ex                      a paired player
  transport/remote/{channel,player_registry}.ex
  viewing.ex command.ex events.ex launch_flags.ex …   unchanged
lib/media_centaur_web/
  remote_access.ex                         the policy
  plugs/remote_access.ex live/player_aware.ex player_socket.ex   the three enforcement points
  plugs/player_channel.ex media_token.ex plugs/media_server.ex   URLs and media
  live/viewing_aware.ex components/viewing_layer.ex              the viewing layer
  controllers/pairing_controller.ex live/settings_live/players_section.ex
```

`Platform.DisplayEnv` stays under `Platform`: it is OS knowledge, as its
doc says.

## 3. The diff against the branch

Every gap, with its disposition. *M8* is this pass's execution; *M9* is
the session's shape, a milestone of its own; *owner* is a call recorded
under the campaign's open decisions.

| # | Found | Disposition |
|---|---|---|
| 1 | The player type is spelled nine times: `SessionRegistry.player/0`, `Sessions.player/0`, `Playback.player/0`, `Viewing.t/0`, four `Events` structs, `LiveHelpers.playback_scope/0`, `PlayerAware.playback_player/1`'s spec; `MpvSession.command/2`'s spec names `Sessions.player()` without an alias, so it resolves to no module. | **M8.** One definition (§2.2); every other spelling references it; `playback_scope/0` goes. |
| 2 | The socket holds `:host \| %Players.Player{}`; Playback holds `:host \| id`; `PlayerAware.playback_player/1` converts; `ViewingAware` and `Plugs.PlayerChannel` pattern-match the struct. Nothing reads a field of the struct. | **M8.** `RemoteAccess.admit/2` returns `{:ok, Playback.player()}`; `:player` is the id; the converter goes; the matches become matches on the id. |
| 3 | `Playback.Remote.Channel` subscribes to `players:updates` and matches `Players.Events.PlayerRemoved`; `Playback`'s Boundary deps include `Players`. ADR-080, the protocol spec and `Sessions`' moduledoc say Playback never depends on Players. | **M8.** The channel's socket (`MediaCentaurWeb.PlayerSocket`) is the gate's third enforcement point: it subscribes to Players and, on its own player's removal, drives `Channel.removed/1`, which tells the session, pushes `stop` and closes `{:shutdown, :removed}` as today. `Transport.Remote` keeps treating that close reason as final. `Players` leaves Playback's deps; ADR-079 gets a dated amendment naming three enforcement points. |
| 4 | `Sessions` decides the kind by `is_binary/1` twice: `transport_for/2` (the transport) and `replace_remote_viewing/1` (whether a player holds one viewing). The second is a property of the remote player's mpv, which the transport knows. | **M8.** A transport callback, "holds one viewing at a time" (name: owner, decision 14); `Sessions.play/2` builds the transport first and asks it; `transport_for/2` becomes the one kind dispatch. |
| 5 | `SessionRecovery` knows both transports' internals: it names socket files, opens Unix sockets and parses IPC lines for the host; it calls `Channel.request/3` and the locators for a remote. That is the interleaving ADR-080 removed from `MpvSession`, left in recovery. The two triggers (boot → `recover_all/0`; channel connect → `recover_player/1`) call `Sessions.resume/2` from two places. | **M8.** Each transport finds its own orphaned mpvs and gives a property reader for each; `SessionRecovery` keeps the shared half (position, profile and entity from a reader and a host path). One door, `Sessions.recover(player)`: the boot task calls it with `:host`, a connecting channel with its player id. `Playback.recover_player/1` leaves the facade. |
| 6 | "A channel connected" is handled in two places: `Channel.connect/2` tells live sessions `{:channel_up, pid}`; `PlayerSocket.init/1` triggers recovery when no session holds the player, reading `SessionRegistry` from the web layer to decide. | **M8**, with 5. `Channel.connect/2` does both; the socket speaks frames only; `SessionRegistry` leaves Playback's exports if nothing else outside needs it. |
| 7 | `MediaToken` signs `{player_id, presence_id}` and `Plugs.MediaServer` ignores the player id. A removed player's media URL serves for up to 12 h. The campaign's completion criteria say revoking a player cuts it off. | **M8.** `MediaServer` admits only when `Players.get(player_id)` is a row: the token's player id gets its purpose, and removal reaches media on the next range request (a handful per viewing; a SQLite read each). |
| 8 | `Transport.Remote.locator/2` returns the host path when the file has no presence row, with a warning. A remote mpv then gets a path it cannot fetch and fails later as an mpv error, not as a `PlaybackFailed`. | **M8.** `locator/2` answers `{:ok, locator} \| {:error, reason}`; the session turns an error at open into `{:closed, {:error, …}}` (a `PlaybackFailed` the page can flash) and an error at queue time into the chain's end. |
| 9 | The host transport's helpers (`IpcFraming`, `MpvExitClassifier`, `MpvLogReader`, `MpvUserConfig`) sit at `Playback.*` beside the observer; only `Transport.Local` uses them. The remote side is split between `Playback.Remote.*` (the channel, the registry) and `Playback.Transport.Remote`. | **M8, owner (decision 13).** The layout of §2.5: each transport's helpers under it. A rename sweep across modules, tests, docs and the glossary; cheap while the branch is unmerged. |
| 10 | `MpvSession`: 1,122 lines, 39 fields, six concerns (§2.4). `Viewing.from_session/1` reads twenty fields of the private struct. `reset_for_file/4` takes a path, a map of foreign keys and a map of numbers because no struct names the entry. | **M9, owner (decision 12).** The session's shape of §2.4, a pure refactor behind `mpv_session_test`, `mpv_session_transport_test`, `track_override_round_trip_test` and both recovery tests. |
| 11 | The entry shape is spelled five times (glossary, *Entry*). | **M9**, with 10. |
| 12 | `Topics`' table lists `playback:events` but not the per-player `playback:viewing:<player>` topics. | **M8.** A row. |
| 13 | "Locators" is a coined term used in four modules and defined in none of the glossaries. | **M8, owner (decision 14).** Either the glossary row above, or a plain name. |
| 14 | Two reducers keep a page's playing set: `LiveHelpers.apply_playback_change/3` (the page's own player, keyed by entity id) and `StatusHelpers.apply_session_change/2` (every player, keyed by player and entity). | **No change.** The registry is the one truth; each map is a read model shaped for its page's reads (`Map.get(playback, entity_id)` on Home and Library, a board on Status). Two shapes for two reads are not two truths. |
| 15 | `Playback.Remote.PlayerRegistry` registers channels and is named for players. | **No change.** It is the connected set, which is what Settings → Players will read for "online" in the campaign the owner named (*player operational status and settings*). The name says what a reader asks it. |

Seams that already fit and stay: `Playback.Transport` and its two
implementations and the fake; `Playback.Viewing` and `Playback.Command`
as the one viewing and the one command door; `Playback.Events` with
`player` on every viewing event; `SessionRegistry` keyed by
`{player, entity_id}`; the locators as the web layer's URL knowledge
handed to a channel at connect; `MediaToken` as a file-scoped
capability; `RemoteAccess.admit/2` as the one policy; `Live.PlayerAware`
and `Live.ViewingAware` as the socket's player and its OSD;
`Players.Pairing` as a process (the one open code is state across
calls).

## 4. Decisions for the owner

Recorded as open decisions 11–14 of the campaign.

11. **Run M8 before the merge.** Recommendation: yes. One session, a
    pure refactor plus two behaviour fixes (7 and 8), behind existing
    tests; it leaves the branch's design true to its own records.
12. **M9, the session's shape: before or after the merge and release.**
    Recommendation: after. It is independent of the release, the branch
    already touches 163 files, and the TV check (`mc-tv-flow osd tv`)
    reruns once at M9's end either way.
13. **The layout of §2.5.** Recommendation: yes, in M8.
14. **Names.** The transport callback for "holds one viewing at a time";
    *Entry* and *property mirror* for M9; *locators* kept as a glossary
    term or renamed. Naming is the owner's.

**Taken 2026-10-23.** 11: yes, now. 12: M9 immediately after M8, on the
branch; the owner is not ready to consider a merge and will name the
checks that come first. 13: yes. 14: the agent suggested
`single_viewing?/1`, `Playback.Entry`, `Playback.MpvProperties` (in
place of "property mirror") and *media URLs* in place of *locators*;
the owner's word is pending. The plan is in the campaign's M8 record.

## 5. Cost

| Milestone | Scope | Sessions | Verification |
|---|---|---|---|
| M8 | Items 1–9, 12, 13 | one | `mix precommit` green; `mc-player-sim` for 5–8; `m6tv` (removal) and `m6tv-d` (channel drop, host restart) on the Sony for 3, 5 and 7 |
| M9 | Items 10, 11 | two to three | the session's existing tests unchanged; `mc-tv-flow osd tv` once at the end |

Documents M8 amends: ADR-079 (three enforcement points; media admitted
by token and row); `Sessions`' and `Channel`'s moduledocs;
`docs/playback.md` (module table, recovery); `docs/GLOSSARY.md` (the
rows above); the protocol spec's host-side architecture; `Topics`.
ADR-080 stands as written.
