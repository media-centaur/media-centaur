# Playback Status Enrichment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the playback status tile's bare "Idle" with a three-band Activity widget — watch narrative, honest plumbing health, and lifetime stats — so the subsystem tells a story at rest like the TMDB/Watcher tiles.

**Architecture:** A new pure view module (`MediaCentaur.WatchHistory.Views.PlaybackActivity`) shapes `WatchHistory.recent_events/1` + `WatchHistory.stats/0` into a status-tile snapshot. `StatusLive` subscribes to the `watch_history:events` topic, assigns the snapshot, and passes it into the widget bundle. `playback_widget/1` is rewritten into three always-present bands; band 2's health is state-derived from existing live-session `state` (no playback-domain change). Frozen-position detection is explicitly out of scope.

**Tech Stack:** Elixir, Phoenix LiveView, Phoenix Storybook, daisyUI/Tailwind, ExUnit (DataCase + LiveViewTest).

---

## Background facts (verified, do not re-derive)

- `MediaCentaur.WatchHistory.recent_events(limit \\ 5)` returns `%Event{}` structs newest-first. `Event` carries denormalized `title`, `entity_type` (`:movie | :episode | :video_object`), `duration_seconds`, `completed_at` — **no preload needed**.
- `MediaCentaur.WatchHistory.stats/0` returns `%{total_count: int, total_seconds: float, streak: int, heatmap: map}`. Cheap DB aggregates.
- The `watch_history:events` topic (`MediaCentaur.Topics.watch_history_events/0`) carries `{:watch_event_created, event}`, `{:watch_completed, playable_item_id}`, `{:watch_event_deleted, event}`. `StatusLive` does **not** subscribe to it yet.
- `MediaCentaur.Playback.MpvSession.get_state/1` snapshot exposes only `state | now_playing | started_at`. It does **not** expose socket/position, so band-2-playing health is derived from `@playback.state`: `:playing`/`:paused` → connected; `:starting` → connecting; `:idle` → recorder-ready branch.
- The widget is registered at `config/config.exs:107` → `{MediaCentaurWeb.ActivityWidgetComponents, :playback_widget}`. `ActivityWidgets.render/3` applies it to the whole render-assigns bundle assembled in `StatusLive` (~`lib/media_centaur_web/live/status_live.ex:240-272`). Widgets must never query at render time — data comes via assigns.
- `time_ago/1` lives in `MediaCentaurWeb.LiveHelpers` and is already imported into `ActivityWidgetComponents`.
- MC0009 (Credo) requires the story at `storybook/status/playback_widget.story.exs` to cover the widget's variation matrix; precommit enforces it.

---

## File Structure

- **Create:** `lib/media_centaur/watch_history/views/playback_activity.ex` — pure snapshot shaping (one responsibility: turn WatchHistory reads into the tile bundle).
- **Create:** `test/media_centaur/watch_history/views/playback_activity_test.exs`
- **Modify:** `lib/media_centaur_web/live/status_live.ex` — subscribe, assign `playback_activity`, handle_info, add to render bundle.
- **Modify:** `lib/media_centaur_web/components/activity_widget_components.ex` — rewrite `playback_widget/1` into three bands + helpers.
- **Modify:** `test/media_centaur_web/live/status_live_test.exs` — wiring assertions.
- **Modify:** `storybook/status/playback_widget.story.exs` — variation matrix.

---

## Task 1: PlaybackActivity view module

