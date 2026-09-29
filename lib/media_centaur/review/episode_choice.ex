defmodule MediaCentaur.Review.EpisodeChoice do
  @moduledoc """
  Which episode a reviewer is offered first for a file matched to a series
  whose name carries no season and episode.

  A yearly special named for its year (`Show.Name.2025.1080p.mkv`) is the
  common case: the year identifies one episode of the series. `preselect/2`
  offers that episode — by its name carrying the year as a whole number
  first, by its air date's year otherwise — and only when exactly one
  episode fits. It never places a file on its own: the reviewer sees the
  offered episode in the picker and approves it or chooses another.

  `seasons` is the shape `MediaCentaur.Review.episode_choices/1` returns:
  `[%{season_number, name, episodes: [%{episode_number, name, air_date}]}]`.
  """

  @spec preselect([map()], integer() | nil) :: {integer(), integer()} | nil
  def preselect(_seasons, nil), do: nil

  def preselect(seasons, year) when is_integer(year) do
    episodes =
      for %{season_number: season_number, episodes: episodes} <- seasons,
          episode <- episodes,
          do: {season_number, episode}

    only(Enum.filter(episodes, &named_for?(&1, year))) ||
      only(Enum.filter(episodes, &aired_in?(&1, year)))
  end

  defp named_for?({_season, %{name: name}}, year) when is_binary(name) do
    Regex.match?(~r/(?<!\d)#{year}(?!\d)/, name)
  end

  defp named_for?(_episode, _year), do: false

  defp aired_in?({_season, %{air_date: <<air_year::binary-size(4), _rest::binary>>}}, year) do
    air_year == Integer.to_string(year)
  end

  defp aired_in?(_episode, _year), do: false

  defp only([{season_number, %{episode_number: episode_number}}]), do: {season_number, episode_number}
  defp only(_episodes), do: nil
end
