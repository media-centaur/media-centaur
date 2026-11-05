defmodule MediaCentaur.Acquisition.ViewModels.PursuitHeader do
  @moduledoc """
  Identity contract for the pursuit window's header: the title, the
  state, the goal's scope over its units (`scope_label`) and the goal's
  facts (`facts`) — who started it, when, how long it ran, how many
  releases it tried, how it ended.

  `scope_label/2` and `facts/3` are pure and built by
  `MediaCentaur.Acquisition.Pursuits.detail_for/1` from the pursuit and
  its units. Search queries belong to a thread that is searching and live
  on `PursuitStatus`, not here.
  """

  alias MediaCentaur.Acquisition.Pursuits.{Recipe, State}
  alias MediaCentaur.Acquisition.ViewModels.PursuitRow
  alias MediaCentaur.Format

  @enforce_keys [:id, :title, :state, :recipe]
  defstruct [
    :id,
    :title,
    :state,
    :recipe,
    :scope_label,
    :criteria_summary,
    :backdrop_url,
    :logo_url,
    awaiting_decision?: false,
    facts: []
  ]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          title: String.t(),
          state: PursuitRow.state(),
          recipe: Recipe.t(),
          # The span over the units: a film's year, "S04E01", "Season 4 · 6
          # episodes", "5 seasons · 30 episodes"; nil for a query-door goal.
          scope_label: String.t() | nil,
          criteria_summary: String.t() | nil,
          backdrop_url: String.t() | nil,
          logo_url: String.t() | nil,
          awaiting_decision?: boolean(),
          # Short phrases the facts line joins with middle dots.
          facts: [String.t()]
        }

  @doc "The goal's scope over its units."
  @spec scope_label(map(), [map()]) :: String.t() | nil
  def scope_label(%{recipe_type: "prowlarr_query"}, _units), do: nil

  def scope_label(%{tmdb_type: type, year: year}, _units) when type in ["movie", :movie],
    do: if(year, do: Integer.to_string(year))

  def scope_label(_pursuit, units) do
    episodes = Enum.filter(units, &is_integer(&1.season_number))
    seasons = episodes |> Enum.map(& &1.season_number) |> Enum.uniq()

    case {seasons, episodes} do
      {[], _} -> nil
      {[season], [%{episode_number: nil}]} -> "Season #{season}"
      {[season], [%{episode_number: episode}]} -> Format.episode_label(season, episode)
      {[season], many} -> "Season #{season} · #{length(many)} episodes"
      {several, many} -> "#{length(several)} seasons · #{length(many)} episodes"
    end
  end

  @doc """
  The goal's facts: who started it, when, how long it ran (to its end, or
  to `now` while active), how many releases were tried, and how it ended.
  """
  @spec facts(map(), non_neg_integer(), DateTime.t()) :: [String.t()]
  def facts(
        %{origin: origin, inserted_at: started, state: state, updated_at: updated} = _pursuit,
        releases_tried,
        now
      ) do
    state = to_string(state)
    ended_at = if State.terminal?(state), do: updated

    Enum.filter(
      [
        started_by(origin),
        started && day_time(started),
        started &&
          "ran #{Format.format_human_duration(DateTime.diff(ended_at || now, started, :second))}",
        releases_tried > 0 &&
          "#{releases_tried} #{if releases_tried == 1, do: "release", else: "releases"} tried",
        ended_at && "#{ended_word(state)} #{day_time(ended_at)}"
      ],
      &is_binary/1
    )
  end

  defp started_by(origin) when origin in ["auto", :auto], do: "Auto-grab started this"
  defp started_by(_origin), do: "You started this"

  defp ended_word("satisfied"), do: "done"
  defp ended_word("exhausted"), do: "gave up"
  defp ended_word("cancelled"), do: "cancelled"
  defp ended_word(_partial_or_other), do: "ended"

  defp day_time(%DateTime{} = at), do: Calendar.strftime(at, "%-d %b %H:%M")
  defp day_time(%NaiveDateTime{} = at), do: Calendar.strftime(at, "%-d %b %H:%M")
end