**Files:**
- Create: `lib/media_centaur/watch_history/views/playback_activity.ex`
- Test: `test/media_centaur/watch_history/views/playback_activity_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.WatchHistory.Views.PlaybackActivityTest do
  use MediaCentaur.DataCase, async: true

  alias MediaCentaur.WatchHistory
  alias MediaCentaur.WatchHistory.Views.PlaybackActivity

  describe "empty/0" do
    test "returns a zeroed snapshot for the disconnected mount" do
      assert PlaybackActivity.empty() == %{
               recent: [],
               last_write_at: nil,
               lifetime: %{hours: 0, titles: 0, streak: 0}
             }
    end
  end

  describe "snapshot/0" do
    test "with no history mirrors empty/0" do
      assert PlaybackActivity.snapshot() == PlaybackActivity.empty()
    end

    test "shapes recent events, last_write_at, and lifetime totals" do
      {:ok, older} =
        WatchHistory.create_event(%{
          entity_type: :movie,
          title: "Movie A",
          duration_seconds: 3600.0,
          completed_at: ~U[2026-06-08 10:00:00.000000Z]
        })

      {:ok, newer} =
        WatchHistory.create_event(%{
          entity_type: :episode,
          title: "Sample Show — Pilot",
          duration_seconds: 1800.0,
          completed_at: ~U[2026-06-09 12:00:00.000000Z]
        })

      snap = PlaybackActivity.snapshot()

      assert snap.last_write_at == newer.completed_at
      assert [%{title: "Sample Show — Pilot", kind: :episode, at: _}, %{title: "Movie A"}] = snap.recent
      assert snap.lifetime == %{hours: 2, titles: 2, streak: 0}
      _ = older
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/media_centaur/watch_history/views/playback_activity_test.exs`
Expected: FAIL — `PlaybackActivity` is undefined.

- [ ] **Step 3: Write the module**

```elixir
defmodule MediaCentaur.WatchHistory.Views.PlaybackActivity do
  @moduledoc """
  Shapes watch-history reads into the snapshot the Playback status tile renders:
  a short recent-watched feed, the timestamp of the most recent write (the
  honest "recorder is alive" signal — see the status-page persona), and lifetime
  totals. Pure read-shaping; no PubSub, no caching. `StatusLive` calls `snapshot/0`
  on mount and after `watch_history:events` messages, and uses `empty/0` for the
  disconnected mount.

  ## Snapshot shape

      %{recent: [%{title: String.t(), kind: :movie | :episode | :video_object, at: DateTime.t()}],
        last_write_at: DateTime.t() | nil,
        lifetime: %{hours: non_neg_integer(), titles: non_neg_integer(), streak: non_neg_integer()}}
  """
  alias MediaCentaur.WatchHistory

  @recent_limit 5

  @spec empty() :: map()
  def empty, do: %{recent: [], last_write_at: nil, lifetime: %{hours: 0, titles: 0, streak: 0}}

  @spec snapshot() :: map()
  def snapshot do
    recent = WatchHistory.recent_events(@recent_limit) |> Enum.map(&shape_event/1)
    stats = WatchHistory.stats()

    %{
      recent: recent,
      last_write_at: List.first(recent) && List.first(recent).at,
      lifetime: %{
        hours: round((stats.total_seconds || 0.0) / 3600),
        titles: stats.total_count,
        streak: stats.streak
      }
    }
  end

  defp shape_event(event) do
    %{title: event.title, kind: event.entity_type, at: event.completed_at}
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/media_centaur/watch_history/views/playback_activity_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/watch_history/views/playback_activity.ex test/media_centaur/watch_history/views/playback_activity_test.exs
git commit -m "feat(status): playback-activity snapshot view (recent watches, last write, lifetime)"
```

---

## Task 2: Wire the snapshot into StatusLive

**Files:**
- Modify: `lib/media_centaur_web/live/status_live.ex`
- Test: `test/media_centaur_web/live/status_live_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/media_centaur_web/live/status_live_test.exs` a new `describe "playback activity widget"`. The widget renders inside the `?subsystem=playback` drill-in (status_live.ex:582). Match the existing tests in this file: they use the `live_async!/2` helper (not bare `live/2`), e.g. `{:ok, view, html} = live_async!(conn, "/status?subsystem=playback")`.

