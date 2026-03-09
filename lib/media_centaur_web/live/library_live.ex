defmodule MediaCentaurWeb.LibraryLive do
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.{LibraryBrowser, Playback.Resume, Playback.ResumeTarget}

  alias MediaCentaurWeb.Components.ModalShell

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "library:updates")
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "playback:events")
    end

    {:ok,
     assign(socket,
       entries: [],
       continue_watching: [],
       resume_targets: %{},
       playback: %{state: :idle, now_playing: nil},
       selected_entity_id: nil,
       reload_timer: nil,
       pending_entity_ids: MapSet.new()
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    selected_id = params["selected"]

    socket =
      if connected?(socket) && socket.assigns.entries == [] do
        load_library(socket)
      else
        socket
      end

    {:noreply, assign(socket, selected_entity_id: selected_id)}
  end

  # --- Events ---

  @impl true
  def handle_event("select_cw_entity", %{"id" => id}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/library?#{if id, do: %{selected: id}, else: %{}}"
     )}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/library")}
  end

  def handle_event("play", %{"id" => id}, socket) do
    LibraryBrowser.play(id)
    {:noreply, socket}
  end

  def handle_event("toggle_season", %{"season" => season_str}, socket) do
    season_number = String.to_integer(season_str)
    expanded = socket.assigns[:expanded_seasons] || MapSet.new()

    expanded =
      if MapSet.member?(expanded, season_number) do
        MapSet.delete(expanded, season_number)
      else
        MapSet.put(expanded, season_number)
      end

    {:noreply, assign(socket, expanded_seasons: expanded)}
  end

  def handle_event("toggle_episode_detail", %{"id" => id}, socket) do
    expanded = socket.assigns[:expanded_episodes] || MapSet.new()

    expanded =
      if MapSet.member?(expanded, id) do
        MapSet.delete(expanded, id)
      else
        MapSet.put(expanded, id)
      end

    {:noreply, assign(socket, expanded_episodes: expanded)}
  end

  # --- PubSub Handlers ---

  @impl true
  def handle_info({:entities_changed, entity_ids}, socket) do
    if socket.assigns[:reload_timer] do
      Process.cancel_timer(socket.assigns.reload_timer)
    end

    pending = MapSet.union(socket.assigns.pending_entity_ids, MapSet.new(entity_ids))
    timer = Process.send_after(self(), :reload_entities, 500)
    {:noreply, assign(socket, reload_timer: timer, pending_entity_ids: pending)}
  end

  def handle_info(:reload_entities, socket) do
    changed_ids = socket.assigns.pending_entity_ids
    {updated_entries, gone_ids} = LibraryBrowser.fetch_entries_by_ids(MapSet.to_list(changed_ids))
    updated_map = Map.new(updated_entries, fn entry -> {entry.entity.id, entry} end)

    entries =
      socket.assigns.entries
      |> Enum.reject(fn entry -> MapSet.member?(gone_ids, entry.entity.id) end)
      |> Enum.map(fn entry -> Map.get(updated_map, entry.entity.id, entry) end)

    existing_ids = MapSet.new(entries, fn entry -> entry.entity.id end)

    new_entries =
      Enum.reject(updated_entries, fn entry -> MapSet.member?(existing_ids, entry.entity.id) end)

    entries = Enum.sort_by(entries ++ new_entries, fn entry -> entry.entity.name || "" end)

    selection_deleted =
      socket.assigns.selected_entity_id != nil &&
        MapSet.member?(gone_ids, socket.assigns.selected_entity_id)

    socket =
      socket
      |> assign(entries: entries, reload_timer: nil, pending_entity_ids: MapSet.new())
      |> recompute_continue_watching()

    if selection_deleted do
      {:noreply, push_patch(socket, to: ~p"/library")}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {:entity_progress_updated, entity_id, summary, resume_target, _child_targets_delta,
         _last_activity_at},
        socket
      ) do
    entries = update_entry_progress(socket.assigns.entries, entity_id, summary)
    resume_targets = Map.put(socket.assigns.resume_targets, entity_id, resume_target)

    {:noreply,
     socket
     |> assign(entries: entries, resume_targets: resume_targets)
     |> recompute_continue_watching()}
  end

  def handle_info({:playback_state_changed, new_state, now_playing}, socket) do
    {:noreply, assign(socket, playback: %{state: new_state, now_playing: now_playing})}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    selected_entry = find_entry(assigns.entries, assigns.selected_entity_id)
    assigns = assign(assigns, :selected_entry, selected_entry)

    ~H"""
    <Layouts.app flash={@flash} current_path="/library" full_width>
      <div class="space-y-6">
        <%!-- Continue Watching zone --%>
        <section id="continue-watching">
          <h2 class="text-lg font-semibold mb-3">Continue Watching</h2>
          <.cw_empty :if={@continue_watching == []} />
          <div
            :if={@continue_watching != []}
            class="grid grid-cols-[repeat(auto-fill,minmax(480px,1fr))] gap-4"
          >
            <.cw_card
              :for={entry <- @continue_watching}
              entry={entry}
              resume={Map.get(@resume_targets, entry.entity.id)}
              playing={playing_entity_id(@playback) == entry.entity.id}
            />
          </div>
        </section>

        <%!-- Edge hint divider --%>
        <div class="divider text-base-content/30 text-sm">
          ↓ Library · {length(@entries)} titles
        </div>

        <%!-- Library Browse zone (placeholder for Phase 4) --%>
        <section id="browse">
          <h2 class="text-lg font-semibold mb-2">Browse</h2>
          <p class="text-base-content/50 text-sm">Coming in Phase 4.</p>
        </section>
      </div>

      <%!-- Detail modal (CW zone uses modal presentation) --%>
      <ModalShell.modal_shell
        :if={@selected_entry}
        entity={@selected_entry.entity}
        progress={@selected_entry.progress}
        resume={Map.get(@resume_targets, @selected_entry.entity.id)}
        progress_records={@selected_entry.progress_records}
        watch_dirs={MediaCentaur.Config.get(:watch_dirs) || []}
        expanded_seasons={assigns[:expanded_seasons]}
        expanded_episodes={assigns[:expanded_episodes] || MapSet.new()}
        on_play="play"
        on_close="close_detail"
      />
    </Layouts.app>
    """
  end

  # --- Continue Watching Card ---

  defp cw_card(assigns) do
    entity = assigns.entry.entity
    backdrop = image_url(entity, "backdrop")
    background = backdrop || image_url(entity, "poster")
    logo = image_url(entity, "logo")
    progress_fraction = compute_progress_fraction(assigns.entry.progress)
    resume_label = format_resume_label(assigns.resume, entity)

    assigns =
      assign(assigns,
        background: background,
        logo: logo,
        progress_fraction: progress_fraction,
        resume_label: resume_label
      )

    ~H"""
    <div
      phx-click="select_cw_entity"
      phx-value-id={@entry.entity.id}
      class={[
        "relative rounded-lg overflow-hidden cursor-pointer group",
        "hover:scale-[1.02] hover:shadow-xl transition-transform",
        @playing && "ring-2 ring-primary"
      ]}
    >
      <%!-- Backdrop image --%>
      <div class="aspect-video glass-inset relative">
        <img
          :if={@background}
          src={@background}
          class="w-full h-full object-cover"
          loading="lazy"
        />
        <div :if={!@background} class="w-full h-full flex items-center justify-center">
          <.icon name="hero-film" class="size-12 text-base-content/20" />
        </div>

        <%!-- Bottom gradient --%>
        <div class="absolute inset-0 bg-gradient-to-t from-black/88 via-black/40 via-40% to-transparent" />

        <%!-- Logo or title (bottom-left) --%>
        <div class="absolute bottom-10 left-4 right-4">
          <img
            :if={@logo}
            src={@logo}
            class="max-h-12 max-w-[60%] object-contain drop-shadow-[0_2px_12px_rgba(0,0,0,0.7)]"
          />
          <h3
            :if={!@logo}
            class="text-lg font-bold text-white drop-shadow-[0_2px_8px_rgba(0,0,0,0.7)]"
          >
            {@entry.entity.name}
          </h3>
        </div>

        <%!-- Resume info (bottom-left, below logo) --%>
        <div class="absolute bottom-4 left-4 right-4 flex items-center justify-between">
          <span :if={@resume_label} class="text-sm text-primary font-medium drop-shadow">
            {@resume_label}
          </span>
        </div>

        <%!-- Now-playing pulse --%>
        <div
          :if={@playing}
          class="absolute top-3 right-3 size-3 rounded-full bg-primary animate-pulse"
        />

        <%!-- Progress bar at bottom edge --%>
        <div
          :if={@progress_fraction > 0}
          class="absolute bottom-0 left-0 right-0 h-1 bg-base-content/20"
        >
          <div class="h-full bg-primary" style={"width: #{@progress_fraction}%"} />
        </div>
      </div>
    </div>
    """
  end

  defp cw_empty(assigns) do
    ~H"""
    <div class="text-base-content/50 py-6 text-center text-sm">
      Nothing in progress. Browse the library below to start watching.
    </div>
    """
  end

  # --- Data Loading ---

  defp load_library(socket) do
    entries = LibraryBrowser.fetch_entities()
    resume_targets = compute_resume_targets(entries)

    socket
    |> assign(
      entries: entries,
      resume_targets: resume_targets,
      playback: MediaCentaur.Playback.Manager.current_state()
    )
    |> recompute_continue_watching()
  end

  defp recompute_continue_watching(socket) do
    continue_watching =
      socket.assigns.entries
      |> Enum.filter(fn entry ->
        case Resume.resolve(entry.entity, entry.progress_records) do
          {:resume, _, _} -> true
          {:play_next, _, _} -> true
          _ -> false
        end
      end)

    assign(socket, continue_watching: continue_watching)
  end

  defp compute_resume_targets(entries) do
    Map.new(entries, fn entry ->
      {entry.entity.id, ResumeTarget.compute(entry.entity, entry.progress_records)}
    end)
  end

  # --- Helpers ---

  defp find_entry(_entries, nil), do: nil

  defp find_entry(entries, id) do
    Enum.find(entries, fn entry -> entry.entity.id == id end)
  end

  defp update_entry_progress(entries, entity_id, summary) do
    Enum.map(entries, fn
      %{entity: %{id: ^entity_id}} = entry ->
        %{entry | progress: summary}

      entry ->
        entry
    end)
  end

  defp playing_entity_id(%{now_playing: %{entity_id: id}}), do: id
  defp playing_entity_id(_), do: nil

  defp image_url(entity, role) do
    image = Enum.find(entity.images || [], &(&1.role == role))

    cond do
      image && image.content_url -> "/media-images/#{image.content_url}"
      image && image.url -> image.url
      true -> nil
    end
  end

  defp compute_progress_fraction(nil), do: 0

  defp compute_progress_fraction(%{
         episode_position_seconds: position,
         episode_duration_seconds: duration
       })
       when duration > 0 do
    Float.round(position / duration * 100, 1)
  end

  defp compute_progress_fraction(_), do: 0

  defp format_resume_label(nil, _entity), do: nil

  defp format_resume_label(%{"action" => "resume"} = resume, _entity) do
    case resume do
      %{"seasonNumber" => season, "episodeNumber" => episode, "positionSeconds" => position} ->
        "Resume S#{season} E#{episode} at #{format_seconds(position)}"

      %{"positionSeconds" => position} ->
        "Resume at #{format_seconds(position)}"

      _ ->
        "Resume"
    end
  end

  defp format_resume_label(%{"action" => "begin"} = resume, _entity) do
    case resume do
      %{"seasonNumber" => season, "episodeNumber" => episode} ->
        "Play S#{season} E#{episode}"

      _ ->
        "Play"
    end
  end

  defp format_resume_label(_resume, _entity), do: nil
end
