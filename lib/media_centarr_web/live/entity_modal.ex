defmodule MediaCentarrWeb.Live.EntityModal do
  @moduledoc """
  Shared modal state, events, and rendering for any LiveView that displays
  the entity detail panel — the `ModalShell` + `DetailPanel` overlay.

  Both `LibraryLive` (when an item in the catalog grid is selected) and
  `HomeLive` (when a Continue Watching / Recently Added / Hero card is
  clicked) `use` this module so the modal is identical across pages.

  ## Host LiveView contract

  Adopt the modal with `use MediaCentarrWeb.Live.EntityModal`. That single
  line:

  - Registers an `on_mount` callback that subscribes to `library:updates`
    and `playback:events`, seeds the modal-default assigns, and attaches
    a `:handle_info` hook that keeps `:selected_entry` and `:playback`
    in sync with PubSub events. **The host cannot forget to wire any of
    this — it is structurally impossible to mount the modal without it.**
  - Injects `handle_event/3` clauses for every modal interaction
    (select / close / play / toggle_* / delete_* / rematch / toggle_tracking).
  - Imports the `entity_modal/1` function component.

  Beyond the `use`, the host must:

  - Implement the `build_modal_path/2` callback returning the LiveView's
    own path with the given URL overrides applied.
  - Call `apply_modal_params/2` from `handle_params/3`.
  - Render `<.entity_modal ... />` once in the template.
  - Maintain these adjacent assigns (read by the modal renderer but owned
    by the host's surrounding context): `:watch_dirs`, `:availability_map`,
    `:tmdb_ready`, `:spoiler_free`. Most are kept in sync via the
    `SpoilerFreeAware` / `CapabilitiesAware` traits (see ADR-038).

  The on_mount hook subscribes for the host. Hosts MUST NOT call
  `Library.subscribe()` or `Playback.subscribe()` themselves — the
  `EntityModalContract` Credo check enforces this so messages are not
  delivered twice.

  ## How the PubSub hook keeps the modal honest

  Four messages can mutate modal-visible state. The hook handles all of
  them in one place so a future host can never silently drop one:

  | Message | Topic | Hook does |
  |---|---|---|
  | `{:entity_progress_updated, payload}` | `playback:events` | merge `summary` / `resume_target` / `changed_record` into `:selected_entry` if the entity matches |
  | `{:extra_progress_updated, payload}` | `playback:events` | merge new `ExtraProgress` into `:selected_entry.entity.extra_progress` if it matches |
  | `{:entities_changed, ids}` | `library:updates` | re-fetch `:selected_entry` from the DB if `selected_entity_id ∈ ids` (entity-level mutation needs a full reload) |
  | `{:playback_state_changed, ...}` | `playback:events` | apply the change to the `:playback` map (used by `playing?/2` for delete-prompt protection) |

  In every case the hook returns `{:cont, socket}` so the host's own
  `handle_info/2` clauses still fire (e.g. LibraryLive updates its grid
  cache; HomeLive schedules section reloads).
  """

  use Phoenix.Component

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.{Format, Library, Playback, ReleaseTracking}
  alias MediaCentarr.Library.FileEventHandler
  alias MediaCentarr.Playback.{ProgressBroadcaster, ResumeTarget}
  alias MediaCentarrWeb.Components.{DetailPanel, ModalShell}
  alias MediaCentarrWeb.ViewModel.SeriesDetail
  alias MediaCentarrWeb.{LibraryProgress, LiveHelpers}

  import MediaCentarrWeb.LibraryProgress, only: [completion_percentage: 1]

  @callback build_modal_path(socket :: Phoenix.LiveView.Socket.t(), overrides :: map()) ::
              String.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour MediaCentarrWeb.Live.EntityModal

      on_mount {MediaCentarrWeb.Live.EntityModal, :default}

      alias MediaCentarr.Playback
      alias MediaCentarrWeb.Components.DetailPanel
      alias MediaCentarrWeb.Live.EntityModal

      import MediaCentarrWeb.Live.EntityModal,
        only: [
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
        if socket.assigns.detail_view in [:info, :credits] do
          {:noreply, push_patch(socket, to: build_modal_path(socket, %{view: :main}))}
        else
          {:noreply,
           socket
           |> assign(rematch_confirm: nil)
           |> push_patch(to: build_modal_path(socket, %{selected: nil, view: :main}))}
        end
      end

      def handle_event("toggle_detail_view", _params, socket) do
        new_view = if socket.assigns.detail_view == :info, do: :main, else: :info
        {:noreply, push_patch(socket, to: build_modal_path(socket, %{view: new_view}))}
      end

      def handle_event("toggle_credits_view", _params, socket) do
        new_view = if socket.assigns.detail_view == :credits, do: :main, else: :credits
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
          EntityModal.toggle_watch_progress(entity_id, fk_key, fk_id)
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
      #
      # Inline-confirm pattern (mirrors Rematch): each delete button is
      # its own two-step gesture. First click sets `delete_confirm` to a
      # target identifier (`{:file, path} | {:folder, path} | :all`) so
      # the button flips its label to "Confirm?". Second click on the
      # *same* target executes. Clicking a different delete button
      # re-targets — only one pending confirmation at a time. There is
      # no separate confirmation modal — we deliberately killed it
      # because modal-on-modal is ugly and the inline gesture matches
      # how Rematch already works in the same view.

      def handle_event("delete_file_prompt", %{"path" => file_path}, socket) do
        cond do
          EntityModal.playing?(
            socket.assigns.playback,
            socket.assigns.selected_entity_id
          ) ->
            {:noreply, put_flash(socket, :error, "Stop playback before deleting")}

          socket.assigns.delete_confirm == {:file, file_path} ->
            EntityModal.run_pending_delete(socket)

          true ->
            {:noreply, assign(socket, delete_confirm: {:file, file_path})}
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

          socket.assigns.delete_confirm == {:folder, folder_path} ->
            EntityModal.run_pending_delete(socket)

          true ->
            {:noreply, assign(socket, delete_confirm: {:folder, folder_path})}
        end
      end

      def handle_event("delete_all_prompt", _params, socket) do
        cond do
          EntityModal.playing?(
            socket.assigns.playback,
            socket.assigns.selected_entity_id
          ) ->
            {:noreply, put_flash(socket, :error, "Stop playback before deleting")}

          socket.assigns.delete_confirm == :all ->
            EntityModal.run_pending_delete(socket)

          true ->
            {:noreply, assign(socket, delete_confirm: :all)}
        end
      end

      def handle_event("delete_cancel", _params, socket) do
        {:noreply, assign(socket, delete_confirm: nil)}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # on_mount + PubSub hook (auto-wired by `use EntityModal`)
  # ---------------------------------------------------------------------------

  @doc """
  Auto-wires every host that `use`s this module. Runs once per LiveView
  mount (HTTP and WebSocket). Subscribes to the modal's PubSub topics on
  the connected pass, seeds modal-default assigns, and attaches a
  `:handle_info` hook so message handling lives here, not duplicated
  across hosts.
  """
  def on_mount(:default, _params, _session, socket) do
    socket = assign_modal_defaults(socket)

    if Phoenix.LiveView.connected?(socket) do
      Library.subscribe()
      Playback.subscribe()
      ReleaseTracking.subscribe()
    end

    socket =
      Phoenix.LiveView.attach_hook(
        socket,
        :entity_modal_pubsub,
        :handle_info,
        &__MODULE__.handle_modal_pubsub/2
      )

    {:cont, socket}
  end

  @doc false
  # The hook. Public only so attach_hook can capture it; not part of the
  # contract — host LiveViews never call this directly.
  def handle_modal_pubsub({:entity_progress_updated, %{entity_id: id} = payload}, socket) do
    if selected?(socket, id) do
      {:cont, refresh_from_progress_payload(socket, payload)}
    else
      {:cont, socket}
    end
  end

  def handle_modal_pubsub({:extra_progress_updated, %{entity_id: id} = payload}, socket) do
    if selected?(socket, id) do
      {:cont, refresh_from_extra_payload(socket, payload)}
    else
      {:cont, socket}
    end
  end

  def handle_modal_pubsub({:entities_changed, %{entity_ids: ids}}, socket) do
    selected = socket.assigns[:selected_entity_id]

    if selected != nil and selected in ids do
      {:cont, refresh_selected_entry(socket)}
    else
      {:cont, socket}
    end
  end

  def handle_modal_pubsub(
        {:playback_state_changed, %{entity_id: entity_id, state: new_state, now_playing: now_playing}},
        socket
      ) do
    playback =
      LiveHelpers.apply_playback_change(
        socket.assigns[:playback] || %{},
        entity_id,
        new_state,
        now_playing
      )

    {:cont, Phoenix.Component.assign(socket, :playback, playback)}
  end

  # Release-tracking updates: refetch the open entry when the open
  # entity is a TV series so its `seasons_view` reflects the new
  # releases. The selectivity check is loose (we refetch on any
  # releases_updated for any item) — release updates are infrequent
  # compared to playback ticks, so the extra query is a fair price for
  # not threading a library-entity-id resolver through the broadcast
  # message.
  def handle_modal_pubsub({:releases_updated, _item_ids}, socket) do
    if tv_series_selected?(socket) do
      {:cont, refresh_selected_entry(socket)}
    else
      {:cont, socket}
    end
  end

  def handle_modal_pubsub({:item_removed, _tmdb_id, _tmdb_type}, socket) do
    if tv_series_selected?(socket) do
      {:cont, refresh_selected_entry(socket)}
    else
      {:cont, socket}
    end
  end

  # Deferred autoplay — queued by `apply_modal_params/2` so the URL
  # patch renders before the LV blocks on Playback.play/1 (which fans
  # out to the Resolver + Sessions GenServer chain).
  def handle_modal_pubsub({:autoplay, entity_id}, socket) do
    _ = Playback.play(entity_id)
    {:halt, socket}
  end

  # Deferred file-info load — fired by the `spawn_files_load/1` task
  # spawned in `apply_modal_params/2`. Drops the result if the modal
  # has since switched to a different entity (the inbound id no longer
  # matches the open selection). Re-applies only when still relevant.
  def handle_modal_pubsub({:detail_files_loaded, entity_id, files}, socket) do
    if socket.assigns[:selected_entity_id] == entity_id do
      {:halt, Phoenix.Component.assign(socket, :detail_files, files)}
    else
      {:halt, socket}
    end
  end

  def handle_modal_pubsub(_msg, socket), do: {:cont, socket}

  defp tv_series_selected?(socket) do
    case socket.assigns[:selected_entry] do
      %{entity: %{type: :tv_series}} -> true
      _ -> false
    end
  end

  defp selected?(socket, entity_id) do
    socket.assigns[:selected_entity_id] != nil and
      socket.assigns[:selected_entity_id] == entity_id
  end

  # In-memory merge from the broadcast payload. Avoids a DB hit on every
  # progress tick (MpvSession persists every few seconds during playback).
  # Falls back to a DB refresh when the entry isn't loaded yet or the
  # payload lacks a summary (defensive — current ProgressBroadcaster
  # always sends both).
  defp refresh_from_progress_payload(socket, %{
         summary: summary,
         resume_target: resume_target,
         changed_record: changed_record
       })
       when is_map(summary) do
    case socket.assigns[:selected_entry] do
      nil ->
        refresh_selected_entry(socket)

      %SeriesDetail{} = sd ->
        records = LibraryProgress.merge_progress_record(sd.progress_records, changed_record)
        updated = SeriesDetail.with_progress(sd, summary, records, resume_target)
        Phoenix.Component.assign(socket, :selected_entry, updated)

      entry ->
        records = LibraryProgress.merge_progress_record(entry.progress_records, changed_record)

        updated = %{
          entry
          | progress: summary,
            progress_records: records,
            resume_target: resume_target
        }

        Phoenix.Component.assign(socket, :selected_entry, updated)
    end
  end

  defp refresh_from_progress_payload(socket, _payload), do: refresh_selected_entry(socket)

  defp refresh_from_extra_payload(socket, %{progress: progress}) when not is_nil(progress) do
    case socket.assigns[:selected_entry] do
      nil ->
        refresh_selected_entry(socket)

      %{entity: entity} = entry ->
        extra_progress =
          LibraryProgress.merge_extra_progress(entity.extra_progress || [], progress)

        updated = %{entry | entity: %{entity | extra_progress: extra_progress}}
        Phoenix.Component.assign(socket, :selected_entry, updated)
    end
  end

  defp refresh_from_extra_payload(socket, _payload), do: refresh_selected_entry(socket)

  # ---------------------------------------------------------------------------
  # Public helpers (called from the host LiveView)
  # ---------------------------------------------------------------------------

  @doc """
  Initial assigns for the modal slice. Called automatically from the
  on_mount callback — hosts no longer invoke this directly.
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
      tracking_status: nil,
      playback: %{}
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

    # Files are loaded asynchronously so the modal can render immediately.
    # `load_entity_files/1` issues a `File.stat/1` per file; on a network
    # mount or sleeping disk this stalls handle_params. Per the
    # "no-blocking LV page loads" rule, kick off a supervised task and
    # receive `{:detail_files_loaded, id, files}` once it's done.
    detail_files =
      cond do
        selection_changed and detail_view == :info and selected_id != nil ->
          spawn_files_load(selected_id)
          []

        selection_changed ->
          []

        detail_view == :info and socket.assigns.detail_files == [] and selected_id != nil ->
          spawn_files_load(selected_id)
          []

        true ->
          socket.assigns.detail_files
      end

    tracking_status =
      cond do
        selection_changed && match?(%SeriesDetail{}, selected_entry) ->
          # Composer already resolved tracking_status; trust the struct.
          selected_entry.tracking_status

        selection_changed && selected_entry ->
          load_tracking_status(selected_entry)

        true ->
          socket.assigns.tracking_status
      end

    # Defer Playback.play/1 to a `handle_info({:autoplay, id}, _)` clause
    # so the URL patch renders + ships to the client before the LV blocks
    # on the resolver + Sessions.play chain. The deferred message is
    # picked up by `handle_modal_pubsub/2` (the EntityModal hook).
    if autoplay? && selected_entry do
      send(self(), {:autoplay, selected_id})
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
  attr :selected_entry, :any,
    required: true,
    doc:
      "the loaded library entry map (`%{entity, progress, progress_records, ...}`) or `nil` when no entity is open. Same shape as `LibraryCards.poster_card/1`'s `:entry`."

  attr :selected_entity_id, :any,
    required: true,
    doc: "the currently-selected entity id (`Ecto.UUID.t()`) or `nil`."

  attr :detail_presentation, :any,
    required: true,
    doc:
      "presentation mode atom — `:modal`, `:inline`, or `nil`. Each host LiveView decides; `:any` keeps the door open for future modes."

  attr :detail_view, :atom, required: true
  attr :detail_files, :list, required: true, doc: "list of file-info maps for the Files sub-view."

  attr :expanded_seasons, MapSet, required: true

  attr :rematch_confirm, :any,
    required: true,
    doc: "`true | false` — confirmation flag for the rematch destructive action."

  attr :delete_confirm, :any,
    required: true,
    doc: "transient delete-confirmation state — see `DetailPanel`'s contract."

  attr :tracking_status, :atom, required: true

  attr :availability_map, :map,
    default: %{},
    doc: "`%{entity_id => boolean}` from `MediaCentarrWeb.LibraryAvailability.availability_map/1`."

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
      seasons_view={MediaCentarrWeb.Live.EntityModal.seasons_view_from_entry(@selected_entry)}
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

  @doc """
  Extracts the typed `[%SeasonView{}]` list from a `selected_entry`.
  Returns `nil` for non-TV entries (movie / movie_series / no entry),
  triggering the existing fallback in `DetailPanel.content_list/1`.
  """
  @spec seasons_view_from_entry(SeriesDetail.t() | map() | nil) :: list() | nil
  def seasons_view_from_entry(%SeriesDetail{seasons: seasons}), do: seasons
  def seasons_view_from_entry(_), do: nil

  # ---------------------------------------------------------------------------
  # Internals shared with the macro (callable from injected handle_event)
  # ---------------------------------------------------------------------------

  @doc false
  def playing?(playback, entity_id), do: Map.has_key?(playback, entity_id)

  @doc false
  defdelegate resolve_progress_fk(entry, entity_id, season_number, episode_number),
    to: MediaCentarrWeb.LibraryProgress,
    as: :resolve_progress_fk_from_entry

  @doc false
  def toggle_watch_progress(entity_id, fk_key, fk_id) do
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
  # Loads the watched-files list for an entity and stats each path. The
  # stats run in parallel under `Task.async_stream` with a short
  # per-file timeout — a stale network mount can take seconds to fail
  # `File.stat/1`, and the synchronous-per-file path made that the
  # bound on the whole list. Per-call concurrency is small (8) because
  # the bottleneck is filesystem latency, not CPU.
  def load_entity_files(entity_id) do
    entity_id
    |> Library.list_watched_files_by_entity_id()
    |> Task.async_stream(
      fn file ->
        size =
          case File.stat(file.file_path) do
            {:ok, %{size: size}} -> size
            _ -> nil
          end

        %{file: file, size: size}
      end,
      max_concurrency: 8,
      ordered: true,
      timeout: 1_500,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, entry} -> entry
      {:exit, _reason} -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Spawns the file-info load on a supervised task so handle_params
  # returns immediately. The task replies via `{:detail_files_loaded,
  # entity_id, files}` which the EntityModal hook applies — see
  # `handle_modal_pubsub/2`.
  defp spawn_files_load(entity_id) do
    parent = self()

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      files = load_entity_files(entity_id)
      send(parent, {:detail_files_loaded, entity_id, files})
    end)
  end

  @doc false
  def run_delete(%{delete_confirm: delete_confirm, detail_files: detail_files, watch_dirs: watch_dirs}) do
    case delete_confirm do
      {:file, file_path} ->
        FileEventHandler.delete_file(file_path)

      {:folder, folder_path} ->
        file_paths =
          detail_files
          |> Enum.map(& &1.file.file_path)
          |> Enum.filter(&String.starts_with?(&1, folder_path <> "/"))

        FileEventHandler.delete_folder(folder_path, file_paths)

      :all ->
        payload =
          MediaCentarrWeb.Components.DetailPanel.build_delete_all_payload(
            detail_files,
            MapSet.new(watch_dirs)
          )

        Enum.each(payload.file_groups, fn group ->
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

  @doc """
  Executes the pending delete in `socket.assigns.delete_confirm`,
  clears the pending state, and refreshes (or closes) the modal based
  on what's left on disk. Returns the same `{:noreply, socket}` shape
  the calling `handle_event/3` returns so the host LV can pipe through.

  Public only so the macro-injected handlers can call it; not part of
  the host contract.
  """
  def run_pending_delete(socket) do
    entity_id = socket.assigns.selected_entity_id
    result = run_delete(socket.assigns)
    socket = Phoenix.Component.assign(socket, delete_confirm: nil)

    case result do
      {:ok, _entity_ids} ->
        files = MediaCentarr.Library.list_watched_files_by_entity_id(entity_id)

        if files == [] do
          {:noreply,
           Phoenix.LiveView.push_patch(socket,
             to: socket.view.build_modal_path(socket, %{selected: nil, view: :main})
           )}
        else
          detail_files = load_entity_files(entity_id)
          {:noreply, Phoenix.Component.assign(socket, detail_files: detail_files)}
        end

      {:error, reason} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Delete failed: #{reason}")}
    end
  end

  # --- Private helpers ---

  defp parse_view("info"), do: :info
  defp parse_view("credits"), do: :credits
  defp parse_view(_), do: :main

  # TV series go through `SeriesDetail.compose/1` and become
  # `%SeriesDetail{}` structs carrying a typed `seasons` list +
  # cached `releases`. Other types stay as the existing
  # `%{entity, progress, progress_records, resume_target}` map shape.
  # Both shapes carry the same fields the modal renderer reads,
  # so the template doesn't branch on entry type.
  defp load_entry_and_expand(id) do
    case SeriesDetail.compose(id) do
      {:ok, %SeriesDetail{} = sd} ->
        expanded = DetailPanel.auto_expand_season(sd.entity, sd.progress)
        {sd, expanded}

      # `SeriesDetail.compose/1` returns `:not_found` for any id that
      # isn't a TV series, including ids that ARE existing movies /
      # video_objects / movie_series. Falling through to the non-TV
      # path lets `Library.load_modal_entry/1` open those modals; if
      # the id is truly orphan it returns `:not_found` itself and we
      # land on `{nil, MapSet.new()}` via `load_non_tv_entry/1`.
      :not_found ->
        load_non_tv_entry(id)
    end
  end

  defp load_non_tv_entry(id) do
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