```elixir
  describe "playback activity widget" do
    test "idle tile shows lifetime stats and the recorder-ready line", %{conn: conn} do
      MediaCentaur.WatchHistory.create_event(%{
        entity_type: :movie,
        title: "Movie A",
        duration_seconds: 3600.0,
        completed_at: ~U[2026-06-09 12:00:00.000000Z]
      })

      {:ok, _view, html} = live_async!(conn, "/status?subsystem=playback")

      assert html =~ "Movie A"
      assert html =~ "Recorder ready"
      assert html =~ "watched"
    end

    test "a watch_event_created message refreshes the snapshot", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/status?subsystem=playback")
      refute render(view) =~ "Movie A"

      {:ok, event} =
        MediaCentaur.WatchHistory.create_event(%{
          entity_type: :movie,
          title: "Movie A",
          duration_seconds: 3600.0,
          completed_at: ~U[2026-06-09 12:00:00.000000Z]
        })

      send(view.pid, {:watch_event_created, event})
      assert render(view) =~ "Movie A"
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/media_centaur_web/live/status_live_test.exs --only-failures` (or the file).
Expected: FAIL — assigns key `playback_activity` missing / widget still shows bare "Idle".

- [ ] **Step 3: Subscribe to watch_history events**

In `mount/3`, in the connected branch where the other `subscribe` calls live (~`status_live.ex:34-39`), add:

```elixir
        MediaCentaur.WatchHistory.subscribe()
```

- [ ] **Step 4: Assign the snapshot on mount**

In the connected-mount assign chain (near `assign(playback: build_playback_state())`, ~line 70) add:

```elixir
        |> assign(playback_activity: MediaCentaur.WatchHistory.Views.PlaybackActivity.snapshot())
```

In the disconnected-mount branch (near `assign(playback: %{state: :idle, ...})`, ~line 87) add:

```elixir
        |> assign(playback_activity: MediaCentaur.WatchHistory.Views.PlaybackActivity.empty())
```

- [ ] **Step 5: Handle refresh messages**

Add a `handle_info/2` clause (group it with the other playback handlers). One clause covers all three message shapes:

```elixir
  @impl true
  def handle_info({msg, _payload}, socket)
      when msg in [:watch_event_created, :watch_completed, :watch_event_deleted] do
    {:noreply,
     assign(socket,
       playback_activity: MediaCentaur.WatchHistory.Views.PlaybackActivity.snapshot()
     )}
  end
```

> If a catch-all `handle_info/2` exists at the bottom of the module, place this clause **above** it.

- [ ] **Step 6: Add `playback_activity` to the widget render bundle**

In the `activity_bundle/1` function (the render bundle passed to `ActivityWidgets.render/2` at status_live.ex:582), in its `# playback` section (~line 260-261), alongside `playback: assigns.playback,` add:

```elixir
      playback_activity: assigns.playback_activity,
```

- [ ] **Step 7: Run test to verify it passes**

Run: `mix test test/media_centaur_web/live/status_live_test.exs`
Expected: the two new tests reference `playback_activity` but the widget still renders the OLD body — `"watched"`/`"Recorder ready"` assertions will still FAIL until Task 3. Verify instead that the page renders without crashing and that `playback_activity` is assigned:

Run: `mix test test/media_centaur_web/live/status_live_test.exs:<line-of-second-test>`
Expected: the `send(...)` / no-crash path passes; the text assertions remain red pending Task 3. Leave them; Task 3 turns them green.

- [ ] **Step 8: Commit**

```bash
git add lib/media_centaur_web/live/status_live.ex test/media_centaur_web/live/status_live_test.exs
git commit -m "feat(status): assign + live-refresh playback-activity snapshot in StatusLive"
```

---

## Task 3: Rewrite playback_widget into three bands

**Files:**
- Modify: `lib/media_centaur_web/components/activity_widget_components.ex`

- [ ] **Step 1: Add the `playback_activity` attr**

