# Social relay observability — design

**Date:** 2026-09-04
**Status:** approved
**Campaign:** `campaigns/friends-recommendations.md`

## Glossary

- **Relay connection** — one `Nostr.Connection` process holding one WebSocket to one configured relay.
- **Connection state** — the single value in a relay's status entry that names how far the connection has got: `connecting`, `connected`, `synced`, `auth_failed`, `disconnected`. Today the same field exists without `synced`.
- **Feed subscription** — the `"feed"` subscription `Recommendations.Sync` opens on every connected relay for friends' recommendations. Its `EOSE` is the proof that the relay answers requests from this identity.
- **Last heard** — the time of the most recent inbound frame of any kind from a relay: event, EOSE, OK, NOTICE, CLOSED, AUTH, or pong.
- **Liveness ping** — a WebSocket ping this side sends on an interval while connected, with a deadline for the pong. A missed deadline is a disconnect with reason `unresponsive`.
- **Retry at** — the instant the connection will next attempt to connect, derived from the reconnect backoff at the moment of loss.
- **Reason** — the plain-language cause attached to a status entry: the relay's own text for `OK false` / `CLOSED` / auth failures, or a translated transport error for everything else.
- **Status entry** — `Social.Connections.status/0`'s per-relay map. Grows from `%{state, last_error, since}` to `%{state, last_error, since, last_heard_at, retry_at}`.
- **Drill-in** — the Social panel under the Status page's health board (`Components.StatusWidgets.Social`).
- **Board tile** — the Social tile on the health board itself; coloured only by `ErrorReports` buckets.
- **Subsystem incident** — an incident with origin `:subsystem`, raised by the `Evaluator` from an `IncidentContext.assess/0` verdict. Today stored but never bucketed, so it colours no tile.

## Problem

The drill-in reports "Connected to 1 of 2 relays" and a raw `%Mint.TransportError{reason: :econnrefused}` with no relay name. The user cannot tell which relay is down, how long it has been down, whether it is flapping, or whether the connected relay is actually serving the feed. Underneath the presentation:

1. A relay that never connects logs nothing to the console; only a previously-connected relay logs "lost".
2. `connected` can be stale. There is no client-side ping, so a half-open socket stays `connected` until the kernel gives up.
3. The board tile reads "No issues" with every relay down, because subsystem incidents never reach the bucket cache.
4. A relay that accepts `AUTH` but refuses the feed with `restricted:` shows as Connected with an error, not Rejected.

## Decisions

