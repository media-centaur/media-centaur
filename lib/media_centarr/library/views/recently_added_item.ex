defmodule MediaCentarr.Library.Views.RecentlyAddedItem do
  @moduledoc """
  View-model for one entry in the Recently Added projection.

  Mirrors the field shape produced by `MediaCentarr.Library.list_recently_added/1`
  so downstream consumers (`MediaCentarrWeb.HomeLive.Logic.recently_added_items/2`)
  can read either source by the same dot-access keys during migration.
  """

  @enforce_keys [:id, :name]
  defstruct [
    :id,
    :name,
    :year,
    :poster_url
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          year: integer() | nil,
          poster_url: String.t() | nil
        }
end
