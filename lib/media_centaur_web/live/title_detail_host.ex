defmodule MediaCentaurWeb.Live.TitleDetailHost do
  @moduledoc """
  The host of the title detail modal (UIDR-043) — one trait for every
  LiveView that opens a title: it owns the URL, the open `Title.Detail`
  and `Title.ModalState`, every event of the modal, the owned asyncs,
  and the subscriptions that keep an open detail honest. `DiscoveryLive`
  and `IncomingLive` `use` it; Home and Library follow.

  ## Host contract

  `use MediaCentaurWeb.Live.TitleDetailHost` registers an `on_mount`
  that declares the modal's topics through `Live.Subscriptions`, seeds
  `:title_detail`, `:modal_state`, `:title_opening` and
  `:title_playback`, and attaches four lifecycle hooks:

  | Hook | Does |
  |---|---|
  | `:handle_params` | opens, refreshes or closes the modal from `?title=<ref>` (`TitleRef`) with `view` and `activity`, or from `?entity=<uuid>` — canonicalised to the title address when the entity has a TMDB identity, else the residue |
  | `:handle_event` | every modal control, halting: `open_title`, `select_entity`, `close_title`, `select_detail_view`, `set_rung`, `reset_lower_quality`, `review_open`, `download`, `download_mode_toggle`, `download_scope_toggle`, `download_menu_close`, `download_scope`, `activity_delete`, `refresh_from_tmdb`, and the library sections' (`LibraryEvents.events/0`) |
  | `:handle_async` | the fetched open, the live preview, the manual plan, the missing-episode plan, the file-info load, the delete and the TMDB check — each landing by subject and dropped when the person moved on |
  | `:handle_info` | refreshes the open detail by identity on the topics below, then continues so the host's own clauses run |
  | `use ReviewFlow` | injects the Review modal's own controls; `review_open` opens it on the detail's title |

  A host that `use`s this module must not also `use` `EntityModal`: both
  inject `ReviewFlow`. Beyond the `use`, the host implements three
  callbacks:

  * `page_facts/3` — what this page alone holds about a ref: an
    in-memory snapshot when it has one (an omnibox result, a plan's
    subject, a feed activity's title). `{nil, %{}}` when it knows
    nothing, which is never a reason not to open. Every other fact —
    the activity the modal speaks for included — is read by identity.
  * `title_detail_path/2` — the page's own path with the modal query
    applied (`[]` closes), so leaving the modal never changes tab.
  * `open_plan_board/2` — navigates to Incoming with the plan's board
    open (`push_navigate` from another page, `push_patch` on Incoming
    itself).

  and keeps `:today`, `:spoiler_free`, `:letterboxd_links`,
  `:tmdb_ready` and `:show_discovery` assigns (the settings traits and
  the router's `CapabilitiesAware`), which the panel reads.

  ## Resolving a title

  The modal's subject is a TMDB identity, and the snapshot it opens from
  is resolved here by that identity, in order: the open detail's own; the
  title intent's embedded snapshot (`Discovery.get_intent/2` — any title
  on the ladder, listed, ignored or tracked); the owner's entity when the
  library owns the title (`Logic.snapshot_from_entity/1`); the activity
  the modal was opened from; the page's in-memory copy; and TMDB itself,
  fetched asynchronously, for a deep link to a title nothing here holds.
  The facts — the library half (`LibraryHalf`), rung, acquisition state,
  artwork, the tracked-title half (`TrackingDetail`), friend activity for
  the pennants, the activity the modal speaks for (`Activities.get_row/1`,
  from the `activity` param), the intent's note — are read from their
  owning contexts by the same identity: local reads, milliseconds
  (ADR-051). An open detail is never closed by the lists changing
  beneath it (`refresh_title_detail/1`); closing is an explicit act.

  ## Subscriptions

  Declared through the one door, so a page declaring the same topic for
  its own rows subscribes once:

  | Topic | Reaction |
  |---|---|
  | `library:updates`, `library:views`, `library:availability` | re-resolve the owner by ref (an import can make an open unowned title owned); reload the half |
  | `playback:events` | in-memory merges by container id; the playing set for delete protection |
  | `release_tracking:updates`, `discovery:updates`, `activities:updates`, `acquisition:updates` | rebuild the detail's facts by identity |

  ## Setting a rung

  `set_rung` is the modal's one intent event: listing, following and
  stopping are one ladder (UIDR-042), written through
  `Acquisition.apply_rung/4`.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3, update: 3]
  import Phoenix.LiveView
  import MediaCentaurWeb.LiveHelpers, only: [image_url: 2, title_poster_url: 1, tmdb_cdn_url: 2]

  alias MediaCentaur.Acquisition.{DownloadParams, PlanEvents, TitleStates}
  alias MediaCentaur.Acquisition.TitleDownloadParams
  alias MediaCentaur.Activities
  alias MediaCentaur.Capabilities
  alias MediaCentaur.Discovery
  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.Library
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Settings.Preferences.PlanningMode
  alias MediaCentaur.TMDB.ReleaseWindow
  alias MediaCentaur.TMDB.Store
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.TmdbArtwork
  alias MediaCentaurWeb.Components.Detail.Logic, as: DetailLogic
  alias MediaCentaurWeb.Components.Detail.TitlePreview
  alias MediaCentaurWeb.Components.ReleaseTracking.TrackingDetail
  alias MediaCentaurWeb.Components.Title.Detail, as: TitleDetail
  alias MediaCentaurWeb.Components.Title.Logic
  alias MediaCentaurWeb.Components.Title.ModalState
  alias MediaCentaurWeb.DiscoveryLive.ActivityWords
  alias MediaCentaurWeb.Live.PlanFlow
  alias MediaCentaurWeb.Live.ReviewFlow
  alias MediaCentaurWeb.Live.Subscriptions
  alias MediaCentaurWeb.Live.TitleDetailHost.Acquisition
  alias MediaCentaurWeb.Live.TitleDetailHost.LibraryEvents
  alias MediaCentaurWeb.Live.TitleDetailHost.TmdbEvents
  alias MediaCentaurWeb.Live.TitleDetailHost.LibraryHalf
  alias MediaCentaurWeb.TitleRef
  alias MediaCentaurWeb.ViewModel.Orientation
  alias MediaCentaurWeb.ViewModel.SeriesDetail

  import MediaCentaur.Acquisition.Pursuits.Events, only: [is_event: 1]

  require MediaCentaur.Log, as: Log

  @callback page_facts(socket :: Phoenix.LiveView.Socket.t(), TitleRef.ref(), params :: map()) ::
              {snapshot :: Title.t() | nil, facts :: map()}

  @callback title_detail_path(socket :: Phoenix.LiveView.Socket.t(), query :: keyword()) ::
              String.t()

  @callback open_plan_board(socket :: Phoenix.LiveView.Socket.t(), plan_id :: Ecto.UUID.t()) ::
              Phoenix.LiveView.Socket.t()

  @modal_events ~w(download_mode_toggle download_scope_toggle download_menu_close download_scope download activity_delete review_open select_detail_view refresh_from_tmdb)
  @library_events LibraryEvents.events()
  @rungs ~w(off list follow grab)

  @topics [
    Library,
    Library.Views,
    MediaCentaur.Playback,
    ReleaseTracking,
    Activities,
    MediaCentaur.Acquisition,
    Discovery,
    Store
  ]

  defmacro __using__(_opts) do
    quote do
      @behaviour MediaCentaurWeb.Live.TitleDetailHost

      use MediaCentaurWeb.Live.ReviewFlow

      on_mount {MediaCentaurWeb.Live.TitleDetailHost, :default}
    end
  end

  def on_mount(:default, _params, _session, socket) do
    socket =
      @topics
      |> Enum.reduce(socket, &Subscriptions.subscribe(&2, &1))
      |> assign(
        title_detail: nil,
        modal_state: ModalState.new(),
        title_opening: nil,
        title_playback: %{}
      )
      |> ReviewFlow.init()
      |> attach_hook(:title_detail_params, :handle_params, &apply_title_params/3)
      |> attach_hook(:title_detail_events, :handle_event, &handle_title_event/3)
      |> attach_hook(:title_detail_async, :handle_async, &handle_title_async/3)
      |> attach_hook(:title_detail_pubsub, :handle_info, &handle_title_info/2)

    {:cont, socket}
  end

  # --- URL ---

  # `?title=<media_type>-<tmdb_id>` drives the modal: back closes, refresh
  # keeps it, the URL is shareable. `&view=` names the sub-view and
  # `&activity=<id>` the act a person card opened it from. `?entity=<uuid>`
  # is the residue's address and what an entity emitter hands the host:
  # it canonicalises to the title address when the entity has a TMDB
  # identity. A malformed or unknown param names nothing to open.
  def apply_title_params(%{"title" => param} = params, _uri, socket) do
    case TitleRef.parse(param) do
      {:ok, ref} -> {:cont, open_title(socket, ref, params)}
      :error -> {:cont, close(socket)}
    end
  end

  def apply_title_params(%{"entity" => id} = params, _uri, socket),
    do: {:cont, open_entity(socket, id, params)}

  def apply_title_params(_params, _uri, socket), do: {:cont, close(socket)}

  defp open_title(socket, ref, params) do
    {page_snapshot, facts} = socket.view.page_facts(socket, ref, params)
    library = LibraryHalf.load(ref)
    activity = activity_for(ref, params)
    facts = Map.merge(facts, %{library: library, activity: activity})

    case snapshot(socket, ref, library, activity, page_snapshot) do
      %Title{} = title -> open_from_snapshot(socket, ref, title, facts, params)
      nil -> open_from_tmdb(socket, ref)
    end
  end

  defp open_entity(socket, id, params) do
    case LibraryHalf.load_entity(id) do
      nil ->
        abandon_open(socket, "That title is no longer in the library.")

      library ->
        case Library.EntityView.title_ref(library.subject) do
          {_tmdb_id, _media_type} = ref -> canonicalise(socket, ref, library, params)
          nil -> open_residue(socket, id, library, params)
        end
    end
  end

  # A re-patch of the open residue keeps its files and may change the
  # view; another entity takes the modal.
  defp open_residue(
         %{assigns: %{title_detail: %TitleDetail{ref: nil} = open}} = socket,
         id,
         library,
         params
       ) do
    if LibraryHalf.subject(open) == {:entity, id} do
      detail = build_residue(socket, LibraryHalf.keep_files(library, open.library))

      socket
      |> assign(:title_detail, detail)
      |> update(:modal_state, &%{&1 | view: resolve_view(detail, params["view"])})
    else
      open_from_detail(socket, {:entity, id}, build_residue(socket, library), params)
    end
  end

  defp open_residue(socket, id, library, params),
    do: open_from_detail(socket, {:entity, id}, build_residue(socket, library), params)

  # A titled entity opens on its title address. The patch needs a live
  # socket; the dead render opens the title in place from the half it
  # already holds, and the join's params patch the URL.
  defp canonicalise(socket, ref, library, params) do
    if connected?(socket) do
      push_patch(socket, to: path(socket, [title: TitleRef.param(ref)] ++ view_query(params)))
    else
      title = snapshot(socket, ref, library, nil, nil)
      open_from_snapshot(socket, ref, title, %{library: library, activity: nil}, params)
    end
  end

  # The snapshot a ref opens from, by identity: the open detail's own,
  # then the TMDB store's (any title the app holds a reference to), then
  # the owner's entity, then the activity's embedded title, then the
  # page's in-memory copy. Nil leaves TMDB as the one source.
  defp snapshot(
         %{assigns: %{title_detail: %TitleDetail{ref: ref, title: title}}},
         ref,
         _library,
         _activity,
         _page_snapshot
       ), do: title

  defp snapshot(_socket, ref, library, activity, page_snapshot) do
    Store.snapshot(ref) || entity_snapshot(library) || activity_snapshot(activity) || page_snapshot
  end

  defp entity_snapshot(%{subject: subject}), do: Logic.snapshot_from_entity(subject)
  defp entity_snapshot(nil), do: nil

  defp activity_snapshot(%{activity: %{title: %Title{} = title}}), do: title
  defp activity_snapshot(_none), do: nil

  # The activity the modal speaks for, by identity — and only for the
  # open title: a link naming another title's activity says nothing.
  defp activity_for(ref, %{"activity" => id}) when is_binary(id) do
    case Activities.get_row(id) do
      %{activity: %{tmdb_id: tmdb_id, media_type: media_type}} = row when {tmdb_id, media_type} == ref ->
        row

      _other ->
        nil
    end
  end

  defp activity_for(_ref, _params), do: nil

  defp activity_params(%TitleDetail{activity: %{activity: %{id: id}}}), do: %{"activity" => id}
  defp activity_params(_detail), do: %{}

  # A re-patch of the open title keeps its preview and its files and may
  # change the view; another title takes the modal.
  defp open_from_snapshot(
         %{assigns: %{title_detail: %TitleDetail{ref: ref} = open}} = socket,
         ref,
         title,
         facts,
         params
       ) do
    facts = Map.update!(facts, :library, &LibraryHalf.keep_files(&1, open.library))
    detail = build_detail(socket, title, facts, open.preview)

    socket
    |> assign(:title_detail, detail)
    |> update(:modal_state, &%{&1 | view: resolve_view(detail, params["view"])})
  end

  defp open_from_snapshot(socket, ref, title, facts, params) do
    detail = build_detail(socket, title, facts, nil)
    socket |> open_from_detail({:title, ref}, detail, params) |> fetch_preview(title)
  end

  # Another title takes the modal: whatever was open or opening is
  # dropped, the per-opening state starts fresh (the series' oriented
  # season expanded), and the owned title's files start loading.
  # A switch to another member of the open collection is the same
  # document (UIDR-023): the state stays, the view follows the params.
  defp open_from_detail(socket, subject, detail, params) do
    view = resolve_view(detail, params["view"])

    if same_document?(socket.assigns.title_detail, detail) do
      library = LibraryHalf.keep_files(detail.library, socket.assigns.title_detail.library)

      socket
      |> cancel_opening()
      |> assign(:title_detail, %{detail | library: library})
      |> update(:modal_state, &%{&1 | view: view})
    else
      socket
      |> reset_detail()
      |> assign(:title_detail, detail)
      |> assign(:modal_state, ModalState.new(view, initial_expanded_seasons(detail)))
      |> start_files_load(subject, detail)
    end
  end

  defp same_document?(%TitleDetail{library: %{}} = open, %TitleDetail{library: %{}} = next),
    do: LibraryHalf.container_id(open) == LibraryHalf.container_id(next)

  defp same_document?(_open, _next), do: false

  defp start_files_load(socket, subject, %TitleDetail{library: %{}} = detail),
    do: LibraryHalf.start_files_load(socket, subject, LibraryHalf.container_id(detail))

  defp start_files_load(socket, _subject, _unowned), do: socket

  # A fetch already under way for the ref is left to land. Otherwise the
  # fetch starts, once connected — the dead render has no process for it
  # to answer to. What stands in the way (no TMDB key, no such title, TMDB
  # not answering) is the fetch's result: flashed, and the param dropped,
  # by the one result handler.
  defp open_from_tmdb(%{assigns: %{title_opening: ref}} = socket, ref), do: socket

  defp open_from_tmdb(socket, ref) do
    socket = reset_detail(socket)

    if connected?(socket) do
      socket
      |> assign(:title_opening, ref)
      |> start_async({:title_open, ref}, fn -> fetch_title(ref) end)
    else
      socket
    end
  end

  defp reset_detail(socket) do
    socket
    |> cancel_opening()
    |> assign(title_detail: nil, modal_state: ModalState.new())
  end

  # Closing also abandons a manual plan being created: the person left, so
  # nobody should be taken to its board.
  defp close(socket) do
    socket
    |> cancel_pending_download()
    |> reset_detail()
  end

  defp cancel_opening(%{assigns: %{title_opening: nil}} = socket), do: socket

  defp cancel_opening(%{assigns: %{title_opening: ref}} = socket),
    do: socket |> cancel_async({:title_open, ref}) |> assign(:title_opening, nil)

  defp cancel_pending_download(
         %{assigns: %{title_detail: %TitleDetail{ref: ref}, modal_state: state}} = socket
       ) do
    case state.pending do
      {:download, name} -> cancel_async(socket, {:title_download, ref, name})
      _none -> socket
    end
  end

  defp cancel_pending_download(socket), do: socket

  # The view a `?view=` value resolves to for the open detail: only the
  # views the subject has, and only an owned title has any.
  defp resolve_view(%TitleDetail{library: nil}, _requested), do: :main

  defp resolve_view(%TitleDetail{library: library}, requested),
    do: DetailLogic.resolve_view(DetailLogic.controls_entity(library), parse_view(requested))

  defp parse_view("info"), do: :info
  defp parse_view("cast"), do: :cast
  defp parse_view(_main), do: :main

  # The season holding the next episode opens expanded, from the same
  # `Orientation` the hero hairline reads, so the two cannot disagree.
  defp initial_expanded_seasons(%TitleDetail{
         library: %{entry: %SeriesDetail{seasons: seasons, resume_target: resume}}
       }) do
    seasons |> Orientation.for_series(resume) |> Orientation.initial_expanded_seasons()
  end

  defp initial_expanded_seasons(_detail), do: MapSet.new()

  @doc """
  Rebuilds the open detail from current facts (a rung moved, a plan
  landed, a friend's act arrived, an import made the title owned). An
  open detail is never closed by a refresh: it keeps its own snapshot,
  its files and its preview, and re-reads the facts the contexts hold by
  identity — so when the bookmark takes the title off the list, or Off
  deletes the tracked title, the control that removed it is still there
  to undo it. Closing is an explicit act. The residue re-reads its
  entity, and closes only when the entity is gone. A no-op while closed.
  """
  @spec refresh_title_detail(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def refresh_title_detail(%{assigns: %{title_detail: nil}} = socket), do: socket

  def refresh_title_detail(
        %{assigns: %{title_detail: %TitleDetail{ref: nil, library: library}}} = socket
      ) do
    case LibraryHalf.reload(library) do
      nil -> push_close(socket)
      reloaded -> assign(socket, :title_detail, build_residue(socket, reloaded))
    end
  end

  def refresh_title_detail(%{assigns: %{title_detail: %TitleDetail{} = detail}} = socket) do
    params = activity_params(detail)
    {_page_snapshot, facts} = socket.view.page_facts(socket, detail.ref, params)
    library = detail.ref |> LibraryHalf.load() |> LibraryHalf.keep_files(detail.library)
    facts = Map.merge(facts, %{library: library, activity: activity_for(detail.ref, params)})
    refreshed = build_detail(socket, detail.title, facts, detail.preview)
    socket = assign(socket, :title_detail, refreshed)

    # An import landed while the title was open: the files start loading.
    if is_nil(detail.library) and library,
      do: start_files_load(socket, {:title, detail.ref}, refreshed),
      else: socket
  end

  # The facts, from the contexts that own them, by identity. The library
  # half and the activity arrive in `given` when the caller has already
  # read them; the rest is read here. An owned title dresses itself from
  # the library's images; an unowned one from the artwork cache and the
  # snapshot's paths.
  defp build_detail(socket, %Title{} = title, given, preview) do
    ref = Title.ref(title)
    library = Map.get_lazy(given, :library, fn -> LibraryHalf.load(ref) end)
    artwork = TmdbArtwork.urls(title.media_type, title.tmdb_id)
    acquisition? = Capabilities.acquisition_ready?()
    planning_mode = PlanningMode.value()
    today = socket.assigns.today

    facts = %{
      library: library,
      activity: Map.get(given, :activity),
      rung: Discovery.rung(title.tmdb_id, title.media_type),
      lower_quality_accepted?:
        DownloadParams.lower_quality_accepted?(TitleDownloadParams.get(title.tmdb_id, title.media_type)),
      acquisition_state: Map.get(TitleStates.for_refs([ref]), ref),
      release_mode_available: Capabilities.prowlarr_ready?(),
      poster_url: library_image(library, "poster") || title_poster_url(title),
      backdrop_url:
        library_image(library, "backdrop") || artwork.backdrop_url ||
          tmdb_cdn_url(title.backdrop_path, :w1280),
      logo_url: library_image(library, "logo") || artwork.logo_url,
      tracking:
        TrackingDetail.load(ref, %{
          today: today,
          acquisition_ready?: acquisition?,
          approval_policy: PlanningMode.approval_policy(planning_mode)
        }),
      acquisition?: acquisition?,
      complete?: ReleaseTracking.complete?(title.tmdb_id, title.media_type),
      release_window: nil,
      planning_mode: planning_mode,
      friend_activity: Map.get(Activities.friend_activity_for([ref]), ref, []),
      intent_note: intent_note(ref),
      preview: preview
    }

    Logic.title_detail(title, facts)
  end

  # The residue: an owned entity with no TMDB identity has the library
  # half as its one fact.
  defp build_residue(_socket, library) do
    Logic.title_detail(nil, %{
      library: library,
      rung: nil,
      acquisition_state: nil,
      release_mode_available: false,
      acquisition?: Capabilities.acquisition_ready?(),
      planning_mode: PlanningMode.value()
    })
  end

  # The library's image ladder (UIDR-021): the subject's art, then the
  # container's — a collection member rarely carries its own backdrop.
  defp library_image(nil, _role), do: nil

  defp library_image(%{subject: subject, entry: %{entity: entity}}, role),
    do: image_url(subject, role) || image_url(entity, role)

  # The person's own words on the record, or the review text copied in as
  # provenance when the title was listed from a friend's review.
  defp intent_note({tmdb_id, media_type}) do
    case Discovery.get_intent(tmdb_id, media_type) do
      %TitleIntent{note: note} -> note
      nil -> nil
    end
  end

  # The live preview runs as an owned async (cancelled with the view,
  # awaitable in tests); the modal reads the snapshot until it lands.
  # An owned title has no preview: its entity is the richer source.
  # Without a working TMDB key the snapshot is all there is.
  defp fetch_preview(socket, %Title{} = title) do
    if Capabilities.tmdb_ready?() and is_nil(socket.assigns.title_detail.library) do
      ref = Title.ref(title)
      today = socket.assigns.today
      start_async(socket, {:title_preview, ref}, fn -> load_preview(title, today) end)
    else
      socket
    end
  end

  defp load_preview(%Title{} = title, today) do
    with {:ok, payload} <- fetch_payload(Title.ref(title)),
         do: {:ok, preview_from_payload(title, payload, today)}
  end

  # A deep link to a title no row knows: the detail payload is both the
  # snapshot the modal opens from and the preview that dresses it, so one
  # fetch serves both. TMDB's 404 is "no such title"; a payload without an
  # identity or a name is reported the same way.
  defp fetch_title({_tmdb_id, media_type} = ref) do
    with :ok <- tmdb_ready(),
         {:ok, payload} <- fetch_payload(ref),
         {:ok, %Title{} = title} <- Title.from_tmdb(payload, media_type) do
      {:ok, {title, payload}}
    else
      {:error, {:http_error, 404, _body}} -> {:error, :not_found}
      {:error, %Ecto.Changeset{}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp tmdb_ready, do: if(Capabilities.tmdb_ready?(), do: :ok, else: {:error, :tmdb_not_ready})

  # The stored title (ADR-071): a request only for a title the store has
  # never held. TMDB's 404 surfaces from that first contact as before.
  defp fetch_payload(ref) do
    with {:ok, %{payload: payload}} <- Store.ensure(ref), do: {:ok, payload}
  end

  # The movie payload also says where the film stands in its release
  # sequence — the fact that decides whether there is a release to track.
  defp preview_from_payload(%Title{media_type: :movie}, movie, today),
    do: {TitlePreview.movie(movie, false), ReleaseWindow.from_payload(movie, today)}

  defp preview_from_payload(%Title{media_type: :tv_series}, show, _today),
    do: {TitlePreview.tv(show, false), nil}

  # --- Asyncs ---

  # A result for a plan the person walked away from — the cancel's own
  # exit, or a reply already queued when the modal closed — is dropped.
  def handle_title_async({:title_download, _ref, name}, result, socket) do
    if Acquisition.pending?(socket, {:download, name}),
      do: {:halt, land_download(socket, name, result)},
      else: {:halt, socket}
  end

  # The fetched open. A result for a ref the person has moved on from — the
  # URL dropped it, or names another title — is dropped with it, the
  # cancel's own exit included.
  def handle_title_async({:title_open, ref}, _result, %{assigns: %{title_opening: opening}} = socket)
      when opening != ref, do: {:halt, socket}

  def handle_title_async({:title_open, ref}, {:ok, {:ok, {%Title{} = title, payload}}}, socket) do
    detail = build_detail(socket, title, %{}, nil)
    {preview, window} = preview_from_payload(title, payload, socket.assigns.today)
    detail = if detail.library, do: detail, else: %{detail | preview: preview, release_window: window}

    {:halt,
     socket
     |> assign(:title_opening, nil)
     |> open_from_detail({:title, ref}, detail, %{})}
  end

  def handle_title_async({:title_open, _ref}, {:ok, {:error, :tmdb_not_ready}}, socket),
    do: {:halt, socket |> assign(:title_opening, nil) |> abandon_open(tmdb_needed_flash())}

  def handle_title_async({:title_open, ref}, {:ok, {:error, :not_found}}, socket),
    do: {:halt, socket |> assign(:title_opening, nil) |> abandon_open(no_such_title_flash(ref))}

  def handle_title_async({:title_open, ref}, {:ok, {:error, reason}}, socket) do
    Log.warning(:tmdb, "could not open #{TitleRef.param(ref)} from TMDB — #{inspect(reason)}")
    {:halt, socket |> assign(:title_opening, nil) |> abandon_open(tmdb_unreachable_flash())}
  end

  def handle_title_async({:title_open, ref}, {:exit, reason}, socket) do
    Log.warning(:tmdb, "opening #{TitleRef.param(ref)} from TMDB crashed — #{inspect(reason)}")
    {:halt, socket |> assign(:title_opening, nil) |> abandon_open(tmdb_unreachable_flash())}
  end

  def handle_title_async(
        {:title_preview, ref},
        {:ok, {:ok, {%TitlePreview{} = preview, window}}},
        socket
      ) do
    case socket.assigns.title_detail do
      %TitleDetail{ref: ^ref, library: nil} = detail ->
        {:halt, assign(socket, :title_detail, %{detail | preview: preview, release_window: window})}

      _closed_owned_or_other ->
        {:halt, socket}
    end
  end

  def handle_title_async({:refresh_from_tmdb, _ref}, {:ok, result}, socket) do
    {level, message} = TmdbEvents.check_flash(result)

    {:halt,
     socket
     |> update(:modal_state, &%{&1 | tmdb_checking: false})
     |> put_flash(level, message)
     |> refresh_title_detail()}
  end

  def handle_title_async({:refresh_from_tmdb, ref}, {:exit, reason}, socket) do
    Log.warning(:tmdb, "refresh from TMDB crashed for #{TitleRef.param(ref)} — #{inspect(reason)}")
    {level, message} = TmdbEvents.check_flash({:error, reason})

    {:halt,
     socket
     |> update(:modal_state, &%{&1 | tmdb_checking: false})
     |> put_flash(level, message)}
  end

  def handle_title_async({:title_preview, _ref}, {:ok, {:error, reason}}, socket) do
    Log.debug(:tmdb, "title preview unavailable — #{inspect(reason)}")
    {:halt, socket}
  end

  def handle_title_async({:title_preview, _ref}, {:exit, reason}, socket) do
    Log.warning(:tmdb, "title preview crashed — #{inspect(reason)}")
    {:halt, socket}
  end

  def handle_title_async({:detail_files, subject}, result, socket),
    do: {:halt, LibraryHalf.apply_files(socket, subject, result)}

  def handle_title_async({:delete, subject}, {:ok, result}, socket),
    do: {:halt, LibraryEvents.apply_delete_result(socket, subject, result)}

  def handle_title_async({:delete, _subject}, {:exit, reason}, socket),
    do: {:halt, LibraryEvents.apply_delete_crash(socket, reason)}

  def handle_title_async({:missing_episode, _subject, unit}, result, socket) do
    if Acquisition.pending?(socket, {:missing_episode, unit}),
      do: {:halt, land_missing_episode(socket, result)},
      else: {:halt, socket}
  end

  def handle_title_async(_name, _result, socket), do: {:cont, socket}

  defp land_download(socket, _name, {:ok, {:ok, plan}}) do
    socket = update(socket, :modal_state, &%{&1 | open_menu: nil})
    socket.view.open_plan_board(socket, plan.id)
  end

  defp land_download(socket, name, {:ok, {:error, reason}}) do
    Log.warning(:acquisition, "could not plan — #{name} — #{inspect(reason)}")
    socket |> Acquisition.pending(nil) |> put_flash(:error, PlanFlow.failure_flash(name, reason))
  end

  defp land_download(socket, name, {:exit, reason}) do
    Log.warning(:acquisition, "planning crashed — #{name} — #{inspect(reason)}")
    socket |> Acquisition.pending(nil) |> put_flash(:error, PlanFlow.failure_flash(name, :crashed))
  end

  defp land_missing_episode(socket, {:ok, result}),
    do: Acquisition.apply_missing_episode_result(socket, result)

  defp land_missing_episode(socket, {:exit, reason}),
    do: Acquisition.apply_missing_episode_crash(socket, reason)

  # --- PubSub ---

  def handle_title_info(message, socket), do: {:cont, react(message, socket)}

  # The playing set is kept while the modal is closed too: a delete
  # prompt must know about playback that started before the open.
  defp react({:playback_state_changed, %{entity_id: id, state: state, now_playing: now_playing}}, socket) do
    update(
      socket,
      :title_playback,
      &MediaCentaurWeb.LiveHelpers.apply_playback_change(&1, id, state, now_playing)
    )
  end

  defp react(_message, %{assigns: %{title_detail: nil}} = socket), do: socket

  defp react({:entity_progress_updated, %{entity_id: id} = payload}, socket),
    do: merge_into_half(socket, id, &LibraryHalf.merge_progress(&1, payload))

  defp react({:extra_progress_updated, %{entity_id: id} = payload}, socket),
    do: merge_into_half(socket, id, &LibraryHalf.merge_extra_progress(&1, payload))

  defp react({:track_override_changed, %{owner_type: type, owner_id: id}}, socket) do
    override = Library.MediaTrackOverrides.get(type, id)
    merge_into_half(socket, id, &LibraryHalf.put_track_override(&1, override))
  end

  # An import can make an open unowned title owned; a change to the owner
  # reloads its half.
  defp react({:entities_changed, %{entity_ids: ids}}, socket) do
    case LibraryHalf.container_id(socket.assigns.title_detail) do
      nil -> refresh_title_detail(socket)
      container_id -> if container_id in ids, do: refresh_title_detail(socket), else: socket
    end
  end

  # A drive mounting or unmounting arrives here too: the detail projection
  # patches `available?` in place on the availability event and announces
  # the change on `library:views`.
  defp react({:library_view_updated, :detail, _id}, socket), do: refresh_if_owned(socket)

  # The open title's stored record changed — a first contact landed, or a
  # check found something new: re-read the facts and the preview.
  defp react(
         {:tmdb_title_changed, ref},
         %{assigns: %{title_detail: %TitleDetail{ref: ref, title: %Title{} = title}}} = socket
       ), do: socket |> refresh_title_detail() |> fetch_preview(title)

  defp react({:tmdb_title_changed, _other_ref}, socket), do: socket

  defp react({tag, _payload}, socket)
       when tag in [
              :releases_updated,
              :item_removed,
              :title_intent_changed,
              :activity_received,
              :activity_sent,
              :activity_deleted
            ], do: refresh_title_detail(socket)

  defp react(%PlanEvents.Changed{}, socket), do: refresh_title_detail(socket)
  defp react(%struct{}, socket) when is_event(struct), do: refresh_title_detail(socket)
  defp react(_message, socket), do: socket

  defp refresh_if_owned(%{assigns: %{title_detail: %TitleDetail{library: nil}}} = socket), do: socket
  defp refresh_if_owned(socket), do: refresh_title_detail(socket)

  # A playback broadcast for the open container merges in memory; a
  # payload the merge cannot use asks for a reload.
  defp merge_into_half(socket, container_id, merge) do
    detail = socket.assigns.title_detail

    if LibraryHalf.container_id(detail) == container_id do
      case merge.(detail.library) do
        nil -> refresh_title_detail(socket)
        half -> assign(socket, :title_detail, %{detail | library: half})
      end
    else
      socket
    end
  end

  # --- Events ---

  def handle_title_event("open_title", %{"ref" => ref} = params, socket) do
    query =
      case params do
        %{"activity" => activity_id} -> [title: ref, activity: activity_id]
        _title_only -> [title: ref]
      end

    {:halt, push_patch(socket, to: path(socket, query))}
  end

  # An entity emitter — a card, a rail tile — hands an id; the host
  # resolves it to the title address, or the entity address for the
  # residue. Opening the open subject again is a no-op patch.
  def handle_title_event("select_entity", %{"id" => id}, socket) do
    query =
      case LibraryHalf.address(id) do
        {:title, ref, half} -> [title: TitleRef.param(ref)] ++ kept_view(socket, half)
        {:entity, entity_id, half} -> [entity: entity_id] ++ kept_view(socket, half)
        :not_found -> []
      end

    {:halt, push_patch(socket, to: path(socket, query))}
  end

  # BACK peels one level of containment: from a sub-view it returns to
  # the root view; from the root there is nothing above, so the modal
  # closes.
  def handle_title_event("close_title", _params, socket), do: {:halt, close_or_return(socket)}

  def handle_title_event(
        "select_detail_view",
        %{"view" => view},
        %{assigns: %{title_detail: %TitleDetail{} = detail}} = socket
      ),
      do:
        {:halt,
         push_patch(socket, to: path(socket, address_query(detail) ++ view_query(%{"view" => view})))}

  def handle_title_event(
        "download_mode_toggle",
        _params,
        %{assigns: %{title_detail: %TitleDetail{}}} = socket
      ), do: {:halt, update(socket, :modal_state, &%{&1 | open_menu: toggle_menu(&1.open_menu, :mode)})}

  def handle_title_event(
        "download_scope_toggle",
        _params,
        %{assigns: %{title_detail: %TitleDetail{}}} = socket
      ), do: {:halt, update(socket, :modal_state, &%{&1 | open_menu: toggle_menu(&1.open_menu, :scope)})}

  def handle_title_event(
        "download_menu_close",
        _params,
        %{assigns: %{title_detail: %TitleDetail{}}} = socket
      ), do: {:halt, update(socket, :modal_state, &%{&1 | open_menu: nil})}

  # A closed set, mapped explicitly: `String.to_existing_atom/1` would
  # depend on whether `DownloadScope` happens to be loaded yet.
  def handle_title_event(
        "download_scope",
        %{"choice" => choice},
        %{assigns: %{title_detail: %TitleDetail{}}} = socket
      )
      when choice in ~w(first_season everything) do
    scope = if choice == "everything", do: :everything, else: :first_season
    {:halt, update(socket, :modal_state, &%{&1 | download_scope: scope, open_menu: nil})}
  end

  # The main segment sends no mode (the person's default); the menu item
  # names the other one. A movie has one scope, so it sends none.
  def handle_title_event(
        "download",
        params,
        %{assigns: %{title_detail: %TitleDetail{} = detail}} = socket
      ) do
    mode =
      case params do
        %{"mode" => "auto_select_best_release"} -> :auto_select_best_release
        %{"mode" => "manually_select_release"} -> :manually_select_release
        _default -> detail.planning_mode
      end

    scope = if detail.title.media_type == :tv_series, do: socket.assigns.modal_state.download_scope

    socket =
      socket
      |> update(:modal_state, &%{&1 | open_menu: nil})
      |> Acquisition.start_download(detail.title, mode, scope)

    # Auto-select planned and flashed: the modal closes; a manual plan is
    # pending and the modal stays for its board.
    if mode == :auto_select_best_release, do: {:halt, push_close(socket)}, else: {:halt, socket}
  end

  def handle_title_event(
        "activity_delete",
        _params,
        %{
          assigns: %{
            title_detail: %TitleDetail{activity: %{activity: %{id: id, kind: kind}, own?: true}}
          }
        } = socket
      ) do
    case Activities.delete(id) do
      {:ok, _activity} ->
        {:halt,
         socket
         |> put_flash(:info, String.capitalize(ActivityWords.noun(kind)) <> " withdrawn")
         |> push_close()}

      {:error, _reason} ->
        {:halt, put_flash(socket, :error, "Only your own activity can be deleted")}
    end
  end

  def handle_title_event("set_rung", %{"choice" => choice, "ref" => param}, socket)
      when choice in @rungs do
    case title_for_param(socket, param) do
      %Title{} = title ->
        socket =
          Acquisition.apply_rung(
            socket,
            title,
            rung_atom(choice),
            provenance(socket.assigns.title_detail)
          )

        {:halt, refresh_title_detail(socket)}

      nil ->
        {:halt, socket}
    end
  end

  # The acceptance is keyed by TMDB identity, not by tracked title, so
  # resetting it neither needs nor touches one (ADR-063 §2) — but only
  # the open title's.
  def handle_title_event("reset_lower_quality", %{"ref" => param}, socket) do
    with {:ok, ref} <- TitleRef.parse(param),
         %TitleDetail{ref: ^ref} <- socket.assigns.title_detail do
      {tmdb_id, media_type} = ref
      {:ok, _params} = TitleDownloadParams.put(tmdb_id, media_type, %{min_quality: nil})
      {:halt, refresh_title_detail(socket)}
    else
      _stale_or_unknown -> {:halt, socket}
    end
  end

  # Refresh from TMDB (UIDR-044): one check of the open title, off the
  # view, for either surface; the result lands in `handle_title_async/3`.
  def handle_title_event("refresh_from_tmdb", %{"ref" => param}, socket) do
    with {:ok, ref} <- TitleRef.parse(param),
         %TitleDetail{ref: ^ref} <- socket.assigns.title_detail do
      socket =
        socket
        |> update(:modal_state, &%{&1 | tmdb_checking: true})
        |> start_async({:refresh_from_tmdb, ref}, fn -> Store.check(ref) end)

      {:halt, socket}
    else
      _stale_or_unknown -> {:halt, socket}
    end
  end

  # The artwork is the detail's own — already resolved on open and
  # refreshed by the live preview.
  def handle_title_event(
        "review_open",
        _params,
        %{assigns: %{title_detail: %TitleDetail{title: %Title{} = title} = detail}} = socket
      ), do: {:halt, ReviewFlow.open(socket, title, detail.poster_url)}

  # Play needs no modal: the hero and the cards fire it too (UIDR-027).
  def handle_title_event("play", %{"id" => id}, socket), do: {:halt, LibraryEvents.play(socket, id)}

  def handle_title_event(event, params, %{assigns: %{title_detail: %TitleDetail{library: %{}}}} = socket)
      when event in @library_events, do: {:halt, LibraryEvents.handle(event, params, socket)}

  # A modal event with no open modal (a stale click after a close), or a
  # library event without a library half, is a no-op.
  def handle_title_event(event, _params, socket) when event in @modal_events or event in @library_events,
    do: {:halt, socket}

  def handle_title_event(_event, _params, socket), do: {:cont, socket}

  # A rail pick lands on another member of the open collection — the
  # same document — and keeps the sub-view it was on.
  defp kept_view(
         %{assigns: %{title_detail: %TitleDetail{library: %{}} = open, modal_state: state}},
         half
       ) do
    if LibraryHalf.container_id(open) == half.entry.entity.id and state.view in [:info, :cast],
      do: [view: state.view],
      else: []
  end

  defp kept_view(_socket, _half), do: []

  defp toggle_menu(open, menu) when open == menu, do: nil
  defp toggle_menu(_open, menu), do: menu

  # A feed-born detail carries the review's provenance onto the
  # record the raise creates — who sent it, and what they said. It applies
  # on creation only, so re-raising an existing record leaves it alone.
  defp provenance(%TitleDetail{activity: %{activity: %{id: id, text: text}, own?: false}}),
    do: TitleIntent.friend_provenance(id, text)

  defp provenance(_detail), do: %{}

  # The title a click names, resolved as an open is: the open detail's,
  # else by identity, else the page's in-memory copy.
  defp title_for_param(socket, param) do
    case TitleRef.parse(param) do
      {:ok, ref} ->
        {page_snapshot, _facts} = socket.view.page_facts(socket, ref, %{})
        snapshot(socket, ref, LibraryHalf.load(ref), nil, page_snapshot)

      :error ->
        nil
    end
  end

  defp rung_atom("off"), do: :off
  defp rung_atom("list"), do: :list
  defp rung_atom("follow"), do: :follow
  defp rung_atom("grab"), do: :grab

  # --- Addresses ---

  @doc """
  The open modal's own query — its address, the sub-view and the
  activity it speaks for — for a page that patches its own params (a
  tab, a sort, a filter) and keeps the modal open across them. `[]`
  while closed.
  """
  @spec modal_query(Phoenix.LiveView.Socket.t()) :: keyword()
  def modal_query(%{assigns: %{title_detail: %TitleDetail{} = detail, modal_state: state}}) do
    address_query(detail) ++ if(state.view in [:info, :cast], do: [view: state.view], else: [])
  end

  def modal_query(_socket), do: []

  defp path(socket, query), do: socket.view.title_detail_path(socket, query)

  defp push_close(socket), do: push_patch(socket, to: path(socket, []))

  defp abandon_open(socket, flash), do: socket |> put_flash(:error, flash) |> push_close()

  defp close_or_return(%{assigns: %{title_detail: %TitleDetail{} = detail, modal_state: state}} = socket) do
    if state.view == resolve_view(detail, nil),
      do: push_close(socket),
      else: push_patch(socket, to: path(socket, address_query(detail)))
  end

  defp close_or_return(socket), do: push_close(socket)

  # The open detail's own query: the title address, or the residue's
  # entity address, and the activity it speaks for.
  defp address_query(%TitleDetail{ref: {_tmdb_id, _media_type} = ref} = detail) do
    case activity_params(detail) do
      %{"activity" => id} -> [title: TitleRef.param(ref), activity: id]
      _none -> [title: TitleRef.param(ref)]
    end
  end

  defp address_query(%TitleDetail{library: %{entry: %{entity: %{id: id}}}}), do: [entity: id]

  defp view_query(%{"view" => view}) when view in ["info", "cast"], do: [view: view]
  defp view_query(_params), do: []

  # What stood in the way of a fetched open, and for the key, where it is set.
  defp tmdb_needed_flash,
    do: "Opening a title that isn't on your lists needs a TMDB API key. Add one in Settings under TMDB."

  defp no_such_title_flash({_tmdb_id, :movie}), do: "TMDB has no movie with that id."
  defp no_such_title_flash({_tmdb_id, :tv_series}), do: "TMDB has no TV series with that id."

  defp tmdb_unreachable_flash, do: "TMDB didn't answer, so the title couldn't be opened."
end