1. **The drill-in lists relays.** The widget moduledoc's "no relay list" rule is withdrawn. Settings → Social lists relays to edit them; the drill-in lists them to diagnose them. Different job, not a duplicate. Per relay: host, state label, duration in state, reason, retry countdown, last heard.
2. **No traffic graph, no per-relay counters, no heartbeat strip.** Traffic on a friends network is a few events a week; a time series of it carries no information. Connectivity over time is answered by the duration in state. Revisit a heartbeat strip only if "was it flapping overnight?" turns out to be a real question after this ships.
3. **`synced` is a connection state.** Set when `EOSE` arrives on the feed subscription; cleared back to `connected` by `CLOSED` on that subscription or by a reconnect. It means "this relay answers this identity's requests", nothing about paging progress.
4. **`restricted:` on the feed means Rejected.** A `CLOSED` on the feed subscription whose reason starts with `restricted:` moves the state to `auth_failed` (from the campaign's proposed rule; prefix match only). khatru cannot refuse an `AUTH` event, so this is the only signal a non-member gets.
5. **Liveness ping.** While connected, ping every 30 s; pong deadline 10 s. A missed pong is `lost/2` with reason `:unresponsive`, entering the normal backoff. The connection answers the relay's pings as before.
6. **Last heard is owner-side.** The owner stamps `last_heard_at` on every connection message except `{:disconnected, _}`. The connection emits a new `:pong` message so pongs count.
7. **Retry at travels with the disconnect.** `{:disconnected, reason}` becomes `{:disconnected, reason, retry_in_ms}`; the owner stores `retry_at`. The UI computes the countdown at render time and does not promise a live ticking clock.
8. **Reasons are translated once, at the wire.** A `Nostr.Reason.describe/1` maps transport terms to a fixed vocabulary: connection refused, host not found, timed out, TLS failed, closed by relay, unresponsive. Relay-authored strings pass through. Anything unmapped becomes "connection failed" and logs the raw term at debug. No `inspect/1` output reaches the UI.
9. **Console lifecycle lines.** One `:nostr` warning when a relay first fails to connect or drops (first failure since the last successful connect), one info on connect (exists today), nothing per retry.
10. **One label vocabulary.** The state labels (Connecting, Connected, Synced, Rejected, Not connected) live in one function used by both the drill-in and Settings → Social. Settings → Social keeps its rows as they are apart from adopting the shared labels.
11. **Board tile fix is stage two, in scope.** Subsystem incidents get a synthetic grouping key and a headline so they bucket like log incidents. This is an `ErrorReports` change and fixes the download-client and search probes too.

## Stage one: drill-in and runtime

### Layout

```
Social
Connected to 1 of 2 relays

relay.example.org     Synced · heard 2 m ago
localhost:7777        Not connected 3 h · connection refused · retry in 42 s

2 friends · 2 sent · 1 received · last received 1d ago

Open Friends · Relay settings
```

Each relay row shows, in order: host (scheme and trailing slash dropped), state label, duration in state, reason when present, retry countdown when disconnected, last heard when the state is `connected` or `synced`. Fields that do not apply are omitted, not blank.

The "Connected to N of M" line counts `connected` and `synced` as connected. "No relays configured" stays for the empty case.

"Relay settings" links to Settings → Social.

### Data changes

- `Nostr.Connection`: ping timer and pong deadline in state; `:pong` message; `{:disconnected, reason, retry_in_ms}`; first-failure warning log.
- `Nostr.Reason.describe/1`: new module, pure.
- `Social.Connections`: entry type gains `last_heard_at` and `retry_at`; `apply_message/2` handles `:synced`, the `restricted:` rule, `:pong`, the three-tuple disconnect; `feed_sub_id/0` exported so `Recommendations.Sync` and `apply_message/2` share the constant.
- `Social.IncidentContext`: treats `synced` as healthy alongside `connected`. No other change.
- `MediaCentaurWeb.Components.StatusWidgets.Social`: relay rows; story updated with the state matrix (each state, with and without reason, with and without last heard).
- Settings → Social section: adopts the shared label function.

### Testing

- `Nostr.Connection` against `FakeRelay`: a pong reaches the owner as `:pong`; a relay that stops answering pings is lost with `:unresponsive` within the deadline; the disconnect carries the backoff; the first failure logs a warning and the second retry does not.
- `Nostr.Reason`: table test over the mapped terms and one unmapped term.
- `Social.Connections.apply_message/2`: pure unit tests for every new transition, including `restricted:` versus another `CLOSED` reason, and `last_heard_at` stamping.
- `Social.IncidentContext.decide/3`: `synced` is `:ok`.
- Widget story renders every state; `status_live_test` asserts the relay rows and that the reason text is plain.

## Stage two: board tile

Subsystem incidents reach the bucket cache:

- The `Evaluator` raises a fault with `fingerprint: "subsystem:<component>:<kind>"` and a `display_title` from a headline the assessor supplies in the fault's context map (`headline:`). The three Social headlines: **Relay rejected this identity**, **No relay reachable**, **A relay is unreachable**.
- `BucketCache.from_incidents/1` then admits them with no change to its filter.
- Resolving a subsystem incident must evict its bucket. Plan-time check: confirm the resolve path used by log-incident dismissal is the one `resolve_fault/2` takes, or route it there.
- The download-client and search assessors gain headlines in the same change.

Testing: an integration test that stands the Social assessor's fault up through the evaluator and asserts the Social tile state is `:error`, then `:ok` after resolution.

## Not doing

- Traffic graph or per-relay send/receive counters.
- Heartbeat strip (deferred, see decision 2).
- Live countdown ticking in the drill-in.
- Any change to Discovery → Friends.

## Wiki

Settings-Reference → Social and Troubleshooting gain the state vocabulary and the reason vocabulary once stage one ships.
