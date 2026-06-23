defmodule MediaCentaur.Reconciliation.Models.TitleMatch do
  @moduledoc """
  Maps an artifact onto the spine node whose canonical title matches the
  artifact's **claimed title** — direct identity evidence, independent of
  any numbering (reconciliation campaign). A title names *which* episode an
  artifact is, so this model corroborates `Models.GapFill` and **corrects**
  the off-by-one it would make when a cour starts a position off from the
  contiguous gap head.

  Decision-independent: it reads only the titles, never the placement state,
  and so it matches against the **whole spine** (a title identifies an
  episode whether or not it is already present). It **abstains** (`[]`) when
  no artifact carries a title or the spine has none — title is the strongest
  signal when present and silent when absent.

  Matching is case- and punctuation-insensitive (releases drop or alter
  punctuation). An artifact whose title is missing from the spine, or whose
  title is ambiguous (matches more than one node), is skipped rather than
  guessed — gap-fill remains the floor for those.
  """

  @behaviour MediaCentaur.Reconciliation.Model

  alias MediaCentaur.Reconciliation.{Interpretation, Placement}

  # Title is direct identity evidence, so an exact title match reads stronger
  # than gap-fill's strongest (ordinal) inference (0.85). Not absolute —
  # normalization can in principle collide — so short of 1.0.
  @confidence 0.9

  @impl true
  def propose(spine, artifacts) when is_list(spine) and is_list(artifacts) do
    by_title = index_unique_titles(spine)

    placements =
      Enum.flat_map(artifacts, fn artifact ->
        case Map.get(by_title, normalize(artifact.claimed_title)) do
          nil -> []
          node -> [%Placement{artifact_id: artifact.id, season: node.season, episode: node.episode}]
        end
      end)

    case placements do
      [] -> []
      placements -> [interpretation(placements)]
    end
  end

  # Build normalized-title → node, dropping titles that are blank or claimed
  # by more than one node (ambiguous — never guess between them).
  defp index_unique_titles(spine) do
    spine
    |> Enum.reject(&is_nil(normalize(&1.title)))
    |> Enum.group_by(&normalize(&1.title))
    |> Enum.flat_map(fn
      {key, [node]} -> [{key, node}]
      {_key, _ambiguous} -> []
    end)
    |> Map.new()
  end

  defp interpretation(placements) do
    %Interpretation{
      model: :title_match,
      placements: placements,
      confidence: @confidence,
      rationale: rationale(placements)
    }
  end

  defp rationale(placements) do
    episodes =
      placements
      |> Enum.sort_by(& &1.episode)
      |> Enum.map_join(", ", &"E#{&1.episode}")

    "Matched #{length(placements)} title(s) to canonical #{episodes}."
  end

  defp normalize(nil), do: nil

  defp normalize(title) do
    normalized =
      title
      |> String.downcase()
      |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
      |> String.trim()

    if normalized != "", do: normalized
  end
end
