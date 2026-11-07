defmodule MediaCentaur.Library.PlaybackOverrides do
  @moduledoc """
  Remembered playback settings — one profile's, per entity (ADR-078):
  the audio and subtitle tracks and the picture's Fill width.

  When a viewer moves a setting away from its default during playback
  (tracks: the language policy's choice; picture: Fit), that divergence is
  stored here (`Playback.Remembered` saves it) so the next play of the
  same entity by the same profile — the next episode of a series, a
  rewatch of a movie — honours it. Another
  profile's choice on the same title is a separate row.

  Overrides are owned by the entities that are *watched as a unit*:
  `:movie`, `:tv_series`, `:video_object`. `:movie_series` is absent
  because a collection is never played directly; its child movies carry
  their own.

  Callers compute the diff against the policy choice; these functions
  just persist what they are given. Every function names the profile
  first.
  """

  alias MediaCentaur.Library.PlaybackOverride
  alias MediaCentaur.Repo

  @doc "The profile's override for an entity, or `nil` if none has been recorded."
  @spec get(Ecto.UUID.t(), PlaybackOverride.owner_type(), Ecto.UUID.t()) ::
          PlaybackOverride.t() | nil
  def get(profile_id, owner_type, owner_id)
      when is_binary(profile_id) and is_atom(owner_type) and is_binary(owner_id) do
    Repo.get_by(PlaybackOverride, profile_id: profile_id, owner_type: owner_type, owner_id: owner_id)
  end

  @doc """
  Inserts the profile's override row for an entity, or updates the
  existing one in place.

  An unknown `owner_type` is rejected with a changeset rather than
  reaching the Repo: `Ecto.Enum` would raise an `Ecto.Query.CastError`
  from the existence check before the changeset could surface a clean
  validation error.
  """
  @spec upsert(Ecto.UUID.t(), PlaybackOverride.owner_type(), Ecto.UUID.t(), map()) ::
          {:ok, PlaybackOverride.t()} | {:error, Ecto.Changeset.t()}
  def upsert(profile_id, owner_type, owner_id, attrs)
      when is_binary(profile_id) and is_atom(owner_type) and is_binary(owner_id) and is_map(attrs) do
    attrs = Map.merge(attrs, %{profile_id: profile_id, owner_type: owner_type, owner_id: owner_id})

    if owner_type in PlaybackOverride.owner_types() do
      case get(profile_id, owner_type, owner_id) do
        nil -> Repo.insert(PlaybackOverride.changeset(%PlaybackOverride{}, attrs))
        existing -> Repo.update(PlaybackOverride.changeset(existing, attrs))
      end
    else
      {:error, PlaybackOverride.changeset(%PlaybackOverride{}, attrs)}
    end
  end

  @doc """
  Deletes the profile's override row for an entity. Returns `:ok` whether
  or not one existed — callers don't need to check first.
  """
  @spec clear(Ecto.UUID.t(), PlaybackOverride.owner_type(), Ecto.UUID.t()) :: :ok
  def clear(profile_id, owner_type, owner_id)
      when is_binary(profile_id) and is_atom(owner_type) and is_binary(owner_id) do
    case get(profile_id, owner_type, owner_id) do
      nil ->
        :ok

      override ->
        {:ok, _} = Repo.delete(override)
        :ok
    end
  end

  @doc """
  Decorates an `EntityView` with the profile's override under
  `:playback_override`.

  Container kinds that cannot own an override — and any map missing
  `:id` / `:type` — get `nil`. Called by the modal-entry builders right
  after `Views.DetailItem.to_entity_view/1`, so both construction paths
  carry the override without the detail UI issuing a second round-trip.
  """
  @spec put_on_entity(Ecto.UUID.t(), map()) :: map()
  def put_on_entity(profile_id, %{id: id, type: type} = entity)
      when is_binary(profile_id) and is_binary(id) do
    if type in PlaybackOverride.owner_types(),
      do: Map.put(entity, :playback_override, get(profile_id, type, id)),
      else: Map.put(entity, :playback_override, nil)
  end

  def put_on_entity(profile_id, entity) when is_binary(profile_id) and is_map(entity),
    do: Map.put(entity, :playback_override, nil)
end
