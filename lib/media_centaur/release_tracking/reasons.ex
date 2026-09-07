defmodule MediaCentaur.ReleaseTracking.Reasons do
  @moduledoc """
  Whether a tracked title should continue to exist, and what mode a new
  one starts in ([ADR-065]).

  A tracked title is not authored — it exists while a **tracking reason**
  holds. There are exactly two, and they are deliberately not equivalent:

    * the **library reason** — the library owns an active container for
      the title — is a *default*. The app tracks the title because you
      own it, so the default evaporates when the library stops owning it.
    * the **watchlist reason** — a person armed the title's watchlist
      entry — is an *act*, and outlives the library.

  Two facts override both. A **movie already in the library** is
  *complete*: a single film has a finite calendar and there is nothing
  left to track, whatever anyone asked for. And an **explicit disarm**
  (`mode: :none`) is durable — the row survives with no reason held,
  inert, so that re-acquiring or re-listing the title later cannot
  silently re-arm what a person turned off.

  Pure: every fact is resolved by the caller, so the rule is testable
  without a database and reads as the decision record does.

  [ADR-065]: `decisions/architecture/2026-09-07-065-tracking-reasons-and-the-derived-tracked-title.md`
  """

  alias MediaCentaur.ReleaseTracking.Item

  @typedoc "Everything the retention rule needs, resolved by the caller."
  @type facts :: %{
          mode: Item.tracking_mode(),
          media_type: :movie | :tv_series,
          library_reason?: boolean(),
          watchlist_reason?: boolean(),
          movie_in_library?: boolean()
        }

  @doc """
  Whether an existing tracked title should be kept.

  Order matters: completion beats the durable disarm, because a movie
  you own has no future release to arm or disarm.
  """
  @spec retain?(facts()) :: boolean()
  def retain?(%{movie_in_library?: true}), do: false
  def retain?(%{mode: :none}), do: true
  def retain?(%{library_reason?: true}), do: true
  def retain?(%{watchlist_reason?: true}), do: true
  def retain?(_no_reason), do: false

  @doc """
  The mode a newly created tracked title starts in.

  Auto-grab is opt-in: a person arming a watchlist entry gets `:watch` —
  the calendar, nothing more — so adding a title to a list can never
  start a download. The library scan gets `:global`, preserving the
  established behaviour in which the global auto-grab setting is the
  person's opt-in.
  """
  @spec seed_mode(:watchlist | :library) :: Item.tracking_mode()
  def seed_mode(:watchlist), do: :watch
  def seed_mode(:library), do: :global
end
