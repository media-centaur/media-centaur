defmodule MediaCentarr.ReleaseTracking.Views.ComingUpItemRef do
  @moduledoc """
  Nested item-reference shape used by `ComingUpItem`. Mirrors the
  `:item` map field returned by `ReleaseTracking.list_releases_between/3`
  so downstream consumers read the same dot-access keys.

  ## Field notes

    * `:id` — `ReleaseTracking.Item.id` (the tracking item's own
      primary key).
    * `:entity_id` — **the linked `Library` container UUID**
      (`library_container_id` — the TVSeries / MovieSeries the item
      tracks), NOT the ReleaseTracking Item id. Kept as `:entity_id`
      rather than `:library_container_id` to match the URL-param
      convention `/library?selected=<container_id>` used by every
      modal-open path. Phase 2 Task J added this surface alongside
      the schema rename from `library_entity_id` →
      `library_container_id`.
  """

  @enforce_keys [:id, :name]
  defstruct [
    :id,
    :entity_id,
    :name,
    :tmdb_id,
    :media_type
  ]

  @type t :: %__MODULE__{
          id: integer() | String.t(),
          entity_id: String.t() | nil,
          name: String.t(),
          tmdb_id: integer() | nil,
          media_type: atom() | nil
        }
end
