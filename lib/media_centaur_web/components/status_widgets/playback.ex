defmodule MediaCentaurWeb.Components.StatusWidgets.Playback do
  @moduledoc """
  Playback subsystem Activity widget: active sessions + now-playing + progress.

  Rendered into the health-board drill-in's :activity slot via
  MediaCentaurWeb.StatusLive.ActivityWidgets, invoked with a plain data
  bundle (no change-tracking) from StatusLive.activity_bundle/1 — derive
  with Map.put/3, never assign/3.
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.StatusHelpers
  import MediaCentaurWeb.LiveHelpers, only: [time_ago: 1, sized_image_url: 2]

  # A `w-10` thumbnail — 40 CSS px, doubled on a 4K panel. It was serving the
  # 1120px poster master.

  @doc "Playback subsystem Activity widget: active sessions with now-playing + progress."
  attr :playback, :map,
    required: true,
    doc: "playback view (%{state, now_playing, sessions}) derived by StatusHelpers.derive_playback/1"

  attr :playback_activity, :map,
    required: true,
    doc:
      "watch-activity snapshot from WatchHistory.Views.PlaybackActivity (%{recent, last_write_at, lifetime})"

  def playback_widget(assigns) do
    sessions =
      assigns.playback.sessions
      |> Enum.map(fn {_id, session} -> session end)
      |> Enum.sort_by(fn session -> session[:started_at] || 0 end)

    assigns = Map.put(assigns, :sessions, sessions)

    health = playback_health(assigns.playback.state, length(sessions))
    assigns = Map.put(assigns, :health, health)

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
            {@playback_activity.lifetime.hours}<span class="ml-1.5 text-base font-normal text-base-content/50">hrs</span>
          </div>
          <div class="mt-2.5 text-[11px] font-semibold uppercase tracking-[0.12em] text-base-content/40">
            Watched, lifetime
          </div>
        </div>
        <div class="border-l border-base-content/10 px-6 py-5">
          <div class="text-4xl font-extralight leading-none tracking-tight tabular-nums">
            {@playback_activity.lifetime.titles}
          </div>
          <div class="mt-2.5 text-[11px] font-semibold uppercase tracking-[0.12em] text-base-content/40">
            Titles finished
          </div>
        </div>
        <div class="border-l border-base-content/10 px-6 py-5">
          <div class={[
            "text-4xl font-extralight leading-none tracking-tight tabular-nums",
            @playback_activity.lifetime.streak == 0 && "text-base-content/40"
          ]}>
            {@playback_activity.lifetime.streak}
          </div>
          <div class="mt-2.5 text-[11px] font-semibold uppercase tracking-[0.12em] text-base-content/40">
            Day streak
          </div>
        </div>
      </div>

      <%!-- List head: section title left, the single health signal right. --%>
      <div class="flex items-baseline justify-between">
        <h4 class="text-[17px] font-semibold tracking-tight">
          {if @sessions == [], do: "Recently watched", else: "Now playing"}
        </h4>
        <span
          class={["flex items-center gap-1.5 text-xs", @health.text_class]}
          data-component="playback-health"
        >
          <span class={["size-2 rounded-full shrink-0", @health.dot_class]}></span>
          {@health.label}
        </span>
      </div>

      <%!-- Now playing: one block per active session --%>
      <div :if={@sessions != []} data-component="playback-narrative" class="mt-3 space-y-3">
        <div :for={session <- @sessions}>
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
            ></progress>
            <span class="text-xs text-base-content/50 whitespace-nowrap tabular-nums">
              {format_remaining(
                session.now_playing.duration_seconds -
                  (session.now_playing[:position_seconds] || 0)
              )}
            </span>
          </div>
        </div>
      </div>

      <%!-- Recently watched (idle): poster thumb + two-tier title + age. --%>
      <ul
        :if={@sessions == [] and @playback_activity.recent != []}
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
            <div class="mt-0.5 truncate text-xs text-base-content/50">{entry.secondary}</div>
          </div>
          <span class="shrink-0 text-xs text-base-content/40 tabular-nums">
            {time_ago(entry.at)}
          </span>
        </li>
      </ul>

      <p
        :if={@sessions == [] and @playback_activity.recent == []}
        data-component="playback-narrative"
        class="mt-3 text-sm text-base-content/50"
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
    do: now_playing[:entity_name] || now_playing.entity_id

  defp now_playing_title(%{movie_name: name}) when is_binary(name), do: name
  defp now_playing_title(%{entity_name: name}) when is_binary(name), do: name
  defp now_playing_title(now_playing), do: now_playing.entity_id

  defp now_playing_detail(%{episode_name: name} = now_playing) when is_binary(name) do
    if now_playing[:season_number] do
      "S#{now_playing[:season_number]}E#{now_playing[:episode_number] || "?"} · #{name}"
    else
      name
    end
  end

  defp now_playing_detail(_), do: nil

  # Header status: the widget's single health signal (color reserved for it).
  # The mpv link is per-session, so "active" reflects live sessions and idle is
  # the calm, healthy resting state — the recent feed is the recorder's proof-of-life.
  defp playback_health(state, count) when state in [:playing, :paused] and count > 0 do
    %{label: "#{count} active", dot_class: "bg-success", text_class: "text-success"}
  end

  defp playback_health(:starting, _count) do
    %{label: "Connecting…", dot_class: "bg-warning", text_class: "text-warning"}
  end

  defp playback_health(_idle, _count) do
    %{label: "Idle", dot_class: "bg-base-content/30", text_class: "text-base-content/50"}
  end

  # Stable iterator id (UIDR-012): completion timestamps are seconds apart.
  defp watch_row_id(%{at: %DateTime{} = at}), do: "watch-#{DateTime.to_unix(at, :microsecond)}"
end
