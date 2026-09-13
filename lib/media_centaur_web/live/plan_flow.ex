defmodule MediaCentaurWeb.Live.PlanFlow do
  @moduledoc """
  The ending a download gets, in one place: how a planning mode maps to a
  plan's approval policy, the flash auto-select raises, and the words for
  each way planning can fail.

  Two surfaces start downloads and neither hosts the other. The title detail
  modal (`MediaCentaurWeb.TitleDetailHost`, on Discovery and Incoming)
  downloads a whole title; the library detail modal
  (`MediaCentaurWeb.Live.EntityModal`, on Library and Home) downloads the one
  episode a missing row names. What they do with the result is identical, and
  it lives here rather than twice.

  Deliberately not a `use` macro: it holds no state and attaches no hooks.
  Both callers keep their own `download_pending` assign and their own async
  naming, because what is pending differs — a title on one side, a
  `{season, episode}` unit on the other.
  """

  alias MediaCentaur.Settings.Preferences.PlanningMode

  @typedoc "Why a plan was not created."
  @type failure :: :nothing_to_plan | :unaired | :already_here | :not_listed | :tracked | term()

  @doc """
  The approval policy a planning mode asks for. Auto-select commits a clean
  plan with nobody looking; manual select parks it on its board.
  """
  @spec approval_policy(PlanningMode.mode()) :: String.t()
  def approval_policy(:auto_select_best_release), do: "automatic"
  def approval_policy(_manually_select_release), do: "review"

  @doc "The flash a one-click download raises, for any label."
  @spec download_flash(String.t()) :: String.t()
  def download_flash(label), do: "Finding a release for #{label}"

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
