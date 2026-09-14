defmodule MediaCentaurWeb.Live.TitleDetailHost.Acquisition do
  @moduledoc """
  The title detail's acquisition acts, shared by every host of the
  modal: moving a title's rung, the Download control's plan, and the
  plan for one missing episode of an owned series.

  `apply_rung/4` is the one write behind the bookmark and the tracking
  switches (`set_rung`). Raising onto a rung that follows releases needs
  the calendar, which is a TMDB fetch — so a title that has none yet is
  set asynchronously (`ReleaseTracking.set_rung_async/3`) and the modal
  catches up on the `:releases_updated` broadcast; every other move is
  local and lands before the reply. `attrs` is the provenance a
  feed-born listing carries onto the record it creates.

  `start_download/4` performs a planning mode on a title (spec
  2026-09-12 §5–7): auto-select hands the plan to the supervised door
  (`Plans.plan_title/2`, `automatic`), flashes, and closes the modal;
  manually selecting plans under `start_async` (`Plans.create_title_plan/2`,
  `review`) and opens the plan's board on Incoming once it exists,
  through the host's `open_plan_board/2`. `download_missing_episode/2`
  does the same for one aired episode of an owned series a gap row
  names, through `Plans.create_series_plan/3`. Either plan is the one
  thing the modal has in flight (`ModalState.pending`); a click while
  one is pending is a no-op, and closing the modal abandons it. A
  download never moves the title's rung (ADR-066).
  """

  import Phoenix.Component, only: [update: 3]
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2, start_async: 3]

  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.Acquisition.Plans.DownloadScope
  alias MediaCentaur.Acquisition.Targeting
  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Settings.Preferences.PlanningMode
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Title.Detail, as: TitleDetail
  alias MediaCentaurWeb.Live.PlanFlow
  alias MediaCentaurWeb.Live.TitleDetailHost.LibraryHalf

  require MediaCentaur.Log, as: Log

  @type socket :: Phoenix.LiveView.Socket.t()

  # --- The rung ---

  @spec apply_rung(socket(), Title.t(), TitleIntent.rung() | :off, map()) :: socket()
  def apply_rung(socket, %Title{} = title, :off, _attrs) do
    {:ok, nil} = ReleaseTracking.set_rung(title, :off)
    socket
  end

  def apply_rung(socket, %Title{} = title, rung, attrs) do
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

  # --- Download ---

  @spec start_download(socket(), Title.t(), PlanningMode.mode(), DownloadScope.scope() | nil) :: socket()
  def start_download(%{assigns: %{modal_state: %{pending: pending}}} = socket, _title, _mode, _scope)
      when not is_nil(pending), do: socket

  def start_download(socket, %Title{} = title, :auto_select_best_release, scope) do
    policy = PlanningMode.approval_policy(:auto_select_best_release)
    :ok = Plans.plan_title(title, [approval_policy: policy] ++ scope_opts(scope))
    put_flash(socket, :info, PlanFlow.download_flash(title.name))
  end

  def start_download(socket, %Title{} = title, :manually_select_release, scope) do
    opts = [approval_policy: PlanningMode.approval_policy(:manually_select_release)] ++ scope_opts(scope)
    name = {:title_download, Title.ref(title), title.name}

    socket
    |> pending({:download, title.name})
    |> start_async(name, fn -> Plans.create_title_plan(title, opts) end)
  end

  defp scope_opts(nil), do: []
  defp scope_opts(scope), do: [scope: scope]

  @doc "Whether the pending plan is the one an async result names."
  @spec pending?(socket(), term()) :: boolean()
  def pending?(%{assigns: %{modal_state: %{pending: pending}}}, pending), do: true
  def pending?(_socket, _pending), do: false

  @doc "Records what the modal has in flight (nil when nothing)."
  @spec pending(socket(), nil | {:download, String.t()} | {:missing_episode, term()}) :: socket()
  def pending(socket, pending), do: update(socket, :modal_state, &%{&1 | pending: pending})

  # --- A missing episode of an owned series ---

  @doc """
  Plans one aired episode a gap row names (spec 2026-09-13
  series-gap-download design, decisions 9-10). Fetches the series'
  targeting selection — a TMDB read, on an explicit click, never on
  render — and creates a one-unit plan through `Plans.create_series_plan/3`.
  The selection is also the guard: an episode that has not aired, that
  arrived since the projection was built, or that release tracking is
  already chasing is not planned. The person's planning mode decides the
  approval policy and the ending, through `PlanFlow`.
  """
  @spec download_missing_episode(socket(), {pos_integer(), pos_integer()}) :: socket()
  def download_missing_episode(socket, unit) do
    detail = socket.assigns.title_detail
    entity = LibraryHalf.container_id(detail) && detail.library.entry.entity

    cond do
      socket.assigns.modal_state.pending -> socket
      is_nil(entity) or is_nil(entity.tmdb_id) -> socket
      true -> start_missing_episode_plan(socket, detail, entity, unit)
    end
  end

  defp start_missing_episode_plan(socket, %TitleDetail{} = detail, entity, unit) do
    name = {:missing_episode, LibraryHalf.subject(detail), unit}
    tmdb_id = entity.tmdb_id
    mode = PlanningMode.value()

    socket
    |> pending({:missing_episode, unit})
    |> start_async(name, fn -> plan_missing_episode(tmdb_id, unit, mode) end)
  end

  # Runs in the async task: TMDB read, the guard, then the plan door.
  defp plan_missing_episode(tmdb_id, {season, episode} = unit, mode) do
    with {:ok, selection} <- Targeting.series_selection(tmdb_id),
         label = "#{selection.title} S#{season}E#{episode}",
         :ok <- unit_plannable(selection, unit) do
      opts = [approval_policy: PlanningMode.approval_policy(mode)]

      case Plans.create_series_plan(selection, [unit], opts) do
        {:ok, plan} -> {:planned, plan, mode, label}
        {:error, reason} -> {:plan_failed, label, reason}
      end
    else
      {:skip, reason} -> {:plan_failed, "that episode", reason}
      {:error, reason} -> {:plan_failed, "that episode", reason}
    end
  end

  # `tracked?` matters because the rendering no longer says so: an aired
  # episode with no file is a Missing row whether or not release tracking
  # holds an open want for it, so planning here would duplicate the cadence.
  defp unit_plannable(selection, {season, episode}) do
    found =
      Enum.find_value(selection.seasons, fn listed_season ->
        listed_season.season_number == season &&
          Enum.find(listed_season.episodes, &(&1.episode_number == episode))
      end)

    cond do
      is_nil(found) -> {:skip, :not_listed}
      not found.aired? -> {:skip, :unaired}
      found.in_library? -> {:skip, :already_here}
      found.tracked? -> {:skip, :tracked}
      true -> :ok
    end
  end

  @doc "Ends a missing-episode plan: auto-select flashes and stays put, manual select lands on the plan's board."
  @spec apply_missing_episode_result(socket(), term()) :: socket()
  def apply_missing_episode_result(socket, {:planned, _plan, :auto_select_best_release, label}) do
    socket |> pending(nil) |> put_flash(:info, PlanFlow.download_flash(label))
  end

  def apply_missing_episode_result(socket, {:planned, plan, _manual, _label}) do
    socket |> pending(nil) |> push_navigate(to: "/incoming?plan=#{plan.id}")
  end

  def apply_missing_episode_result(socket, {:plan_failed, label, reason}) do
    Log.warning(:acquisition, "could not plan #{label} — #{inspect(reason)}")
    socket |> pending(nil) |> put_flash(:info, PlanFlow.failure_flash(label, reason))
  end

  @doc "A crashed planning task leaves the modal usable and says so."
  @spec apply_missing_episode_crash(socket(), term()) :: socket()
  def apply_missing_episode_crash(socket, reason) do
    Log.warning(:acquisition, "planning crashed for a missing episode — #{inspect(reason)}")
    socket |> pending(nil) |> put_flash(:error, PlanFlow.failure_flash("that episode", :crashed))
  end
end
