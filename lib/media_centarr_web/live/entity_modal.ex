defmodule MediaCentarrWeb.Live.EntityModal do
  @moduledoc """
  Shared modal state, events, and rendering for any LiveView that displays
  the entity detail panel — the `ModalShell` + `DetailPanel` overlay.

  Both `LibraryLive` (when an item in the catalog grid is selected) and
  `HomeLive` (when a Continue Watching / Recently Added / Hero card is
  clicked) `use` this module so the modal is identical across pages.

  ## Host LiveView contract

  The host must:

  - Implement the `build_modal_path/2` callback returning the LiveView's
    own path with the given URL overrides applied.
  - Call `assign_modal_defaults/1` in `mount/3`.
  - Call `apply_modal_params/2` from the LiveView's `handle_params/3`.
  - Maintain these assigns (the modal renderer reads them directly):
    `:playback`, `:watch_dirs`, `:availability_map`, `:tmdb_ready`,
    `:spoiler_free`. Most are kept in sync via shared traits
    (`SpoilerFreeAware`, `CapabilitiesAware`) — see ADR-038.
  - Stamp `:resume_target` on every `:selected_entry` via
    `EntityModal.put_resume_target/1`. Done automatically by the
    `load_entry_and_expand/1` and `refresh_selected_entry/1` paths
    inside this module; LiveViews that re-snap the selected entry
    from their own in-memory store (e.g. LibraryLive's
    `entries_by_id`) call `put_resume_target/1` themselves.
  - Render `<.entity_modal modal={@modal} />` once in the template.

  ## What the macro injects

  - `handle_event/3` clauses for every modal interaction (select / close /
    play / toggle_* / delete_* / rematch / toggle_tracking).
  - The `entity_modal/1` function component (imported, not generated).

  Pure helpers (`assign_modal_defaults/1`, `apply_modal_params/2`) live
  in this module and are imported by the macro.
  """

  use Phoenix.Component

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.{Format, Library, Playback}
  alias MediaCentarr.Library.{FileEventHandler, MovieList}
  alias MediaCentarr.Playback.{ProgressBroadcaster, ResumeTarget}
  alias MediaCentarrWeb.Components.{DetailPanel, ModalShell}

  import MediaCentarrWeb.LibraryProgress, only: [completion_percentage: 1]

  @callback build_modal_path(socket :: Phoenix.LiveView.Socket.t(), overrides :: map()) ::
              String.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour MediaCentarrWeb.Live.EntityModal

      alias MediaCentarr.Playback
      alias MediaCentarrWeb.Components.DetailPanel
      alias MediaCentarrWeb.Live.EntityModal

      import MediaCentarrWeb.Live.EntityModal,
        only: [
          assign_modal_defaults: 1,
          apply_modal_params: 2,
          entity_modal: 1,
          refresh_selected_entry: 1
        ]

      # --- Modal: open / close ---

      @impl true
      def handle_event("select_entity", %{"id" => id} = params, socket) do
        autoplay = params["autoplay"] == "1" || params["autoplay"] == true
        new_id = if socket.assigns.selected_entity_id != id, do: id

        overrides = %{selected: new_id}
        overrides = if autoplay, do: Map.put(overrides, :autoplay, "1"), else: overrides

        {:noreply, push_patch(socket, to: build_modal_path(socket, overrides))}
      end

      def handle_event("close_detail", _params, socket) do
        if socket.assigns.detail_view == :info do
          {:noreply, push_patch(socket, to: build_modal_path(socket, %{view: :main}))}
        else
          {:noreply,
           socket
           |> assign(rematch_confirm: nil)
           |> push_patch(to: build_modal_path(socket, %{selected: nil, view: :main}))}
        end
      end

      def handle_event("toggle_detail_view", _params, socket) do
        new_view = if socket.assigns.detail_view == :main, do: :info, else: :main
        {:noreply, push_patch(socket, to: build_modal_path(socket, %{view: new_view}))}
      end

      def handle_event("toggle_season", %{"season" => season_str}, socket) do
        season_number = String.to_integer(season_str)
        expanded = socket.assigns[:expanded_seasons] || MapSet.new()

        expanded =
          if MapSet.member?(expanded, season_number),
            do: MapSet.delete(expanded, season_number),
            else: MapSet.put(expanded, season_number)

        {:noreply, assign(socket, expanded_seasons: expanded)}
      end

      # --- Playback ---

      def handle_event("play", %{"id" => id}, socket) do
        case Playback.play(id) do
          :ok ->
            {:noreply, socket}

          {:error, :file_not_found} ->
            {:noreply, put_flash(socket, :error, "File not available — is your media drive mounted?")}

          {:error, :already_playing} ->
            {:noreply, socket}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Couldn't start playback.")}
        end
      end

      # --- Watch progress ---

      def handle_event(
            "toggle_watched",
            %{"entity-id" => entity_id, "season" => season_str, "episode" => episode_str},
            socket
          ) do
        season_number = String.to_integer(season_str)
        episode_number = String.to_integer(episode_str)

        {fk_key, fk_id} =
          EntityModal.resolve_progress_fk(
            socket.assigns.selected_entry,
            entity_id,
            season_number,
            episode_number
          )

        Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
          EntityModal.update_watch_progress(entity_id, fk_key, fk_id)
        end)

        {:noreply, socket}
      end

      def handle_event(
            "toggle_extra_watched",
            %{"extra-id" => extra_id, "entity-id" => entity_id},
            socket
          ) do
        Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
          EntityModal.toggle_extra_watched(entity_id, extra_id)
        end)

        {:noreply, socket}
      end

      # --- Rematch ---

      def handle_event("rematch", %{"id" => entity_id}, socket) do
        if socket.assigns.rematch_confirm == entity_id do
          Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
            MediaCentarr.Review.Rematch.rematch_entity(entity_id)
          end)

          {:noreply,
           socket
           |> assign(rematch_confirm: nil)
           |> push_navigate(to: ~p"/review")}
        else
          {:noreply, assign(socket, rematch_confirm: entity_id)}
        end
      end

      # --- Tracking ---

      def handle_event("toggle_tracking", _params, socket) do
        case {socket.assigns.tracking_status, EntityModal.find_tmdb_id(socket.assigns.selected_entry)} do
          {:watching, {tmdb_id, media_type}} ->
            item = MediaCentarr.ReleaseTracking.get_item_by_tmdb(tmdb_id, media_type)
            if item, do: MediaCentarr.ReleaseTracking.ignore_item(item)
            {:noreply, assign(socket, tracking_status: :ignored)}

          {:ignored, {tmdb_id, media_type}} ->
            item = MediaCentarr.ReleaseTracking.get_item_by_tmdb(tmdb_id, media_type)
            if item, do: MediaCentarr.ReleaseTracking.watch_item(item)
            {:noreply, assign(socket, tracking_status: :watching)}

          _ ->
            {:noreply, socket}
        end
      end

      # --- Delete ---

      def handle_event("delete_file_prompt", %{"path" => file_path}, socket) do
        if EntityModal.playing?(
             socket.assigns.playback,
             socket.assigns.selected_entity_id
           ) do
          {:noreply, put_flash(socket, :error, "Stop playback before deleting")}
        else
          file_info =
            Enum.find(socket.assigns.detail_files, fn %{file: file} ->
              file.file_path == file_path
            end)

          size = if file_info, do: file_info.size

          {:noreply,
           assign(socket,
             delete_confirm: {:file, %{path: file_path, name: Path.basename(file_path), size: size}}
           )}
        end
      end

      def handle_event("delete_folder_prompt", %{"path" => folder_path, "count" => _count}, socket) do
        cond do
          EntityModal.playing?(
            socket.assigns.playback,
            socket.assigns.selected_entity_id
          ) ->
            {:noreply, put_flash(socket, :error, "Stop playback before deleting")}

          folder_path in socket.assigns.watch_dirs ->
            {:noreply, put_flash(socket, :error, "Cannot delete a watch directory")}

          true ->
            folder_files =
              socket.assigns.detail_files
              |> Enum.filter(fn %{file: file} -> Path.dirname(file.file_path) == folder_path end)
              |> Enum.map(fn %{file: file, size: size} ->
                %{name: Path.basename(file.file_path), size: size}
              end)

            total_size =
              Enum.reduce(folder_files, 0, fn %{size: size}, acc -> acc + (size || 0) end)

            {:noreply,
             assign(socket,
               delete_confirm:
                 {:folder,
                  %{
                    path: folder_path,
                    name: Path.basename(folder_path),
                    files: folder_files,
                    total_size: total_size
                  }}
             )}
        end
      end

      def handle_event("delete_all_prompt", _params, socket) do
        if EntityModal.playing?(
             socket.assigns.playback,
             socket.assigns.selected_entity_id
           ) do
          {:noreply, put_flash(socket, :error, "Stop playback before deleting")}
        else
          payload =
            MediaCentarrWeb.Components.DetailPanel.build_delete_all_payload(
              socket.assigns.detail_files,
              MapSet.new(socket.assigns.watch_dirs)
            )

          {:noreply, assign(socket, delete_confirm: {:all, payload})}
        end
      end

      def handle_event("delete_confirm", _params, socket) do
        entity_id = socket.assigns.selected_entity_id
        result = EntityModal.run_delete(socket.assigns)
        socket = assign(socket, delete_confirm: nil)

        case result do
          {:ok, _entity_ids} ->
            files = MediaCentarr.Library.list_watched_files_by_entity_id(entity_id)

            if files == [] do
              {:noreply, push_patch(socket, to: build_modal_path(socket, %{selected: nil, view: :main}))}
            else
              detail_files = EntityModal.load_entity_files(entity_id)
              {:noreply, assign(socket, detail_files: detail_files)}
            end

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Delete failed: #{reason}")}
        end
      end

      def handle_event("delete_cancel", _params, socket) do
        {:noreply, assign(socket, delete_confirm: nil)}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Public helpers (called from the host LiveView)
  # ---------------------------------------------------------------------------

  @doc """
  Initial assigns for the modal slice. Call from `mount/3`.
  """
  @spec assign_modal_defaults(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def assign_modal_defaults(socket) do
    Phoenix.Component.assign(socket,
      selected_entity_id: nil,
      selected_entry: nil,
      detail_presentation: nil,
      detail_view: :main,
      detail_files: [],
      expanded_seasons: MapSet.new(),
      rematch_confirm: nil,
      delete_confirm: nil,
      tracking_status: nil
    )
  end

  @doc """
  Reads the modal-related URL params (`selected`, `view`, `autoplay`),
  loads the selected entry on demand, and assigns the modal slice on
  the socket. Returns the updated socket.

  - `selected` UUID → loads via `Library.load_modal_entry/1`. If the
    entity doesn't exist or has no present file, the modal stays closed
    (selected_entry: nil).
  - `view=info` → opens the file/info pane inside the modal.
  - `autoplay=1` → fires `Playback.play/1` once for the loaded entity
    (used by Continue Watching cards and the Hero "Play" button).

  Idempotent: re-applying the same params is a no-op.
  """
  @spec apply_modal_params(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def apply_modal_params(socket, params) do
    selected_id = params["selected"]
    detail_view = parse_view(params["view"])
    autoplay? = params["autoplay"] == "1"

    selection_changed = selected_id != socket.assigns.selected_entity_id
    entity_switched = selection_changed && socket.assigns.selected_entity_id != nil
    detail_view = if entity_switched, do: :main, else: detail_view

    {selected_entry, expanded_seasons} =
      cond do
        selected_id == nil ->
          {nil, MapSet.new()}

        selection_changed ->
          load_entry_and_expand(selected_id)

        true ->
          {socket.assigns.selected_entry, socket.assigns.expanded_seasons}
      end

    detail_files =
      if selection_changed do
        if detail_view == :info && selected_id, do: load_entity_files(selected_id), else: []
      else
        if detail_view == :info && socket.assigns.detail_files == [] && selected_id do
          load_entity_files(selected_id)
        else
          socket.assigns.detail_files
        end
      end

    tracking_status =
      if selection_changed && selected_entry,
        do: load_tracking_status(selected_entry),
        else: socket.assigns.tracking_status

    if autoplay? && selected_entry do
      _ = Playback.play(selected_id)
    end

    Phoenix.Component.assign(socket,
      selected_entity_id: selected_id,
      selected_entry: selected_entry,
      detail_presentation: if(selected_id, do: :modal),
      detail_view: detail_view,
      detail_files: detail_files,
      expanded_seasons: expanded_seasons,
      tracking_status: tracking_status
    )
  end

  @doc """
  Reload the currently-selected entry from the database. Call from the
  host LiveView's PubSub handlers when the selected entity may have
  changed (e.g. on `:entities_changed` containing `selected_entity_id`).
  """
  @spec refresh_selected_entry(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def refresh_selected_entry(%{assigns: %{selected_entity_id: nil}} = socket), do: socket

  def refresh_selected_entry(socket) do
    case Library.load_modal_entry(socket.assigns.selected_entity_id) do
      {:ok, entry} ->
        Phoenix.Component.assign(socket, :selected_entry, put_resume_target(entry))

      :not_found ->
        Phoenix.Component.assign(socket,
          selected_entity_id: nil,
          selected_entry: nil,
          detail_presentation: nil
        )
    end
  end

  # ---------------------------------------------------------------------------
  # Function component
  # ---------------------------------------------------------------------------

  @doc """
  Renders the entity detail modal. Reads everything it needs from the
  host LiveView's modal-related assigns plus a few shared assigns
  (`@playback`, `@availability_map`, `@tmdb_ready`, `@spoiler_free`).

  The resume target is read directly from the loaded entry — every place
  that assigns `:selected_entry` is responsible for stamping it via
  `put_resume_target/1`. This keeps the modal decoupled from how each
  host LiveView tracks resume state for the rest of its UI.
  """
  attr :selected_entry, :any, required: true
  attr :selected_entity_id, :any, required: true
  attr :detail_presentation, :any, required: true
  attr :detail_view, :atom, required: true
  attr :detail_files, :list, required: true
  attr :expanded_seasons, :any, required: true
  attr :rematch_confirm, :any, required: true
  attr :delete_confirm, :any, required: true
  attr :tracking_status, :atom, required: true
  attr :availability_map, :map, default: %{}
  attr :tmdb_ready, :boolean, default: true
  attr :spoiler_free, :boolean, default: false

  def entity_modal(assigns) do
    ~H"""
    <ModalShell.modal_shell
      open={@selected_entry != nil && @detail_presentation == :modal}
      entity={(@selected_entry && @selected_entry.entity) || nil}
      progress={@selected_entry && @selected_entry.progress}
      resume={@selected_entry && Map.get(@selected_entry, :resume_target)}
      progress_records={(@selected_entry && @selected_entry.progress_records) || []}
      expanded_seasons={@expanded_seasons}
      rematch_confirm={@rematch_confirm == @selected_entity_id}
      detail_view={@detail_view}
      detail_files={@detail_files}
      delete_confirm={@delete_confirm}
      spoiler_free={@spoiler_free}
      tracking_status={@tracking_status}
      available={
        @selected_entry == nil ||
          Map.get(@availability_map, @selected_entry.entity.id, true)
      }
      tmdb_ready={@tmdb_ready}
      on_play="play"
      on_close="close_detail"
    />
    """
  end

  # ---------------------------------------------------------------------------
  # Internals shared with the macro (callable from injected handle_event)
  # ---------------------------------------------------------------------------

  @doc false
  def playing?(playback, entity_id), do: Map.has_key?(playback, entity_id)

  @doc false
  @spec resolve_progress_fk(map() | nil, String.t(), non_neg_integer(), non_neg_integer()) ::
          {:movie_id, String.t() | nil} | {:episode_id, String.t() | nil}
  def resolve_progress_fk(_entry, entity_id, 0, _ordinal) do
    # The DetailPanel emits season=0 + episode=ordinal for movies and
    # extras. For a standalone movie selection, the entity_id is the
    # movie row. For movie-series children, the play row carries the
    # actual movie id, so the entity_id we receive is already correct.
    {:movie_id, entity_id}
  end

  def resolve_progress_fk(%{entity: %{type: :movie_series, movies: movies}}, _entity_id, 0, ordinal)
      when is_list(movies) do
    available = MovieList.list_available(%{movies: movies})

    movie_id =
      case Enum.find(available, fn {ord, _id, _url} -> ord == ordinal end) do
        {_ord, id, _url} -> id
        nil -> nil
      end

    {:movie_id, movie_id}
  end

  def resolve_progress_fk(
        %{entity: %{type: :tv_series, seasons: seasons}},
        _entity_id,
        season_number,
        episode_number
      )
      when is_list(seasons) do
    episode_id =
      with %{episodes: episodes} when is_list(episodes) <-
             Enum.find(seasons, &(&1.season_number == season_number)),
           %{id: id} <- Enum.find(episodes, &(&1.episode_number == episode_number)) do
        id
      else
        _ -> nil
      end

    {:episode_id, episode_id}
  end

  def resolve_progress_fk(_entry, _entity_id, _season, _episode), do: {:episode_id, nil}

  @doc false
  def update_watch_progress(entity_id, fk_key, fk_id) do
    progress = load_progress_by_fk(fk_key, fk_id)
    changed_record = apply_progress_transition(progress, fk_key, fk_id)
    ProgressBroadcaster.broadcast(entity_id, changed_record)
  end

  defp load_progress_by_fk(_fk_key, nil), do: nil

  defp load_progress_by_fk(fk_key, fk_id) do
    case Library.fetch_watch_progress_by_fk(fk_key, fk_id) do
      {:ok, record} -> record
      _ -> nil
    end
  end

  defp apply_progress_transition(%{completed: true} = progress, _fk_key, _fk_id) do
    Log.info(
      :library,
      "toggled incomplete — was completed, position #{Format.format_seconds(progress.position_seconds)} of #{Format.format_seconds(progress.duration_seconds)}"
    )

    Library.mark_watch_incomplete!(progress)
  end

  defp apply_progress_transition(%{completed: false} = progress, _fk_key, _fk_id) do
    Log.info(:library, fn ->
      "toggled completed — was #{completion_percentage(progress)} through (#{Format.format_seconds(progress.position_seconds)} of #{Format.format_seconds(progress.duration_seconds)})"
    end)

    Library.mark_watch_completed!(progress)
  end

  defp apply_progress_transition(nil, fk_key, fk_id) when not is_nil(fk_id) do
    Log.info(:library, "toggled completed — no prior progress, created fresh record")

    params = %{fk_key => fk_id, position_seconds: 0.0, duration_seconds: 0.0}
    {:ok, record} = create_progress_by_fk(fk_key, params)
    Library.mark_watch_completed!(record)
  end

  defp apply_progress_transition(nil, _fk_key, nil), do: nil

  defp create_progress_by_fk(:movie_id, params),
    do: Library.find_or_create_watch_progress_for_movie(params)

  defp create_progress_by_fk(:episode_id, params),
    do: Library.find_or_create_watch_progress_for_episode(params)

  @doc false
  def toggle_extra_watched(entity_id, extra_id) do
    progress = Library.get_extra_progress_by_extra(extra_id)

    case progress do
      %{completed: true} ->
        Log.info(:library, "extra toggled incomplete")
        Library.mark_extra_incomplete!(progress)

      %{completed: false} ->
        Log.info(:library, "extra toggled completed")
        Library.mark_extra_completed!(progress)

      nil ->
        Log.info(:library, "extra toggled completed — no prior progress, created fresh record")

        {:ok, record} =
          Library.find_or_create_extra_progress(%{
            extra_id: extra_id,
            entity_id: entity_id,
            position_seconds: 0.0,
            duration_seconds: 0.0
          })

        Library.mark_extra_completed!(record)
    end

    ProgressBroadcaster.broadcast_extra(entity_id, extra_id)
  end

  @doc false
  def find_tmdb_id(%{entity: %{type: :tv_series} = entity}) do
    case Enum.find(entity.external_ids, &(&1.source == "tmdb")) do
      nil -> nil
      ext_id -> {String.to_integer(ext_id.external_id), :tv_series}
    end
  end

  def find_tmdb_id(%{entity: %{type: :movie_series} = entity}) do
    case Enum.find(entity.external_ids, &(&1.source == "tmdb_collection")) do
      nil -> nil
      ext_id -> {String.to_integer(ext_id.external_id), :movie}
    end
  end

  def find_tmdb_id(_), do: nil

  @doc false
  def load_entity_files(entity_id) do
    Enum.map(Library.list_watched_files_by_entity_id(entity_id), fn file ->
      size =
        case File.stat(file.file_path) do
          {:ok, %{size: size}} -> size
          _ -> nil
        end

      %{file: file, size: size}
    end)
  end

  @doc false
  def run_delete(%{delete_confirm: delete_confirm, detail_files: detail_files}) do
    case delete_confirm do
      {:file, %{path: file_path}} ->
        FileEventHandler.delete_file(file_path)

      {:folder, %{path: folder_path}} ->
        file_paths =
          detail_files
          |> Enum.map(& &1.file.file_path)
          |> Enum.filter(&String.starts_with?(&1, folder_path <> "/"))

        FileEventHandler.delete_folder(folder_path, file_paths)

      {:all, %{file_groups: file_groups}} ->
        Enum.each(file_groups, fn group ->
          if group.is_watch_dir do
            Enum.each(group.files, fn %{path: path} -> FileEventHandler.delete_file(path) end)
          else
            file_paths = Enum.map(group.files, & &1.path)
            FileEventHandler.delete_folder(group.dir, file_paths)
          end
        end)

        {:ok, []}

      nil ->
        {:ok, []}
    end
  end

  # --- Private helpers ---

  defp parse_view("info"), do: :info
  defp parse_view(_), do: :main

  defp load_entry_and_expand(id) do
    case Library.load_modal_entry(id) do
      {:ok, entry} ->
        expanded = DetailPanel.auto_expand_season(entry.entity, entry.progress)
        {put_resume_target(entry), expanded}

      :not_found ->
        {nil, MapSet.new()}
    end
  end

  @doc """
  Stamps `:resume_target` on a loaded entry. Every host LiveView's path
  to `:selected_entry` must run through this so the modal sees the
  current hint without each host having to maintain its own
  resume-target map (per ADR-038).
  """
  @spec put_resume_target(map()) :: map()
  def put_resume_target(entry) do
    Map.put(entry, :resume_target, ResumeTarget.compute(entry.entity, entry.progress_records))
  end

  defp load_tracking_status(entry) do
    case find_tmdb_id(entry) do
      {tmdb_id, media_type} ->
        MediaCentarr.ReleaseTracking.tracking_status({tmdb_id, media_type})

      nil ->
        nil
    end
  end
end
