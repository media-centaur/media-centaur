defmodule MediaCentaurWeb.Live.PlanFlow do
  @moduledoc """
  The ending a download gets, in one place: the flash auto-select raises,
  and the words for each way planning can fail. How a planning mode maps
  to a plan's approval policy is the setting's own
  (`Settings.Preferences.PlanningMode.approval_policy/1`).

  Three surfaces start downloads and none hosts another. The title detail
  modal (`MediaCentaurWeb.Live.TitleDetailHost`, on Home, Library,
  Discovery and Incoming) downloads a whole title by scope, and one
  missing episode of an owned series from its gap row. The picker on
  Incoming (`MediaCentaurWeb.IncomingLive`, the plan modal's targeting
  stage and movie confirm) downloads what the person chose there. A plan
  any of them has just created ends through `land_plan/5`. The scoped
  title download's auto-select path is the one exception: it hands the
  title to the supervised door (`Plans.plan_title/2`) and has no plan in
  hand, so it flashes `download_flash/1` directly.

  Deliberately not a `use` macro: it holds no state and attaches no hooks.
  The title detail keeps what it has in flight in `Title.ModalState.pending`;
  the picker creates its plan synchronously and has nothing pending.
  """

  import Phoenix.LiveView, only: [put_flash: 3]

  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.Settings.Preferences.PlanningMode
  alias MediaCentaurWeb.IncomingLive.PlanQuery

  @type socket :: Phoenix.LiveView.Socket.t()

  @typedoc "Why a plan was not created."
  @type failure :: :nothing_to_plan | :unaired | :already_here | :not_listed | :tracked | term()

  @doc "The flash a one-click download raises, for any label."
  @spec download_flash(String.t()) :: String.t()
  def download_flash(label), do: "Finding a release for #{label}"

  @doc """
  Ends a plan a surface has just created under `mode` (spec 2026-09-23
  §7). Manual selection opens the plan's board through the host's
  `open_plan/2`. Auto-select flashes `download_flash/1` for `label` and
  leaves the surface as `close` says — the picker drops its modal, the
  title detail's gap row stays put (`& &1`).
  """
  @spec land_plan(socket(), PlanningMode.mode(), Plans.Plan.t(), String.t(), (socket() -> socket())) ::
          socket()
  def land_plan(socket, :manually_select_release, plan, _label, _close),
    do: socket.view.open_plan(socket, PlanQuery.board(plan.id))

  def land_plan(socket, :auto_select_best_release, _plan, label, close),
    do: socket |> put_flash(:info, download_flash(label)) |> close.()

  @doc """
  Plain words for each way planning can end without a plan. The first four
  are facts about the library or the calendar; anything else is TMDB's
  answer or its absence.
  """
  @spec failure_flash(String.t(), failure()) :: String.t()
  def failure_flash(label, :nothing_to_plan),
    do: "Nothing to download for #{label}: every aired episode is already in your library or on its way."

  def failure_flash(_label, :unaired), do: "That episode hasn't aired yet."
  def failure_flash(_label, :already_here), do: "That episode is already in your library."
  def failure_flash(_label, :not_listed), do: "TMDB doesn't list that episode for this season."
  def failure_flash(_label, :tracked), do: "That episode is already on its way."

  def failure_flash(label, _reason),
    do: "Couldn't plan #{label}. Check TMDB under Settings and try again."
end
