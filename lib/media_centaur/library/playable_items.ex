defmodule MediaCentaur.Library.PlayableItems do
  @moduledoc """
  Records and lookup for `PlayableItem` — the canonical playable-leaf
  identity that files, progress, and subtitles key against (Library
  Schema v2 Phase 2).

  A PlayableItem is addressed by `(container_type, container_id,
  position)`. The three leaf types are `:movie`, `:episode`, and
  `:video_object`; `position` distinguishes multi-cut movies and
  multi-part episodes, and defaults to the leaf's own natural ordinal
  (see `canonical_position/2`).

  There is no DB-level FK from the discriminator pair to the container
  table — see the `PlayableItem` moduledoc for that design decision — so
  callers are responsible for pointing at a container that exists.
  """

  import Ecto.Query

  alias MediaCentaur.Library.{Episode, Movie, PlayableItem, Season}
  alias MediaCentaur.Repo

  @leaf_types [:movie, :episode, :video_object]

  @doc "The leaf types a PlayableItem can point at."
  @spec leaf_types() :: [PlayableItem.container_type()]
  def leaf_types, do: @leaf_types

  @doc """
  Inserts a new `PlayableItem` row. The caller is responsible for
  ensuring the `(container_type, container_id)` pair points at an
  existing container.
  """
  @spec create(map()) :: {:ok, PlayableItem.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs), do: Repo.insert(PlayableItem.create_changeset(attrs))

  @doc "Bang variant of `create/1` — raises on changeset error."
  @spec create!(map()) :: PlayableItem.t()
  def create!(attrs), do: Repo.bang!(create(attrs))

  @doc "Fetches a `PlayableItem` by id."
  @spec fetch(Ecto.UUID.t()) :: {:ok, PlayableItem.t()} | {:error, :not_found}
  def fetch(id) do
    case Repo.get(PlayableItem, id) do
      nil -> {:error, :not_found}
      item -> {:ok, item}
    end
  end

  @doc """
  Lists every `PlayableItem` for a container, ordered by `:position`
  ascending. Empty list when the container has none.
  """
  @spec list_for(PlayableItem.container_type(), Ecto.UUID.t()) :: [PlayableItem.t()]
  def list_for(container_type, container_id)
      when container_type in @leaf_types and is_binary(container_id) do
    Repo.all(
      from(p in PlayableItem,
        where: p.container_type == ^container_type and p.container_id == ^container_id,
        order_by: [asc: p.position]
      )
    )
  end

  @doc """
  The natural ordinal a leaf's canonical PlayableItem sits at.

  Each leaf type carries its own notion of position — a Movie's
  `:position` within its collection, an Episode's `:episode_number` —
  and a VideoObject has no multi-part variants, so it is always 1.
  Falls back to 1 when the leaf is absent or carries no ordinal.

  This is the only genuinely per-type behaviour in the progress write
  path; everything else dispatches on the type atom alone.
  """
  @spec canonical_position(PlayableItem.container_type(), Ecto.UUID.t()) :: integer()
  def canonical_position(:movie, movie_id) do
    case Repo.get(Movie, movie_id) do
      %Movie{position: position} when is_integer(position) -> position
      _ -> 1
    end
  end

  def canonical_position(:episode, episode_id) do
    case Repo.get(Episode, episode_id) do
      %Episode{episode_number: number} when is_integer(number) -> number
      _ -> 1
    end
  end

  def canonical_position(:video_object, _video_object_id), do: 1

  @doc """
  Finds the `PlayableItem` at `(container_type, container_id, position)`,
  creating it if absent.

  Race-loss recovery follows the same pattern as
  `Library.Inbound.ensure_playable_item_for_event/2`: a concurrent
  insert surfaces as a `unique_constraint` changeset error and the
  winning row is re-fetched. Used by the progress writer seam so a save
  against a not-yet-ingested leaf does not race with `Library.Inbound`.
  """
  @spec find_or_create(PlayableItem.container_type(), Ecto.UUID.t(), integer()) ::
          {:ok, PlayableItem.t()} | {:error, term()}
  def find_or_create(container_type, container_id, position)
      when container_type in @leaf_types and is_binary(container_id) and is_integer(position) do
    case find(container_type, container_id, position) do
      %PlayableItem{} = item ->
        {:ok, item}

      nil ->
        create_recovering_from_race(container_type, container_id, position)
    end
  end

  @doc """
  Resolves top-level entity UUIDs to the set of `PlayableItem` UUIDs
  they own.

    * Movie / VideoObject ids resolve directly via `container_id` on the
      `:movie` / `:video_object` discriminator.
    * TVSeries ids resolve via Season → Episode → PlayableItem.
    * MovieSeries ids resolve via child Movies' PlayableItems.

  Used by `Library.Views.Detail.handle_message/1` to translate
  `EntitiesChanged{entity_ids: ids}` into the per-row set of
  PlayableItems whose detail-projection entries need rebuilding.
  """
  @spec ids_for_entities([Ecto.UUID.t()]) :: [Ecto.UUID.t()]
  def ids_for_entities([]), do: []

  def ids_for_entities(entity_ids) when is_list(entity_ids) do
    direct =
      from(p in PlayableItem,
        where: p.container_type in [:movie, :video_object] and p.container_id in ^entity_ids,
        select: p.id
      )

    via_tv_series =
      from(p in PlayableItem,
        join: e in Episode,
        on: e.id == p.container_id,
        join: s in Season,
        on: s.id == e.season_id,
        where: p.container_type == :episode and s.tv_series_id in ^entity_ids,
        select: p.id
      )

    via_movie_series =
      from(p in PlayableItem,
        join: m in Movie,
        on: m.id == p.container_id,
        where: p.container_type == :movie and m.movie_series_id in ^entity_ids,
        select: p.id
      )

    Enum.uniq(Repo.all(direct) ++ Repo.all(via_tv_series) ++ Repo.all(via_movie_series))
  end

  defp find(container_type, container_id, position) do
    Repo.one(
      from(p in PlayableItem,
        where:
          p.container_type == ^container_type and p.container_id == ^container_id and
            p.position == ^position
      )
    )
  end

  defp create_recovering_from_race(container_type, container_id, position) do
    attrs = %{container_type: container_type, container_id: container_id, position: position}

    case create(attrs) do
      {:ok, item} ->
        {:ok, item}

      {:error, %Ecto.Changeset{errors: errors}} ->
        if Keyword.has_key?(errors, :container_type) or Keyword.has_key?(errors, :container_id) or
             Keyword.has_key?(errors, :position) do
          case find(container_type, container_id, position) do
            %PlayableItem{} = item -> {:ok, item}
            nil -> {:error, :race_loss_recovery_failed}
          end
        else
          {:error, errors}
        end
    end
  end
end
