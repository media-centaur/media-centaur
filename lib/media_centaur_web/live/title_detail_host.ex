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
  that subscribes to `release_tracking:updates`, seeds `:title_detail`
  and `:scope_menu_open`, and attaches four lifecycle hooks:

  | Hook | Does |
  |---|---|
  | `:handle_params` | opens, refreshes or closes the modal from `?title=<ref>` (`TitleRef`) and `&activity=<id>` |
  | `:handle_event` | every modal control, halting: `open_title`, `close_title`, `title_scope_*`, `title_download`, `title_activity_delete`, `title_recommend_open`, `set_rung`, `reset_lower_quality` |
  | `:handle_async` | the live TMDB preview (`{:title_preview, ref}`) |
  | `:handle_info` | refreshes the open detail on `:releases_updated`, watchlist and library changes, then continues so the host's own clauses run |
  | `use RecommendFlow` | injects the Recommend modal's own controls; `title_recommend_open` opens it on the detail's title |

  A host that `use`s this module must not also `use` `EntityModal`: both
  inject `RecommendFlow`, and the duplicated clauses and `init/1` seed
  would collide.

  Hosts MUST NOT call `ReleaseTracking.subscribe/0` themselves. A host
  that also uses `IntentAware` must `use` this module *first*: hooks
  run in attach order and `IntentAware` halts the watchlist messages.

  Beyond the `use`, the host implements two callbacks:

  * `resolve_title/3` — the `TMDB.Title` a ref names on this page plus
    any page-specific facts for `Logic.title_detail/2` (Discovery's feed
    provenance and recommendations), or nil when the page does not know
    the title, which leaves the modal closed.
  * `title_detail_path/2` — the page's own path with the modal query
    applied (`[]` closes), so leaving the modal never changes tab.

  and keeps a `:today` assign. The common facts — library owner,
  watchlist membership, acquisition state, artwork, the tracked-title
  half (`TrackingDetail`) — are read here from their owning contexts:
  local reads, milliseconds (ADR-051).

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

  alias MediaCentaur.Acquisition.{AutoGrabSettings, DownloadParams, Plans, TitleStates}
  alias MediaCentaur.Acquisition.TitleDownloadParams
  alias MediaCentaur.Activities
  alias MediaCentaur.Capabilities
  alias MediaCentaur.Discovery
  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.Library.ExternalIds
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.TMDB.Client, as: TMDBClient
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.TmdbArtwork
  alias MediaCentaurWeb.Components.Detail.TitlePreview
  alias MediaCentaurWeb.Components.Title.Detail, as: TitleDetail
  alias MediaCentaurWeb.Components.ReleaseTracking.TrackingDetail
  alias MediaCentaurWeb.DiscoveryLive.ActivityWords
  alias MediaCentaurWeb.Components.Title.Logic
  alias MediaCentaurWeb.Live.RecommendFlow
  alias MediaCentaurWeb.TitleRef

  require MediaCentaur.Log, as: Log

  @callback resolve_title(socket :: Phoenix.LiveView.Socket.t(), TitleRef.ref(), params :: map()) ::
              {Title.t(), facts :: map()} | nil

  @callback title_detail_path(socket :: Phoenix.LiveView.Socket.t(), query :: keyword()) ::
              String.t()

  @modal_events ~w(title_scope_toggle title_scope_close title_download title_activity_delete title_recommend_open)
  @rungs ~w(ignored off list follow ask grab default)

  defmacro __using__(_opts) do
    quote do
      @behaviour MediaCentaurWeb.Live.TitleDetailHost

      use MediaCentaurWeb.Live.RecommendFlow

      on_mount {MediaCentaurWeb.Live.TitleDetailHost, :default}
    end
  end

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket), do: ReleaseTracking.subscribe()

    socket =
      socket
      |> assign(title_detail: nil, scope_menu_open: false)
      |> RecommendFlow.init()
      |> attach_hook(:title_detail_params, :handle_params, &apply_title_params/3)
      |> attach_hook(:title_detail_events, :handle_event, &handle_title_event/3)
      |> attach_hook(:title_detail_async, :handle_async, &handle_title_async/3)
      |> attach_hook(:title_detail_pubsub, :handle_info, &handle_title_info/2)

    {:cont, socket}
  end

  # --- URL ---

  # `?title=<media_type>-<tmdb_id>` drives the modal (UIDR-017 idiom):
  # back closes, refresh keeps it, the URL is shareable. `&activity=<id>`
  # names the act a person card opened it from. A ref the page does not
  # know leaves it closed. A fresh open starts the live TMDB preview
  # fetch; a re-patch of the same title keeps the preview it already has.
  def apply_title_params(%{"title" => param} = params, _uri, socket) do
    with {:ok, ref} <- TitleRef.parse(param),
         {%Title{} = title, facts} <- socket.view.resolve_title(socket, ref, params) do
      case socket.assigns.title_detail do
        %TitleDetail{ref: ^ref} = open ->
          {:cont, assign(socket, :title_detail, build_detail(socket, title, facts, open.preview))}

        _closed_or_other ->
          socket =
            socket
            |> assign(title_detail: build_detail(socket, title, facts, nil), scope_menu_open: false)
            |> fetch_preview(title)

          {:cont, socket}
      end
    else
      _unknown -> {:cont, close(socket)}
    end
  end

  def apply_title_params(_params, _uri, socket), do: {:cont, close(socket)}

  defp close(socket), do: assign(socket, title_detail: nil, scope_menu_open: false)

  @doc """
  Rebuilds the open detail from current facts (a row reloaded, a mode
  moved, a plan landed). Closes it when the page no longer knows the
  title. A no-op while closed.
  """
  @spec refresh_title_detail(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def refresh_title_detail(%{assigns: %{title_detail: nil}} = socket), do: socket

  def refresh_title_detail(%{assigns: %{title_detail: %TitleDetail{} = detail}} = socket) do
    params = if detail.activity_id, do: %{"activity" => detail.activity_id}, else: %{}

    case socket.view.resolve_title(socket, detail.ref, params) do
      {%Title{} = title, facts} ->
        assign(socket, :title_detail, build_detail(socket, title, facts, detail.preview))

      nil ->
        close(socket)
    end
  end

  # The common facts, from the contexts that own them; the host's facts
  # (feed provenance, recommendations) merge over them.
  defp build_detail(socket, %Title{} = title, host_facts, preview) do
    ref = Title.ref(title)
    artwork = TmdbArtwork.urls(title.media_type, title.tmdb_id)
    acquisition? = Capabilities.acquisition_ready?()
    default_grab_mode = AutoGrabSettings.load().default_mode
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
          auto_grab_default_mode: default_grab_mode
        }),
      acquisition?: acquisition?,
      default_grab_mode: default_grab_mode,
      preview: preview
    }

    Logic.title_detail(title, Map.merge(facts, host_facts))
  end

  # The live preview runs as an owned async (cancelled with the view,
  # awaitable in tests); the modal reads the snapshot until it lands.
  # Without a working TMDB key the snapshot is all there is.
  defp fetch_preview(socket, %Title{} = title) do
    if Capabilities.tmdb_ready?() do
      ref = Title.ref(title)
      in_library? = match?({:in_library, _owner}, socket.assigns.title_detail.primary)

      start_async(socket, {:title_preview, ref}, fn -> load_preview(title, in_library?) end)
    else
      socket
    end
  end

  defp load_preview(%Title{media_type: :movie, tmdb_id: id}, in_library?) do
    with {:ok, movie} <- TMDBClient.get_movie(id), do: {:ok, TitlePreview.movie(movie, in_library?)}
  end

  defp load_preview(%Title{media_type: :tv_series, tmdb_id: id}, in_library?) do
    with {:ok, show} <- TMDBClient.get_tv(id), do: {:ok, TitlePreview.tv(show, in_library?)}
  end

  def handle_title_async({:title_preview, ref}, {:ok, {:ok, %TitlePreview{} = preview}}, socket) do
    case socket.assigns.title_detail do
      %TitleDetail{ref: ^ref} = detail ->
        {:halt, assign(socket, :title_detail, %{detail | preview: preview})}

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
        "title_scope_toggle",
        _params,
        %{assigns: %{title_detail: %TitleDetail{}}} = socket
      ), do: {:halt, update(socket, :scope_menu_open, &(!&1))}

  def handle_title_event("title_scope_close", _params, socket),
    do: {:halt, assign(socket, :scope_menu_open, false)}

  # Movies send no scope; a series sends first_season or everything.
  def handle_title_event(
        "title_download",
        params,
        %{assigns: %{title_detail: %TitleDetail{} = detail}} = socket
      ) do
    # A closed set, mapped explicitly: `String.to_existing_atom/1` would
    # depend on whether `DownloadScope` happens to be loaded yet.
    scope =
      case params do
        %{"scope" => "first_season"} -> [scope: :first_season]
        %{"scope" => "everything"} -> [scope: :everything]
        _movie_or_unknown -> []
      end

    # A download says nothing about the future: whichever scope, the
    # title's rung is untouched (ADR-066).
    :ok = Plans.plan_title(detail.title, [approval_policy: "automatic"] ++ scope)

    {:halt,
     socket
     |> put_flash(:info, download_flash(detail.title.name))
     |> push_close()}
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
        "title_recommend_open",
        _params,
        %{assigns: %{title_detail: %TitleDetail{} = detail}} = socket
      ), do: {:halt, RecommendFlow.open(socket, detail.title, detail.poster_url)}

  # A modal event with no open modal (a stale click after a close) is a no-op.
  def handle_title_event(event, _params, socket) when event in @modal_events, do: {:halt, socket}

  def handle_title_event(_event, _params, socket), do: {:cont, socket}

  # A feed-born detail carries the recommendation's provenance onto the
  # record the raise creates — who sent it, and what they said. It applies
  # on creation only, so re-raising an existing record leaves it alone.
  defp provenance(%TitleDetail{activity_id: id, own?: own?, note: note}) when is_binary(id) and not own?,
    do: TitleIntent.friend_provenance(id, note)

  defp provenance(_detail), do: %{}

  @doc """
  The flash a one-click download raises — the one wording, for the
  modal's Download and the Feed toolbar's.
  """
  @spec download_flash(String.t()) :: String.t()
  def download_flash(name), do: "Finding a release for #{name}"

  defp push_close(socket), do: push_patch(socket, to: socket.view.title_detail_path(socket, []))

  # The open detail's title when the click names it (the modal), else
  # whatever the page knows the ref as (a watchlist row).
  defp title_for_param(socket, param) do
    case TitleRef.parse(param) do
      {:ok, ref} ->
        case socket.assigns.title_detail do
          %TitleDetail{ref: ^ref, title: title} ->
            title

          _other ->
            case socket.view.resolve_title(socket, ref, %{}) do
              {%Title{} = title, _facts} -> title
              nil -> nil
            end
        end

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

  defp rung_atom("ignored"), do: :ignored
  defp rung_atom("off"), do: :off
  defp rung_atom("list"), do: :list
  defp rung_atom("follow"), do: :follow
  defp rung_atom("ask"), do: :ask
  defp rung_atom("grab"), do: :grab
  defp rung_atom("default"), do: :default
end
