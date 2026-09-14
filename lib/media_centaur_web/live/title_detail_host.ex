defmodule MediaCentaurWeb.Live.TitleDetailHost do
  @moduledoc """
  Shared modal state, events and loading for any LiveView that hosts the
  title detail modal — `TitleDetailModal`, the depth surface for a title
  without files (UIDR-035). `DiscoveryLive` and `IncomingLive` both
  `use` this module so the modal is one surface with one vocabulary
  wherever a title is opened; the library detail panel remains
  `EntityModal`'s, for titles with files.

  ## Host contract

  `use MediaCentaurWeb.Live.TitleDetailHost` registers an `on_mount`
  that subscribes to `release_tracking:updates`, seeds `:title_detail`,
  `:title_opening`, `:open_menu`, `:download_scope` and `:download_pending`,
  and attaches
  four lifecycle hooks:

  | Hook | Does |
  |---|---|
  | `:handle_params` | opens, refreshes or closes the modal from `?title=<ref>` (`TitleRef`) and `&activity=<id>` — from the snapshot resolved by identity, or from TMDB when nothing here holds one |
  | `:handle_event` | every modal control, halting: `open_title`, `close_title`, `title_mode_toggle`, `title_scope_toggle`, `title_menu_close`, `title_scope`, `title_download`, `title_activity_delete`, `title_review_open`, `set_rung`, `reset_lower_quality` |
  | `:handle_async` | the fetched open (`{:title_open, ref}`), the live TMDB preview (`{:title_preview, ref}`) and the manual plan (`{:title_download, ref, name}`) that opens its board |
  | `:handle_info` | refreshes the open detail on `:releases_updated`, watchlist and library changes, then continues so the host's own clauses run |
  | `use ReviewFlow` | injects the Review modal's own controls; `title_review_open` opens it on the detail's title |

  A host that `use`s this module must not also `use` `EntityModal`: both
  inject `ReviewFlow`, and the duplicated clauses and `init/1` seed
  would collide.

  Hosts MUST NOT call `ReleaseTracking.subscribe/0` themselves. A host
  that also uses `IntentAware` must `use` this module *first*: hooks
  run in attach order and `IntentAware` halts the watchlist messages.

  Beyond the `use`, the host implements three callbacks:

  * `page_facts/3` — what this page alone knows about a ref: an
    in-memory snapshot when it holds one (an omnibox result, a plan's
    subject, a feed activity's title) and the facts only it can supply
    for `Logic.title_detail/2` (the feed's provenance: kind, sender,
    activity id, the review's words as the note). `{nil, %{}}` when it
    knows nothing, which is never a reason not to open.
  * `title_detail_path/2` — the page's own path with the modal query
    applied (`[]` closes), so leaving the modal never changes tab.
  * `open_plan_board/2` — navigates to Incoming with the plan's board
    open (`push_navigate` from another page, `push_patch` on Incoming
    itself).

  and keeps a `:today` assign.

  ## Resolving a title

  The modal's subject is a TMDB identity, and the snapshot it opens from
  is resolved here by that identity, in order: the open detail's own; the
  title intent's embedded snapshot (`Discovery.get_intent/2` — any title
  on the ladder, listed, ignored or tracked); the page's in-memory copy;
  and TMDB itself, fetched asynchronously, for a deep link to a title
  nothing here holds. The common facts — library owner, rung, acquisition
  state, artwork, the tracked-title half (`TrackingDetail`), friend
  activity for the pennants, the intent's note — are read from their
  owning contexts by the same identity: local reads, milliseconds
  (ADR-051). The page's facts merge over them. An open detail is never
  closed by the lists changing beneath it (`refresh_title_detail/1`);
  closing is an explicit act.

  ## Setting a rung

  `set_rung` is the modal's one intent event, and there is no other:
  listing, following and stopping are all one ladder now, so the separate
  watchlist add/remove events are gone. `ReleaseTracking.set_rung/3`
  writes the person's intent and derives everything from it, including
  deleting the tracked title when the rung drops below Follow or to Off.
  A raise onto Follow or above with no calendar yet fetches from TMDB, so
  it runs async and the modal catches up on the `:releases_updated`
  broadcast.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3, update: 3]
  import Phoenix.LiveView
  import MediaCentaurWeb.LiveHelpers, only: [title_poster_url: 1, tmdb_cdn_url: 2]

  alias MediaCentaur.Acquisition.{DownloadParams, Plans, TitleStates}
  alias MediaCentaur.Acquisition.Plans.DownloadScope
  alias MediaCentaur.Acquisition.TitleDownloadParams
  alias MediaCentaur.Activities
  alias MediaCentaur.Capabilities
  alias MediaCentaur.Discovery
  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.Library.ExternalIds
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Settings.Preferences.PlanningMode
  alias MediaCentaur.TMDB.Client, as: TMDBClient
  alias MediaCentaur.TMDB.ReleaseWindow
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.TmdbArtwork
  alias MediaCentaurWeb.Live.PlanFlow
  alias MediaCentaurWeb.Components.Detail.TitlePreview
  alias MediaCentaurWeb.Components.Title.Detail, as: TitleDetail
  alias MediaCentaurWeb.Components.ReleaseTracking.TrackingDetail
  alias MediaCentaurWeb.DiscoveryLive.ActivityWords
  alias MediaCentaurWeb.Components.Title.Logic
  alias MediaCentaurWeb.Live.ReviewFlow
  alias MediaCentaurWeb.TitleRef

  require MediaCentaur.Log, as: Log

  @callback page_facts(socket :: Phoenix.LiveView.Socket.t(), TitleRef.ref(), params :: map()) ::
              {snapshot :: Title.t() | nil, facts :: map()}

  @callback title_detail_path(socket :: Phoenix.LiveView.Socket.t(), query :: keyword()) ::
              String.t()

  @callback open_plan_board(socket :: Phoenix.LiveView.Socket.t(), plan_id :: Ecto.UUID.t()) ::
              Phoenix.LiveView.Socket.t()

  @modal_events ~w(title_mode_toggle title_scope_toggle title_menu_close title_scope title_download title_activity_delete title_review_open)
  @rungs ~w(off list follow grab)

  defmacro __using__(_opts) do
    quote do
      @behaviour MediaCentaurWeb.Live.TitleDetailHost

      use MediaCentaurWeb.Live.ReviewFlow

      on_mount {MediaCentaurWeb.Live.TitleDetailHost, :default}
    end
  end

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket), do: ReleaseTracking.subscribe()

    socket =
      socket
      |> assign(
        title_detail: nil,
        title_opening: nil,
        open_menu: nil,
        download_scope: :first_season,
        download_pending: nil
      )
      |> ReviewFlow.init()
      |> attach_hook(:title_detail_params, :handle_params, &apply_title_params/3)
      |> attach_hook(:title_detail_events, :handle_event, &handle_title_event/3)
      |> attach_hook(:title_detail_async, :handle_async, &handle_title_async/3)
      |> attach_hook(:title_detail_pubsub, :handle_info, &handle_title_info/2)

    {:cont, socket}
  end

  # --- URL ---

  # `?title=<media_type>-<tmdb_id>` drives the modal (UIDR-035): back
  # closes, refresh keeps it, the URL is shareable. `&activity=<id>` names
  # the act a person card opened it from. The snapshot is resolved by
  # identity (`snapshot/3`), and TMDB is the last source: a ref nothing
  # here holds is fetched, and the modal opens when the detail lands. A
  # fresh open from a snapshot starts the live preview fetch; a re-patch of
  # the open title keeps the preview it already has. A malformed param
  # names nothing to open.
  def apply_title_params(%{"title" => param} = params, _uri, socket) do
    case TitleRef.parse(param) do
      {:ok, ref} ->
        {page_snapshot, facts} = socket.view.page_facts(socket, ref, params)

        case snapshot(socket, ref, page_snapshot) do
          %Title{} = title -> {:cont, open_from_snapshot(socket, ref, title, facts)}
          nil -> {:cont, open_from_tmdb(socket, ref)}
        end

      :error ->
        {:cont, close(socket)}
    end
  end

  def apply_title_params(_params, _uri, socket), do: {:cont, close(socket)}

  # The snapshot a ref opens from, by identity: the open detail's own,
  # then the title intent's (any title on the ladder — listed, ignored,
  # tracked), then the page's in-memory copy. Nil leaves TMDB as the one
  # source.
  defp snapshot(%{assigns: %{title_detail: %TitleDetail{ref: ref, title: title}}}, ref, _page_snapshot),
    do: title

  defp snapshot(_socket, ref, page_snapshot), do: intent_snapshot(ref) || page_snapshot

  defp intent_snapshot({tmdb_id, media_type}) do
    case Discovery.get_intent(tmdb_id, media_type) do
      %TitleIntent{title: %Title{} = title} -> title
      _none -> nil
    end
  end

  # A re-patch of the open title keeps the preview it already has.
  defp open_from_snapshot(
         %{assigns: %{title_detail: %TitleDetail{ref: ref} = open}} = socket,
         ref,
         title,
         facts
       ), do: assign(socket, :title_detail, build_detail(socket, title, facts, open.preview))

  defp open_from_snapshot(socket, _ref, title, facts) do
    socket
    |> reset_detail()
    |> assign(:title_detail, build_detail(socket, title, facts, nil))
    |> fetch_preview(title)
  end

  # A fetch already under way for the ref is left to land. Otherwise the
  # fetch starts, once connected — the dead render has no process for it
  # to answer to. What stands in the way (no TMDB key, no such title, TMDB
  # not answering) is the fetch's result: flashed, and the param dropped,
  # by the one result handler — which also keeps the page's path out of
  # this hook, where on the first mount the page has not assigned its own
  # URL state yet.
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

  # Another title takes the modal: whatever was open or opening is dropped.
  defp reset_detail(socket) do
    socket
    |> cancel_pending(:title_opening, &{:title_open, &1})
    |> assign(title_detail: nil, open_menu: nil, download_scope: :first_season)
  end

  # Closing also abandons a manual plan being created: the person left, so
  # nobody should be taken to its board.
  defp close(socket) do
    socket
    |> cancel_pending(:download_pending, & &1)
    |> reset_detail()
  end

  defp cancel_pending(socket, key, name_of) do
    case socket.assigns[key] do
      nil -> socket
      pending -> socket |> cancel_async(name_of.(pending)) |> assign(key, nil)
    end
  end

  @doc """
  Rebuilds the open detail from current facts (a rung moved, a plan
  landed, a friend's act arrived). An open detail is never closed by a
  refresh: it keeps its own snapshot and re-reads the facts the contexts
  hold by identity, and the page's facts come and go with its rows — so
  when the bookmark takes the title off the list, or Off deletes the
  tracked title, the control that removed it is still there to undo it.
  Closing is an explicit act (the URL dropping `?title`, an own activity
  deleted, an auto-select download landing). A no-op while closed.
  """
  @spec refresh_title_detail(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def refresh_title_detail(%{assigns: %{title_detail: nil}} = socket), do: socket

  def refresh_title_detail(%{assigns: %{title_detail: %TitleDetail{} = detail}} = socket) do
    params = if detail.activity_id, do: %{"activity" => detail.activity_id}, else: %{}
    {_page_snapshot, facts} = socket.view.page_facts(socket, detail.ref, params)
    assign(socket, :title_detail, build_detail(socket, detail.title, facts, detail.preview))
  end

  # The common facts, from the contexts that own them, by identity; the
  # page's facts merge over them (a review's words over the intent's note).
  defp build_detail(socket, %Title{} = title, page_facts, preview) do
    ref = Title.ref(title)
    artwork = TmdbArtwork.urls(title.media_type, title.tmdb_id)
    acquisition? = Capabilities.acquisition_ready?()
    planning_mode = PlanningMode.value()
    today = socket.assigns.today

    facts = %{
      library_owner_id: Map.get(ExternalIds.tmdb_owners([ref]), ref),
      rung: Discovery.rung(title.tmdb_id, title.media_type),
      lower_quality_accepted?:
        DownloadParams.lower_quality_accepted?(TitleDownloadParams.get(title.tmdb_id, title.media_type)),
      acquisition_state: Map.get(TitleStates.for_refs([ref]), ref),
      release_mode_available: Capabilities.prowlarr_ready?(),
      today: today,
      poster_url: title_poster_url(title),
      backdrop_url: artwork.backdrop_url || tmdb_cdn_url(title.backdrop_path, :w1280),
      logo_url: artwork.logo_url,
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
      note: intent_note(ref),
      preview: preview
    }

    Logic.title_detail(title, Map.merge(facts, page_facts))
  end

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
  # Without a working TMDB key the snapshot is all there is.
  defp fetch_preview(socket, %Title{} = title) do
    if Capabilities.tmdb_ready?() do
      ref = Title.ref(title)
      in_library? = match?({:in_library, _owner}, socket.assigns.title_detail.primary)

      today = socket.assigns.today
      start_async(socket, {:title_preview, ref}, fn -> load_preview(title, in_library?, today) end)
    else
      socket
    end
  end

  defp load_preview(%Title{} = title, in_library?, today) do
    with {:ok, payload} <- fetch_payload(Title.ref(title)),
         do: {:ok, preview_from_payload(title, payload, in_library?, today)}
  end

  # A deep link to a title no row knows: the detail payload is both the
  # snapshot the modal opens from and the preview that dresses it, so one
  # fetch serves both. The fetch needs TMDB, so its readiness is the first
  # thing checked. TMDB's 404 is "no such title"; a payload without an
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

  defp fetch_payload({tmdb_id, :movie}), do: TMDBClient.get_movie(tmdb_id)
  defp fetch_payload({tmdb_id, :tv_series}), do: TMDBClient.get_tv(tmdb_id)

  # The movie payload also says where the film stands in its release
  # sequence — the fact that decides whether there is a release to track.
  defp preview_from_payload(%Title{media_type: :movie}, movie, in_library?, today),
    do: {TitlePreview.movie(movie, in_library?), ReleaseWindow.from_payload(movie, today)}

  defp preview_from_payload(%Title{media_type: :tv_series}, show, in_library?, _today),
    do: {TitlePreview.tv(show, in_library?), nil}

  # A result for a plan the person walked away from — the cancel's own
  # exit, or a reply already queued when the modal closed — is dropped.
  def handle_title_async(
        {:title_download, _ref, _name} = name,
        _result,
        %{assigns: %{download_pending: pending}} = socket
      )
      when pending != name, do: {:halt, socket}

  # `download_pending` stays set: Discovery navigates away, and on
  # Incoming the patch closes the modal, which resets it.
  def handle_title_async({:title_download, _ref, _name}, {:ok, {:ok, plan}}, socket) do
    socket = assign(socket, :open_menu, nil)
    {:halt, socket.view.open_plan_board(socket, plan.id)}
  end

  def handle_title_async({:title_download, _ref, name}, {:ok, {:error, reason}}, socket) do
    Log.warning(:acquisition, "could not plan — #{name} — #{inspect(reason)}")

    {:halt,
     socket
     |> assign(:download_pending, nil)
     |> put_flash(:error, PlanFlow.failure_flash(name, reason))}
  end

  def handle_title_async({:title_download, _ref, name}, {:exit, reason}, socket) do
    Log.warning(:acquisition, "planning crashed — #{name} — #{inspect(reason)}")

    {:halt,
     socket
     |> assign(:download_pending, nil)
     |> put_flash(:error, PlanFlow.failure_flash(name, :crashed))}
  end

  # The fetched open. A result for a ref the person has moved on from — the
  # URL dropped it, or names another title — is dropped with it, the
  # cancel's own exit included.
  def handle_title_async({:title_open, ref}, _result, %{assigns: %{title_opening: opening}} = socket)
      when opening != ref, do: {:halt, socket}

  def handle_title_async({:title_open, _ref}, {:ok, {:ok, {%Title{} = title, payload}}}, socket) do
    detail = build_detail(socket, title, %{}, nil)
    in_library? = match?({:in_library, _owner}, detail.primary)
    {preview, window} = preview_from_payload(title, payload, in_library?, socket.assigns.today)

    {:halt,
     assign(socket,
       title_detail: %{detail | preview: preview, release_window: window},
       title_opening: nil,
       open_menu: nil,
       download_scope: :first_season
     )}
  end

  def handle_title_async({:title_open, _ref}, {:ok, {:error, :tmdb_not_ready}}, socket),
    do: {:halt, abandon_open(socket, tmdb_needed_flash())}

  def handle_title_async({:title_open, ref}, {:ok, {:error, :not_found}}, socket),
    do: {:halt, abandon_open(socket, no_such_title_flash(ref))}

  def handle_title_async({:title_open, ref}, {:ok, {:error, reason}}, socket) do
    Log.warning(:tmdb, "could not open #{TitleRef.param(ref)} from TMDB — #{inspect(reason)}")
    {:halt, abandon_open(socket, tmdb_unreachable_flash())}
  end

  def handle_title_async({:title_open, ref}, {:exit, reason}, socket) do
    Log.warning(:tmdb, "opening #{TitleRef.param(ref)} from TMDB crashed — #{inspect(reason)}")
    {:halt, abandon_open(socket, tmdb_unreachable_flash())}
  end

  def handle_title_async(
        {:title_preview, ref},
        {:ok, {:ok, {%TitlePreview{} = preview, window}}},
        socket
      ) do
    case socket.assigns.title_detail do
      %TitleDetail{ref: ^ref} = detail ->
        {:halt, assign(socket, :title_detail, %{detail | preview: preview, release_window: window})}

      _closed_or_other ->
        {:halt, socket}
    end
  end

  def handle_title_async({:title_preview, _ref}, {:ok, {:error, reason}}, socket) do
    Log.debug(:tmdb, "title preview unavailable — #{inspect(reason)}")
    {:halt, socket}
  end

  def handle_title_async({:title_preview, _ref}, {:exit, reason}, socket) do
    Log.warning(:tmdb, "title preview crashed — #{inspect(reason)}")
    {:halt, socket}
  end

  def handle_title_async(_name, _result, socket), do: {:cont, socket}

  # --- PubSub ---

  @refresh_on [:releases_updated, :title_intent_changed, :entities_changed]

  def handle_title_info({tag, _payload}, socket) when tag in @refresh_on,
    do: {:cont, refresh_title_detail(socket)}

  def handle_title_info(_message, socket), do: {:cont, socket}

  # --- Events ---

  def handle_title_event("open_title", %{"ref" => ref} = params, socket) do
    query =
      case params do
        %{"activity" => activity_id} -> [title: ref, activity: activity_id]
        _title_only -> [title: ref]
      end

    {:halt, push_patch(socket, to: socket.view.title_detail_path(socket, query))}
  end

  def handle_title_event("close_title", _params, socket), do: {:halt, push_close(socket)}

  def handle_title_event(
        "title_mode_toggle",
        _params,
        %{assigns: %{title_detail: %TitleDetail{}}} = socket
      ), do: {:halt, update(socket, :open_menu, &toggle_menu(&1, :mode))}

  def handle_title_event(
        "title_scope_toggle",
        _params,
        %{assigns: %{title_detail: %TitleDetail{}}} = socket
      ), do: {:halt, update(socket, :open_menu, &toggle_menu(&1, :scope))}

  def handle_title_event(
        "title_menu_close",
        _params,
        %{assigns: %{title_detail: %TitleDetail{}}} = socket
      ), do: {:halt, assign(socket, :open_menu, nil)}

  # A closed set, mapped explicitly: `String.to_existing_atom/1` would
  # depend on whether `DownloadScope` happens to be loaded yet.
  def handle_title_event(
        "title_scope",
        %{"choice" => choice},
        %{assigns: %{title_detail: %TitleDetail{}}} = socket
      )
      when choice in ~w(first_season everything) do
    scope = if choice == "everything", do: :everything, else: :first_season
    {:halt, assign(socket, download_scope: scope, open_menu: nil)}
  end

  # The main segment sends no mode (the person's default); the menu item
  # names the other one. A movie has one scope, so it sends none.
  def handle_title_event(
        "title_download",
        params,
        %{assigns: %{title_detail: %TitleDetail{} = detail}} = socket
      ) do
    mode =
      case params do
        %{"mode" => "auto_select_best_release"} -> :auto_select_best_release
        %{"mode" => "manually_select_release"} -> :manually_select_release
        _default -> detail.planning_mode
      end

    scope = if detail.scoped?, do: socket.assigns.download_scope

    {:halt, socket |> assign(:open_menu, nil) |> start_download(detail.title, mode, scope)}
  end

  def handle_title_event(
        "title_activity_delete",
        _params,
        %{assigns: %{title_detail: %TitleDetail{activity_id: id, kind: kind}}} = socket
      )
      when is_binary(id) do
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
        socket = apply_rung(socket, title, rung_atom(choice), provenance(socket.assigns.title_detail))
        {:halt, refresh_title_detail(socket)}

      nil ->
        {:halt, socket}
    end
  end

  # The acceptance is keyed by TMDB identity, not by tracked title, so
  # resetting it neither needs nor touches one (ADR-063 §2).
  def handle_title_event("reset_lower_quality", %{"ref" => param}, socket) do
    with {:ok, {tmdb_id, media_type}} <- TitleRef.parse(param) do
      TitleDownloadParams.put(tmdb_id, media_type, %{min_quality: nil})
    end

    {:halt, refresh_title_detail(socket)}
  end

  # The artwork is the detail's own — already resolved on open and
  # refreshed by the live preview. Deriving it again here would be a
  # second source for one value.
  def handle_title_event(
        "title_review_open",
        _params,
        %{assigns: %{title_detail: %TitleDetail{} = detail}} = socket
      ), do: {:halt, ReviewFlow.open(socket, detail.title, detail.poster_url)}

  # A modal event with no open modal (a stale click after a close) is a no-op.
  def handle_title_event(event, _params, socket) when event in @modal_events, do: {:halt, socket}

  def handle_title_event(_event, _params, socket), do: {:cont, socket}

  defp toggle_menu(open, menu) when open == menu, do: nil
  defp toggle_menu(_open, menu), do: menu

  @doc """
  Performs a planning mode on a title (spec 2026-09-12 §5–7). Auto-select
  hands the plan to the supervised door (`Plans.plan_title/2`,
  `automatic`), flashes, and closes the modal when one is open. Manually
  selecting plans here under `start_async` (`Plans.create_title_plan/2`,
  `review`) and opens the plan's board on Incoming once it exists,
  through the host's `open_plan_board/2`; a failure flashes on the modal
  instead. A click while one is pending is a no-op. `scope` is nil for
  a movie. A download never moves the title's rung (ADR-066).
  """
  @spec start_download(
          Phoenix.LiveView.Socket.t(),
          Title.t(),
          PlanningMode.mode(),
          DownloadScope.scope() | nil
        ) :: Phoenix.LiveView.Socket.t()
  def start_download(%{assigns: %{download_pending: name}} = socket, _title, _mode, _scope)
      when not is_nil(name), do: socket

  def start_download(socket, %Title{} = title, :auto_select_best_release, scope) do
    policy = PlanningMode.approval_policy(:auto_select_best_release)
    :ok = Plans.plan_title(title, [approval_policy: policy] ++ scope_opts(scope))

    socket = put_flash(socket, :info, PlanFlow.download_flash(title.name))
    if socket.assigns.title_detail, do: push_close(socket), else: socket
  end

  def start_download(socket, %Title{} = title, :manually_select_release, scope) do
    opts = [approval_policy: PlanningMode.approval_policy(:manually_select_release)] ++ scope_opts(scope)
    name = {:title_download, Title.ref(title), title.name}

    socket
    |> assign(:download_pending, name)
    |> start_async(name, fn -> Plans.create_title_plan(title, opts) end)
  end

  defp scope_opts(nil), do: []
  defp scope_opts(scope), do: [scope: scope]

  # A feed-born detail carries the review's provenance onto the
  # record the raise creates — who sent it, and what they said. It applies
  # on creation only, so re-raising an existing record leaves it alone.
  defp provenance(%TitleDetail{activity_id: id, own?: own?, note: note}) when is_binary(id) and not own?,
    do: TitleIntent.friend_provenance(id, note)

  defp provenance(_detail), do: %{}

  defp push_close(socket), do: push_patch(socket, to: socket.view.title_detail_path(socket, []))

  defp abandon_open(socket, flash),
    do: socket |> assign(:title_opening, nil) |> put_flash(:error, flash) |> push_close()

  # What stood in the way of a fetched open, and for the key, where it is set.
  defp tmdb_needed_flash,
    do: "Opening a title that isn't on your lists needs a TMDB API key. Add one in Settings under TMDB."

  defp no_such_title_flash({_tmdb_id, :movie}), do: "TMDB has no movie with that id."
  defp no_such_title_flash({_tmdb_id, :tv_series}), do: "TMDB has no TV series with that id."

  defp tmdb_unreachable_flash, do: "TMDB didn't answer, so the title couldn't be opened."

  # The title a click names, resolved as an open is: the open detail's,
  # else by identity, else the page's in-memory copy.
  defp title_for_param(socket, param) do
    case TitleRef.parse(param) do
      {:ok, ref} ->
        {page_snapshot, _facts} = socket.view.page_facts(socket, ref, %{})
        snapshot(socket, ref, page_snapshot)

      :error ->
        nil
    end
  end

  # Raising onto a rung that follows releases needs the calendar, which is
  # a TMDB fetch — so a title that has none yet is set asynchronously and
  # the modal catches up on the broadcast. Every other move is local.
  defp apply_rung(socket, %Title{} = title, :off, _attrs) do
    {:ok, nil} = ReleaseTracking.set_rung(title, :off)
    socket
  end

  defp apply_rung(socket, %Title{} = title, rung, attrs) do
    needs_calendar? =
      TitleIntent.follows_releases?(rung) and
        is_nil(ReleaseTracking.get_item_by_tmdb(title.tmdb_id, title.media_type))

    if needs_calendar? do
      ReleaseTracking.set_rung_async(title, rung, attrs)
      put_flash(socket, :info, "Tracking #{title.name} — releases will appear under Coming up.")
    else
      {:ok, _intent} = ReleaseTracking.set_rung(title, rung, attrs)
      socket
    end
  end

  defp rung_atom("off"), do: :off
  defp rung_atom("list"), do: :list
  defp rung_atom("follow"), do: :follow
  defp rung_atom("grab"), do: :grab
end
