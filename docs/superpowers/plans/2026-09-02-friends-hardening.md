# Friends Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote the iteration-phase Discovery UI to first-class components with stories, give the Feed, tab strip, Friends tab and Recommend modal keyboard and gamepad navigation, and close the small findings the layer reviews deferred.

**When:** after the owner has iterated on the Friends/Feed UI (spec decision 11 — "iterate light, harden after"). Do not start until the owner says the shapes have settled; the component moves below are cheap only once the markup stops changing.

**Spec:** `docs/superpowers/specs/2026-09-02-friends-recommendations-design.md` decision 11 and build-order step 9. Layer 9.

**House rules:** the `input-system` skill before any nav work (`mc-nav-trace` is the first tool for nav questions; verify driving state, not animated properties); MC0009 stories for every component moved under `components/**`; the `user-interface` and `storybook` skills for the moves; wiki *Keyboard-and-Gamepad* updated in the same unit of work; commits end with `Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz`, never `Co-Authored-By`; no push, no tag.

---

### Task 1: Components with stories

Move, unchanged in markup, from `lib/media_centaur_web/live/discovery_live/` to `lib/media_centaur_web/components/discovery/`: `identity_block.ex`, `relay_block.ex`, `roster_block.ex`, `feed_row.ex`, `recommend_modal.ex` (and `status_widgets/friends.ex` already lives under components). Module names `MediaCentaurWeb.Components.Discovery.*`. Stories under `storybook/discovery/` covering each block's state matrix: identity (hidden/revealed nsec, unarmed/armed import), relays (empty; connected/connecting/not connected/rejected with last error), roster (empty; rows), feed row (add / on watchlist / in library; with and without note), recommend modal (closed; open with 0 relays; open with N of M). Update `_discovery.index.exs`. `RecommendFlow` stays under `live/` (it is LiveView state, not a component). Update every caller and the `no_db_on_render`/storybook tests.

### Task 2: Navigation

Per the input-system skill: the Discovery layout in `assets/js/input/config.js` gains zones for the Feed (`feed` grid of rows, each row a 1-track grid with its one action), the Friends tab (`identity`, `relays`, `roster` zones stacked; each list row a `data-nav-grid` with its actions; the add forms' inputs and buttons as nav items), and the Recommend modal (a `recommend_modal` layout: note textarea, Cancel, Send; Escape/B cancels via the modal's persistent-dismiss contract). Add `data-nav-item`/`tabindex="0"`/`data-nav-grid` attributes accordingly; the tab strip already carries `zone-tabs`. Verify each path with `mc-nav-trace` on the dev server (Feed: strip → rows → sidebar; Friends: strip → identity → relays → roster and back; modal: focus lands on the note, Down to Send, Escape closes) and record the traces in the commit message. `config_coverage.test.js` and the JS tests updated; `mix assets.build`. Wiki *Keyboard-and-Gamepad*: a *Discovery* section listing the moves.

### Task 3: Deferred review findings

- `RelayBlock.dom_id/1` / `RosterBlock.dom_id/1`: append a short hash of the URL/pubkey so distinct inputs cannot collide; tests updated to compute ids through the helpers.
- `Nostr.Connection`: Dialyzer notes — the `%Mint.WebSocket{}` pattern on an opaque type in `send_raw/2`'s error clause (match on the 3-tuple shape without the struct, or use `is_struct/2` guarded by a `case` on the tag) and the `Mint.WebSocket.new/4` success-type note (add `@spec`s/typed state so Dialyzer sees `http_status` as an integer after `{:status, …}`); `Owner.reconcile/1` `MapSet.difference/2` opaque note (build both sets with `MapSet.new/1` from lists — likely already the case; make the types line up). Run `mix dialyzer` if a PLT is affordable in CI; otherwise rely on ElixirLS locally.
- `connections_test.exs` teardown warning (`lost …: :closed_by_relay` when the fake relay stops before the connection): stop connections before relays in the tests (`stop_supervised/1` order) rather than silencing the warning.
- The `/status` no-DB-on-render budget comment if layer 7 bumped it.
- `Friends.IncidentContext`: reconsider the 180 s grace against real relay behaviour once the owner has run a private relay for a while.
- The end-to-end test `discovery_live_e2e_test.exs` (identity → FakeRelay stored friend event → Sync → feed row "from Sample Friend" → Add to watchlist → `/discovery/watchlist` row with `source: :friend` and the marker → Track hands off to ReleaseTracking).
- Re-auth after `:auth_failed` (drop the socket, re-enter backoff) with the wiki Rejected row updated.
- Inbound frame-size cap before `Jason.decode`.
- `Nostr.Connection` child `restart: :transient` + Owner reconcile on `:DOWN` (or wider `max_restarts`) so a crashing relay cannot cascade.
- One subscription map (`Sync.resubscribe/1` per relay via `subscribe/3`; delete `subscribe_all/2`).
- Stop the Owner before the FakeRelay in `connections_test`, `sync_test`, `connection_test` to kill the teardown warning.
- Extract `keyed_list_section/1` and `copyable_code/1` from the three Friends blocks.
- `DiscoveryLive.find_item/2`.
- `list_feed/0` returns `nickname: nil` instead of the "a former friend" sentinel (FeedRow owns the copy).
- `Sync` prunes `seen[url]` on `relay_removed`.
- An "As built" note in the spec recording: Friends deps `[Nostr]` only, `Connections.status/0` returns entry maps, connection auth messages are `{:auth, :ok | {:failed, reason}}`, feed decoration lives in the web layer.

### Task 4: Precommit + campaign closure

- `mix precommit` PASSED.
- `campaigns/friends-recommendations.md`: bucket every remaining item by destination (ship / verify / defer-to-X) per the closure rule; if nothing remains, retire the campaign file (delete it, update `campaigns/README.md`) and record the closure in the memory index.
- Commit `docs(campaign): friends-recommendations hardened; campaign closed`.

---

## Self-review

**Spec coverage:** decision 11's hardening pass (components + stories, navigation) → Tasks 1–2; review leftovers with named owners → Task 3; closure by destination → Task 4.

**Placeholders:** none; Task 2's zone names are the ones the components already use or introduce.
