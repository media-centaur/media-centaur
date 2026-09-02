defmodule MediaCentaurWeb.Live.EntityModal do
  @moduledoc """
  Shared modal state, events, and rendering for any LiveView that displays
  the entity detail panel — the `DetailPanel` overlay (the library tenant
  of `CinematicShell`).

  Both `LibraryLive` (when an item in the catalog grid is selected) and
  `HomeLive` (when a Continue Watching / Recently Added / Hero card is
  clicked) `use` this module so the modal is identical across pages.

  ## Host LiveView contract

  Adopt the modal with `use MediaCentaurWeb.Live.EntityModal`. That single
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
    by the host's surrounding context): `:media_dirs`, `:availability_map`,
    `:tmdb_ready`, `:spoiler_free`, `:watchlisted_refs`. Most are kept in
    sync via the `SpoilerFreeAware` / `CapabilitiesAware` /
    `WatchlistAware` traits (see ADR-038).

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

  require MediaCentaur.Log, as: Log
  require Phoenix.LiveView

  alias MediaCentaur.{Discovery, Format, Library, Playback, ReleaseTracking}
  alias MediaCentaur.Library.FileEventHandler
  alias MediaCentaur.Playback.{ProgressBroadcaster, ResumeTarget}
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Detail.CastSelection
  alias MediaCentaurWeb.Components.Detail.Logic
  alias MediaCentaurWeb.Components.Detail.ManagePanel
  alias MediaCentaurWeb.Components.DetailPanel
  alias MediaCentaurWeb.ViewModel.CollectionDetail
  alias MediaCentaurWeb.ViewModel.Orientation
  alias MediaCentaurWeb.ViewModel.SeriesDetail
  alias MediaCentaurWeb.{LibraryProgress, LiveHelpers}

  import MediaCentaurWeb.LibraryProgress, only: [completion_percentage: 1]

  @callback build_modal_path(socket :: Phoenix.LiveView.Socket.t(), overrides :: map()) ::
              String.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour MediaCentaurWeb.Live.EntityModal

      on_mount {MediaCentaurWeb.Live.EntityModal, :default}

      alias MediaCentaur.Playback
      alias MediaCentaurWeb.Components.DetailPanel
      alias MediaCentaurWeb.Live.EntityModal

      import MediaCentaurWeb.Live.EntityModal,
        only: [
          apply_modal_params: 2,
          entity_modal: 1,
          refresh_selected_entry: 1
        ]

      # --- Modal: open / close ---

      @impl true
      def handle_event("select_entity", %{"id" => id}, socket) do
        new_id = if socket.assigns.selected_entity_id != id, do: id

        # A member selection belongs to one collection — never carry it
        # across to the next entity.
        {:noreply, push_patch(socket, to: build_modal_path(socket, %{selected: new_id, movie: nil}))}
      end

      # Poster-rail pick inside a collection modal (UIDR-023): re-anchors
      # the panel to that member via the URL. Selecting never plays.
      def handle_event("select_movie", %{"id" => id}, socket) do
        {:noreply, push_patch(socket, to: build_modal_path(socket, %{movie: id}))}
      end

      def handle_event("close_detail", _params, socket) do
        {action, overrides} = EntityModal.close_detail_target(socket.assigns)
        socket = if action == :close, do: assign(socket, rematch_confirm: nil), else: socket
        {:noreply, push_patch(socket, to: build_modal_path(socket, overrides))}
      end

      def handle_event("select_detail_view", %{"view" => view}, socket) do
        {:noreply,
         push_patch(socket, to: build_modal_path(socket, %{view: EntityModal.parse_view(view)}))}
      end

      def handle_event("filter_cast", params, socket) do
        EntityModal.handle_filter_cast(params, socket)
      end

      def handle_event("show_more_cast", _params, socket) do
        EntityModal.handle_show_more_cast(socket)
      end

      def handle_event("toggle_season", params, socket) do
        EntityModal.handle_toggle_season(params, socket)
      end

      def handle_event("toggle_file_group", params, socket) do
        EntityModal.handle_toggle_file_group(params, socket)
      end

      def handle_event("toggle_item_details", params, socket) do
        EntityModal.handle_toggle_item_details(params, socket)
      end

      def handle_event("toggle_all_episode_details", _params, socket) do
        EntityModal.handle_toggle_all_episode_details(socket)
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

      def handle_event("toggle_watched", params, socket) do
        EntityModal.handle_toggle_watched(params, socket)
      end

      def handle_event(
            "toggle_extra_watched",
            %{"extra-id" => extra_id, "entity-id" => entity_id},
            socket
          ) do
        EntityModal.toggle_extra_watched(entity_id, extra_id)
        {:noreply, socket}
      end

      # --- Rematch ---

      def handle_event("rematch", %{"id" => entity_id}, socket) do
        if socket.assigns.rematch_confirm == entity_id do
          # Just a PubSub broadcast — instant; the rematch work runs in the
          # command handler. Synchronous (ADR-049).
          MediaCentaur.Review.Rematch.rematch_entity(entity_id)

          {:noreply,
           socket
           |> assign(rematch_confirm: nil)
           |> push_navigate(to: ~p"/review")}
        else
          {:noreply, assign(socket, rematch_confirm: entity_id)}
        end
      end

      # --- Refresh artwork ---

      def handle_event("refresh_artwork", %{"id" => entity_id}, socket) do
        type = socket.assigns.selected_entry.entity.type
        result = MediaCentaur.Pipeline.ImageRefresh.enqueue_refresh(entity_id, type)
        {level, message} = EntityModal.refresh_artwork_flash(result)
        {:noreply, put_flash(socket, level, message)}
      end

      # --- Tracking ---

      def handle_event("toggle_tracking", _params, socket) do
        case {socket.assigns.tracking_status, EntityModal.find_tmdb_id(socket.assigns.selected_entry)} do
          {:watching, {tmdb_id, media_type}} ->
            item = MediaCentaur.ReleaseTracking.get_item_by_tmdb(tmdb_id, media_type)
            if item, do: MediaCentaur.ReleaseTracking.ignore_item(item)
            {:noreply, assign(socket, tracking_status: :ignored)}

          {:ignored, {tmdb_id, media_type}} ->
            item = MediaCentaur.ReleaseTracking.get_item_by_tmdb(tmdb_id, media_type)
            if item, do: MediaCentaur.ReleaseTracking.watch_item(item)
            {:noreply, assign(socket, tracking_status: :watching)}

          _ ->
            {:noreply, socket}
        end
      end

      # --- Watchlist ---

      def handle_event("modal_watchlist_toggle", _params, socket) do
        {:noreply, EntityModal.toggle_watchlist(socket)}
      end

      # --- Track overrides ---

      def handle_event("reset_track_override", _params, socket) do
        {:noreply, EntityModal.reset_track_override(socket)}
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

          folder_path in socket.assigns.media_dirs ->
            {:noreply, put_flash(socket, :error, "Cannot delete a media directory")}

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

      # Owned async (ADR-049): the modal's deferred file-info load runs via
      # start_async/3 (see EntityModal.apply_modal_params/2). Result lands
      # here and is applied only if the same entity is still selected.
      @impl true
      def handle_async({:detail_files, entity_id}, {:ok, files}, socket) do
        {:noreply, EntityModal.apply_detail_files(socket, entity_id, files)}
      end

      def handle_async({:delete, entity_id}, {:ok, result}, socket) do
        {:noreply, EntityModal.apply_delete_result(socket, entity_id, result)}
      end

      def handle_async({:delete, _entity_id}, {:exit, reason}, socket) do
        {:noreply, EntityModal.apply_delete_crash(socket, reason)}
      end

      def handle_async(_name, {:exit, _reason}, socket), do: {:noreply, socket}
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

  # Post-refresh signal from the Detail projection's cache worker, emitted
  # *after* it has rebuilt the ETS row that `load_modal_entry/1` reads. The
  # raw `:entities_changed` above fires *before* that rebuild, so in
  # production (cache worker running) refreshing on it alone re-read a
  # stale, image-less row — a placeholder never flipped to artwork that
  # landed while the modal was open. Reacting here, after the cache is
  # fresh, is the same projection-refresh signal the grid/home consume.
  # A whole-table rebuild now arrives as a single `:all`; a partial refresh
  # still names the row that changed. Both refresh the open entry — the modal
  # holds an `entity_id`, not a `playable_item_id`, so it cannot filter a
  # partial id, and partial refreshes are genuinely one-at-a-time. What this
  # clause must never do again is refresh once per row in the library, which
  # is what the old per-row rebuild fan-out caused.
  def handle_modal_pubsub({:library_view_updated, :detail, _id}, socket) do
    if socket.assigns[:selected_entity_id] do
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

  # A mid-playback track change was captured (or cleared) as a per-entity
  # override. When it's the open entity, refresh the *Remembered tracks*
  # badge in place — no full reload, so a composed `%SeriesDetail{}` entry
  # keeps its typed seasons. Payload matched structurally (the Events
  # struct isn't exported across the Playback boundary).
  def handle_modal_pubsub({:track_override_changed, %{owner_type: type, owner_id: id}}, socket) do
    if selected?(socket, id) do
      {:cont, put_entry_track_override(socket, Library.MediaTrackOverrides.get(type, id))}
    else
      {:cont, socket}
    end
  end

  # Release-tracking updates: refetch the open entry when the open
  # entity carries a release overlay (TV `seasons_view`, collection
  # `movies` list) so it reflects the new releases. The selectivity
  # check is loose (we refetch on any releases_updated for any item) —
  # release updates are infrequent compared to playback ticks, so the
  # extra query is a fair price for not threading a
  # library-entity-id resolver through the broadcast message.
  def handle_modal_pubsub({:releases_updated, _item_ids}, socket) do
    if release_overlay_selected?(socket) do
      {:cont, refresh_selected_entry(socket)}
    else
      {:cont, socket}
    end
  end

  def handle_modal_pubsub({:item_removed, _tmdb_id, _tmdb_type}, socket) do
    if release_overlay_selected?(socket) do
      {:cont, refresh_selected_entry(socket)}
    else
      {:cont, socket}
    end
  end

  # Deferred file-info load — fired by the `spawn_files_load/1` task
  # spawned in `apply_modal_params/2`. Drops the result if the modal
  # has since switched to a different entity (the inbound id no longer
  # matches the open selection). Re-applies only when still relevant.
  def handle_modal_pubsub(_msg, socket), do: {:cont, socket}

  defp release_overlay_selected?(socket) do
    case socket.assigns[:selected_entry] do
      %{entity: %{type: type}} when type in [:tv_series, :movie_series] -> true
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

      %CollectionDetail{} = cd ->
        records = LibraryProgress.merge_progress_record(cd.progress_records, changed_record)
        updated = CollectionDetail.with_progress(cd, summary, records, resume_target)
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
      selected_member_id: nil,
      selected_entry: nil,
      detail_presentation: nil,
      detail_view: :main,
      detail_files: [],
      expanded_file_groups: nil,
      cast_filter: "",
      cast_limit: CastSelection.page_size(),
      expanded_seasons: MapSet.new(),
      expanded_item_details: MapSet.new(),
      all_episode_details_open: false,
      rematch_confirm: nil,
      delete_confirm: nil,
      deleting: nil,
      tracking_status: nil,
      playback: %{}
    )
  end

  @doc """
  Reads the modal-related URL params (`selected`, `view`), loads the
  selected entry on demand, and assigns the modal slice on the socket.
  Returns the updated socket.

  - `selected` UUID → resolved via `Library.Presentable` and composed by
    the matching loader (`SeriesDetail` / `CollectionDetail` /
    `Library.ModalEntry`). If the entity doesn't exist or has no present
    file, the modal stays closed (selected_entry: nil).
  - `view=info` → opens the file/info pane inside the modal.

  Playback never routes through here: play affordances fire the shared
  `"play"` event and play in place (UIDR-027).

  Idempotent: re-applying the same params is a no-op.
  """
  @spec apply_modal_params(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def apply_modal_params(socket, params) do
    selected_id = params["selected"]
    detail_view = parse_view(params["view"])

    selection_changed = selected_id != socket.assigns.selected_entity_id
    entity_switched = selection_changed && socket.assigns.selected_entity_id != nil
    detail_view = if entity_switched, do: :main, else: detail_view

    # The season holding the next episode opens expanded (2026-08-05
    # auto-orient design, revising the blanket collapse of 2026-08-04).
    # Which season that is comes from `Orientation` — the same value the
    # hero hairline reads — so the open season and the hairline cannot
    # disagree. Seeded on selection change only; within one selection
    # `expanded_seasons` changes solely via toggle_season clicks.
    {selected_entry, expanded_seasons} =
      cond do
        selected_id == nil ->
          {nil, MapSet.new()}

        selection_changed ->
          entry = load_entry_or_nil(selected_id)
          {entry, initial_expanded_seasons(entry)}

        true ->
          {socket.assigns.selected_entry, socket.assigns.expanded_seasons}
      end

    # A tab that cannot render must never be the selected one, whether it
    # was asked for by URL, carried over from the previous entity, or
    # arrived at by default. `Logic.resolve_view/2` is the single place that
    # decides, shared with the strip that draws the tabs.
    detail_view = resolve_view(selected_entry, detail_view)

    selected_member_id = params["movie"] || implied_member_id(selected_entry, selected_id)

    # Files are loaded asynchronously so the modal can render immediately.
    # `load_entity_files/1` issues a `File.stat/1` per file; on a network
    # mount or sleeping disk this stalls handle_params. Per ADR-049, defer
    # it to an owned start_async (kicked off below, after assign) whose
    # result lands in `handle_async({:detail_files, id}, …)`.
    #
    # Kicked off when the modal *opens*, not when Manage is opened. Deferring
    # it that far made the first press of the cog render an empty sheet with
    # the files arriving as a second patch, which reads as a flash: nothing in
    # the sheet means nothing to scroll, so the scrollport collapses to the top
    # and snaps back once the content lands. Paying for the stats on open — for
    # a title the user may never manage — is the cheaper trade, and it is the
    # same one UIDR-012 makes everywhere else.
    #
    # Exactly once per selection. `apply_detail_files/3` drops a result whose
    # entity is no longer the selected one, so browsing quickly through titles
    # cannot land a stale list.
    should_load_files? = selected_id != nil and selection_changed

    detail_files = if selection_changed, do: [], else: socket.assigns.detail_files

    tracking_status =
      cond do
        selection_changed &&
            (match?(%SeriesDetail{}, selected_entry) || match?(%CollectionDetail{}, selected_entry)) ->
          # Composer already resolved tracking_status; trust the struct.
          selected_entry.tracking_status

        selection_changed && selected_entry ->
          load_tracking_status(selected_entry)

        true ->
          socket.assigns.tracking_status
      end

    socket =
      socket
      |> Phoenix.Component.assign(
        selected_entity_id: selected_id,
        selected_member_id: selected_member_id,
        selected_entry: selected_entry,
        detail_presentation: if(selected_id, do: :modal),
        detail_view: detail_view,
        detail_files: detail_files,
        expanded_seasons: expanded_seasons,
        tracking_status: tracking_status
      )
      |> Phoenix.Component.assign(per_selection_assigns(socket.assigns, selection_changed))

    if should_load_files?, do: start_async_files_load(socket, selected_id), else: socket
  end

  # A `selected` id that resolved *away* from itself — a member movie the
  # resolver routed to its collection — carries information: the caller
  # pointed at that specific movie, so it is the member selection
  # (UIDR-025 click contract for activity surfaces). An explicit `movie`
  # param outranks it; the resume-target ladder applies only when the
  # modal is entered with no selection at all (the collection's own id).
  defp implied_member_id(%CollectionDetail{entity: %{id: collection_id}}, selected_id)
       when selected_id != collection_id, do: selected_id

  defp implied_member_id(_selected_entry, _selected_id), do: nil

  # State the user built up against the entity that was open, which means
  # nothing against the next one: which episode disclosures they opened,
  # what they typed into the cast filter, and how far they paged the cast
  # grid. Carried across re-params of the same selection, dropped when the
  # selection changes — a stale cast query would render the new entity's
  # cast as "no matches".
  #
  # Grouped rather than reset inline so adding the next one is a line here
  # instead of another branch in `apply_modal_params/2`.
  @per_selection_defaults %{
    expanded_item_details: MapSet.new(),
    all_episode_details_open: false,
    cast_filter: "",
    cast_limit: CastSelection.page_size(),
    expanded_file_groups: nil
  }

  defp per_selection_assigns(_assigns, true = _selection_changed), do: @per_selection_defaults

  defp per_selection_assigns(assigns, false = _selection_changed),
    do: Map.take(assigns, Map.keys(@per_selection_defaults))

  # Only TV carries a season accordion; movie / movie-series entries load
  # as plain maps and open with nothing expanded.
  defp initial_expanded_seasons(%SeriesDetail{seasons: seasons, resume_target: resume_target}) do
    seasons
    |> Orientation.for_series(resume_target)
    |> Orientation.initial_expanded_seasons()
  end

  defp initial_expanded_seasons(_entry), do: MapSet.new()

  @doc """
  The modal's own URL query params (`selected` / `view` / `movie`),
  resolved from the current assigns with `overrides` applied. Hosts
  merge this map into their page-specific params inside
  `build_modal_path/2` — one implementation of the modal's URL contract
  instead of a copy per host.

  Every param is guarded on `selected`: a closed modal contributes no
  params, whatever stale assigns say.
  """
  @spec modal_query_params(map(), map()) :: map()
  def modal_query_params(assigns, overrides) do
    selected = Map.get(overrides, :selected, assigns.selected_entity_id)
    view = Map.get(overrides, :view, assigns.detail_view)
    movie = Map.get(overrides, :movie, assigns.selected_member_id)

    params = %{}
    params = if selected, do: Map.put(params, :selected, selected), else: params
    params = if selected && view in [:info, :cast], do: Map.put(params, :view, view), else: params
    params = if selected && movie, do: Map.put(params, :movie, movie), else: params
    params
  end

  @doc """
  Resolves the member the movie-first collection modal shows (UIDR-023):
  the URL-selected member, falling back through the resume target to the
  first member. Returns `nil` for non-collection entries or an empty
  collection, and `%{member, subject}` otherwise — `member` the
  `MovieListItem.Library`, `subject` its `:movie`-shaped entity map.

  Derived at render time from the loaded entry, so progress merges and
  projection refreshes can never leave a stale subject behind.
  """
  @spec member_view(CollectionDetail.t() | map() | nil, Ecto.UUID.t() | nil) :: map() | nil
  def member_view(%CollectionDetail{} = entry, member_id) do
    case CollectionDetail.select_member(entry, member_id) do
      nil ->
        nil

      member ->
        %{
          member: member,
          subject: CollectionDetail.member_subject(member)
        }
    end
  end

  def member_view(_entry, _member_id), do: nil

  @doc """
  Reload the currently-selected entry from the database. Call from the
  host LiveView's PubSub handlers when the selected entity may have
  changed (e.g. on `:entities_changed` containing `selected_entity_id`).
  """
  @spec refresh_selected_entry(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def refresh_selected_entry(%{assigns: %{selected_entity_id: nil}} = socket), do: socket

  def refresh_selected_entry(socket) do
    case load_entry(socket.assigns.selected_entity_id) do
      {:ok, entry} ->
        Phoenix.Component.assign(socket, :selected_entry, entry)

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

  attr :selected_member_id, :any,
    required: true,
    doc:
      "URL-selected collection member id (`Ecto.UUID.t()`) or `nil` — resolved through `member_view/2`; stale ids fall back to the default member."

  attr :detail_presentation, :any,
    required: true,
    doc:
      "presentation mode atom — `:modal`, `:inline`, or `nil`. Each host LiveView decides; `:any` keeps the door open for future modes."

  attr :detail_view, :atom, required: true
  attr :detail_files, :list, required: true, doc: "list of file-info maps for the Files sub-view."

  attr :expanded_file_groups, :any,
    required: true,
    doc:
      "`MapSet.t()` of expanded Manage-ledger folder dirs, or `nil` for the automatic default. Owned here (`toggle_file_group`), reset on selection change."

  attr :cast_filter, :string,
    required: true,
    doc: "current Cast-view filter query. Reset when the modal switches entities."

  attr :cast_limit, :integer,
    required: true,
    doc:
      "how many cast matches the Cast view renders. Bumped by `show_more_cast`, reset when the modal switches entities."

  attr :expanded_seasons, MapSet, required: true

  attr :expanded_item_details, MapSet,
    required: true,
    doc:
      "leaf container ids of content rows whose synopsis disclosure is open — one key space for episodes and collection movies alike. Reset on selection change."

  attr :all_episode_details_open, :boolean,
    required: true,
    doc:
      "list-level episode-details toggle — opens every episode disclosure at once. Reset on selection change."

  attr :rematch_confirm, :any,
    required: true,
    doc: "`true | false` — confirmation flag for the rematch destructive action."

  attr :delete_confirm, :any,
    required: true,
    doc: "transient delete-confirmation state — see `DetailPanel`'s contract."

  attr :deleting, :any,
    required: true,
    doc:
      "in-flight async delete target — see `DetailPanel`'s `:deleting` contract. Required (no default) so a host can't silently drop it and lose the \"Deleting…\" feedback."

  attr :tracking_status, :atom, required: true

  attr :availability_map, :map,
    default: %{},
    doc: "`%{entity_id => boolean}` from `MediaCentaurWeb.LibraryAvailability.availability_map/1`."

  attr :tmdb_ready, :boolean, default: true
  attr :spoiler_free, :boolean, default: false
  attr :letterboxd_links, :boolean, default: true

  attr :watchlisted_refs, :any,
    required: true,
    doc:
      "`MapSet.t({tmdb_id, media_type})` from the host's `WatchlistAware` trait — drives the view controls' watchlist toggle. Required so a host cannot mount the modal without the trait."

  def entity_modal(assigns) do
    ~H"""
    <DetailPanel.detail_panel
      open={@selected_entry != nil && @detail_presentation == :modal}
      entity={(@selected_entry && @selected_entry.entity) || nil}
      progress={@selected_entry && @selected_entry.progress}
      resume={@selected_entry && Map.get(@selected_entry, :resume_target)}
      progress_records={(@selected_entry && @selected_entry.progress_records) || []}
      seasons_view={MediaCentaurWeb.Live.EntityModal.seasons_view_from_entry(@selected_entry)}
      movies_view={MediaCentaurWeb.Live.EntityModal.movies_view_from_entry(@selected_entry)}
      member_view={MediaCentaurWeb.Live.EntityModal.member_view(@selected_entry, @selected_member_id)}
      expanded_seasons={@expanded_seasons}
      expanded_item_details={@expanded_item_details}
      all_episode_details_open={@all_episode_details_open}
      rematch_confirm={@rematch_confirm == @selected_entity_id}
      detail_view={@detail_view}
      detail_files={@detail_files}
      expanded_file_groups={@expanded_file_groups}
      cast_filter={@cast_filter}
      cast_limit={@cast_limit}
      delete_confirm={@delete_confirm}
      deleting={@deleting}
      spoiler_free={@spoiler_free}
      letterboxd_links={@letterboxd_links}
      watchlisted?={
        MediaCentaurWeb.Live.EntityModal.watchlisted?(
          @selected_entry,
          @selected_member_id,
          @watchlisted_refs
        )
      }
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
  triggering the extras-only fallback in the detail panel's content dispatch.
  """
  @spec seasons_view_from_entry(SeriesDetail.t() | map() | nil) :: list() | nil
  def seasons_view_from_entry(%SeriesDetail{seasons: seasons}), do: seasons
  def seasons_view_from_entry(_), do: nil

  @doc """
  Extracts the typed `[%MovieListItem{}]` list from a `selected_entry`.
  Returns `nil` for non-collection entries (TV / movie / no entry).
  """
  @spec movies_view_from_entry(CollectionDetail.t() | map() | nil) :: list() | nil
  def movies_view_from_entry(%CollectionDetail{movies: movies}), do: movies
  def movies_view_from_entry(_), do: nil

  # ---------------------------------------------------------------------------
  # Internals shared with the macro (callable from injected handle_event)
  # ---------------------------------------------------------------------------

  @doc false
  def playing?(playback, entity_id), do: Map.has_key?(playback, entity_id)

  @doc """
  Flips a row's watched state. Every row names its own leaf container
  outright (`container-type` + `container-id`) — no ordinal or
  season-episode round-trip through the loaded entry.

  Local DB upsert + PubSub broadcast — fast, runs synchronously
  (ADR-044/049). The UI updates via the broadcast, not a return.
  """
  @spec handle_toggle_watched(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_toggle_watched(
        %{"entity-id" => entity_id, "container-type" => container_type, "container-id" => container_id},
        socket
      ) do
    toggle_watch_progress(entity_id, parse_container_type(container_type), container_id)
    {:noreply, socket}
  end

  # The container-type atom a row's `phx-value-container-type` names.
  # Explicit clauses — never `String.to_atom/1` on client input.
  defp parse_container_type("movie"), do: :movie
  defp parse_container_type("episode"), do: :episode
  defp parse_container_type("video_object"), do: :video_object

  @doc """
  Toggles one season's accordion expansion. `expanded_seasons` holds
  season numbers; nothing auto-expands (2026-08-04 orientation design).
  """
  @spec handle_toggle_season(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_toggle_season(%{"season" => season_str}, socket) do
    season_number = String.to_integer(season_str)
    expanded = socket.assigns[:expanded_seasons] || MapSet.new()

    expanded =
      if MapSet.member?(expanded, season_number),
        do: MapSet.delete(expanded, season_number),
        else: MapSet.put(expanded, season_number)

    {:noreply, Phoenix.Component.assign(socket, expanded_seasons: expanded)}
  end

  @doc """
  Toggles one folder group's disclosure in the Manage ledger.

  `expanded_file_groups` starts as `nil` — "the automatic default"
  (`ManagePanel.effective_expanded_dirs/2`: everything open for small
  inventories, everything closed for large ones). The first toggle
  materialises that default into a concrete set and flips the one dir,
  so auto-expanded groups collapse exactly as a user would expect.
  Resets to `nil` on selection change (`@per_selection_defaults`).
  """
  def handle_toggle_file_group(%{"dir" => dir}, socket) do
    media_dirs = MapSet.new(MediaCentaur.Settings.Config.get(:media_dirs) || [])
    file_groups = ManagePanel.build_file_groups(socket.assigns.detail_files, media_dirs)

    expanded =
      ManagePanel.effective_expanded_dirs(file_groups, socket.assigns[:expanded_file_groups])

    expanded =
      if MapSet.member?(expanded, dir),
        do: MapSet.delete(expanded, dir),
        else: MapSet.put(expanded, dir)

    {:noreply, Phoenix.Component.assign(socket, expanded_file_groups: expanded)}
  end

  @doc """
  Toggles the synopsis disclosure for one content row — episode or
  collection movie alike. `expanded_item_details` holds leaf container
  ids (one key space for every row family); the set resets on selection
  change (`apply_modal_params/2`).
  """
  @spec handle_toggle_item_details(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_toggle_item_details(%{"item-id" => item_id}, socket) do
    expanded = socket.assigns[:expanded_item_details] || MapSet.new()

    expanded =
      if MapSet.member?(expanded, item_id),
        do: MapSet.delete(expanded, item_id),
        else: MapSet.put(expanded, item_id)

    {:noreply, Phoenix.Component.assign(socket, expanded_item_details: expanded)}
  end

  @doc """
  Flips the list-level episode-details toggle — every episode row's
  synopsis/thumbnail block opens (or closes) at once. ORed with the
  per-row `expanded_episode_details` set in the renderer, so per-row
  disclosures survive turning the toggle off. Resets on selection
  change (`apply_modal_params/2`).
  """
  @spec handle_toggle_all_episode_details(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_toggle_all_episode_details(socket) do
    {:noreply,
     Phoenix.Component.assign(
       socket,
       :all_episode_details_open,
       !socket.assigns[:all_episode_details_open]
     )}
  end

  @doc """
  The view a requested one resolves to for the open entry, given which tabs
  that entry actually has. `nil` entry passes the request through — there is
  no entity to resolve against yet.

  Delegates to `Detail.Logic.resolve_view/2`, which the view control also
  uses, so the URL and the control can never disagree about what is
  selected. For a collection the *member subject* answers (UIDR-023): Cast
  exists when the default member has cast, with the collection's extras
  standing in for the body — the same composed shape the panel hands its
  view control.
  """
  @spec resolve_view(map() | nil, atom()) :: atom()
  def resolve_view(nil, requested_view), do: requested_view

  def resolve_view(%CollectionDetail{} = entry, requested_view) do
    case member_view(entry, nil) do
      nil ->
        Logic.resolve_view(entry.entity, requested_view)

      %{subject: subject} ->
        Logic.resolve_view(Map.put(subject, :extras, entry.extras || []), requested_view)
    end
  end

  def resolve_view(entry, requested_view), do: Logic.resolve_view(entry.entity, requested_view)

  @doc """
  The tab an entry opens on, and the one BACK closes the modal from.

  Usually the body tab; a title with no contents of its own (a movie with no
  extras) has no body tab, so its default is Cast.
  """
  @spec default_view(map() | nil) :: atom()
  def default_view(entry), do: resolve_view(entry, :main)

  @doc """
  What BACK (or a backdrop click, or Escape) should do from the current
  view: `{:close, overrides}` or `{:return, overrides}`, with the modal-path
  overrides for either.

  BACK peels one level of containment. From a tab other than the entity's
  root, it returns to that root; from the root there is nothing above, so
  the modal closes. Comparing against the *resolved* root is what makes this
  correct for a movie with no extras — its root is Cast, so BACK there
  must close rather than land on a body that renders nothing.

  `:close` additionally clears any pending rematch confirmation, which is
  why the caller needs the tag and not just the overrides.
  """
  @spec close_detail_target(map()) :: {:close | :return, map()}
  def close_detail_target(assigns) do
    root_view = default_view(assigns.selected_entry)

    if assigns.detail_view == root_view do
      {:close, %{selected: nil, view: root_view}}
    else
      {:return, %{view: root_view}}
    end
  end

  @doc """
  Applies the Cast-view filter query. Plain assign, no URL round-trip:
  a half-typed actor name is not a place worth restoring someone to.
  """
  @spec handle_filter_cast(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_filter_cast(%{"cast_filter" => query}, socket) do
    {:noreply, Phoenix.Component.assign(socket, :cast_filter, query)}
  end

  @doc """
  Pages another `CastSelection.page_size/0` cast cards into the Cast view.
  Plain assign for the same reason as the filter: how far someone has
  paged is not a place worth restoring them to.
  """
  @spec handle_show_more_cast(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_show_more_cast(socket) do
    limit = socket.assigns.cast_limit + CastSelection.page_size()
    {:noreply, Phoenix.Component.assign(socket, :cast_limit, limit)}
  end

  @doc """
  Clear the per-entity track override for the open entity and drop the
  *Remembered tracks* badge from the modal. No-op when nothing is open or
  the open entity isn't a movie / TV series (only those own overrides).
  Public so the macro-injected `reset_track_override` event can call it.
  """
  @spec reset_track_override(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def reset_track_override(%{assigns: %{selected_entry: %{entity: %{id: id, type: type}}}} = socket)
      when type in [:movie, :tv_series] and is_binary(id) do
    Library.MediaTrackOverrides.clear(type, id)
    put_entry_track_override(socket, nil)
  end

  def reset_track_override(socket), do: socket

  @doc """
  Adds or removes the modal's watchlist subject on the watchlist — the
  open entity, or for a collection the selected member's `:movie`-shaped
  subject (the same subject the view controls render, via
  `member_view/2`, so the button and the action can never disagree).

  No assign update: hosts carry `:watchlisted_refs` via `WatchlistAware`,
  refreshed by the Discovery broadcast. No-op when the subject carries no
  TMDB id (the toggle isn't rendered then).
  """
  @spec toggle_watchlist(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def toggle_watchlist(socket) do
    subject = watchlist_subject(socket.assigns.selected_entry, socket.assigns.selected_member_id)

    case watchlist_ref(subject) do
      nil ->
        socket

      {tmdb_id, media_type} ->
        if MapSet.member?(socket.assigns.watchlisted_refs, {tmdb_id, media_type}) do
          Discovery.remove_from_watchlist(tmdb_id, media_type)
        else
          # No poster_path on purpose: library subjects don't carry a TMDB
          # poster path — artwork arrives via Discovery's async TmdbArtwork.ensure.
          Discovery.add_to_watchlist(
            Title.new!(%{
              tmdb_id: tmdb_id,
              media_type: media_type,
              name: subject.name,
              year: watchlist_year(subject[:date_published]),
              release_date: subject[:date_published],
              overview: subject[:description]
            })
          )
        end

        socket
    end
  end

  @doc """
  Whether the modal's watchlist subject is on the watchlist — the state
  the view controls' bookmark toggle renders. Resolves the subject
  exactly as `toggle_watchlist/1` does.
  """
  @spec watchlisted?(map() | nil, Ecto.UUID.t() | nil, MapSet.t()) :: boolean()
  def watchlisted?(selected_entry, selected_member_id, watchlisted_refs) do
    case watchlist_ref(watchlist_subject(selected_entry, selected_member_id)) do
      nil -> false
      ref -> MapSet.member?(watchlisted_refs, ref)
    end
  end

  # The entity the watchlist toggle acts on: the open entity, except in a
  # collection, where it is the selected member's subject (UIDR-023 —
  # downstream components never learn a collection is involved).
  defp watchlist_subject(nil, _member_id), do: nil

  defp watchlist_subject(%CollectionDetail{} = entry, member_id) do
    case member_view(entry, member_id) do
      %{subject: subject} -> subject
      nil -> nil
    end
  end

  defp watchlist_subject(entry, _member_id), do: entry.entity

  # `{tmdb_id, media_type}` for a watchlist-eligible subject, nil
  # otherwise. `:movie` / `:tv_series` map 1:1 onto Discovery's media_type
  # vocabulary. The subject's tmdb_id is a string on `DetailItem`
  # entity maps and an integer on collection-member projections —
  # normalized to the integer Discovery keys on.
  defp watchlist_ref(%{type: type, tmdb_id: tmdb_id})
       when type in [:movie, :tv_series] and not is_nil(tmdb_id) do
    {normalize_tmdb_id(tmdb_id), type}
  end

  defp watchlist_ref(_subject), do: nil

  defp normalize_tmdb_id(tmdb_id) when is_integer(tmdb_id), do: tmdb_id
  defp normalize_tmdb_id(tmdb_id) when is_binary(tmdb_id), do: String.to_integer(tmdb_id)

  defp watchlist_year(%Date{year: year}), do: Integer.to_string(year)
  defp watchlist_year(_date), do: nil

  # Replace the open entry's `:track_override` in place. Surgical so we
  # don't reload (and thereby downgrade) a composed `%SeriesDetail{}`
  # entry to a plain map — both the modal-entry map and the SeriesDetail
  # struct expose `:entity`, so `%{entry | entity: …}` works on either.
  defp put_entry_track_override(%{assigns: %{selected_entry: entry}} = socket, override)
       when not is_nil(entry) do
    entity = Map.put(entry.entity, :track_override, override)
    Phoenix.Component.assign(socket, :selected_entry, %{entry | entity: entity})
  end

  defp put_entry_track_override(socket, _override), do: socket

  @doc false
  def toggle_watch_progress(entity_id, container_type, container_id) do
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
      "toggled completed — was #{completion_percentage(progress)} through (#{Format.format_seconds(progress.position_seconds)} of #{Format.format_seconds(progress.duration_seconds)})"
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

  @doc false
  def toggle_extra_watched(entity_id, extra_id) do
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

  @doc """
  Maps a `Pipeline.ImageRefresh.enqueue_refresh/2` result to a
  `{flash_level, message}` pair for the detail-panel Refresh-artwork action.
  """
  def refresh_artwork_flash({:ok, _job}), do: {:info, "Refreshing artwork from TMDB…"}
  def refresh_artwork_flash({:error, :no_tmdb_id}), do: {:error, "No TMDB match — Rematch first."}
  def refresh_artwork_flash({:error, _reason}), do: {:error, "Couldn't start artwork refresh."}

  @doc false
  # Loads the watched-files list for an entity and stats each path. The
  # stats run in parallel under `Task.async_stream` with a short
  # per-file timeout — a stale network mount can take seconds to fail
  # `File.stat/1`, and the synchronous-per-file path made that the
  # bound on the whole list. Per-call concurrency is small (8) because
  # the bottleneck is filesystem latency, not CPU.
  def load_entity_files(entity_id) do
    entity_id
    |> Library.Files.list_by_entity_id()
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

  # Owned async (ADR-049): the file-info load runs under the host LiveView
  # via start_async/3 so handle_params returns immediately, the task is
  # cancelled with the LiveView, and tests can await it. Result lands in
  # the injected `handle_async({:detail_files, entity_id}, …)` clause,
  # which calls `apply_detail_files/3`.
  defp start_async_files_load(socket, entity_id) do
    Phoenix.LiveView.start_async(socket, {:detail_files, entity_id}, fn ->
      load_entity_files(entity_id)
    end)
  end

  @doc false
  # Applies a deferred file-info load result, but only if the same entity is
  # still selected — the user may have switched entities while the load was
  # in flight.
  def apply_detail_files(socket, entity_id, files) do
    if socket.assigns[:selected_entity_id] == entity_id do
      Phoenix.Component.assign(socket, :detail_files, files)
    else
      socket
    end
  end

  @doc false
  def run_delete(%{delete_confirm: delete_confirm, detail_files: detail_files, media_dirs: media_dirs}) do
    case delete_confirm do
      {:file, file_path} ->
        FileEventHandler.delete_file(file_path)

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
          FileEventHandler.delete_folder(folder_path, file_paths)
        else
          {:error, "folder also contains other library content"}
        end

      :all ->
        payload =
          ManagePanel.build_delete_all_payload(
            detail_files,
            MapSet.new(media_dirs)
          )

        Enum.each(payload.file_groups, fn group ->
          file_paths = Enum.map(group.files, & &1.path)

          if !group.is_media_dir and
               MediaCentaur.DeleteTargets.safe_to_delete_folder?(group.dir, file_paths) do
            FileEventHandler.delete_folder(group.dir, file_paths)
          else
            # A media directory root, or a folder that also holds other
            # already-imported content, can't be `rm -rf`'d wholesale — fall
            # back to deleting just this entity's own files in it.
            FileEventHandler.delete_files(file_paths)
          end
        end)

        {:ok, []}

      nil ->
        {:ok, []}
    end
  end

  @doc """
  Kicks off the pending delete in `socket.assigns.delete_confirm` as an
  owned async task (ADR-049) instead of running it inline.

  Deleting an entity's files is `File.rm`/`File.rm_rf` plus a per-file DB
  cleanup cascade — for a large entity (dozens of files / tens of GB, or
  any file on a network mount) that is seconds of blocking work. Run
  inline it froze the LiveView process: clicks queued behind it and the
  client heartbeat timed out, dropping the socket and reconnecting (it
  looked like the app crashed). The read path (`load_entity_files/1`,
  `File.stat` per file) was already deferred for the same reason — this
  closes the gap on the destructive write path.

  Clears `delete_confirm`, marks `deleting` with the target so the
  matching button shows "Deleting…" and all delete buttons disable, and
  hands the actual deletion to `start_async/3`. The result lands in
  `handle_async({:delete, id}, …)` → `apply_delete_result/3`.

  Public only so the macro-injected handlers can call it; not part of
  the host contract.
  """
  def run_pending_delete(socket) do
    entity_id = socket.assigns.selected_entity_id
    target = socket.assigns.delete_confirm
    delete_args = Map.take(socket.assigns, [:delete_confirm, :detail_files, :media_dirs])

    socket =
      socket
      |> Phoenix.Component.assign(delete_confirm: nil, deleting: target)
      |> Phoenix.LiveView.start_async({:delete, entity_id}, fn -> run_delete(delete_args) end)

    {:noreply, socket}
  end

  @doc """
  Applies the result of the async delete task: clears the `deleting`
  flag, then closes the modal if the entity has no files left on disk or
  refreshes the file list if some remain. Surfaces `{:error, reason}` as
  a flash. Returns a socket (the macro-injected `handle_async` wraps it).
  """
  def apply_delete_result(socket, entity_id, result) do
    socket = Phoenix.Component.assign(socket, deleting: nil)

    case result do
      {:ok, _entity_ids} ->
        if MediaCentaur.Library.Files.list_by_entity_id(entity_id) == [] do
          Phoenix.LiveView.push_patch(socket,
            to: socket.view.build_modal_path(socket, %{selected: nil, view: :main})
          )
        else
          Phoenix.Component.assign(socket, detail_files: load_entity_files(entity_id))
        end

      {:error, reason} ->
        Log.warning(:library, "delete failed — #{inspect(reason)}")
        Phoenix.LiveView.put_flash(socket, :error, "Delete failed: #{reason}")
    end
  end

  @doc """
  Handles a crashed delete task (`{:exit, reason}`): clears the
  `deleting` flag, logs, and flashes so the modal recovers instead of
  staying stuck on "Deleting…".
  """
  def apply_delete_crash(socket, reason) do
    Log.error(:library, "delete task crashed — #{inspect(reason)}")

    socket
    |> Phoenix.Component.assign(deleting: nil)
    |> Phoenix.LiveView.put_flash(:error, "Delete failed")
  end

  # --- Private helpers ---

  @doc """
  The `detail_view` atom a `?view=` URL value names. Anything unrecognised
  falls to `:main`, which `resolve_view/2` then narrows to something the
  entity can actually render.
  """
  @spec parse_view(String.t() | nil) :: atom()
  def parse_view("info"), do: :info
  def parse_view("cast"), do: :cast
  def parse_view(_), do: :main

  defp load_entry_or_nil(id) do
    case load_entry(id) do
      {:ok, entry} -> entry
      :not_found -> nil
    end
  end

  # The single loader both the fresh open (`load_entry_or_nil/1`) and
  # the post-mutation refresh (`refresh_selected_entry/1`) go through, so
  # the two paths can never disagree on an entry's shape. The container
  # kind is resolved exactly once (`Library.Presentable.resolve/1` — the
  # same hoist authority every read surface consults) and dispatched to
  # the matching composer: TV becomes a `%SeriesDetail{}`, a collection a
  # `%CollectionDetail{}` — typed content lists + cached `releases` — and
  # leaf kinds (movie / video_object) stay the
  # `%{entity, progress, progress_records, resume_target}` map from
  # `ModalEntry.load_resolved/2` (leaves have no content list to type).
  # All shapes carry the same fields the modal renderer reads, so the
  # template doesn't branch on entry type — but the renderer reads the
  # content lists *only* off the composed structs. When refresh loaded a
  # series via the plain-map loader instead, that list silently dropped
  # and the modal's episode list vanished after a player close.
  defp load_entry(id) do
    case Library.Presentable.resolve(id) do
      {:tv_series, resolved_id} ->
        SeriesDetail.compose(resolved_id)

      {:movie_series, resolved_id} ->
        CollectionDetail.compose(resolved_id)

      {kind, resolved_id} ->
        case Library.ModalEntry.load_resolved(kind, resolved_id) do
          {:ok, entry} -> {:ok, put_resume_target(entry)}
          :not_found -> :not_found
        end

      :not_found ->
        :not_found
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
        MediaCentaur.ReleaseTracking.tracking_status({tmdb_id, media_type})

      nil ->
        nil
    end
  end
end
