defmodule MediaCentaurWeb.DashboardLive do
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.{Dashboard, Library, Storage}
  alias MediaCentaur.Pipeline.Stats
  alias MediaCentaur.ImagePipeline

  @storage_refresh_ms 5 * 60 * 1_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.watcher_state())
        Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.library_updates())
        Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.playback_events())

        Process.send_after(self(), :tick_pipeline, 1_000)
        Process.send_after(self(), :refresh_storage, @storage_refresh_ms)

        stats = Dashboard.fetch_stats()
        pipeline_stats = Stats.get_snapshot()
        image_stats = ImagePipeline.Stats.get_snapshot()

        socket
        |> assign(library_stats: stats.library)
        |> assign(pending_review_count: length(stats.pending_review))
        |> assign(recent_changes: stats.recent_changes)
        |> assign(recent_changes_days: Dashboard.recent_changes_days())
        |> assign(recent_errors: merge_recent_errors(pipeline_stats, image_stats))
        |> assign(pipeline_stats: pipeline_stats)
        |> assign(image_pipeline_stats: image_stats)
        |> assign(watcher_statuses: MediaCentaur.Watcher.Supervisor.statuses())
        |> assign(storage_drives: Storage.measure_all())
        |> assign(config: load_config())
        |> assign(rate_limiter: fetch_rate_limiter())
        |> assign(retry_status: fetch_retry_status())
        |> assign(playback: build_playback_state())
      else
        socket
        |> assign(library_stats: %{episodes: 0, files: 0, images: 0, by_type: %{}})
        |> assign(pending_review_count: 0)
        |> assign(recent_changes: [])
        |> assign(recent_changes_days: 3)
        |> assign(recent_errors: [])
        |> assign(pipeline_stats: Stats.empty_snapshot())
        |> assign(image_pipeline_stats: ImagePipeline.Stats.empty_snapshot())
        |> assign(watcher_statuses: [])
        |> assign(storage_drives: [])
        |> assign(config: %{})
        |> assign(rate_limiter: nil)
        |> assign(retry_status: nil)
        |> assign(playback: %{state: :idle, now_playing: nil, sessions: %{}})
      end

    {:ok,
     assign(socket,
       stats_timer: nil,
       pipeline_concurrency: MediaCentaur.Pipeline.processor_concurrency(),
       image_pipeline_concurrency: 4
     )}
  end

  # --- Events ---

  @impl true
  def handle_event("set_recent_changes_days", %{"days" => days_str}, socket) do
    days = String.to_integer(days_str)

    Library.upsert_setting!(%{
      key: "dashboard:recent_changes_days",
      value: %{"days" => days}
    })

    {:noreply,
     socket
     |> assign(recent_changes_days: days)
     |> assign(recent_changes: Dashboard.fetch_recent_changes())}
  end

  # --- Info handlers ---

  @impl true
  def handle_info(:tick_pipeline, socket) do
    Process.send_after(self(), :tick_pipeline, 1_000)
    pipeline_stats = Stats.get_snapshot()
    image_stats = ImagePipeline.Stats.get_snapshot()

    {:noreply,
     socket
     |> assign(pipeline_stats: pipeline_stats)
     |> assign(image_pipeline_stats: image_stats)
     |> assign(recent_errors: merge_recent_errors(pipeline_stats, image_stats))
     |> assign(rate_limiter: fetch_rate_limiter())
     |> assign(retry_status: fetch_retry_status())}
  end

  def handle_info(:refresh_storage, socket) do
    Process.send_after(self(), :refresh_storage, @storage_refresh_ms)
    {:noreply, assign(socket, storage_drives: Storage.measure_all())}
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
     |> assign(pending_review_count: length(stats.pending_review))
     |> assign(recent_changes: stats.recent_changes)
     |> assign(recent_errors: stats.recent_errors)}
  end

  def handle_info(
        {:playback_state_changed, entity_id, new_state, now_playing, started_at},
        socket
      ) do
    sessions = socket.assigns.playback.sessions

    sessions =
      case new_state do
        :stopped ->
          Map.delete(sessions, entity_id)

        _ ->
          existing = Map.get(sessions, entity_id)
          kept_started_at = (existing && existing[:started_at]) || started_at

          Map.put(sessions, entity_id, %{
            state: new_state,
            now_playing: now_playing,
            started_at: kept_started_at
          })
      end

    {:noreply, assign(socket, playback: derive_playback(sessions))}
  end

  def handle_info(
        {:entity_progress_updated, entity_id, _summary, _resume_target, _child_targets_delta,
         progress_records, _last_activity_at},
        socket
      ) do
    sessions = socket.assigns.playback.sessions

    socket =
      case Map.get(sessions, entity_id) do
        %{now_playing: now_playing} = session when not is_nil(now_playing) ->
          record =
            Enum.find(progress_records, fn record ->
              record.season_number == (now_playing[:season_number] || 0) &&
                record.episode_number == (now_playing[:episode_number] || 0)
            end)

          if record do
            updated =
              Map.merge(now_playing, %{
                position_seconds: record.position_seconds,
                duration_seconds: record.duration_seconds
              })

            updated_sessions =
              Map.put(sessions, entity_id, %{session | now_playing: updated})

            assign(socket, playback: derive_playback(updated_sessions))
          else
            socket
          end

        _ ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/dashboard">
      <div data-page-behavior="dashboard" data-nav-default-zone="dashboard" class="space-y-6">
        <h1 class="text-2xl font-bold">Dashboard</h1>

        <div data-nav-zone="sections">
          <.link navigate="/" data-nav-item tabindex="0" class="block">
            <.library_stats stats={@library_stats} pending_review_count={@pending_review_count} />
          </.link>

          <.recent_changes_card entries={@recent_changes} days={@recent_changes_days} />

          <.link navigate="/settings?section=services" data-nav-item tabindex="0" class="block mt-6">
            <div class="grid grid-cols-1 lg:grid-cols-[3fr_2fr] gap-6">
              <.pipeline_card
                content_stats={@pipeline_stats}
                image_stats={@image_pipeline_stats}
                retry_status={@retry_status}
                pipeline_concurrency={@pipeline_concurrency}
                image_concurrency={@image_pipeline_concurrency}
              />

              <div class="flex flex-col gap-6">
                <.playback_summary_card playback={@playback} />
                <.watcher_health statuses={@watcher_statuses} />
                <.external_integrations rate_limiter={@rate_limiter} config={@config} />
              </div>
            </div>
          </.link>

          <.link navigate="/settings?section=services" data-nav-item tabindex="0" class="block mt-6">
            <.recent_errors_table files={@recent_errors} />
          </.link>

          <.link
            navigate="/settings?section=configuration"
            data-nav-item
            tabindex="0"
            class="block mt-6"
          >
            <.storage_health drives={@storage_drives} />
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # --- Section Components ---

  defp library_stats(assigns) do
    ~H"""
    <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
      <div class="p-4 rounded-lg glass-surface">
        <div class="text-2xl font-bold">{@stats.by_type[:movie] || 0}</div>
        <div class="text-sm text-base-content/60">Movies</div>
        <div class="text-xs text-base-content/40 mt-1">
          {@stats.by_type[:movie_series] || 0} collections
        </div>
      </div>
      <div class="p-4 rounded-lg glass-surface">
        <div class="text-2xl font-bold">{@stats.by_type[:tv_series] || 0}</div>
        <div class="text-sm text-base-content/60">TV Series</div>
        <div class="text-xs text-base-content/40 mt-1">{@stats.episodes} episodes</div>
      </div>
      <div :if={(@stats.by_type[:video_object] || 0) > 0} class="p-4 rounded-lg glass-surface">
        <div class="text-2xl font-bold">{@stats.by_type[:video_object]}</div>
        <div class="text-sm text-base-content/60">Videos</div>
      </div>
      <div class="p-4 rounded-lg glass-surface">
        <div class="text-2xl font-bold">{@stats.files}</div>
        <div class="text-sm text-base-content/60">Files Tracked</div>
      </div>
      <div class="p-4 rounded-lg glass-surface">
        <div class="text-2xl font-bold">{@stats.images}</div>
        <div class="text-sm text-base-content/60">Images Cached</div>
      </div>
      <div class={[
        "p-4 rounded-lg glass-surface",
        if(@pending_review_count > 0, do: "border-l-3 border-warning")
      ]}>
        <div class="text-2xl font-bold">{@pending_review_count}</div>
        <div class="text-sm text-base-content/60">Pending Review</div>
      </div>
    </div>
    """
  end

  @days_options [1, 3, 7, 14, 30]

  defp recent_changes_card(assigns) do
    assigns = assign(assigns, :days_options, @days_options)

    ~H"""
    <div class="card glass-surface mt-6">
      <div class="card-body">
        <div class="flex items-center justify-between">
          <h2 class="card-title text-lg">Recent Changes</h2>
          <select
            phx-change="set_recent_changes_days"
            name="days"
            class="select select-xs select-ghost text-base-content/60"
          >
            <option :for={d <- @days_options} value={d} selected={d == @days}>
              {d}d
            </option>
          </select>
        </div>

        <p :if={@entries == []} class="text-base-content/60">
          No changes in the last {@days} {if @days == 1, do: "day", else: "days"}.
        </p>

        <ul :if={@entries != []} class="space-y-1">
          <li :for={entry <- @entries}>
            <.change_entry_row entry={entry} />
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp change_entry_row(%{entry: %{kind: :added}} = assigns) do
    ~H"""
    <.link
      navigate={"/?zone=library&selected=#{@entry.entity_id}"}
      class="flex items-center gap-3 py-1 hover:bg-base-content/5 rounded px-2 -mx-2"
    >
      <span class="w-2 h-2 rounded-full bg-success shrink-0"></span>
      <span class="text-sm truncate flex-1">{@entry.entity_name}</span>
      <span class="text-xs text-base-content/50">
        {MediaCentaurWeb.LibraryHelpers.format_type(@entry.entity_type)}
      </span>
      <span class="text-xs text-base-content/40 whitespace-nowrap">
        {MediaCentaurWeb.LiveHelpers.time_ago(@entry.inserted_at)}
      </span>
    </.link>
    """
  end

  defp change_entry_row(%{entry: %{kind: :removed}} = assigns) do
    ~H"""
    <div class="flex items-center gap-3 py-1 px-2 -mx-2">
      <span class="w-2 h-2 rounded-full bg-error shrink-0"></span>
      <span class="text-sm truncate flex-1 text-base-content/60">{@entry.entity_name}</span>
      <span class="text-xs text-base-content/50">
        {MediaCentaurWeb.LibraryHelpers.format_type(@entry.entity_type)}
      </span>
      <span class="text-xs text-base-content/40 whitespace-nowrap">
        {MediaCentaurWeb.LiveHelpers.time_ago(@entry.inserted_at)}
      </span>
    </div>
    """
  end

  @stage_grid_columns "grid-template-columns: 0.5rem 1fr 5rem 4.5rem 4.5rem 3rem"

  defp pipeline_card(assigns) do
    assigns =
      assigns
      |> assign(:stage_order, [:parse, :search, :fetch_metadata, :ingest])
      |> assign(:grid_columns, @stage_grid_columns)

    ~H"""
    <div class="card glass-surface self-start">
      <div class="card-body">
        <%!-- Pipeline header --%>
        <div class="flex items-center justify-between">
          <h2 class="card-title text-lg">Pipeline</h2>
          <div class="flex items-center gap-3 text-sm">
            <span :if={@content_stats.queue_depth > 0} class="text-info text-sm">
              {@content_stats.queue_depth} queued
            </span>
            <span :if={@content_stats.total_failed > 0} class="text-error text-xs">
              {@content_stats.total_failed} failed
            </span>
          </div>
        </div>

        <%!-- New Media section with column headers --%>
        <div
          class="grid items-center gap-2 mt-3 mb-1"
          style={@grid_columns}
        >
          <span></span>
          <span class="text-xs text-base-content/50 uppercase tracking-wide">New Media</span>
          <span class="text-xs text-base-content/40 uppercase tracking-wide">Status</span>
          <span class="text-xs text-base-content/40 uppercase tracking-wide text-right">Rate</span>
          <span class="text-xs text-base-content/40 uppercase tracking-wide text-right">Avg</span>
          <span class="text-xs text-base-content/40 uppercase tracking-wide text-right">Slots</span>
        </div>

        <%!-- Content pipeline stages --%>
        <div class="space-y-0.5">
          <.pipeline_stage
            :for={stage <- @stage_order}
            stage={stage}
            data={@content_stats.stages[stage]}
            concurrency={@pipeline_concurrency}
            grid_columns={@grid_columns}
          />
        </div>

        <%!-- Images section --%>
        <h3 class="text-xs text-base-content/50 uppercase tracking-wide mt-3">Images</h3>

        <%!-- Image pipeline row — same grid as content stages --%>
        <div
          class="grid items-center gap-2 py-1"
          style={@grid_columns}
        >
          <span class={["w-2 h-2 rounded-full", stage_dot_class(@image_stats.status)]}></span>

          <span class="text-sm font-medium truncate">
            Download + Resize
            <span :if={@image_stats.last_error} class="text-error text-xs font-normal ml-2">
              {elem(@image_stats.last_error, 0)}
            </span>
          </span>

          <span class={["text-xs", stage_text_class(@image_stats.status)]}>
            {stage_status_label(@image_stats.status)}
          </span>

          <span class="text-xs font-mono text-base-content/60 text-right">
            {format_throughput(@image_stats.throughput)}
          </span>

          <span class="text-xs font-mono text-base-content/60 text-right">
            {format_duration(@image_stats.avg_duration_ms)}
          </span>

          <span class="text-xs font-mono text-base-content/40 text-right">
            {@image_stats.active_count}/{@image_concurrency}
          </span>
        </div>

        <div
          :if={
            @image_stats.total_downloaded > 0 or @image_stats.total_failed > 0 or
              @image_stats.queue_depth > 0 or
              (@retry_status && @retry_status.retrying_count > 0)
          }
          class="flex items-center gap-3 text-xs text-base-content/50 ml-6"
        >
          <span :if={@image_stats.total_downloaded > 0}>
            {@image_stats.total_downloaded} downloaded
          </span>
          <span :if={@image_stats.total_failed > 0} class="text-error">
            {@image_stats.total_failed} failed
          </span>
          <span :if={@image_stats.queue_depth > 0}>
            {@image_stats.queue_depth} queued
          </span>
          <span :if={@retry_status && @retry_status.retrying_count > 0} class="text-warning">
            {@retry_status.retrying_count} retrying
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp pipeline_stage(assigns) do
    ~H"""
    <div
      class="grid items-center gap-2 py-1"
      style={@grid_columns}
    >
      <span class={["w-2 h-2 rounded-full", stage_dot_class(@data.status)]}></span>

      <span class="text-sm font-medium truncate">
        {stage_display_name(@stage)}
        <span :if={@data.last_error} class="text-error text-xs font-normal ml-2">
          {elem(@data.last_error, 0)}
        </span>
      </span>

      <span class={["text-xs", stage_text_class(@data.status)]}>
        {stage_status_label(@data.status)}
      </span>

      <span class="text-xs font-mono text-base-content/60 text-right">
        {format_throughput(@data.throughput)}
      </span>

      <span class="text-xs font-mono text-base-content/60 text-right">
        {format_duration(@data.avg_duration_ms)}
      </span>

      <span class="text-xs font-mono text-base-content/40 text-right">
        {@data.active_count}/{@concurrency}
      </span>
    </div>
    """
  end

  defp watcher_health(assigns) do
    ~H"""
    <div class="card glass-surface">
      <div class="card-body">
        <h2 class="card-title text-lg">Watcher Health</h2>

        <p :if={@statuses == []} class="text-base-content/60">No watch directories configured.</p>

        <ul :if={@statuses != []} class="space-y-2">
          <li :for={status <- @statuses} class="flex items-center gap-3">
            <span class={["text-sm", watcher_text_class(status.state)]}>
              {status.state}
            </span>
            <code class="text-sm">{status.dir}</code>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp external_integrations(assigns) do
    ~H"""
    <div class="card glass-surface">
      <div class="card-body">
        <h2 class="card-title text-lg">External Integrations</h2>

        <div class="space-y-3">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class="text-sm font-medium">TMDB</span>
              <span :if={@config[:tmdb_configured]} class="text-success text-xs">
                configured
              </span>
              <span :if={!@config[:tmdb_configured]} class="text-error text-xs">
                not configured
              </span>
            </div>

            <div :if={@rate_limiter} class="flex items-center gap-3 text-sm">
              <span class="font-mono text-base-content/60">
                {@rate_limiter.used}/{@rate_limiter.total} used
              </span>
              <span class={[
                "font-mono",
                if(@rate_limiter.available == 0, do: "text-warning", else: "text-success")
              ]}>
                {@rate_limiter.available} available
              </span>
            </div>

            <span :if={!@rate_limiter} class="text-sm text-base-content/40">
              rate limiter not started
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp recent_errors_table(assigns) do
    ~H"""
    <div class="card glass-surface">
      <div class="card-body">
        <h2 class="card-title text-lg">
          Recent Errors <span :if={@files != []} class="text-error text-sm">{length(@files)}</span>
        </h2>

        <p :if={@files == []} class="text-base-content/60">No errors.</p>

        <div :if={@files != []} class="overflow-x-auto">
          <table class="table table-sm table-zebra">
            <thead>
              <tr>
                <th>Stage</th>
                <th>File</th>
                <th>Error Message</th>
                <th>Time</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={error <- @files}>
                <td>
                  <span class="text-error text-xs">{error[:stage] || "—"}</span>
                </td>
                <td class="font-mono text-xs max-w-xs truncate-left" title={error.file_path}>
                  {error.file_path || "—"}
                </td>
                <td class="text-error text-xs max-w-md truncate">{error.error_message || "—"}</td>
                <td class="text-xs">{format_datetime(error.updated_at)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  defp storage_health(assigns) do
    ~H"""
    <div class="card glass-surface">
      <div class="card-body">
        <h2 class="card-title text-lg">Storage</h2>

        <p :if={@drives == []} class="text-base-content/60">No directories configured.</p>

        <div :if={@drives != []} class="space-y-6">
          <div :for={drive <- @drives}>
            <div class="flex items-baseline justify-between mb-1">
              <span class="text-sm font-medium">
                {drive.mount_point}
                <span class="text-base-content/40 font-normal">({drive.device})</span>
              </span>
              <span class="text-xs text-base-content/60 font-mono">
                {format_bytes(drive.used_bytes)} / {format_bytes(drive.total_bytes)}
              </span>
            </div>
            <div class="flex items-center gap-3 mb-3">
              <progress
                class={["progress flex-1", usage_progress_class(drive.usage_percent)]}
                value={drive.usage_percent}
                max="100"
              >
              </progress>
              <span class={[
                "text-sm font-mono w-10 text-right",
                usage_text_class(drive.usage_percent)
              ]}>
                {drive.usage_percent}%
              </span>
            </div>
            <div class="space-y-1 ml-2">
              <div
                :for={role <- drive.roles}
                class="grid gap-3 text-xs"
                style="grid-template-columns: 6rem 1fr"
              >
                <span class="text-base-content/50">{role.label}</span>
                <code
                  class="truncate-left text-base-content/70"
                  title={role.path}
                >
                  {role.path}
                </code>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp playback_summary_card(assigns) do
    sessions =
      assigns.playback.sessions
      |> Enum.map(fn {_id, session} -> session end)
      |> Enum.sort_by(fn s -> s[:started_at] || 0 end)

    assigns = assign(assigns, :sessions, sessions)

    ~H"""
    <div class={[
      "card glass-surface border-l-3",
      playback_border_class(@playback.state)
    ]}>
      <div class="card-body">
        <div class="flex justify-between items-center">
          <h2 class="card-title text-lg">Playback</h2>
          <span :if={@sessions == []} class="text-sm text-base-content/60">idle</span>
          <span :if={@sessions != []} class="text-sm text-base-content/60">
            {length(@sessions)} active
          </span>
        </div>

        <div :if={@sessions == []} class="mt-1 text-sm text-base-content/60">Idle</div>

        <div :for={session <- @sessions} class="mt-2">
          <div class="flex items-center gap-2">
            <span class={["text-xs", playback_text_class(session.state)]}>
              {session.state}
            </span>
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
      </div>
    </div>
    """
  end

  # --- Playback State ---

  defp build_playback_state do
    sessions =
      MediaCentaur.Playback.Sessions.list()
      |> Map.new(fn session ->
        {session.entity_id,
         %{
           state: session.state,
           now_playing: session.now_playing,
           started_at: session.started_at
         }}
      end)

    derive_playback(sessions)
  end

  # Derives the dashboard's single-card playback view from the sessions map.
  # Shows the most recently active session (playing > paused).
  defp derive_playback(sessions) when sessions == %{} do
    %{state: :idle, now_playing: nil, sessions: sessions}
  end

  defp derive_playback(sessions) do
    # Prefer playing sessions, then paused
    {_entity_id, primary} =
      sessions
      |> Enum.sort_by(fn {_id, s} -> if s.state == :playing, do: 0, else: 1 end)
      |> hd()

    %{state: primary.state, now_playing: primary.now_playing, sessions: sessions}
  end

  # --- Helpers ---

  defp merge_recent_errors(content_stats, image_stats) do
    (content_stats.recent_errors ++ image_stats.recent_errors)
    |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
    |> Enum.take(50)
  end

  defp fetch_rate_limiter do
    MediaCentaur.TMDB.RateLimiter.status()
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp fetch_retry_status do
    MediaCentaur.ImagePipeline.RetryScheduler.status()
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp load_config do
    config = MediaCentaur.Config

    %{
      tmdb_configured: config.get(:tmdb_api_key) not in [nil, ""],
      auto_approve_threshold: config.get(:auto_approve_threshold),
      mpv_path: config.get(:mpv_path),
      database_path: config.get(:database_path),
      watch_dirs_count: length(config.get(:watch_dirs) || [])
    }
  end

  defp format_datetime(nil), do: "—"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end

  defp format_remaining(seconds) when seconds <= 0, do: "finished"
  defp format_remaining(seconds) when seconds < 60, do: "#{round(seconds)}s remaining"
  defp format_remaining(seconds) when seconds < 3600, do: "#{round(seconds / 60)}m remaining"
  defp format_remaining(seconds), do: "#{Float.round(seconds / 3600, 1)}h remaining"

  defp format_throughput(rate) when rate == 0.0, do: "—"
  defp format_throughput(rate), do: "#{rate}/s"

  defp format_duration(nil), do: "—"
  defp format_duration(ms) when ms < 1_000, do: "#{round(ms)}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1_000, 1)}s"
  defp format_duration(ms), do: "#{Float.round(ms / 60_000, 1)}m"

  defp stage_dot_class(:idle), do: "bg-base-content/20"
  defp stage_dot_class(:active), do: "bg-success"
  defp stage_dot_class(:saturated), do: "bg-warning"
  defp stage_dot_class(:erroring), do: "bg-error"

  defp stage_text_class(:idle), do: "text-base-content/60"
  defp stage_text_class(:active), do: "text-success"
  defp stage_text_class(:saturated), do: "text-warning"
  defp stage_text_class(:erroring), do: "text-error"

  defp stage_status_label(:idle), do: "idle"
  defp stage_status_label(:active), do: "active"
  defp stage_status_label(:saturated), do: "saturated"
  defp stage_status_label(:erroring), do: "erroring"

  defp stage_display_name(:parse), do: "Parse Media Path"
  defp stage_display_name(:search), do: "Match on TMDB"
  defp stage_display_name(:fetch_metadata), do: "Enrich Metadata"
  defp stage_display_name(:ingest), do: "Add to Library"

  defp watcher_text_class(:watching), do: "text-success"
  defp watcher_text_class(:initializing), do: "text-warning"
  defp watcher_text_class(_), do: "text-error"

  defp playback_text_class(:idle), do: "text-base-content/60"
  defp playback_text_class(:playing), do: "text-success"
  defp playback_text_class(:paused), do: "text-warning"
  defp playback_text_class(_), do: "text-info"

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

  defp playback_progress_class(:playing), do: "progress-success"
  defp playback_progress_class(:paused), do: "progress-warning"
  defp playback_progress_class(_), do: "progress-info"

  defp playback_border_class(:playing), do: "border-success"
  defp playback_border_class(:paused), do: "border-warning"
  defp playback_border_class(_), do: "border-base-content/20"

  @gib Float.pow(1024.0, 3)
  @tib Float.pow(1024.0, 4)

  defp format_bytes(bytes) when bytes >= @tib do
    "#{Float.round(bytes / @tib, 1)} TiB"
  end

  defp format_bytes(bytes) do
    "#{Float.round(bytes / @gib, 1)} GiB"
  end

  defp usage_progress_class(percent) when percent >= 90, do: "progress-error"
  defp usage_progress_class(percent) when percent >= 75, do: "progress-warning"
  defp usage_progress_class(_percent), do: "progress-success"

  defp usage_text_class(percent) when percent >= 90, do: "text-error"
  defp usage_text_class(percent) when percent >= 75, do: "text-warning"
  defp usage_text_class(_percent), do: "text-success"
end