Above `def playback_widget(assigns)` (the existing `attr :playback` block ends ~line 562), add:

```elixir
  attr :playback_activity, :map,
    required: true,
    doc:
      "watch-activity snapshot from WatchHistory.Views.PlaybackActivity (%{recent, last_write_at, lifetime})"
```

- [ ] **Step 2: Replace the widget body**

Replace the whole `def playback_widget(assigns) do ... end` (~lines 564-630) with the three-band version. Band 1 keeps the existing session loop verbatim for the playing case; the idle case and bands 2–3 are new.

```elixir
  def playback_widget(assigns) do
    sessions =
      assigns.playback.sessions
      |> Enum.map(fn {_id, session} -> session end)
      |> Enum.sort_by(fn session -> session[:started_at] || 0 end)

    assigns = Map.put(assigns, :sessions, sessions)

    ~H"""
    <div
      class={["card glass-surface border-l-3", playback_border_class(@playback.state)]}
      data-testid="playback-widget"
    >
      <div class="card-body">
        <div class="flex justify-between items-center">
          <h2 class="card-title text-lg">Playback</h2>
          <span :if={@sessions == []} class="text-sm text-base-content/60">idle</span>
          <span :if={@sessions != []} class="text-sm text-base-content/60">
            {length(@sessions)} active
          </span>
        </div>

        <%!-- Band 1 · Now / Recently --%>
        <div data-component="playback-narrative" class="mt-1">
          <%!-- playing: one block per active session (unchanged) --%>
          <div :for={session <- @sessions} class="mt-2">
            <div class="flex items-center gap-2">
              <span class={["text-xs", playback_text_class(session.state)]}>{session.state}</span>
              <span class="text-base font-medium truncate">
                {now_playing_title(session.now_playing)}
              </span>
            </div>
            <div
              :if={now_playing_detail(session.now_playing)}
              class="text-sm text-base-content/60 truncate"
            >
              {now_playing_detail(session.now_playing)}
            </div>
            <div
              :if={
                session.now_playing[:duration_seconds] != nil &&
                  session.now_playing[:duration_seconds] > 0
              }
              class="flex items-center gap-2 mt-1"
            >
              <progress
                class={["progress h-1.5 flex-1", playback_progress_class(session.state)]}
                value={session.now_playing[:position_seconds] || 0}
                max={session.now_playing.duration_seconds}
              >
              </progress>
              <span class="text-xs text-base-content/50 whitespace-nowrap">
                {format_remaining(
                  session.now_playing.duration_seconds -
                    (session.now_playing[:position_seconds] || 0)
                )}
              </span>
            </div>
          </div>

          <%!-- idle: last-watched line + recent feed --%>
          <div :if={@sessions == [] and @playback_activity.recent != []}>
            <p class="text-sm text-base-content/70">
              Last watched {format_recent_title(hd(@playback_activity.recent))}
              · {time_ago(hd(@playback_activity.recent).at)}
            </p>
            <ul class="mt-2 space-y-0.5">
              <li
                :for={entry <- @playback_activity.recent}
                id={watch_row_id(entry)}
                class="flex items-baseline gap-2 text-xs"
              >
                <span class="text-base-content/40 w-16 shrink-0">{watch_kind_label(entry.kind)}</span>
                <span class="truncate text-base-content/70">{format_recent_title(entry)}</span>
                <span class="ml-auto text-base-content/40 shrink-0">{time_ago(entry.at)}</span>
              </li>
            </ul>
          </div>

          <p
            :if={@sessions == [] and @playback_activity.recent == []}
            class="mt-1 text-sm text-base-content/60"
          >
            Nothing watched yet.
          </p>
        </div>

        <%!-- Band 2 · Plumbing health (only band that carries state color) --%>
        <div
          data-component="playback-health"
          class="mt-4 pt-3 border-t border-base-content/10 flex items-center gap-2 text-xs"
        >
          <% health = playback_link_health(@playback.state, @playback_activity.last_write_at) %>
          <span class={["size-2 rounded-full shrink-0", health.dot_class]}></span>
          <span class={health.text_class}>{health.label}</span>
        </div>

        <%!-- Band 3 · Lifetime stats (neutral) --%>
        <div data-component="playback-lifetime" class="mt-3 text-xs text-base-content/50">
          {@playback_activity.lifetime.hours} {pluralize(@playback_activity.lifetime.hours, "hour")} watched
          · {@playback_activity.lifetime.titles} {pluralize(
            @playback_activity.lifetime.titles,
            "title"
          )} completed
          <span :if={@playback_activity.lifetime.streak > 0}>
            · {@playback_activity.lifetime.streak}-day streak
          </span>
        </div>
      </div>
    </div>
    """
  end
```

