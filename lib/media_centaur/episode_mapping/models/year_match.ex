defmodule MediaCentaur.EpisodeMapping.Models.YearMatch do
  @moduledoc """
  Places a file whose name carries a year but no episode number — a
  yearly special named for its year — on the one episode that year
  identifies: an episode whose title carries the year as a whole number
  (`:year_in_title`), or, when no title does, the episode aired that year
  (`:air_date_year`). A year that fits more than one episode, or none,
  places nothing: the person chooses.

  Reads the whole spine, like `Models.TitleMatch`: a year names which
  episode a file is whether or not the library already has one there.
  Files that number their episode are left to the numbering models.
  """

  @behaviour MediaCentaur.EpisodeMapping.Model

  alias MediaCentaur.EpisodeMapping.{Interpretation, Placement}

  # A year in the episode title is identity evidence, as strong as a title
  # match. A matching air year is weaker: an episode can air in the year
  # a special is named for without being it.
  @title_confidence 0.9
  @air_date_confidence 0.75

  @impl true
  def propose(spine, artifacts) when is_list(spine) and is_list(artifacts) do
    placed =
      for %{claimed_year: year, claimed_episode: nil} = artifact <- artifacts,
          is_integer(year),
          {model, node} <- [place(spine, year)],
          do: {model, %Placement{artifact_id: artifact.id, season: node.season, episode: node.episode}}

    placed
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {model, placements} -> interpretation(model, placements) end)
    |> Enum.sort_by(& &1.confidence, :desc)
  end

  # The one node the year identifies — by title first, then by air date —
  # or nil, which the generator in `propose/2` skips.
  defp place(spine, year) do
    case {only(Enum.filter(spine, &named_for?(&1, year))),
          only(Enum.filter(spine, &aired_in?(&1, year)))} do
      {%{} = node, _by_date} -> {:year_in_title, node}
      {nil, %{} = node} -> {:air_date_year, node}
      {nil, nil} -> nil
    end
  end

  defp named_for?(%{title: title}, year) when is_binary(title),
    do: Regex.match?(~r/(?<!\d)#{year}(?!\d)/, title)

  defp named_for?(_node, _year), do: false

  defp aired_in?(%{air_date: %Date{year: air_year}}, year), do: air_year == year
  defp aired_in?(_node, _year), do: false

  defp only([node]), do: node
  defp only(_nodes), do: nil

  defp interpretation(model, placements) do
    %Interpretation{
      model: model,
      placements: placements,
      confidence: confidence(model),
      rationale: rationale(model, placements)
    }
  end

  defp confidence(:year_in_title), do: @title_confidence
  defp confidence(:air_date_year), do: @air_date_confidence

  defp rationale(:year_in_title, placements),
    do: "Matched #{length(placements)} file(s) by the year in the episode title."

  defp rationale(:air_date_year, placements),
    do: "Matched #{length(placements)} file(s) by the year the episode aired."
end
