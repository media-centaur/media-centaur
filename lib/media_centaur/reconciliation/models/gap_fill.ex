defmodule MediaCentaur.Reconciliation.Models.GapFill do
  @moduledoc """
  The reliable floor: align the unplaced artifacts, in order, onto the
  contiguous **missing** spine nodes, in order — ignoring the artifacts'
  claimed numbering entirely (it's used only to sort the batch). Needs no
  metadata, so it always proposes when there's both a gap and a batch
  (reconciliation campaign). Confidence is shaped by how the batch size
  fits the gap; the title/absolute models corroborate or correct it.

  **Season 0 (specials/OVAs) is excluded** — TMDB special ordering is
  unreliable, so ordinal fill would misplace; specials reconcile by title
  or land unplaced for manual assignment.
  """

  @behaviour MediaCentaur.Reconciliation.Model

  alias MediaCentaur.Reconciliation.{Interpretation, Placement}

  # Provisional confidence bands (the campaign flags the auto/proposed
  # threshold as an open question — these are starting values, not final):
  # exact fit reads strongest, a partial fill is plausible, an overflow
  # (more files than the gap can hold) signals the alignment is probably
  # wrong.
  @exact 0.85
  @partial 0.7
  @overflow 0.4

  @impl true
  def propose(spine, artifacts) when is_list(spine) and is_list(artifacts) do
    # Season 0 (specials/OVAs) is excluded: TMDB special ordering is
    # unreliable, so ordinal fill would misplace. Specials reconcile by
    # title (`Models.TitleMatch`) or land unplaced for manual assignment.
    missing =
      spine
      |> Enum.filter(&(not &1.present? and &1.season != 0))
      |> Enum.sort_by(&{&1.season, &1.episode})

    ordered = Enum.sort_by(artifacts, &{&1.claimed_season, &1.claimed_episode})

    case {missing, ordered} do
      {[], _} -> []
      {_, []} -> []
      {missing, ordered} -> [interpretation(missing, ordered)]
    end
  end

  defp interpretation(missing, ordered) do
    placements =
      ordered
      |> Enum.zip(missing)
      |> Enum.map(fn {artifact, node} ->
        %Placement{artifact_id: artifact.id, season: node.season, episode: node.episode}
      end)

    %Interpretation{
      model: :gap_fill,
      placements: placements,
      confidence: confidence(length(ordered), length(missing)),
      rationale: rationale(missing, placements)
    }
  end

  defp confidence(artifacts, gap) when artifacts == gap, do: @exact
  defp confidence(artifacts, gap) when artifacts < gap, do: @partial
  defp confidence(_artifacts, _gap), do: @overflow

  defp rationale(missing, placements) do
    first = List.first(placements)
    last = List.last(placements)
    span = "E#{first.episode}–E#{last.episode}"
    "Fills the missing #{span}, in order (#{length(placements)} of #{length(missing)})."
  end
end