- [ ] **Step 3: Add the helper functions**

Place these private helpers near the existing playback helpers (e.g. after `now_playing_detail/1`, ~line 766). `playback_link_health/2` is the honest state-aware band-2 logic.

```elixir
  # Band 2: honest, state-aware plumbing health. The mpv link is per-session, so
  # at rest we report the recorder's proof-of-life (last write), not a fake link.
  defp playback_link_health(state, _last_write_at) when state in [:playing, :paused] do
    %{label: "Link connected", dot_class: "bg-success", text_class: "text-success"}
  end

  defp playback_link_health(:starting, _last_write_at) do
    %{label: "Connecting…", dot_class: "bg-warning", text_class: "text-warning"}
  end

  defp playback_link_health(_idle, nil) do
    %{label: "Recorder ready · no writes yet", dot_class: "bg-base-content/30", text_class: "text-base-content/50"}
  end

  defp playback_link_health(_idle, last_write_at) do
    %{
      label: "Recorder ready · last write #{time_ago(last_write_at)}",
      dot_class: "bg-success/60",
      text_class: "text-base-content/50"
    }
  end

  defp watch_kind_label(:movie), do: "Movie"
  defp watch_kind_label(:episode), do: "Episode"
  defp watch_kind_label(:video_object), do: "Video"
  defp watch_kind_label(_), do: "Watch"

  defp format_recent_title(%{title: title}) when is_binary(title) and title != "", do: title
  defp format_recent_title(_), do: "Untitled"

  defp pluralize(1, word), do: word
  defp pluralize(_n, word), do: word <> "s"

  # Stable iterator id (UIDR-012): completion timestamps are seconds apart.
  defp watch_row_id(%{at: %DateTime{} = at}), do: "watch-#{DateTime.to_unix(at, :microsecond)}"
```

- [ ] **Step 4: Run the StatusLive wiring tests (now fully green)**

Run: `mix test test/media_centaur_web/live/status_live_test.exs`
Expected: PASS — the `"Movie A"` / `"Recorder ready"` / `"watched"` assertions from Task 2 now resolve.

- [ ] **Step 5: Compile clean (zero-warnings policy)**

