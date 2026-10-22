---
status: accepted
date: 2026-10-22
---
# One playback session type over two transports

Campaign: `campaigns/remote-players.md` (M2). Design: `docs/superpowers/specs/2026-10-22-remote-players-protocol-design.md`. Builds on ADR-023 (mpv outlives the backend), ADR-062 (auto-advance rides the mpv playlist) and ADR-079 (admission by pairing).

## Context and Problem Statement

A viewing on a paired TV must have everything a viewing on the host has: progress, completion, track memory, auto-advance, the finish prompt, recovery after a backend restart. All of that lives in `Playback.MpvSession`, written against mpv's property model over its JSON IPC socket. The TV app embeds libmpv, which exposes the same property and command model. The question was whether the remote viewing gets a second session type, or the one session type gets a second way to reach an mpv.

## Decision Outcome

Chosen option: **one observer, two transports.** `MpvSession` keeps its name and its logic; `Playback.Transport` is the seam, a struct inside the session's state behind a behaviour, and only it differs per player.

1. **The transport owns how an mpv is reached and how it names a file, nothing else.** `Transport.Local` spawns mpv on the host and speaks over its entity-scoped Unix socket, with a host path. `Transport.Remote` speaks over the player channel, a WebSocket the device dials, with a media URL. Both fold their raw messages into the same transport events: attached, message, detached, closed.
2. **The session keeps the host path as the identity of what plays.** `locator/2` turns it into what mpv is told to load; `identify/2` turns the path mpv reports back into it. Auto-advance compares identities, never locators, so a chain on a TV advances exactly as on the host.
3. **Launch options are `{option, value}` pairs in three kinds** (`Playback.LaunchFlags`): process options only a spawned mpv needs, session options every mpv playing a session needs, the file target. The local transport renders argv; the remote transport sends IPC. The TV app owns its own process options and ships the bundled scripts itself.
4. **A session is keyed by `{player, entity_id}`**, and every viewing event names its player, so an entity can play on two players and the UI can say where.
5. **A dropped channel detaches, it does not end.** The session stops persisting and waits a window (60 s) for the player's next channel, which announces itself and the transport reattaches; the window's end finalises the viewing. A host restart recovers a remote viewing by asking the reconnecting player what it plays, the same questions recovery asks a host socket.
6. **`quit` on a remote player is stop.** The device's mpv lives on; the `end-file` it reports with reason `stop` or `quit` closes the viewing. A deliberate `Sessions.stop/2` quits the player; a supervisor shutdown leaves it playing (ADR-023 for both players).
7. **Media bytes never pass through the BEAM.** A remote player fetches `/media/:presence_id` by a file-scoped capability token; the plug confines the path to the media directories and hands the file to the kernel with `sendfile`.

Declined on 2026-10-22: a second session type for remote viewings (two copies of completion, advance and recovery policy); a transport as a separate process (the socket handler already is one, and the local socket is the session's); Phoenix Channels for the player channel (mpv IPC has its own framing and correlation).

### Consequences

* Good, because the remote viewing got progress, completion, auto-advance, recovery and the finish prompt on the day the transport landed, with no second implementation of any of them.
* Good, because the observer became testable through its own door: a fake transport drives attach, pause, end, detach and failure without a process or a clock.
* Good, because the TV app is small: a bridge from IPC JSON to libmpv calls, not a client of the library.
* Bad, because the bridge must implement the IPC subset the host uses, including replies by `request_id` and node-valued properties observed as JSON strings, and coalesce `time-pos` to 1 Hz.
* Bad, because a removed player's open channel is closed only on its next event, and a detached session shows as playing for up to a minute.

## Amendment 2026-10-22 — a remote player's options ride on the file; readers get one viewing and one command door (M5)

Point 3 said the remote transport *sends* the session options as IPC. Measured on the Sony the same day (`android-app` `docs/playback-on-android.md`): the device's mpv lives for the app's life, so every `set_property` is for the player's life — `keep-open` left the next viewing paused at its first frame, and an `audio-spdif` set for one test froze the viewing after it. So:

3a. **`Transport.Remote` sets nothing on the instance.** It sends one `loadfile … replace` whose options argument carries the session options and the resume position (`LaunchFlags.per_file_options/2`, mpv's `%n%` quoting), which mpv applies while the file plays and restores at its end; `{"pause", "no"}` joined the session options. The successor the session appends carries the same set: the append is the transport's (`Transport.queue/3`), not `NextEpisode`'s, since a spawned process carries its options for its life and a device's mpv does not.

8. **Every reader sees one viewing.** `Playback.Viewing` is the session's state as a reader needs it — the title words, position, pause, chapters and current chapter, tracks (bitmap subtitle tracks marked), the subtitle line and the **prompt** (Skip Intro, Next Episode, the countdown — the desktop package's rules, judged on the host). It is `PlaybackStateChanged.now_playing` and the message on the per-player viewing stream (`Playback.subscribe_viewing/1`): on attach, on every discrete change, on position once a second, then `ViewingEnded`.

9. **A reader commands a viewing through one typed door.** `Playback.command/3` takes a `Playback.Command` (pause, a relative seek, the prompt's action, a track); the session renders it to IPC and sends it through its transport. No reader composes mpv IPC. This is how a remote player's keys act: they go to the host's page, which is the player's OSD (`campaigns/remote-players.md`, M5; the UIDR to follow).

10. **A transport says whether its mpv draws subtitles** (`draws_subtitles?/1`). A remote player draws nothing (`vo=mediacodec_embed`), so the resolver never sees its bitmap tracks and a file with only bitmap subtitles gets them off; the page's menu lists them disabled.
