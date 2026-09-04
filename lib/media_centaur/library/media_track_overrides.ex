defmodule MediaCentaur.Library.MediaTrackOverrides do
  @moduledoc """
  Per-entity remembered audio and subtitle track selections.

  When a user changes tracks during playback and the new selection
  differs from what the language policy chose, that divergence is stored
  here so the next play of the same entity — the next episode of a
  series, a rewatch of a movie — honours it.

  Overrides are owned by the entities that are *watched as a unit*:
  `:movie`, `:tv_series`, `:video_object`. `:movie_series` is absent
  because a collection is never played directly; its child movies carry
  their own.

  Callers compute the diff against the policy choice; these functions
  just persist what they are given.
  """

  alias MediaCentaur.Library.MediaTrackOverride
  alias MediaCentaur.Repo

  @doc "The override for an entity, or `nil` if none has been recorded."
  @spec get(MediaTrackOverride.owner_type(), Ecto.UUID.t()) :: MediaTrackOverride.t() | nil
  def get(owner_type, owner_id) when is_atom(owner_type) and is_binary(owner_id) do
    Repo.get_by(MediaTrackOverride, owner_type: owner_type, owner_id: owner_id)
  end

  @doc """
  Inserts an override row for an entity, or updates the existing one in
  place.

  An unknown `owner_type` is rejected with a changeset rather than
  reaching the Repo: `Ecto.Enum` would raise an `Ecto.Query.CastError`
  from the existence check before the changeset could surface a clean
  validation error.
  """
  @spec upsert(MediaTrackOverride.owner_type(), Ecto.UUID.t(), map()) ::
          {:ok, MediaTrackOverride.t()} | {:error, Ecto.Changeset.t()}
  def upsert(owner_type, owner_id, attrs)
      when is_atom(owner_type) and is_binary(owner_id) and is_map(attrs) do
    attrs =
      attrs
      |> Map.put(:owner_type, owner_type)
      |> Map.put(:owner_id, owner_id)

    if owner_type in MediaTrackOverride.owner_types() do
      case get(owner_type, owner_id) do
        nil -> Repo.insert(MediaTrackOverride.changeset(%MediaTrackOverride{}, attrs))
        existing -> Repo.update(MediaTrackOverride.changeset(existing, attrs))
      end
    else
      {:error, MediaTrackOverride.changeset(%MediaTrackOverride{}, attrs)}
    end
  end

  @doc """
  Deletes the override row for an entity. Returns `:ok` whether or not
  one existed — callers don't need to check first.
  """
  @spec clear(MediaTrackOverride.owner_type(), Ecto.UUID.t()) :: :ok
  def clear(owner_type, owner_id) when is_atom(owner_type) and is_binary(owner_id) do
    case get(owner_type, owner_id) do
      nil ->
        :ok

      override ->
        {:ok, _} = Repo.delete(override)
        :ok
    end
  end

  @doc """
  Decorates an `EntityView` with its override under `:track_override`.

  Container kinds that cannot own an override — and any map missing
  `:id` / `:type` — get `nil`. Called by the modal-entry builders right
  after `Views.DetailItem.to_entity_view/1`, so both construction paths
  carry the override without the detail UI issuing a second round-trip.
  """
  @spec put_on_entity(map()) :: map()
  def put_on_entity(%{id: id, type: type} = entity) when is_binary(id) do
    if type in MediaTrackOverride.owner_types() do
      Map.put(entity, :track_override, get(type, id))
    else
      Map.put(entity, :track_override, nil)
    end
  end

  def put_on_entity(entity) when is_map(entity), do: Map.put(entity, :track_override, nil)
end
