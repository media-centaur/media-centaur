defmodule MediaCentaur.Library.OwnerRef do
  @moduledoc """
  The `(owner_type, owner_id)` discriminator pair that sidecar rows use
  to point at the library entity they belong to.

  Library Schema v2 Phase 2 Task D collapsed the per-type foreign keys
  (`movie_id`, `tv_series_id`, `movie_series_id`, …) on `Image`,
  `ExternalId` and `Extra` into a single discriminator pair, so one
  sidecar table can hang off any entity type. Callers written before that
  — and the fixtures that outlived them — still pass the per-type key,
  because "the image for this movie" is a natural way to say it.

  `normalise/2` is the single place that translation happens. Each
  sidecar kind declares which per-type keys it accepts and what owner
  type each maps to; anything already carrying `owner_type` + `owner_id`
  passes through untouched.

  Note the accepted key sets differ, and the differences are real: only
  `Image` accepts `:episode_id` (episodes have stills), and only `Extra`
  accepts `:season_id` (a season can own a featurette).
  """

  @owner_keys %{
    image: [
      movie_id: :movie,
      episode_id: :episode,
      tv_series_id: :tv_series,
      movie_series_id: :movie_series,
      video_object_id: :video_object
    ],
    extra: [
      movie_id: :movie,
      tv_series_id: :tv_series,
      movie_series_id: :movie_series,
      season_id: :season
    ],
    external_id: [
      movie_id: :movie,
      tv_series_id: :tv_series,
      movie_series_id: :movie_series,
      video_object_id: :video_object
    ]
  }

  @type kind :: :image | :extra | :external_id

  @doc "The sidecar kinds that accept a per-type owner key."
  @spec kinds() :: [kind()]
  def kinds, do: Map.keys(@owner_keys)

  @doc "The owner types `kind` can point at."
  @spec owner_types(kind()) :: [atom()]
  def owner_types(kind), do: @owner_keys |> Map.fetch!(kind) |> Keyword.values()

  @doc """
  Rewrites a per-type owner key in `attrs` into the `(owner_type,
  owner_id)` pair, leaving attrs that already carry the pair alone.

  The first matching key wins, and every per-type key for the kind is
  dropped — so passing two is not silently half-applied.
  """
  @spec normalise(map(), kind()) :: map()
  def normalise(attrs, kind) when is_map(attrs) do
    legacy_keys = Map.fetch!(@owner_keys, kind)

    case Enum.find(legacy_keys, fn {key, _type} -> not is_nil(Map.get(attrs, key)) end) do
      nil ->
        attrs

      {legacy_key, owner_type} ->
        attrs
        |> Map.drop(Keyword.keys(legacy_keys))
        |> Map.put_new(:owner_type, owner_type)
        |> Map.put_new(:owner_id, Map.get(attrs, legacy_key))
    end
  end
end
