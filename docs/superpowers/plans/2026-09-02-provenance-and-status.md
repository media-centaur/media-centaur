# Watchlist Provenance + Status Section Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Watchlist items added from the feed carry their provenance ("from Alex"), the Friends subsystem gets a Status page tile with an incident assessor and a health-and-aggregates widget, and the new log component tags are first-class in the console.

**Architecture:** `WatchlistItem` gains `source: :friend` and a nullable `recommendation_id` (bare UUID — Discovery and Recommendations still never depend on each other; `DiscoveryLive` resolves the nickname). The Status tile's colour comes from the proven incident path: a `Friends.IncidentContext.assess/0` registered as a diagnostics contributor grades `Friends.Connections.status/0` with a grace window; the drill-in's Activity widget shows aggregates (connected N of M, last error, friend count, sent/received counts, last received) and one link to the Friends tab. The console's known-component list registers `:nostr` and `:friends` with chip styles, and crash frames from the new modules map to the Friends tile.

**Tech Stack:** Ecto migration (additive), LiveView, `ErrorReports` diagnostics contributors + `EvaluatorJob`, `StatusWidgets`, Phoenix Storybook (MC0009 — the widget lives under `components/`), console `View`/`Entry`, CSS chips (`mix assets.build`).

**Spec:** `docs/superpowers/specs/2026-09-02-friends-recommendations-design.md` — Discovery changes (`:friend`, `recommendation_id`, web-layer nickname join), decision 12 + UI › Status page Friends section, Error handling (`:nostr`/`:friends` tags). Layer 7. Depends on layers 4–6 being on disk.

**Decisions fixed by this plan:**
- Feed → watchlist adds set `source: :friend`, `recommendation_id`, and copy the recommendation's note. Watchlist rows show a quiet marker `from <nickname>` in the title's markers slot; the note stays in the secondary slot. A watchlist item whose recommendation or friend no longer exists shows no marker (nil-safe join).
- Status tile state: no relays configured → healthy (unconfigured never faults); any relay `:auth_failed` → error `relay_auth_failed` immediately; all relays disconnected for longer than the grace window (180 s) → error `relays_unreachable`; some disconnected past grace → warning `relay_degraded`; otherwise healthy. The assessor is pure over `(status_map, now, grace_seconds)`.
- Widget copy (house voice, aggregates only): **Connected to N of M relays** (or **No relays configured**), the last error as quiet text if any, **F friends · S sent · R received**, **Last received <relative time>** (or omitted when none), one link **Open the Friends tab**. No relay list, no roster, no feed rows.
- Console tags: `:nostr` (protocol frames, connection lifecycle) and `:friends` (identity, roster, relays, recommendations sync). Crash frames from `MediaCentaur.Nostr.*`, `MediaCentaur.Friends.*`, `MediaCentaur.Recommendations.*` map to the `:friends` board tile.
- Tile label **Friends**, glyph `hero-users`, description **"Connects to your relays to send and receive recommendations from friends."**, placed after Acquisition on the board.

**House rules:** test-first; zero warnings; `mix format`; `mix credo --strict` (MC0009 story for the widget; MC0024; MC0015 — the migration is additive); asset watchers OFF → `mix assets.build` after the CSS change; no-DB-on-render budget for `/status` is tight (52; jitter 38–50) — measure and bump with a comment only if needed; commits end with `Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz`, never `Co-Authored-By`; no push, no tag.

---

## File map

