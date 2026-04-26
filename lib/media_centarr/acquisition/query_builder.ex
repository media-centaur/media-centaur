defmodule MediaCentarr.Acquisition.QueryBuilder do
  @moduledoc """
  Builds an ordered list of Prowlarr search queries for a `Grab`.

  Returns `[{query_string, opts}]` ordered best-to-worst — the worker tries each
  in turn until one yields acceptable results. Opts may carry `:type` (`:movie`
  or `:tv`) and `:year` (movies only — episode release titles do not embed the
  show's first-air year, so adding it usually shrinks results unhelpfully).

  Pure function module — no I/O, no DB.
  """

  alias MediaCentarr.Acquisition.Grab

  @type opt :: {:type, :movie | :tv} | {:year, integer()}
  @type query :: {String.t(), [opt()]}

  @spec build(Grab.t()) :: [query()]
  def build(%Grab{tmdb_type: "movie"} = grab), do: build_movie(grab)
  def build(%Grab{tmdb_type: "tv"} = grab), do: build_tv(grab)

  defp build_movie(%Grab{title: title, year: nil}), do: [{title, [type: :movie]}]

  defp build_movie(%Grab{title: title, year: year}) when is_integer(year) do
    [{"#{title} #{year}", [type: :movie, year: year]}]
  end

  defp build_tv(%Grab{title: title, season_number: season, episode_number: nil})
       when is_integer(season) do
    [
      {"#{title} Season #{season}", [type: :tv]},
      {"#{title} #{season_tag(season)}", [type: :tv]}
    ]
  end

  defp build_tv(%Grab{title: title, season_number: season, episode_number: episode})
       when is_integer(season) and is_integer(episode) do
    [
      {"#{title} #{season_tag(season)}#{episode_tag(episode)}", [type: :tv]},
      {"#{title} Season #{season}", [type: :tv]}
    ]
  end

  # Whole-series fallback (no season/episode known) — rare in the auto-grab
  # flow because Refresher always emits a release with episode info, but
  # legitimate when a manual enqueue targets the series itself.
  defp build_tv(%Grab{title: title, season_number: nil, episode_number: nil}) do
    [{title, [type: :tv]}]
  end

  defp season_tag(season), do: "S" <> pad2(season)
  defp episode_tag(episode), do: "E" <> pad2(episode)

  defp pad2(n) when n < 10, do: "0" <> Integer.to_string(n)
  defp pad2(n), do: Integer.to_string(n)
end
