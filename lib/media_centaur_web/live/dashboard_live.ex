defmodule MediaCentaurWeb.DashboardLive do
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.Dashboard
  alias MediaCentaur.Pipeline.Stats

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "watcher:state")
        Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "library:updates")
        Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "playback:events")

        Process.send_after(self(), :tick_pipeline, 2_000)

        stats = Dashboard.fetch_stats()
        pipeline_stats = Stats.get_snapshot()

        socket
        |> assign(library_stats: stats.library)
        |> assign(pending_review_count: length(stats.pending_review))
        |> assign(pipeline_stats: pipeline_stats)
        |> assign(watcher_statuses: MediaCentaur.Watcher.Supervisor.statuses())
        |> assign(playback: MediaCentaur.Playback.Manager.current_state())
      else
        socket
        |> assign(library_stats: %{episodes: 0, files: 0, images: 0, by_type: %{}})
        |> assign(pending_review_count: 0)
        |> assign(pipeline_stats: Stats.empty_snapshot())
        |> assign(watcher_statuses: [])
        |> assign(playback: %{state: :idle, now_playing: nil})
      end

    {:ok, assign(socket, stats_timer: nil)}
  end

  # --- Info handlers ---

  @impl true
  def handle_info(:tick_pipeline, socket) do
    Process.send_after(self(), :tick_pipeline, 2_000)
    pipeline_stats = Stats.get_snapshot()
    {:noreply, assign(socket, pipeline_stats: pipeline_stats)}
  end

  def handle_info({:watcher_state_changed, _dir, _new_state}, socket) do
    {:noreply, assign(socket, watcher_statuses: MediaCentaur.Watcher.Supervisor.statuses())}
  end

  def handle_info({:entities_changed, _entity_ids}, socket) do
    {:noreply, debounce_stats_refresh(socket)}
  end

  def handle_info(:refresh_stats, socket) do
    stats = Dashboard.fetch_stats()

    {:noreply,
     socket
     |> assign(stats_timer: nil)
     |> assign(library_stats: stats.library)
     |> assign(pending_review_count: length(stats.pending_review))}
  end

  def handle_info({:playback_state_changed, new_state, now_playing}, socket) do
    {:noreply, assign(socket, playback: %{state: new_state, now_playing: now_playing})}
  end

  def handle_info({:playback_progress, progress}, socket) do
    playback = socket.assigns.playback

    now_playing =
      if playback.now_playing do
        playback.now_playing
        |> Map.put(:position_seconds, progress.position_seconds)
        |> Map.put(:duration_seconds, progress.duration_seconds)
      end

    {:noreply, assign(socket, playback: %{playback | now_playing: now_playing})}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/">
      <div class="space-y-6">
        <h1 class="text-2xl font-bold">Dashboard</h1>

        <.library_stats stats={@library_stats} />

        <div class="grid md:grid-cols-3 gap-4">
          <.ops_summary_card
            pipeline_stats={@pipeline_stats}
            watcher_statuses={@watcher_statuses}
          />
          <.review_summary_card count={@pending_review_count} />
          <.playback_summary_card playback={@playback} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  # --- Section Components ---

  defp library_stats(assigns) do
    ~H"""
    <div class="card glass-surface">
      <div class="card-body">
        <h2 class="card-title text-lg">Library</h2>

        <div class="stats stats-horizontal glass-inset w-full">
          <div class="stat">
            <div class="stat-title">Movies</div>
            <div class="stat-value text-2xl">{@stats.by_type[:movie] || 0}</div>
            <div class="stat-desc">{@stats.by_type[:movie_series] || 0} collections</div>
          </div>
          <div class="stat">
            <div class="stat-title">TV Series</div>
            <div class="stat-value text-2xl">{@stats.by_type[:tv_series] || 0}</div>
            <div class="stat-desc">{@stats.episodes} episodes</div>
          </div>
          <div :if={(@stats.by_type[:video_object] || 0) > 0} class="stat">
            <div class="stat-title">Videos</div>
            <div class="stat-value text-2xl">{@stats.by_type[:video_object]}</div>
          </div>
        </div>

        <div class="flex gap-4 text-sm text-base-content/60 px-1">
          <span>{@stats.files} files tracked</span>
          <span>{@stats.images} images cached</span>
        </div>
      </div>
    </div>
    """
  end

  defp ops_summary_card(assigns) do
    assigns = assign(assigns, :overall_status, derive_pipeline_status(assigns.pipeline_stats))

    ~H"""
    <.link
      navigate="/operations"
      class={[
        "card glass-surface hover:shadow-md transition-shadow border-l-3",
        ops_border_class(@overall_status)
      ]}
    >
      <div class="card-body">
        <h2 class="card-title text-lg">Operations</h2>

        <div class="space-y-2 text-sm">
          <div class="flex items-center justify-between">
            <span class="text-base-content/60">Pipeline</span>
            <span class={["w-2 h-2 rounded-full", pipeline_dot_class(@overall_status)]}></span>
          </div>

          <div class="flex items-center justify-between">
            <span class="text-base-content/60">Watchers</span>
            <div class="flex gap-1">
              <span
                :for={status <- @watcher_statuses}
                class={["w-2 h-2 rounded-full", watcher_dot_class(status.state)]}
              >
              </span>
              <span :if={@watcher_statuses == []} class="text-xs text-base-content/40">none</span>
            </div>
          </div>

          <div :if={@pipeline_stats.queue_depth > 0} class="flex items-center justify-between">
            <span class="text-base-content/60">Queue</span>
            <span class="font-mono">{@pipeline_stats.queue_depth} queued</span>
          </div>

          <div :if={@pipeline_stats.total_failed > 0} class="flex items-center justify-between">
            <span class="text-base-content/60">Errors</span>
            <span class="text-error font-mono">{@pipeline_stats.total_failed}</span>
          </div>
        </div>
      </div>
    </.link>
    """
  end

  defp review_summary_card(assigns) do
    ~H"""
    <.link
      navigate="/review"
      class={[
        "card glass-surface hover:shadow-md transition-shadow border-l-3",
        if(@count > 0, do: "border-warning", else: "border-base-content/20")
      ]}
    >
      <div class="card-body">
        <h2 class="card-title text-lg">Review</h2>

        <div class="text-sm">
          <span :if={@count == 0} class="text-base-content/60">No files pending review</span>
          <div :if={@count > 0} class="flex items-center gap-2">
            <span class="badge badge-warning badge-sm">{@count}</span>
            <span>files awaiting review</span>
          </div>
        </div>
      </div>
    </.link>
    """
  end

  defp playback_summary_card(assigns) do
    ~H"""
    <div class={[
      "card glass-surface border-l-3",
      playback_border_class(@playback.state)
    ]}>
      <div class="card-body">
        <h2 class="card-title text-lg">Playback</h2>

        <div class="text-sm">
          <div class="flex items-center gap-2">
            <span class={["badge badge-sm", playback_badge_class(@playback.state)]}>
              {@playback.state}
            </span>

            <span :if={@playback.now_playing} class="truncate">
              {now_playing_label(@playback.now_playing)}
            </span>
            <span :if={!@playback.now_playing} class="text-base-content/60">Idle</span>
          </div>

          <div
            :if={
              @playback.now_playing &&
                @playback.now_playing[:duration_seconds] &&
                @playback.now_playing.duration_seconds > 0
            }
            class="mt-1 text-xs text-base-content/60"
          >
            {format_seconds(@playback.now_playing[:position_seconds] || 0)} / {format_seconds(
              @playback.now_playing.duration_seconds
            )}
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Helpers ---

  defp derive_pipeline_status(pipeline_stats) do
    stages = Map.values(pipeline_stats.stages)

    cond do
      Enum.any?(stages, &(&1.status == :erroring)) -> :error
      Enum.any?(stages, &(&1.status in [:active, :saturated])) -> :active
      true -> :idle
    end
  end

  defp pipeline_dot_class(:idle), do: "bg-base-content/30"
  defp pipeline_dot_class(:active), do: "bg-success"
  defp pipeline_dot_class(:error), do: "bg-error"

  defp watcher_dot_class(:watching), do: "bg-success"
  defp watcher_dot_class(:initializing), do: "bg-warning"
  defp watcher_dot_class(_), do: "bg-error"

  defp playback_badge_class(:idle), do: "badge-ghost"
  defp playback_badge_class(:playing), do: "badge-success"
  defp playback_badge_class(:paused), do: "badge-warning"
  defp playback_badge_class(_), do: "badge-info"

  defp ops_border_class(:error), do: "border-error"
  defp ops_border_class(_), do: "border-info"

  defp now_playing_label(%{episode_name: name} = np) when is_binary(name) do
    "S#{np[:season_number] || "?"}E#{np[:episode_number] || "?"} · #{name}"
  end

  defp now_playing_label(%{movie_name: name}) when is_binary(name), do: name

  defp now_playing_label(%{entity_name: name}) when is_binary(name), do: name

  defp now_playing_label(np), do: np.entity_id

  defp playback_border_class(:playing), do: "border-success"
  defp playback_border_class(:paused), do: "border-warning"
  defp playback_border_class(_), do: "border-base-content/20"
end
