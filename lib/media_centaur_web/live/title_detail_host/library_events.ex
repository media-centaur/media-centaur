defmodule MediaCentaurWeb.Live.TitleDetailHost.LibraryEvents do
  @moduledoc """
  The events the library sections of the title detail raise — the ones
  that need the library half: playing, marking watched, the season and
  disclosure toggles, the Cast view's filter and paging, the Manage
  sheet's acts (rematch, artwork refresh, the track-override reset, the
  inline-confirm deletes) and the gap row's missing-episode plan. The
  host dispatches `events/0` here once it knows a library half is open;
  every handler reads the open `Title.Detail` and writes the
  `Title.ModalState`.

  Deleting an entity's files is `File.rm` / `File.rm_rf` plus a per-file
  DB cleanup cascade — seconds of blocking work for a large entity or a
  network mount — so it runs as an owned async (`{:delete, subject}`,
  ADR-049): `deleting` marks the target so the matching button reads
  "Deleting…" and every delete button disables, and the result lands
  through `apply_delete_result/3`. Each delete button is its own two-step
  gesture: the first click arms `delete_confirm` with the target, the
  second on the same target executes, a different target re-arms. No
  delete runs while the entity is playing.
  """

  import Phoenix.Component, only: [assign: 3, update: 3]
  import Phoenix.LiveView, only: [push_navigate: 2, push_patch: 2, put_flash: 3, start_async: 3]

  alias MediaCentaur.Format
  alias MediaCentaur.Library
  alias MediaCentaur.Library.Deletion
  alias MediaCentaur.Playback
  alias MediaCentaur.Playback.ProgressBroadcaster
  alias MediaCentaurWeb.Components.Detail.CastSelection
  alias MediaCentaurWeb.Components.Detail.ManagePanel
  alias MediaCentaurWeb.Components.Title.Detail, as: TitleDetail
  alias MediaCentaurWeb.LibraryProgress
  alias MediaCentaurWeb.Live.TitleDetailHost.Acquisition
  alias MediaCentaurWeb.Live.TitleDetailHost.LibraryHalf

  require MediaCentaur.Log, as: Log

  @type socket :: Phoenix.LiveView.Socket.t()

  @events ~w(play toggle_watched toggle_extra_watched toggle_season toggle_item_details
             toggle_all_episode_details toggle_file_group filter_cast show_more_cast rematch
             refresh_artwork reset_track_override delete_file_prompt delete_folder_prompt
             delete_all_prompt delete_cancel download_missing_episode)

  @doc "The event names this module handles."
  @spec events() :: [String.t()]
  def events, do: @events

  @doc "Plays a playable id in place (UIDR-027); what stands in the way is flashed."
  @spec play(socket(), Ecto.UUID.t()) :: socket()
  def play(socket, id) do
    case Playback.play(id) do
      :ok ->
        socket

      {:error, :file_not_found} ->
        put_flash(socket, :error, "File not available — is your media drive mounted?")

      {:error, :already_playing} ->
        socket

      {:error, _reason} ->
        put_flash(socket, :error, "Couldn't start playback.")
    end
  end

  @doc "Handles one library-section event for the open detail; the host has checked a library half is open."
  @spec handle(String.t(), map(), socket()) :: socket()
  def handle("play", %{"id" => id}, socket), do: play(socket, id)

  def handle(
        "toggle_watched",
        %{"entity-id" => entity_id, "container-type" => container_type, "container-id" => container_id},
        socket
      ) do
    toggle_watch_progress(entity_id, parse_container_type(container_type), container_id)
    socket
  end

  def handle("toggle_extra_watched", %{"extra-id" => extra_id, "entity-id" => entity_id}, socket) do
    toggle_extra_watched(entity_id, extra_id)
    socket
  end

  def handle("toggle_season", %{"season" => season}, socket) do
    season_number = String.to_integer(season)
    update_state(socket, :expanded_seasons, &flip(&1, season_number))
  end

  def handle("toggle_item_details", %{"item-id" => item_id}, socket),
    do: update_state(socket, :expanded_item_details, &flip(&1, item_id))

  def handle("toggle_all_episode_details", _params, socket),
    do: update_state(socket, :all_episode_details_open, &(!&1))

  # `expanded_file_groups` starts as nil — "the automatic default"
  # (`ManagePanel.effective_expanded_dirs/2`: everything open for small
  # inventories, everything closed for large ones). The first toggle
  # materialises that default into a concrete set and flips the one dir.
  def handle("toggle_file_group", %{"dir" => dir}, socket) do
    file_groups = ManagePanel.build_file_groups(files(socket), media_dirs())

    expanded =
      ManagePanel.effective_expanded_dirs(file_groups, socket.assigns.modal_state.expanded_file_groups)

    update_state(socket, :expanded_file_groups, fn _current -> flip(expanded, dir) end)
  end

  # Plain state, no URL round-trip: a half-typed actor name, or how far
  # someone has paged, is not a place worth restoring them to.
  def handle("filter_cast", %{"cast_filter" => query}, socket),
    do: update_state(socket, :cast_filter, fn _current -> query end)

  def handle("show_more_cast", _params, socket),
    do:
      update_state(socket, :cast_limit, &((&1 || CastSelection.page_size()) + CastSelection.page_size()))

  # Just a PubSub broadcast — instant; the rematch work runs in the
  # command handler. Synchronous (ADR-049).
  def handle("rematch", %{"id" => entity_id}, socket) do
    if socket.assigns.modal_state.rematch_confirm do
      MediaCentaur.Review.Rematch.rematch_entity(entity_id)
      socket |> update_state(:rematch_confirm, fn _armed -> false end) |> push_navigate(to: "/review")
    else
      update_state(socket, :rematch_confirm, fn _armed -> true end)
    end
  end

  def handle("refresh_artwork", %{"id" => entity_id}, socket) do
    type = socket.assigns.title_detail.library.entry.entity.type
    result = MediaCentaur.Pipeline.ImageRefresh.enqueue_refresh(entity_id, type)
    {level, message} = refresh_artwork_flash(result)
    put_flash(socket, level, message)
  end

  # Clears the per-entity track override and drops the *Remembered
  # tracks* badge in place. Only a movie or a series owns one.
  def handle("reset_track_override", _params, socket) do
    case socket.assigns.title_detail.library.entry.entity do
      %{id: id, type: type} when type in [:movie, :tv_series] and is_binary(id) ->
        Library.MediaTrackOverrides.clear(type, id)
        update_half(socket, &LibraryHalf.put_track_override(&1, nil))

      _other ->
        socket
    end
  end

  def handle("delete_file_prompt", %{"path" => file_path}, socket),
    do: delete_gesture(socket, {:file, file_path})

  def handle("delete_folder_prompt", %{"path" => folder_path}, socket) do
    if folder_path in media_dirs() do
      put_flash(socket, :error, "Cannot delete a media directory")
    else
      delete_gesture(socket, {:folder, folder_path})
    end
  end

  def handle("delete_all_prompt", _params, socket), do: delete_gesture(socket, :all)

  def handle("delete_cancel", _params, socket),
    do: update_state(socket, :delete_confirm, fn _armed -> nil end)

  def handle("download_missing_episode", %{"season" => season, "episode" => episode}, socket),
    do:
      Acquisition.download_missing_episode(
        socket,
        {String.to_integer(season), String.to_integer(episode)}
      )

  def handle(_event, _params, socket), do: socket

  # --- Watched toggles ---

  # The container-type atom a row's `phx-value-container-type` names.
  # Explicit clauses — never `String.to_atom/1` on client input.
  defp parse_container_type("movie"), do: :movie
  defp parse_container_type("episode"), do: :episode
  defp parse_container_type("video_object"), do: :video_object

  defp toggle_watch_progress(entity_id, container_type, container_id) do
    progress = load_progress(container_type, container_id)
    changed_record = apply_progress_transition(progress, container_type, container_id)
    ProgressBroadcaster.broadcast(entity_id, changed_record)
  end

  defp load_progress(_container_type, nil), do: nil

  defp load_progress(container_type, container_id) do
    case Library.ProgressRecords.fetch_for_container(container_type, container_id) do
      {:ok, record} -> record
      _ -> nil
    end
  end

  defp apply_progress_transition(%{completed: true} = progress, _container_type, _container_id) do
    Log.info(
      :library,
      "toggled incomplete — was completed, position #{Format.format_seconds(progress.position_seconds)} of #{Format.format_seconds(progress.duration_seconds)}"
    )

    Library.ProgressRecords.mark_incomplete!(progress)
  end

  defp apply_progress_transition(%{completed: false} = progress, _container_type, _container_id) do
    Log.info(:library, fn ->
      "toggled completed — was #{LibraryProgress.completion_percentage(progress)} through (#{Format.format_seconds(progress.position_seconds)} of #{Format.format_seconds(progress.duration_seconds)})"
    end)

    Library.ProgressRecords.mark_completed!(progress)
  end

  defp apply_progress_transition(nil, container_type, container_id) when not is_nil(container_id) do
    Log.info(:library, "toggled completed — no prior progress, created fresh record")

    {:ok, record} =
      Library.ProgressRecords.find_or_create_for_container(container_type, container_id, %{
        position_seconds: 0.0,
        duration_seconds: 0.0
      })

    Library.ProgressRecords.mark_completed!(record)
  end

  defp apply_progress_transition(nil, _container_type, nil), do: nil

  defp toggle_extra_watched(entity_id, extra_id) do
    case Library.ProgressRecords.fetch_for_extra(extra_id) do
      {:ok, %{completed: true} = progress} ->
        Log.info(:library, "extra toggled incomplete")
        Library.ProgressRecords.mark_incomplete!(progress)

      {:ok, progress} ->
        Log.info(:library, "extra toggled completed")
        Library.ProgressRecords.mark_completed!(progress)

      {:error, :not_found} ->
        Log.info(:library, "extra toggled completed — no prior progress, created fresh record")

        {:ok, record} =
          Library.ProgressRecords.find_or_create_for_extra(%{
            extra_id: extra_id,
            entity_id: entity_id,
            position_seconds: 0.0,
            duration_seconds: 0.0
          })

        Library.ProgressRecords.mark_completed!(record)
    end

    ProgressBroadcaster.broadcast_extra(entity_id, extra_id)
  end

  # --- Artwork ---

  @doc "Maps a `Pipeline.ImageRefresh.enqueue_refresh/2` result to a `{level, message}` flash."
  def refresh_artwork_flash({:ok, _job}), do: {:info, "Refreshing artwork from TMDB…"}
  def refresh_artwork_flash({:error, :no_tmdb_id}), do: {:error, "No TMDB match — Rematch first."}
  def refresh_artwork_flash({:error, _reason}), do: {:error, "Couldn't start artwork refresh."}

  # --- Delete ---

  defp delete_gesture(socket, target) do
    cond do
      playing?(socket) -> put_flash(socket, :error, "Stop playback before deleting")
      socket.assigns.modal_state.delete_confirm == target -> run_pending_delete(socket)
      true -> update_state(socket, :delete_confirm, fn _armed -> target end)
    end
  end

  defp playing?(socket) do
    Map.has_key?(socket.assigns.title_playback, LibraryHalf.container_id(socket.assigns.title_detail))
  end

  # Clears `delete_confirm`, marks `deleting` with the target, and hands
  # the deletion to `start_async/3`; the result lands in
  # `apply_delete_result/3`.
  defp run_pending_delete(socket) do
    detail = socket.assigns.title_detail
    target = socket.assigns.modal_state.delete_confirm
    args = %{delete_confirm: target, detail_files: files(socket), media_dirs: media_dirs()}

    socket
    |> update(:modal_state, &%{&1 | delete_confirm: nil, deleting: target})
    |> start_async({:delete, LibraryHalf.subject(detail)}, fn -> run_delete(args) end)
  end

  @doc false
  def run_delete(%{delete_confirm: delete_confirm, detail_files: detail_files, media_dirs: media_dirs}) do
    case delete_confirm do
      {:file, file_path} ->
        Deletion.delete_file(file_path)

      {:folder, folder_path} ->
        file_paths =
          detail_files
          |> Enum.map(& &1.file.file_path)
          |> Enum.filter(&String.starts_with?(&1, folder_path <> "/"))

        # Belt-and-suspenders: `folder_path` is already derived from this
        # entity's own files (never user-typed), but this confirms nothing
        # ELSE already in the library also lives under it before the
        # recursive `rm -rf` — see `MediaCentaur.DeleteTargets`.
        if MediaCentaur.DeleteTargets.safe_to_delete_folder?(folder_path, file_paths) do
          Deletion.delete_folder(folder_path, file_paths)
        else
          {:error, "folder also contains other library content"}
        end

      :all ->
        payload = ManagePanel.build_delete_all_payload(detail_files, MapSet.new(media_dirs))

        Enum.each(payload.file_groups, fn group ->
          file_paths = Enum.map(group.files, & &1.path)

          if !group.is_media_dir and
               MediaCentaur.DeleteTargets.safe_to_delete_folder?(group.dir, file_paths) do
            Deletion.delete_folder(group.dir, file_paths)
          else
            # A media directory root, or a folder that also holds other
            # already-imported content, can't be `rm -rf`'d wholesale — fall
            # back to deleting just this entity's own files in it.
            Deletion.delete_files(file_paths)
          end
        end)

        {:ok, []}

      nil ->
        {:ok, []}
    end
  end

  @doc """
  Lands the async delete: clears `deleting`, then closes the modal when
  the entity has no files left on disk, or reloads the file list when
  some remain. A failure is flashed. A result for a subject the person
  has moved on from is dropped.
  """
  @spec apply_delete_result(socket(), LibraryHalf.subject(), {:ok, term()} | {:error, term()}) ::
          socket()
  def apply_delete_result(socket, subject, result) do
    case socket.assigns.title_detail do
      %TitleDetail{library: %{}} = detail ->
        if LibraryHalf.subject(detail) == subject,
          do: land_delete(socket, detail, result),
          else: socket

      _closed_or_unowned ->
        socket
    end
  end

  defp land_delete(socket, detail, result) do
    socket = update(socket, :modal_state, &%{&1 | deleting: nil})
    container_id = LibraryHalf.container_id(detail)

    case result do
      {:ok, _entity_ids} ->
        if Library.Files.list_by_entity_id(container_id) == [] do
          push_patch(socket, to: socket.view.title_detail_path(socket, []))
        else
          socket
          |> update_half(&%{&1 | files: :loading})
          |> LibraryHalf.start_files_load(LibraryHalf.subject(detail), container_id)
        end

      {:error, reason} ->
        Log.warning(:library, "delete failed — #{inspect(reason)}")
        put_flash(socket, :error, "Delete failed: #{reason}")
    end
  end

  @doc "A crashed delete task clears `deleting`, logs, and flashes so the modal recovers."
  @spec apply_delete_crash(socket(), term()) :: socket()
  def apply_delete_crash(socket, reason) do
    Log.error(:library, "delete task crashed — #{inspect(reason)}")

    socket
    |> update(:modal_state, &%{&1 | deleting: nil})
    |> put_flash(:error, "Delete failed")
  end

  # --- Helpers ---

  defp files(socket) do
    case socket.assigns.title_detail.library.files do
      {:ok, files} -> files
      _loading_or_failed -> []
    end
  end

  defp media_dirs, do: MediaCentaur.Settings.Config.get(:media_dirs) || []

  defp flip(set, member) do
    if MapSet.member?(set, member), do: MapSet.delete(set, member), else: MapSet.put(set, member)
  end

  defp update_state(socket, key, fun), do: update(socket, :modal_state, &Map.update!(&1, key, fun))

  defp update_half(socket, fun) do
    detail = socket.assigns.title_detail
    assign(socket, :title_detail, %{detail | library: fun.(detail.library)})
  end
end