Run: `mix compile --warnings-as-errors`
Expected: no warnings (watch for an unused `format_remaining`/helper or an unused `_last_write_at`).

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur_web/components/activity_widget_components.ex
git commit -m "feat(status): three-band playback widget — narrative, health, lifetime"
```

---

## Task 4: Update the storybook variation matrix (MC0009)

**Files:**
- Modify: `storybook/status/playback_widget.story.exs`

- [ ] **Step 1: Replace `variations/0`**

Every variation must now supply both `playback` and `playback_activity`. Cover: idle-with-history, idle-no-history, playing-connected, playing-connecting.

```elixir
  def variations do
    base_activity = %{
      recent: [
        %{title: "Sample Show — Pilot", kind: :episode, at: ~U[2026-06-09 12:00:00.000000Z]},
        %{title: "Movie A", kind: :movie, at: ~U[2026-06-08 20:00:00.000000Z]}
      ],
      last_write_at: ~U[2026-06-09 12:00:00.000000Z],
      lifetime: %{hours: 142, titles: 87, streak: 5}
    }

    empty_activity = %{recent: [], last_write_at: nil, lifetime: %{hours: 0, titles: 0, streak: 0}}

    playing_session = %{
      "entity-1" => %{
        state: :playing,
        started_at: 1,
        now_playing: %{
          entity_id: "entity-1",
          entity_name: "Sample Show",
          episode_name: "Pilot",
          season_number: 1,
          episode_number: 1,
          position_seconds: 600,
          duration_seconds: 1800
        }
      }
    }

    [
      %Variation{
        id: :idle_with_history,
        attributes: %{
          playback: %{state: :idle, now_playing: nil, sessions: %{}},
          playback_activity: base_activity
        }
      },
      %Variation{
        id: :idle_no_history,
        attributes: %{
          playback: %{state: :idle, now_playing: nil, sessions: %{}},
          playback_activity: empty_activity
        }
      },
      %Variation{
        id: :playing_connected,
        attributes: %{
          playback: %{state: :playing, now_playing: nil, sessions: playing_session},
          playback_activity: base_activity
        }
      },
      %Variation{
        id: :playing_connecting,
        attributes: %{
          playback: %{
            state: :starting,
            now_playing: nil,
            sessions: %{"entity-1" => %{playing_session["entity-1"] | state: :starting}}
          },
          playback_activity: base_activity
        }
      }
    ]
  end
```

- [ ] **Step 2: Run the storybook compile + render tests**

Run: `mix test test/storybook_compile_test.exs test/storybook_render_test.exs`
Expected: PASS — the playback story compiles and all four variations render.

- [ ] **Step 3: Commit**

```bash
git add storybook/status/playback_widget.story.exs
git commit -m "test(storybook): playback widget variation matrix — idle/playing × history/health"
```

---

## Task 5: Full precommit + wiki sync

- [ ] **Step 1: Run precommit**

Run: `MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix precommit`
Expected: format clean, Credo (incl. MC0009) clean, boundaries pass, sobelow/deps.audit clean, full test suite green.

> If the suite hits an intermittent SQLite "Database busy" / on_exit OwnershipError under parallelism, re-run the affected file with `mix test <file> --repeat-until-failure 50` to confirm it's the known pre-existing concurrency flake, not this change.

- [ ] **Step 2: Wiki sync (user-visible UI change)**

The Status page's playback tile gains a recent-watched feed, a recorder-health line, and lifetime stats. Update the wiki page that documents the Status page / health board.

```sh
cd ~/src/media-centaur/media-centaur.wiki
# edit the Status/observability page: note the playback tile now shows recent watches,
# recorder health (last write), and lifetime totals even when nothing is playing.
git add -A
git commit -m "wiki: playback status tile now shows watch narrative, recorder health, lifetime stats"
git push
```

> If the exact wiki page is unclear, grep the wiki for "status" / "health" and update the matching page; if none exists, note this as a follow-up rather than blocking.

- [ ] **Step 3: Final commit (if precommit reformatted anything)**

```bash
git add -A
git commit -m "chore: precommit formatting for playback status enrichment" || true
```

---

## Notes / explicit scope cuts

- **No heatmap** (cut during brainstorming — not interesting enough to earn the space).
- **No frozen-position detection** in band 2 — would require extending `MpvSession.get_state/1` to expose socket/position; deferred. Band 2 health is purely `state`-derived + last-write timestamp.
- **No Continue Watching / resume shortlist** — out of scope for the health board (browse-UI concern).
- Reserve color for health/severity: only band 2 uses state color; bands 1 and 3 stay neutral (no-chip-palette rule).
- Persona reference: auto-memory `project-status-page-persona`. Spec: `docs/superpowers/specs/2026-06-09-playback-status-enrichment-design.md`.
```
