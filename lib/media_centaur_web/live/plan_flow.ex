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
  any of them has just created ends through `land_plan/5`; a download
  that has just started under auto-select — a plan in hand or not (the
  scoped title download hands the title to the supervised door,
  `Plans.plan_title/2`) — ends through `land_started/3`.

  Activity on Incoming is where a started download shows up (UIDR-015),
  so starting one points the page there: `land_started/3` remembers
  `/incoming?zone=activity` for the sidebar's Incoming entry
  (`remember_activity/1`, the `phx:nav-remember` listener in the root
  layout — the store the sidebar-remember script already reads) and then
  either leaves the surface through the host's `download_started/1`
  (Incoming patches to Activity itself; the others close the title
  detail) or stays put, as the surface says.

  Deliberately not a `use` macro: it holds no state and attaches no hooks.
  The title detail keeps what it has in flight in `Title.ModalState.pending`;
  the picker creates its plan synchronously and has nothing pending.
  """

  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]

  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.Settings.Preferences.PlanningMode
  alias MediaCentaurWeb.IncomingLive.Logic, as: IncomingLogic
  alias MediaCentaurWeb.IncomingLive.PlanQuery

  @type socket :: Phoenix.LiveView.Socket.t()

  @typedoc """
  What a surface does with itself once a download has started: `:leave`
  hands the person to the host's `download_started/1` (the title detail,
  the picker); `:stay` keeps the surface as it is (a gap row, whose
  neighbours may be next; a feed row, which has no modal to drop).
  """
  @type ending :: :leave | :stay

  @typedoc "Why a plan was not created."
  @type failure :: :nothing_to_plan | :unaired | :already_here | :not_listed | :tracked | term()

  @doc "The flash a one-click download raises, for any label."
  @spec download_flash(String.t()) :: String.t()
  def download_flash(label), do: "Finding a release for #{label}"

  @doc """
  Ends a plan a surface has just created under `mode` (spec 2026-09-23
  §7). Manual selection opens the plan's board through the host's
  `open_plan/2`. Auto-select is a download that has started:
  `land_started/3`.
  """
  @spec land_plan(socket(), PlanningMode.mode(), Plans.Plan.t(), String.t(), ending()) :: socket()
  def land_plan(socket, :manually_select_release, plan, _label, _ending),
    do: socket.view.open_plan(socket, PlanQuery.board(plan.id))

  def land_plan(socket, :auto_select_best_release, _plan, label, ending),
    do: land_started(socket, label, ending)

  @doc """
  Ends a download that has just started under auto-select (spec
  2026-09-23 follow-up §1): the flash for `label`, Incoming pointed at
  Activity for the sidebar, then the surface's `ending`. LiveView
  refuses two redirects in one reply, so `:leave` is the host's one act.
  """
  @spec land_started(socket(), String.t(), ending()) :: socket()
  def land_started(socket, label, ending) do
    socket = socket |> put_flash(:info, download_flash(label)) |> remember_activity()

    case ending do
      :leave -> socket.view.download_started(socket)
      :stay -> socket
    end
  end

  @doc """
  Points the sidebar's Incoming entry at Activity until the person picks
  another tab there. The entry reopens the URL the root layout remembers
  for the page (`data-nav-remember`); the `phx:nav-remember` listener
  beside that script writes it.
  """
  @spec remember_activity(socket()) :: socket()
  def remember_activity(socket),
    do:
      push_event(socket, "nav-remember", %{
        path: IncomingLogic.path(),
        url: IncomingLogic.zone_path(:activity)
      })

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
