---
status: accepted
date: 2026-10-22
---
# A device is admitted by pairing, and the browser session holds the player

Campaign: `campaigns/remote-players.md` (M1). Extends ADR-078's session model from *who watches* to *where*.

## Context and Problem Statement

The endpoint binds to loopback and the app has no authentication: anyone who can reach the port can edit settings, read integration credentials and act as the install's social identity. The roadmap's third era puts the UI and playback on the user's other devices — first a Google TV on the same network — so the install has to be reachable from the LAN without becoming reachable by everything on it. Accounts and passwords are the wrong shape for a household appliance driven by a remote; trusting the whole LAN is the wrong shape for an app that holds API keys and a signing key.

## Decision Outcome

Chosen option: a device joins the install by **pairing**, and the device's browser session holds the **player** it became.

1. **`bind` is a bootstrap TOML key**, default `127.0.0.1`, parsed by `Settings.Config.BindAddress` for both the endpoint (`config/runtime.exs`) and `Config.get(:bind)`. Opening the install to the LAN is the owner's explicit act, and a restart.
2. **`MediaCentaur.Players` is a bounded context with no deps**: one `Player` row per paired device (a name, when it paired), the one open pairing code (`Players.Pairing`, six digits, five minutes, five misses), three typed events on `players:updates`. Modelled on `Profiles`: the context knows nothing about which player a request is from.
3. **The credential is the signed browser session.** Pairing writes `"player_id"` into it beside ADR-078's `"profile_id"`; no second cookie, token or table of tokens. A session is still not a device, and per-device state stays session state.
4. **One policy, two enforcement points.** `MediaCentaurWeb.RemoteAccess.admit/2` judges a request by its address and its session's player id: loopback is the **host player**, `:host`, whatever the session holds; any other address is admitted only as the paired player its session names, read back from the row on every judgement so a removal cuts the device off at once. `Plugs.RemoteAccess` carries the verdict for HTTP, in the endpoint ahead of `ImageServer` so artwork is behind it; `Live.PlayerAware` carries it for the LiveView socket, which bypasses plugs, ahead of `ProfileAware` so an unpaired device never reaches the profile picker. The static bundle stays open: the pairing page needs it and it is public.
5. **The pairing page is the one page an unpaired device sees.** An unpaired `GET` is sent to `/pair`; any other unpaired request is refused. The owner starts pairing in Settings → Players, which shows the code and the addresses a device can reach the install at; the device offers the code with its name.
6. **The host is not a row.** It is admitted by address. Media Centaur 3's playback transport will select on `:host` against a `Player` (`campaigns/remote-players.md`, M3).

Declined on 2026-10-22: trusting the LAN as-is once `bind` opens (the install holds credentials); a separate token cookie per device (a second credential beside the session for one idea); login accounts (the wrong shape for a remote-driven appliance); a long-lived code (the attempt budget is what makes six digits enough).

### Consequences

* Good, because a stock install is unchanged: loopback, no pairing page, the gate admits everything as the host.
* Good, because admission is one function with one test, and the plug and the hook are both thin.
* Good, because the session already carried per-device state (the profile), so the player joins an established idea rather than adding one.
* Bad, because the LiveView socket needs `:peer_data` in `connect_info`, and any future socket or channel must judge the same way or it opens a hole.
* Bad, because a removed player's open LiveView is only dropped on the next event or request; nothing tears down its WebSocket at once.

## Amendment 2026-10-23 — three enforcement points, and media

Point 4 named two enforcement points. The player channel is a third surface the verdict reaches, and it is enforced where the other two are, in the web layer: `MediaCentaurWeb.PlayerSocket` subscribes to `players:updates` and its own player's removal closes the channel at once through `Playback.Remote.Channel.removed/1` (the device's mpv told `stop`, the close final). Playback hears of a removal only as its channel closing for good; it does not depend on `Players` (ADR-080's boundary rule, which M6 of `campaigns/remote-players.md` had crossed by subscribing inside the channel). The verdict's value is the player id (`Players.Player.id/0`, `:host` or a row's id), which the socket's `:player` assign and the plug's hold as the value `Playback.play/3` takes; nothing read a field of the row. Media requests, admitted by the capability token ahead of the gate, are admitted only while the token's player is still a row, so a removal reaches media on the next range request. The last consequence above no longer holds for the channel.
