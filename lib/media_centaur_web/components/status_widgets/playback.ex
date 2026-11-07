defmodule MediaCentaurWeb.Components.StatusWidgets.Playback do
  @moduledoc """
  Playback subsystem Activity widget: one row per player — this computer,
  then each paired player — with whether it is reachable and what it
  plays, for whom; then what was recently watched.

  Rendered into the health-board drill-in's :activity slot via
  MediaCentaurWeb.StatusLive.ActivityWidgets, invoked with a plain data
  bundle (no change-tracking) from StatusLive.activity_bundle/1 — derive
  with Map.put/3, never assign/3. The rows come from
  `StatusHelpers.player_rows/1`.
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.StatusHelpers
  import MediaCentaurWeb.LiveHelpers, only: [time_ago: 1, sized_image_url: 2]

  # A `w-10` thumbnail — 40 CSS px, doubled on a 4K panel. It was serving the
  # 1120px poster master.

  @doc "Playback subsystem Activity widget: every player's connection and viewings, then recent history."
  attr :player_rows, :list,
    required: true,
    doc: "one row per player, `StatusHelpers.player_rows/1`"

  attr :playback_activity, :map,
    required: true,
    doc:
      "watch-activity snapshot from WatchHistory.Views.PlaybackActivity (%{recent, last_write_at, lifetime})"

  def playback_widget(assigns) do
    assigns = Map.put(assigns, :health, assigns.player_rows |> playback_health() |> health_classes())

    ~H"""
    <div data-testid="playback-widget">
      <%!-- Hero stat band: lifetime numbers framed as instrumentation, not
           spread across the column. A zero streak dims — at-rest information,
           not a headline. --%>
      <div
        :if={@playback_activity.lifetime.titles > 0}
        data-component="playback-lifetime"
        class="glass-inset mb-7 grid grid-cols-3 overflow-hidden rounded-xl"
      >
        <div class="px-6 py-5">
          <div class="text-4xl font-extralight leading-none tracking-tight tabular-nums">
            {@playback_activity.lifetime.hours}<span class="ml-1.5 text-base font-normal text-base-content/55">hrs</span>
          </div>
          <div class="mt-2.5 text-[11px] font-semibold uppercase tracking-[0.12em] text-base-content/55">
            Watched, lifetime
          </div>
        </div>
        <div class="border-l border-base-content/10 px-6 py-5">
          <div class="text-4xl font-extralight leading-none tracking-tight tabular-nums">
            {@playback_activity.lifetime.titles}
          </div>
          <div class="mt-2.5 text-[11px] font-semibold uppercase tracking-[0.12em] text-base-content/55">
            Titles finished
          </div>
        </div>
        <div class="border-l border-base-content/10 px-6 py-5">
          <div class={[
            "text-4xl font-extralight leading-none tracking-tight tabular-nums",
            @playback_activity.lifetime.streak == 0 && "text-base-content/55"
          ]}>
            {@playback_activity.lifetime.streak}
          </div>
          <div class="mt-2.5 text-[11px] font-semibold uppercase tracking-[0.12em] text-base-content/55">
            Day streak
          </div>
        </div>
      </div>

      <%!-- List head: section title left, the single health signal right. --%>
      <div class="flex items-baseline justify-between">
        <h4 class="text-[17px] font-semibold tracking-tight">Players</h4>
        <span
          class={["flex items-center gap-1.5 text-xs", @health.text_class]}
          data-component="playback-health"
        >
          <span class={["size-2 rounded-full shrink-0", @health.dot_class]}></span>
          {@health.label}
        </span>
      </div>

      <ul data-component="playback-players" class="mt-2">
        <li
          :for={row <- @player_rows}
          id={"playback-player-#{row.id}"}
          class="border-t border-base-content/5 py-3 first:border-t-0"
        >
          <div class="flex items-center gap-3">
            <.icon name={row.icon} class="size-5 shrink-0 text-base-content/55" />
            <span class="min-w-0 truncate text-base font-medium">{row.name}</span>
            <span
              :if={row.connection != :host}
              class="ml-auto flex shrink-0 items-center gap-1.5 text-xs text-base-content/60"
            >
              <span class={["size-2 rounded-full", connection_dot(row.connection)]}></span>
              {connection_word(row.connection)}
            </span>
          </div>
          <div
            :if={row.device_line || row.seen_line}
            class="mt-0.5 space-y-0.5 pl-8 text-xs text-base-content/55"
          >
            <div :if={row.device_line} class="truncate">{row.device_line}</div>
            <div :if={row.seen_line}>{row.seen_line}</div>
          </div>

          <div :if={row.viewings != []} class="mt-2 space-y-3 pl-8">
            <div :for={viewing <- row.viewings} id={"playback-viewing-#{viewing.key}"}>
              <div class="flex items-center gap-2">
                <span class={["text-xs", viewing_class(viewing)]}>{viewing_word(viewing)}</span>
                <span class="text-base font-medium truncate">
                  {now_playing_title(viewing.now_playing)}
                </span>
              </div>
              <div
                :if={detail = viewing_detail(viewing)}
                class="text-sm text-base-content/60 truncate"
              >
                {detail}
              </div>
              <div
                :if={(Map.get(viewing.now_playing, :duration_seconds) || 0) > 0}
                class="flex items-center gap-2 mt-1"
              >
                <progress
                  class={["progress h-1.5 flex-1", playback_progress_class(viewing.state)]}
                  value={Map.get(viewing.now_playing, :position_seconds) || 0}
                  max={viewing.now_playing.duration_seconds}
                ></progress>
                <span class="text-xs text-base-content/55 whitespace-nowrap tabular-nums">
                  {format_remaining(
                    viewing.now_playing.duration_seconds -
                      (Map.get(viewing.now_playing, :position_seconds) || 0)
                  )}
                </span>
              </div>
            </div>
          </div>
        </li>
      </ul>

      <h4 class="mt-6 text-[17px] font-semibold tracking-tight">Recently watched</h4>

      <%!-- Recently watched: poster thumb + two-tier title + age. --%>
      <ul
        :if={@playback_activity.recent != []}
        data-component="playback-narrative"
        class="mt-2"
      >
        <li
          :for={entry <- @playback_activity.recent}
          id={watch_row_id(entry)}
          class="grid grid-cols-[2.5rem_minmax(0,1fr)_auto] items-center gap-4 border-t border-base-content/5 py-2.5 first:border-t-0"
        >
          <img
            :if={entry.poster_url}
            src={sized_image_url(entry.poster_url, 160)}
            alt=""
            loading="eager"
            decoding="sync"
            class="h-[3.75rem] w-10 rounded-md border border-base-content/10 object-cover"
          />
          <div
            :if={is_nil(entry.poster_url)}
            class="glass-inset grid h-[3.75rem] w-10 place-items-center rounded-md"
          >
            <.icon name={kind_glyph(entry.kind)} class="size-4 text-base-content/30" />
          </div>
          <div class="min-w-0">
            <div class="truncate text-sm font-medium">{entry.primary}</div>
            <div class="mt-0.5 truncate text-xs text-base-content/55">{entry.secondary}</div>
          </div>
          <span class="shrink-0 text-xs text-base-content/55 tabular-nums">
            {time_ago(entry.at)}
          </span>
        </li>
      </ul>

      <p
        :if={@playback_activity.recent == []}
        data-component="playback-narrative"
        class="mt-3 text-sm text-base-content/55"
      >
        Nothing watched yet.
      </p>

      <%!-- Sole entry point to /history since it left the sidebar — the full
           event list, heatmap, and per-event delete live there. --%>
      <.link
        :if={@playback_activity.lifetime.titles > 0}
        navigate={~p"/history"}
        class="mt-4 inline-flex items-center gap-1.5 text-[13px] font-medium text-primary hover:text-primary/80"
        data-component="watch-history-link"
        data-nav-item
        tabindex="0"
      >
        View full watch history <.icon name="hero-arrow-right-mini" class="size-3.5 shrink-0" />
      </.link>
    </div>
    """
  end

  defp kind_glyph(:movie), do: "hero-film"
  defp kind_glyph(:episode), do: "hero-tv"
  defp kind_glyph(_video), do: "hero-video-camera"

  defp now_playing_title(%{episode_name: _} = now_playing),
    do: Map.get(now_playing, :entity_name) || now_playing.entity_id

  defp now_playing_title(%{movie_name: name}) when is_binary(name), do: name
  defp now_playing_title(%{entity_name: name}) when is_binary(name), do: name
  defp now_playing_title(now_playing), do: now_playing.entity_id

  # The episode line, then whom it plays for.
  defp viewing_detail(%{now_playing: now_playing, profile_name: profile_name}) do
    [episode_line(now_playing), profile_name && "for #{profile_name}"]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end

  defp episode_line(%{episode_name: name} = now_playing) when is_binary(name) do
    if Map.get(now_playing, :season_number) do
      "S#{Map.get(now_playing, :season_number)}E#{Map.get(now_playing, :episode_number) || "?"} · #{name}"
    else
      name
    end
  end

  defp episode_line(_now_playing), do: nil

  defp viewing_word(%{waiting?: true}), do: "waiting for the player"
  defp viewing_word(%{state: state}), do: state

  defp viewing_class(%{waiting?: true}), do: "text-warning"
  defp viewing_class(%{state: state}), do: playback_text_class(state)

  defp connection_word(:connected), do: "Connected"
  defp connection_word(:offline), do: "Not connected"

  # A dot, not coloured words: an unreachable player is quiet, not an alarm —
  # a TV switched off is its normal state. A viewing waiting on one is the alarm.
  defp connection_dot(:connected), do: "bg-success"
  defp connection_dot(:offline), do: "bg-base-content/30"

  # Header status: the widget's single health signal (color reserved for it).
  defp health_classes(%{label: label, tone: :success}),
    do: %{label: label, dot_class: "bg-success", text_class: "text-success"}

  defp health_classes(%{label: label, tone: :warning}),
    do: %{label: label, dot_class: "bg-warning", text_class: "text-warning"}

  defp health_classes(%{label: label, tone: :idle}),
    do: %{label: label, dot_class: "bg-base-content/30", text_class: "text-base-content/55"}

  # Stable iterator id (UIDR-012): completion timestamps are seconds apart.
  defp watch_row_id(%{at: %DateTime{} = at}), do: "watch-#{DateTime.to_unix(at, :microsecond)}"
end