| Action | Path | Responsibility |
|---|---|---|
| Create | `priv/repo/migrations/20260902190000_add_recommendation_id_to_watchlist_items.exs` | nullable uuid |
| Modify | `lib/media_centaur/discovery/watchlist_item.ex`, `lib/media_centaur/discovery.ex` (doc only) | `:friend`, `recommendation_id`, pairing validation |
| Modify | `lib/media_centaur_web/components/discovery/watchlist_row.ex` + `storybook/discovery/watchlist_row.story.exs` | `from_nickname` marker |
| Modify | `lib/media_centaur_web/live/discovery_live.ex` | feed add sets provenance; watchlist rows resolve nickname |
| Modify | `lib/media_centaur/console/view.ex`, `lib/media_centaur/console/entry.ex`, `assets/css/app.css` | tags + chips + crash-frame mapping |
| Create | `lib/media_centaur/friends/incident_context.ex` + test | assessor |
| Modify | `config/config.exs` | diagnostics contributor; activity widget registry |
| Modify | `lib/media_centaur_web/live/status_live/health_board.ex`, `lib/media_centaur_web/live/status_live.ex` | subsystem + bundle + subscription |
| Create | `lib/media_centaur_web/components/status_widgets/friends.ex`, `storybook/status/friends_widget.story.exs`, `storybook/status/_status.index.exs` entry | widget |
| Tests | `test/media_centaur/discovery_test.exs`, `discovery_live_test.exs`, `test/media_centaur/friends/incident_context_test.exs`, `test/media_centaur_web/live/status_live_test.exs` (or the nearest), `page_smoke_test.exs`, `no_db_on_render_test.exs`, `test/media_centaur/console/view_test.exs` (if it enumerates components) | |

---

### Task 1: Watchlist provenance

- [ ] **Step 1: Failing tests**

`test/media_centaur/discovery_test.exs` (in the `create_changeset/2` describe):

```elixir
    test "a friend-sourced item carries its recommendation id; the pairing is enforced" do
      title = Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})
      id = Ecto.UUID.generate()
      assert WatchlistItem.create_changeset(title, %{source: :friend, recommendation_id: id}).valid?
      refute WatchlistItem.create_changeset(title, %{source: :friend}).valid?
      refute WatchlistItem.create_changeset(title, %{source: :manual, recommendation_id: id}).valid?
    end
```

`discovery_live_test.exs` (feed describe): after the existing "rows … add to the watchlist" flow, assert provenance:

```elixir
      assert [%{item: %{source: :friend, recommendation_id: rec_id, note: "Watch it."}}] = Discovery.list_watchlist()
      assert rec_id == rec.id
```

and a watchlist-tab test:

```elixir
    test "a friend-sourced watchlist row says who recommended it", %{conn: conn} do
      {:ok, _} = Friends.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Recommendations.ingest(friend_event(777, "Watch it."))
      {:ok, _} = Discovery.add_to_watchlist(rec.title, %{source: :friend, recommendation_id: rec.id, note: rec.note})
      {:ok, view, _html} = live(conn, "/discovery/watchlist")
      assert has_element?(view, "#watchlist-item-movie-777", "from Sample Friend")
      assert has_element?(view, "#watchlist-item-movie-777", "Watch it.")
      await_supervised_tasks()
    end
```

- [ ] **Step 2: Migration** — `change/0`: `alter table(:watchlist_items) do add :recommendation_id, :uuid end`. Moduledoc: bare uuid, no FK (contexts stay independent), nullable, no backfill.

- [ ] **Step 3: Schema** — `source` values `[:manual, :friend]`; `field :recommendation_id, Ecto.UUID`; cast it; add

```elixir
  # Provenance pairing: a friend-sourced item names its recommendation; a
  # manual one carries none.
  defp validate_provenance(changeset) do
    case {get_field(changeset, :source), get_field(changeset, :recommendation_id)} do
      {:friend, nil} -> add_error(changeset, :recommendation_id, "is required for a friend-sourced item")
      {:manual, id} when not is_nil(id) -> add_error(changeset, :recommendation_id, "only a friend-sourced item carries one")
      _ok -> changeset
    end
  end
```

  in the pipeline; update `@type t` and the moduledoc's provenance paragraph ("`:friend` items carry `recommendation_id`; the nickname is resolved by the web layer from the recommendation's author").

- [ ] **Step 4: Web** — `discovery_live.ex`: the feed's `feed_add_to_watchlist` passes `%{source: :friend, recommendation_id: rec.id, note: rec.note}`; `load_items/1` resolves `from_nickname` per row: for items with `recommendation_id`, `Recommendations.get(id)` → `Friends.friend_by_pubkey(author_pubkey)` → nickname (batch it: collect ids, one `Recommendations.get_many/1` if you add it, else per-row `get/1` is acceptable for a watchlist-sized list — prefer adding `Recommendations.get_many([ids]) :: %{id => rec}` in the context, exported); pass `from_nickname={row.from_nickname}` to `WatchlistRow`. `watchlist_row.ex`: `attr :from_nickname, :string, default: nil, doc: "who recommended it, when the item came from the feed"` and `<:markers :if={@from_nickname}><span class="shrink-0 text-xs text-base-content/50">from {@from_nickname}</span></:markers>` on the `title_summary` call (the secondary slot keeps the note). Story: a `:from_friend` variation.

