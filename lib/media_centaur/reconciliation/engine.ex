defmodule MediaCentaur.Reconciliation.Engine do
  @moduledoc """
  Runs the interpretation models over a show's spine + artifact batch and
  merges their proposals into a single `Resolution` (reconciliation
  campaign). Pure — the caller assembles the spine (TMDB fetch + library
  present-set) and supplies any pinned overrides; the engine does no I/O.

  ## How it merges

  Every model proposes independently. The engine ranks interpretations by
  confidence (title-match's identity signal, 0.9, outranks gap-fill's
  ordinal inference, 0.85) and builds a **recommended** mapping by letting
  the highest-confidence model that placed each artifact win — so title
  evidence corrects gap-fill's off-by-one, and gap-fill fills the artifacts
  no title covered. The raw per-model interpretations are kept as ranked
  `alternatives` for the review surface.

  ## When it auto-links (conservative rule, decided 2026-06-24)

  `auto?` is true only when **≥2 models corroborate the same node for every
  recommended placement**, the placements **fill the gap exactly** (1:1, no
  partial/overflow), and **nothing is unplaced**. Everything else is
  `proposed` and awaits the user — human arbitration is the designed state.

  Pinned placements are honored: their nodes are marked taken and their
  artifacts are withheld from the models, so proposals form *around* the
  pin rather than overturning it.
  """

  alias MediaCentaur.Reconciliation.{Artifact, Interpretation, Resolution, SpineNode}
  alias MediaCentaur.Reconciliation.Models.{GapFill, TitleMatch}

  @default_models [TitleMatch, GapFill]

  @spec resolve([SpineNode.t()], [Artifact.t()], keyword()) :: Resolution.t()
  def resolve(spine, artifacts, opts \\ []) when is_list(spine) and is_list(artifacts) do
    models = Keyword.get(opts, :models, @default_models)
    pinned = Keyword.get(opts, :pinned, [])

    {spine_for_models, artifacts_for_models} = withhold_pinned(spine, artifacts, pinned)

    interpretations =
      models
      |> Enum.flat_map(& &1.propose(spine_for_models, artifacts_for_models))
      |> Enum.sort_by(& &1.confidence, :desc)

    recommended = merge(interpretations, artifacts_for_models)

    %Resolution{
      recommended: recommended,
      alternatives: interpretations,
      pinned: pinned,
      unplaced: unplaced(recommended, artifacts_for_models),
      auto?: auto?(recommended, interpretations, spine_for_models)
    }
  end

  # Mark pinned nodes present (so models never reuse them) and drop pinned
  # artifacts from the batch (their placement is already decided).
  defp withhold_pinned(spine, artifacts, pinned) do
    pinned_nodes = MapSet.new(pinned, &{&1.season, &1.episode})
    pinned_ids = MapSet.new(pinned, & &1.artifact_id)

    spine =
      Enum.map(spine, fn node ->
        if MapSet.member?(pinned_nodes, {node.season, node.episode}),
          do: %{node | present?: true},
          else: node
      end)

    {spine, Enum.reject(artifacts, &MapSet.member?(pinned_ids, &1.id))}
  end

  defp merge([], _artifacts), do: nil

  defp merge(interpretations, artifacts) do
    placements =
      Enum.flat_map(artifacts, fn artifact ->
        # interpretations are ranked desc, so the first that placed this
        # artifact is the highest-confidence model's choice.
        case Enum.find_value(interpretations, &find_placement(&1, artifact.id)) do
          nil -> []
          placement -> [placement]
        end
      end)

    case placements do
      [] ->
        nil

      placements ->
        %Interpretation{
          model: :recommended,
          placements: placements,
          confidence: recommended_confidence(interpretations, placements),
          rationale: recommended_rationale(interpretations, placements)
        }
    end
  end

  defp find_placement(interpretation, artifact_id) do
    Enum.find(interpretation.placements, &(&1.artifact_id == artifact_id))
  end

  defp recommended_confidence(interpretations, placements) do
    interpretations
    |> contributing(placements)
    |> Enum.map(& &1.confidence)
    |> Enum.max()
  end

  defp recommended_rationale(interpretations, placements) do
    models =
      interpretations
      |> contributing(placements)
      |> Enum.map_join(" + ", &to_string(&1.model))

    "Recommended mapping of #{length(placements)} file(s) (#{models})."
  end

  # Interpretations that supplied at least one of the recommended placements.
  defp contributing(interpretations, placements) do
    chosen = MapSet.new(placements, &placement_key/1)

    Enum.filter(interpretations, fn i ->
      Enum.any?(i.placements, &MapSet.member?(chosen, placement_key(&1)))
    end)
  end

  defp unplaced(recommended, artifacts) do
    placed = if recommended, do: MapSet.new(recommended.placements, & &1.artifact_id), else: MapSet.new()

    artifacts
    |> Enum.map(& &1.id)
    |> Enum.reject(&MapSet.member?(placed, &1))
  end

  defp auto?(nil, _interpretations, _spine), do: false

  defp auto?(recommended, interpretations, spine) do
    fills_gap_exactly?(recommended, spine) and
      one_to_one?(recommended) and
      all_corroborated?(recommended, interpretations)
  end

  # Exact fit: the recommended placements cover every fillable gap node
  # (missing, excluding season 0) and no more — no partial, no overflow.
  defp fills_gap_exactly?(recommended, spine) do
    gap =
      spine
      |> Enum.filter(&(not &1.present? and &1.season != 0))
      |> MapSet.new(&{&1.season, &1.episode})

    placed = MapSet.new(recommended.placements, &{&1.season, &1.episode})

    MapSet.size(gap) > 0 and MapSet.equal?(gap, placed)
  end

  defp one_to_one?(recommended) do
    nodes = Enum.map(recommended.placements, &{&1.season, &1.episode})
    length(Enum.uniq(nodes)) == length(nodes)
  end

  # Every recommended placement must appear identically in ≥2 interpretations.
  defp all_corroborated?(recommended, interpretations) do
    Enum.all?(recommended.placements, fn placement ->
      count =
        Enum.count(interpretations, fn i ->
          Enum.any?(i.placements, &same_placement?(&1, placement))
        end)

      count >= 2
    end)
  end

  defp same_placement?(a, b),
    do: a.artifact_id == b.artifact_id and a.season == b.season and a.episode == b.episode

  defp placement_key(placement), do: {placement.artifact_id, placement.season, placement.episode}
end
