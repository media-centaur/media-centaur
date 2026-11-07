defmodule MediaCentaurWeb.Live.PlanHost do
  @moduledoc """
  The host of the plan modal (UIDR-014) — one trait for every LiveView
  that starts a download: it owns the modal's URL (`?plan=…`,
  `Live.PlanQuery`), its state (`:plan`, a `State`), every event of the
  picker and the board, the owned asyncs, and the PubSub reactions that
  keep an open board honest. Home, Library, Discovery, Social, Watchlist
  and Downloads `use` it beside `TitleDetailHost`, so the plan modal is a
  tenant of whichever page opened it, as the title detail is
  (`campaigns/adaptive-layout.md`, M9: behaviour never keys on the device
  — what happens after a plan keys on the host page).

  ## Host contract

  `use MediaCentaurWeb.Live.PlanHost` registers an `on_mount` that
  subscribes `acquisition:updates` and `watchlist:updates` through
  `Live.Subscriptions`, seeds `:plan`, and attaches four hooks:

  | Hook | Does |
  |---|---|
  | `:handle_params` | opens the picker or a board from `?plan=…`, or closes the modal when the param is gone or cannot be meant |
  | `:handle_event` | every `plan_*` control, `close_plan`, and `plan_open` (a page control that opens the picker for a series), halting |
  | `:handle_async` | the targeting load, the board's artwork, a movie's release window, the swap picker's live search |
  | `:handle_info` | the plan events for the open plan (the board re-read on `Changed`, the ticker on `SearchActivity`, the itinerary on `SearchProgress`) and the rung on a watchlist change; `Changed` continues so a page's own lists react |

  The host page provides two things the title detail host already asks
  for: `overlay_path/2` — its own path with an overlay's query applied,
  `[]` closing every overlay — and `download_started/1`, where it leaves
  the person once a download has started (Downloads patches to Activity,
  every other page closes its overlays and stays). Opening the picker
  swaps the title detail for it: the address carries `plan`, not `title`.
  Cancel patches to the bare host page.

  The page renders the modal with one line, `overlay/1`, beside its title
  detail; the modal's typed attrs (`Components.Acquisition.PlanModal`)
  stay the component's contract.
  """

  use Phoenix.Component

  import Phoenix.LiveView

  alias MediaCentaur.Acquisition
  alias MediaCentaur.Acquisition.{PlanEvents, Plans, Targeting}
  alias MediaCentaur.Acquisition.ViewModels.{GapVerdict, PlanBoard, SearchOutage, SearchProgressPanel}
  alias MediaCentaur.Capabilities
  alias MediaCentaur.Search.IndexerHealth
  alias MediaCentaur.Settings.Preferences.PlanningMode
  alias MediaCentaur.TMDB.ReleaseWindow
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.Watchlist
  alias MediaCentaurWeb.Components.Acquisition.PlanModal
  alias MediaCentaurWeb.Components.Detail.TitlePreview
  alias MediaCentaurWeb.DownloadsLive.Logic
  alias MediaCentaurWeb.DownloadsLive.PlanLogic
  alias MediaCentaurWeb.Live.ArmGesture
  alias MediaCentaurWeb.Live.PlanFlow
  alias MediaCentaurWeb.Live.PlanQuery
  alias MediaCentaurWeb.Live.Subscriptions

  require MediaCentaur.Log, as: Log

  defmodule State do
    @moduledoc """
    The plan modal's state on its host: the address it answers to
    (`param` — `{tmdb_id, tmdb_type, mode}` for the picker, a plan id for
    a board, nil closed), the stage, and what each stage shows. The search
    health and outage are read from their caches when a board loads and
    on the events that change them; the rung is the subject's, for the
    board's bookmark.
    """

    defstruct param: nil,
              stage: :loading,
              menu_open?: false,
              selection: nil,
              chosen: MapSet.new(),
              movie: nil,
              board: nil,
              gap_verdict: nil,
              rejected: nil,
              error: nil,
              last_activity: nil,
              search_progress: nil,
              alternatives: nil,
              identity: nil,
              artwork: nil,
              title: nil,
              release_window: nil,
              search_health: nil,
              search_outage: nil,
              rung: nil

    @type t :: %__MODULE__{}
  end

  defmacro __using__(_opts) do
    quote do
      on_mount {MediaCentaurWeb.Live.PlanHost, :default}
    end
  end

  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> Subscriptions.subscribe(Acquisition)
      |> Subscriptions.subscribe(Watchlist)
      |> assign(:plan, %State{
        search_health: IndexerHealth.cached(),
        search_outage: SearchOutage.reason()
      })
      |> attach_hook(:plan_params, :handle_params, &apply_params/3)
      |> attach_hook(:plan_events, :handle_event, &handle_event/3)
      |> attach_hook(:plan_async, :handle_async, &handle_async/3)
      |> attach_hook(:plan_info, :handle_info, &handle_info/2)

    {:cont, socket}
  end

  # --- the page's side ---

  @query_keys %{"plan" => :plan, "tmdb_id" => :tmdb_id, "tmdb_type" => :tmdb_type, "mode" => :mode}

  @doc """
  Opens the plan modal on this page with a `PlanQuery` query — the board
  of a plan, or the picker for a title — by patching the page's own path.
  """
  @spec open_plan(Phoenix.LiveView.Socket.t(), PlanQuery.query()) :: Phoenix.LiveView.Socket.t()
  def open_plan(socket, query) when is_map(query) do
    keyword =
      for key <- ~w(plan tmdb_id tmdb_type mode),
          Map.has_key?(query, key),
          do: {@query_keys[key], query[key]}

    push_patch(socket, to: socket.view.overlay_path(socket, keyword))
  end

  @doc "The open plan's subject — for a page's `page_facts/3`, when the title detail asks about it."
  @spec subject(Phoenix.LiveView.Socket.t()) :: Title.t() | nil
  def subject(%{assigns: %{plan: %State{title: title}}}), do: title
  def subject(_socket), do: nil

  attr :plan, State, required: true
  attr :disclosures, :any, required: true, doc: "the page's `DisclosureState`"
  attr :armed_gesture, :any, required: true, doc: "the page's `ArmGesture` state"

  @doc "The plan modal from the host's state — the one line a page renders beside its title detail."
  def overlay(assigns) do
    assigns =
      assign(
        assigns,
        :backdrop_url,
        PlanLogic.shell_backdrop_url(assigns.plan.stage, %{
          identity: assigns.plan.identity,
          selection: assigns.plan.selection,
          movie: assigns.plan.movie,
          artwork: assigns.plan.artwork
        })
      )

    ~H"""
    <PlanModal.plan_modal
      open={@plan.param != nil}
      stage={@plan.stage}
      mode={PlanLogic.picker_mode(@plan.param)}
      menu_open={@plan.menu_open?}
      backdrop_url={@backdrop_url}
      identity={@plan.identity}
      selection={@plan.selection}
      chosen={@plan.chosen}
      movie={@plan.movie}
      board={@plan.board}
      error={@plan.error}
      last_activity={@plan.last_activity}
      search_progress={@plan.search_progress}
      disclosures={@disclosures}
      alternatives={@plan.alternatives}
      discard_armed={ArmGesture.armed?(@armed_gesture, "plan_discard")}
      search_health={@plan.search_health}
      gap_verdict={@plan.gap_verdict}
      rejected={@plan.rejected}
      subject={@plan.title}
      rung={@plan.rung}
    />
    """
  end

  # --- URL ---

  # `?plan=new&tmdb_id=…&tmdb_type=…[&mode=…]` opens targeting; `?plan=<id>`
  # the durable draft's board; no param closes. A link the app cannot mean
  # — a bad mode or type, a plan id that is not one — opens nothing, and
  # the flash says why.
  defp apply_params(params, _uri, socket) do
    socket =
      case PlanQuery.parse(params) do
        :closed ->
          close_plan(socket)

        {:picker, tmdb_id, tmdb_type, mode} ->
          open_targeting(socket, tmdb_id, tmdb_type, mode)

        {:board, plan_id} ->
          load_board(socket, plan_id)

        {:error, :malformed} ->
          Log.warning(
            :acquisition,
            "malformed plan link — #{inspect(Map.take(params, ~w(plan tmdb_id tmdb_type mode)))}"
          )

          socket |> close_plan() |> put_flash(:error, "Malformed plan link.")
      end

    {:cont, socket}
  end

  defp close_path(socket), do: socket.view.overlay_path(socket, [])

  # Closing hands the page back; Downloads' omnibox takes the focus again
  # (client-side, pointer users only — the `omnibox:refocus` listener in
  # app.js; keyboard/gamepad focus is the input system's, ADR-053).
  defp close_plan(%{assigns: %{plan: %State{param: nil}}} = socket), do: socket

  defp close_plan(socket) do
    socket
    |> push_event("omnibox:refocus", %{})
    |> put_plan(
      param: nil,
      menu_open?: false,
      selection: nil,
      movie: nil,
      board: nil,
      gap_verdict: nil,
      rejected: nil,
      search_progress: nil,
      alternatives: nil,
      error: nil,
      identity: nil,
      artwork: nil,
      title: nil,
      rung: nil
    )
  end

  defp put_plan(socket, attrs), do: update(socket, :plan, &struct!(&1, attrs))

  # --- events ---

  defp handle_event("plan_open", %{"tmdb_id" => tmdb_id, "tmdb_type" => tmdb_type}, socket)
       when tmdb_type in ["tv", "movie"],
       do: {:halt, open_plan(socket, PlanQuery.picker(tmdb_id, tmdb_type))}

  defp handle_event("close_plan", _params, socket),
    do: {:halt, push_patch(socket, to: close_path(socket))}

  defp handle_event("plan_" <> _ = event, params, socket), do: {:halt, plan_event(event, params, socket)}
  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp plan_event("plan_preset", %{"preset" => preset}, socket)
       when preset in ~w(everything_aired continue latest_season clear) do
    selection = socket.assigns.plan.selection
    put_plan(socket, chosen: PlanLogic.apply_preset(selection, String.to_existing_atom(preset)))
  end

  defp plan_event("plan_toggle_season", %{"season" => season}, socket) do
    %State{chosen: chosen, selection: selection} = socket.assigns.plan
    put_plan(socket, chosen: PlanLogic.toggle_season(chosen, selection, String.to_integer(season)))
  end

  defp plan_event("plan_toggle_unit", %{"season" => season, "episode" => episode}, socket) do
    %State{chosen: chosen, selection: selection} = socket.assigns.plan
    unit = {String.to_integer(season), String.to_integer(episode)}
    put_plan(socket, chosen: PlanLogic.toggle_unit(chosen, selection, unit))
  end

  # The Download split's menu is open state the host owns; the item's
  # event landing (`plan_create` with a mode) closes it.
  defp plan_event("plan_mode_toggle", _params, socket),
    do: put_plan(socket, menu_open?: not socket.assigns.plan.menu_open?)

  defp plan_event("plan_menu_close", _params, socket), do: put_plan(socket, menu_open?: false)

  # The main segment sends no mode and performs the one the picker was
  # opened with; the menu item names the other.
  defp plan_event("plan_create", params, socket) do
    %State{param: {_tmdb_id, _tmdb_type, main_mode}} = plan = socket.assigns.plan
    mode = PlanningMode.parse_mode(params["mode"], main_mode)
    opts = [approval_policy: PlanningMode.approval_policy(mode)]
    socket = put_plan(socket, menu_open?: false)

    result =
      case plan.stage do
        :targeting ->
          units = PlanLogic.chosen_in_order(plan.chosen, plan.selection)
          if units == [], do: :noop, else: Plans.create_series_plan(plan.selection, units, opts)

        :movie_confirm ->
          if plan.movie.in_library?, do: :noop, else: Plans.create_movie_plan(plan.movie, opts)
      end

    case result do
      :noop ->
        socket

      # The ending follows the mode (spec 2026-09-23 §7): manual selection
      # opens the board; auto-select lands by the host's `download_started/1`,
      # the plan committing on its own when clean and parking otherwise.
      {:ok, created} ->
        PlanFlow.land_plan(socket, mode, created, created.title, :leave)

      {:error, reason} ->
        Log.warning(:acquisition, "plan create failed — #{inspect(reason)}")
        put_flash(socket, :error, Logic.failure_flash("create the plan", reason))
    end
  end

  defp plan_event("plan_show_alternatives", %{"unit-id" => unit_id}, socket) do
    case Plans.Alternatives.for_unit(unit_id) do
      {:ok, items} ->
        put_plan(socket, alternatives: %{unit_id: unit_id, items: items, searching?: false})

      {:error, :not_found} ->
        socket
    end
  end

  defp plan_event("plan_find_more_alternatives", %{"unit-id" => unit_id}, socket) do
    case socket.assigns.plan.alternatives do
      %{unit_id: ^unit_id, searching?: false} = open ->
        socket
        |> put_plan(alternatives: Map.put(open, :searching?, true))
        |> start_async(:plan_find_more, fn -> {unit_id, Plans.Alternatives.search(unit_id)} end)

      _other ->
        socket
    end
  end

  defp plan_event("plan_hide_alternatives", _params, socket), do: put_plan(socket, alternatives: nil)

  # The gap banner's escape hatch (UIDR-022): list every raw candidate
  # the run rejected, with the gate it failed. Movie boards only —
  # `movie_gap_unit_id/1` is nil elsewhere and the button never renders.
  defp plan_event("plan_show_rejected", _params, socket) do
    with %{plan_id: plan_id} = board <- socket.assigns.plan.board,
         unit_id when is_binary(unit_id) <- PlanBoard.movie_gap_unit_id(board),
         {:ok, plan} <- Plans.fetch(plan_id) do
      items = plan |> Plans.Alternatives.gap_evidence() |> PlanLogic.rejected_items()
      put_plan(socket, rejected: %{unit_id: unit_id, items: items})
    else
      _no_movie_gap -> socket
    end
  end

  defp plan_event("plan_hide_rejected", _params, socket), do: put_plan(socket, rejected: nil)

  defp plan_event("plan_choose_rejected", %{"unit-id" => unit_id, "guid" => guid}, socket) do
    case Plans.Alternatives.choose_rejected(unit_id, guid) do
      {:ok, _plan} ->
        put_plan(socket, rejected: nil)

      {:error, reason} ->
        Log.warning(:acquisition, "plan rejected-pick failed — #{inspect(reason)}")
        put_flash(socket, :error, Logic.failure_flash("pick that release", reason))
    end
  end

  defp plan_event("plan_choose_release", %{"unit-id" => unit_id, "guid" => guid}, socket) do
    case Plans.Alternatives.choose_release(unit_id, guid) do
      {:ok, _plan} ->
        put_plan(socket, alternatives: nil)

      {:error, reason} ->
        Log.warning(:acquisition, "plan choose failed — #{inspect(reason)}")
        put_flash(socket, :error, Logic.failure_flash("pick that release", reason))
    end
  end

  defp plan_event("plan_swap_release", %{"unit-id" => unit_id, "guid" => guid}, socket) do
    case Plans.exclude_release(unit_id, guid) do
      {:ok, _plan} ->
        put_plan(socket, alternatives: nil)

      {:error, reason} ->
        Log.warning(:acquisition, "plan swap failed — #{inspect(reason)}")
        put_flash(socket, :error, Logic.failure_flash("swap that release", reason))
    end
  end

  # The board cell is the control. Which way it runs is read from the stored
  # unit, not from what this page last rendered, so a stale board cannot
  # exclude the same unit twice.
  defp plan_event("plan_toggle_unit_excluded", %{"unit-id" => unit_id}, socket) do
    case Plans.toggle_unit_excluded(unit_id) do
      {:ok, _plan} ->
        socket

      {:error, reason} ->
        Log.warning(:acquisition, "plan unit toggle failed — #{inspect(reason)}")
        put_flash(socket, :error, Logic.failure_flash("change that episode", reason))
    end
  end

  defp plan_event("plan_search_again", _params, socket) do
    with %{plan_id: plan_id} <- socket.assigns.plan.board,
         {:ok, plan} <- Plans.fetch(plan_id),
         {:ok, _plan} <- Plans.replan(plan, force_search: true) do
      socket
    else
      {:error, reason} -> put_flash(socket, :error, Logic.failure_flash("re-run the search", reason))
      _no_board -> put_flash(socket, :error, "Could not re-run the search — no plan is open.")
    end
  end

  # Approval is a write — the pursuit, a grabbing target per release and the
  # commit, one transaction; the grabs run in jobs (campaign durable-work,
  # G1) — so it runs here rather than in a task the page could lose.
  defp plan_event("plan_approve", _params, socket) do
    case socket.assigns.plan.board do
      %{plan_id: plan_id} ->
        outcome = with {:ok, plan} <- Plans.fetch(plan_id), do: Plans.approve(plan)
        approved(socket, outcome)

      _no_board ->
        socket
    end
  end

  # Discarding a draft loses the person's targeting: the arm gesture
  # (MC0027 tier 2).
  defp plan_event("plan_discard", _params, socket) do
    case ArmGesture.press(socket, "plan_discard") do
      {:armed, socket} -> socket
      {:fire, socket} -> discard(socket)
    end
  end

  # The per-title acceptance (UIDR-029 / ADR-063 §2): one press means
  # lower quality is fine for this title — track it, store the
  # preference, re-solve. The global default never changes.
  defp plan_event("plan_accept_lower_quality", _params, socket) do
    with %{plan_id: plan_id} <- socket.assigns.plan.board,
         {:ok, plan} <- Plans.fetch(plan_id),
         {:ok, _planning} <- Plans.accept_lower_quality(plan) do
      socket
    else
      {:error, reason} ->
        put_flash(socket, :error, Logic.failure_flash("accept lower quality for this title", reason))

      _no_board ->
        put_flash(socket, :error, "Could not accept lower quality for this title — no plan is open.")
    end
  end

  defp plan_event("plan_undo_lower_quality", _params, socket) do
    with %{plan_id: plan_id} <- socket.assigns.plan.board,
         {:ok, plan} <- Plans.fetch(plan_id),
         {:ok, _planning} <- Plans.undo_lower_quality(plan) do
      socket
    else
      {:error, reason} ->
        put_flash(socket, :error, Logic.failure_flash("undo the lower-quality acceptance", reason))

      _no_board ->
        put_flash(socket, :error, "Could not undo the lower-quality acceptance — no plan is open.")
    end
  end

  # Stopping a search is one press, no confirmation — nothing is lost
  # by stopping (UIDR-029). The run observes the discard within one
  # search term (ADR-063 §3). Discard-with-confirmation remains for
  # ready boards, where a solved plan is being thrown away.
  defp plan_event("plan_stop_searching", _params, socket) do
    with %{plan_id: plan_id, status: :planning} <- socket.assigns.plan.board,
         {:ok, plan} <- Plans.fetch(plan_id),
         {:ok, _discarded} <- Plans.discard(plan) do
      socket |> put_flash(:info, "Stopped searching.") |> push_patch(to: close_path(socket))
    else
      {:error, reason} -> put_flash(socket, :error, Logic.failure_flash("stop this search", reason))
      _no_board -> put_flash(socket, :error, "Could not stop this search — no plan is open.")
    end
  end

  defp plan_event(_event, _params, socket), do: socket

  defp approved(socket, {:ok, _committed}) do
    socket |> put_flash(:info, "Download started.") |> socket.view.download_started()
  end

  defp approved(socket, {:error, {:overlap, units}}) do
    put_flash(
      socket,
      :error,
      "Already being pursued: #{Logic.overlap_labels(units)}. Remove the overlap first."
    )
  end

  defp approved(socket, {:error, :nothing_to_grab}),
    do: put_flash(socket, :error, "Nothing in this plan is grabbable yet.")

  defp approved(socket, {:error, reason}) do
    Log.warning(:acquisition, "plan approve failed — #{inspect(reason)}")
    put_flash(socket, :error, Logic.failure_flash("commit the plan", reason))
  end

  defp discard(socket) do
    with %{plan_id: plan_id} <- socket.assigns.plan.board,
         {:ok, plan} <- Plans.fetch(plan_id),
         {:ok, _discarded} <- Plans.discard(plan) do
      socket |> put_flash(:info, "Plan discarded.") |> push_patch(to: close_path(socket))
    else
      {:error, reason} -> put_flash(socket, :error, Logic.failure_flash("discard the plan", reason))
      _no_board -> put_flash(socket, :error, "Could not discard the plan — no plan is open.")
    end
  end

  # --- asyncs ---

  defp handle_async(:plan_targeting, {:ok, outcome}, socket) do
    socket =
      case outcome do
        {:tv, selection} ->
          put_plan(socket,
            stage: :targeting,
            selection: selection,
            chosen: PlanLogic.apply_preset(selection, :everything_aired)
          )

        {:movie, movie} ->
          put_plan(socket, stage: :movie_confirm, movie: movie)

        {:error, reason} ->
          Log.warning(:acquisition, "plan targeting failed — #{inspect(reason)}")
          put_plan(socket, stage: :error, error: "Couldn't load this title from TMDB.")
      end

    {:halt, socket}
  end

  defp handle_async(:plan_targeting, {:exit, reason}, socket) do
    Log.warning(:acquisition, "plan targeting crashed — #{inspect(reason)}")
    {:halt, put_plan(socket, stage: :error, error: "Couldn't load this title from TMDB.")}
  end

  defp handle_async({:plan_artwork, plan_id}, {:ok, urls}, socket) do
    if socket.assigns.plan.param == plan_id,
      do: {:halt, put_plan(socket, artwork: urls)},
      else: {:halt, socket}
  end

  defp handle_async({:plan_artwork, _plan_id}, {:exit, reason}, socket) do
    Log.warning(:acquisition, "plan artwork fetch crashed — #{inspect(reason)}")
    {:halt, socket}
  end

  # The window landed: re-read the board so a ready verdict speaks it.
  # The durable rows are the state of record, so a re-read is the whole
  # of what "recompute" means here.
  defp handle_async({:plan_release_window, plan_id}, {:ok, {:ok, payload}}, socket) do
    if socket.assigns.plan.param == plan_id do
      window = ReleaseWindow.from_payload(payload, socket.assigns.today)
      {:halt, socket |> put_plan(release_window: window) |> load_board(plan_id)}
    else
      {:halt, socket}
    end
  end

  defp handle_async({:plan_release_window, _plan_id}, {:ok, {:error, reason}}, socket) do
    Log.debug(:tmdb, "release window unavailable — #{inspect(reason)}")
    {:halt, socket}
  end

  defp handle_async({:plan_release_window, _plan_id}, {:exit, reason}, socket) do
    Log.warning(:acquisition, "release window fetch crashed — #{inspect(reason)}")
    {:halt, socket}
  end

  defp handle_async(:plan_find_more, {:ok, {unit_id, result}}, socket) do
    socket =
      case {result, socket.assigns.plan.alternatives} do
        {{:ok, items}, %{unit_id: ^unit_id}} ->
          put_plan(socket, alternatives: %{unit_id: unit_id, items: items, searching?: false})

        {_result, %{unit_id: ^unit_id} = open} ->
          put_plan(socket, alternatives: Map.put(open, :searching?, false))

        _other ->
          socket
      end

    {:halt, socket}
  end

  defp handle_async(:plan_find_more, {:exit, reason}, socket) do
    Log.warning(:acquisition, "find-more alternatives crashed — #{inspect(reason)}")

    case socket.assigns.plan.alternatives do
      %{} = open -> {:halt, put_plan(socket, alternatives: Map.put(open, :searching?, false))}
      _other -> {:halt, socket}
    end
  end

  defp handle_async(_name, _result, socket), do: {:cont, socket}

  # --- PubSub ---

  # The durable plan rows are the state of record — a Changed event for
  # the open plan just re-reads the board. The page's own lists (Downloads'
  # drafts) react to the same message, so it continues.
  defp handle_info(%PlanEvents.Changed{plan_id: plan_id}, socket) do
    if socket.assigns.plan.param == plan_id do
      socket =
        socket
        |> put_plan(search_health: IndexerHealth.cached(), search_outage: SearchOutage.reason())
        |> load_board(plan_id)

      {:cont, socket}
    else
      {:cont, socket}
    end
  end

  defp handle_info(%PlanEvents.SearchActivity{} = activity, socket) do
    if socket.assigns.plan.param == activity.plan_id do
      # A zero-result live search just refreshed the IndexerHealth cache
      # and the availability value (Corpus disambiguates empty-vs-blind at
      # search time, UIDR-016) — re-read both, so the ticker and the gap
      # banner speak from the same moment.
      outage = SearchOutage.reason()

      {:halt,
       put_plan(socket,
         last_activity: PlanLogic.search_activity_line(activity, outage),
         search_health: IndexerHealth.cached(),
         search_outage: outage
       )}
    else
      {:halt, socket}
    end
  end

  defp handle_info(%PlanEvents.SearchProgress{} = status, socket) do
    if socket.assigns.plan.param == status.plan_id do
      {:halt,
       put_plan(socket,
         search_progress: SearchProgressPanel.build(status),
         gap_verdict: GapVerdict.searching(status) || socket.assigns.plan.gap_verdict
       )}
    else
      {:halt, socket}
    end
  end

  # The board's bookmark reads the ladder.
  defp handle_info({:title_intent_changed, _event}, socket),
    do: {:cont, put_plan(socket, rung: rung_for(socket.assigns.plan.title))}

  defp handle_info(_message, socket), do: {:cont, socket}

  defp rung_for(%Title{} = title), do: Map.get(Watchlist.rungs(), Title.ref(title))
  defp rung_for(nil), do: nil

  # --- the picker ---

  defp open_targeting(socket, tmdb_id, tmdb_type, mode) do
    param = {tmdb_id, tmdb_type, mode || PlanningMode.value()}

    if socket.assigns.plan.param == param do
      socket
    else
      socket
      |> put_plan(
        param: param,
        stage: :loading,
        menu_open?: false,
        selection: nil,
        movie: nil,
        board: nil,
        gap_verdict: nil,
        rejected: nil,
        chosen: MapSet.new(),
        error: nil,
        identity: matching_identity(socket, tmdb_id, tmdb_type),
        artwork: nil
      )
      |> start_async(:plan_targeting, fn -> load_targeting(tmdb_id, tmdb_type) end)
    end
  end

  # The picked search result survives into the loading stage only when it
  # actually is this plan's title — a URL-driven open (refresh, shared
  # link) has nothing in hand and gets the scrim-only shell.
  defp matching_identity(socket, tmdb_id, tmdb_type) do
    identity = socket.assigns.plan.identity
    wanted_type = if tmdb_type == "movie", do: :movie, else: :tv_series

    if identity && to_string(identity.tmdb_id) == to_string(tmdb_id) &&
         identity.media_type == wanted_type do
      identity
    end
  end

  # Runs in the :plan_targeting async task — TMDB + library reads only.
  defp load_targeting(tmdb_id, "tv") do
    case Targeting.series_selection(tmdb_id) do
      {:ok, selection} -> {:tv, selection}
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_targeting(tmdb_id, "movie") do
    case MediaCentaur.TMDB.Store.ensure({tmdb_id, :movie}) do
      {:ok, %{payload: movie}} ->
        in_library? =
          case MediaCentaur.Library.ExternalIds.find_present_movie(to_string(tmdb_id)) do
            {:ok, _path} -> true
            :not_found -> false
          end

        {:movie, TitlePreview.movie(movie, in_library?)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- the board ---

  defp load_board(socket, plan_id) do
    case Plans.fetch(plan_id) do
      {:ok, plan} ->
        board = Plans.Board.build(plan)
        # Live activity is per-plan and session-only (no persisted history):
        # switching to a different plan must drop the previous plan's ticker
        # line rather than let it linger as if it described this one.
        switching_plan? = socket.assigns.plan.param != plan_id

        socket =
          socket
          |> maybe_load_artwork(plan_id, plan)
          |> maybe_load_release_window(plan_id, plan)

        title = Plans.Plan.tmdb_title(plan)

        put_plan(socket,
          param: plan_id,
          stage: :board,
          board: board,
          title: title,
          rung: rung_for(title),
          gap_verdict: verdict_for(socket, plan_id, plan, board),
          search_progress: search_progress_for(socket, plan_id, board),
          error: nil,
          last_activity: if(!switching_plan?, do: socket.assigns.plan.last_activity)
        )

      {:error, :not_found} ->
        put_plan(socket,
          param: plan_id,
          stage: :error,
          error: "Plan not found — it may have been discarded."
        )
    end
  end

  # The board's identity artwork — release tracking's local cache first
  # (same store the pursuit modal reads), the network `TmdbArtwork.ensure/2`
  # kicked off-process only on a fresh open with an empty cache.
  defp maybe_load_artwork(socket, plan_id, plan) do
    if socket.assigns.plan.param == plan_id do
      socket
    else
      artwork = MediaCentaur.TmdbArtwork.urls(plan.tmdb_type, plan.tmdb_id)
      socket = put_plan(socket, artwork: artwork)

      if is_nil(artwork.backdrop_url) and Capabilities.tmdb_ready?() do
        start_async(socket, {:plan_artwork, plan_id}, fn ->
          MediaCentaur.TmdbArtwork.ensure(plan.tmdb_type, plan.tmdb_id)
        end)
      else
        socket
      end
    end
  end

  # A movie's release window — the calendar the verdict speaks (spec
  # 2026-09-14) — read once per board open, off-process, from the TMDB
  # store (ADR-071). Never stored on the plan: a draft can sit for days,
  # and a digital date announced since must read as the store says it
  # today — the store is checked while the film is unsettled, so it
  # does. Series boards read nothing.
  defp maybe_load_release_window(socket, plan_id, plan) do
    cond do
      socket.assigns.plan.param == plan_id ->
        socket

      plan.tmdb_type == "movie" and Capabilities.tmdb_ready?() ->
        socket
        |> put_plan(release_window: nil)
        |> start_async({:plan_release_window, plan_id}, fn ->
          with {:ok, %{payload: movie}} <- MediaCentaur.TMDB.Store.ensure({plan.tmdb_id, :movie}),
               do: {:ok, movie}
        end)

      true ->
        put_plan(socket, release_window: nil)
    end
  end

  # Keep a live-updated panel across board reloads; seed the itinerary
  # for a freshly-opened planning board; movies don't narrate.
  # A planning TV board's verdict is the searching world (kept across
  # re-reads of the same plan so a SearchProgress event's headline is
  # not clobbered by the initial one); a ready board's is the diagnosis.
  defp verdict_for(socket, plan_id, plan, board) do
    %State{} = state = socket.assigns.plan

    cond do
      board.status == :planning and board.movie? ->
        nil

      board.status == :planning and state.param == plan_id and
          match?(%GapVerdict{world: :searching}, state.gap_verdict) ->
        state.gap_verdict

      board.status == :planning ->
        GapVerdict.searching_initial(board.wanted)

      true ->
        gap_verdict(plan, board, state.search_outage, state.release_window)
    end
  end

  # The adaptive verdict (UIDR-022, extended by UIDR-029 and the calendar
  # worlds of spec 2026-09-14) — a ready board with gaps or
  # below-preference units leads with the world the counts prove;
  # recomputed on every board re-read so a forced re-search refreshes
  # the evidence's freshness and a late-arriving release window is read.
  defp gap_verdict(plan, board, outage, release_window) do
    gaps = PlanBoard.gap_labels(board)
    below_preference = PlanBoard.below_preference(board)

    if board.status == :ready and (gaps != [] or below_preference != nil) do
      below =
        case below_preference do
          nil -> nil
          summary -> %{units: summary.units, releases: summary.releases}
        end

      GapVerdict.build(
        Plans.Alternatives.gap_evidence(plan),
        gaps: gaps,
        movie?: board.movie?,
        blind_reason: outage,
        now: DateTime.utc_now(),
        below: below,
        wanted: board.wanted,
        covered: board.covered,
        release_window: release_window
      )
    end
  end

  defp search_progress_for(socket, plan_id, board) do
    %State{} = state = socket.assigns.plan

    cond do
      state.param == plan_id && state.search_progress -> state.search_progress
      board.status == :planning and not board.movie? -> SearchProgressPanel.initial(board.wanted)
      true -> nil
    end
  end
end