- [ ] **Step 5:** tests + gates (`storybook_render_test` included); `mix ecto.migrate` on the dev DB. Commit `feat(discovery): friend provenance on watchlist items (source :friend + recommendation id)`.

---

### Task 2: Console component tags

- [ ] **Step 1: Failing test** — find the console view test that pins `known_components/0` (`grep -rn "known_components" test`); add `:nostr` and `:friends` to its expectation (and to any chip-class test). If none exists, add to `test/media_centaur/console/view_test.exs` (create if absent, `ExUnit.Case, async: true`): `assert :nostr in Console.View.known_components()` and `assert :friends in Console.View.known_components()`.

- [ ] **Step 2:** `lib/media_centaur/console/view.ex`: add `:nostr` and `:friends` to `@known_components` and `@app_components`, chip classes `chip-nostr`, `chip-friends` in `@component_chip_classes`; `assets/css/app.css`: define `.chip-nostr` and `.chip-friends` next to the other `.chip-<component>` rules using two unused hues from the existing chip palette (no new colour vocabulary — pick from what the palette already defines; the memory rule "no chip palette in new UI" applies to product surfaces, not the console's existing component chips). `lib/media_centaur/console/entry.ex` crash-frame prefix map: `{"MediaCentaur.Nostr", :friends}`, `{"MediaCentaur.Friends", :friends}`, `{"MediaCentaur.Recommendations", :friends}` (board home; the log tag itself stays whichever the emitting module chose). `mix assets.build`.

- [ ] **Step 3:** tests + gates; commit `feat(console): nostr and friends component tags`.

---

### Task 3: `Friends.IncidentContext`

- [ ] **Step 1: Failing tests** — `test/media_centaur/friends/incident_context_test.exs` (pure `decide/3`):

```elixir
defmodule MediaCentaur.Friends.IncidentContextTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Friends.IncidentContext

  @now ~U[2026-09-02 12:00:00Z]
  @grace 180

  defp status(entries), do: Map.new(entries, fn {url, state, since} -> {url, %{state: state, last_error: nil, since: since}} end)

  test "no relays is healthy" do
    assert IncidentContext.decide(%{}, @now, @grace) == :ok
  end

  test "all connected is healthy" do
    assert IncidentContext.decide(status([{"wss://a/", :connected, @now}]), @now, @grace) == :ok
  end

  test "auth failure faults immediately" do
    assert {:fault, :relay_auth_failed, :error, _} = IncidentContext.decide(status([{"wss://a/", :auth_failed, @now}]), @now, @grace)
  end

  test "disconnected inside the grace window is still healthy" do
    since = DateTime.add(@now, -60, :second)
    assert IncidentContext.decide(status([{"wss://a/", :disconnected, since}]), @now, @grace) == :ok
  end

  test "all relays down past grace is an error; some down is a warning" do
    old = DateTime.add(@now, -600, :second)
    assert {:fault, :relays_unreachable, :error, _} = IncidentContext.decide(status([{"wss://a/", :disconnected, old}]), @now, @grace)
    assert {:fault, :relay_degraded, :warning, _} = IncidentContext.decide(status([{"wss://a/", :disconnected, old}, {"wss://b/", :connected, @now}]), @now, @grace)
  end
end
```

This needs `Friends.Connections.status/0` entries to carry `since` (the time the current state began). Add it in the owner's `apply_message/2` (`since: DateTime.utc_now()` on every state change) — a small extension of layer 4's status map; update its test to accept the extra key.

- [ ] **Step 2:** `lib/media_centaur/friends/incident_context.ex` modeled on `lib/media_centaur/downloads/incident_context.ex` (`assess/0` reads `Connections.status/0` and `DateTime.utc_now()`, delegates to `decide/3`; kinds `:relay_auth_failed`, `:relays_unreachable`, `:relay_degraded`; `@grace_seconds 180`). Register `friends: MediaCentaur.Friends.IncidentContext` under `:diagnostics_contributors` in `config/config.exs`. Check the contributor behaviour/contract module (`lib/media_centaur/error_reports/contributors.ex`) for the exact callback shape and any incident-kind registry (headlines/descriptions per kind — `grep -rn "download_client_unreachable" lib` to find every place a kind is described; add the three new kinds there with house-voice headlines: **Relay rejected this identity**, **No relay reachable**, **A relay is unreachable**).

- [ ] **Step 3:** tests + gates; commit `feat(friends): incident assessor for relay health`.

---

### Task 4: Status tile + widget

- [ ] **Step 1: Failing tests** — `page_smoke_test.exs`: `{"/status?subsystem=friends", "status friends drill-in"}`. A LiveView test (in the status live test file — `ls test/media_centaur_web/live | grep status`): with two relays added and one friend, `live(conn, "/status?subsystem=friends")` shows the tile `Friends` and the widget with "Connected to 0 of 2 relays" (no owner under test), "1 friends", and the link to `/discovery/friends`. Storybook render test covers the widget's variations.

- [ ] **Step 2:** `health_board.ex`: `:friends` in `@board_subsystems` (after `:acquisition`), label, glyph `hero-users`, description. `config/config.exs` `:health_activity_widgets`: `friends: {MediaCentaurWeb.Components.StatusWidgets.Friends, :friends_widget}`. Widget `lib/media_centaur_web/components/status_widgets/friends.ex` (plain-bundle contract as `self_update.ex`): attrs `relay_status` (`:map`, doc), `friend_count`, `sent_count`, `received_count`, `last_received_at` (`:any`, doc), `now` (`:any`, doc); renders the aggregate lines and the link; `data-testid="friends-widget"`. Story `storybook/status/friends_widget.story.exs` (variations: unconfigured, healthy, degraded with last error, auth failed) + index entry. `status_live.ex`: `ensure_loaded/1` reads `Friends.Connections.status/0`, `length(Friends.list_friends())`, `length(Recommendations.list_sent())`, `Recommendations.list_feed()` (count + head's `recommended_at`) — if the render budget objects, add `Recommendations.counts/0 :: %{sent: n, received: n, last_received_at: dt|nil}` as one query pair in the context instead; `mount/3` `Friends.subscribe_connections()`; `handle_info({:relay_connection, _, _})` refreshes the relay status assign; `activity_bundle/1` gains the `friends:` keys. `no_db_on_render_test.exs`: measure `/status`; bump with a comment only if needed.

- [ ] **Step 3:** tests + gates (`storybook_compile_test`, `storybook_render_test`, `no_db_on_render_test`, smoke); `page-shot` of `/status?subsystem=friends`. Commit `feat(status): Friends tile and widget — relay health and aggregates`.

---

### Task 5: Precommit + campaign

- [ ] `mix precommit` PASSED.
- [ ] `campaigns/friends-recommendations.md` Status: "Layer 7 (watchlist provenance, console tags, Friends incident assessor + Status tile/widget) landed 2026-09-02; next: layer 8 (wiki + changelog notes), then 9 (hardening)." Next steps: keep the flat-column-drop item; add "**Console: crash frames from Nostr/Friends/Recommendations map to the Friends tile** — revisit if a separate Nostr tile is ever wanted."
- [ ] Commit `docs(campaign): provenance + Status section landed; next = wiki`.

---

## Self-review

**Spec coverage:** Discovery changes (`:friend`, `recommendation_id`, web-layer nickname join, no cross-context dep) → Task 1; Error handling tags → Task 2; decision 12 / UI Status section (per-relay state as an aggregate + last error, friend count, sent/received counts, last received, link; no duplicated lists) → Tasks 3–4; the tile's health derives from a proper incident source with grace → Task 3.

**Type consistency:** `WatchlistItem.source :: :manual | :friend`, `recommendation_id`; `WatchlistRow` attr `from_nickname`; `Recommendations.get_many/1` (added) and `counts/0` (conditional); `Friends.IncidentContext.assess/0`, `decide/3`; `Connections.status/0` entries gain `since`; widget `friends_widget/1` attrs as listed; subsystem atom `:friends`.

**Placeholders:** none; two conditionals are named with their trigger (the render budget).
