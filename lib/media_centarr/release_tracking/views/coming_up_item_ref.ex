defmodule MediaCentarr.ReleaseTracking.Views.ComingUpItemRef do
  @moduledoc """
  Nested item-reference shape used by `ComingUpItem`. Mirrors the
  `:item` map field returned by `ReleaseTracking.list_releases_between/3`
  so downstream consumers read the same dot-access keys.
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
