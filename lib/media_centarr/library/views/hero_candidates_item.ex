defmodule MediaCentarr.Library.Views.HeroCandidatesItem do
  @moduledoc """
  View-model for one entry in the Hero Candidates projection.

  Mirrors the field shape produced by `MediaCentarr.Library.list_hero_candidates/1`
  so downstream consumers (`MediaCentarrWeb.HomeLive.Logic.hero_card_item/2`)
  can read either source by the same dot-access keys during migration.
  """

  @enforce_keys [:id, :name]
  defstruct [
    :id,
    :name,
    :year,
    :runtime_minutes,
    :genres,
    :overview,
    :backdrop_url,
    :logo_url
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          year: integer() | nil,
          runtime_minutes: integer() | nil,
          genres: [String.t()] | String.t() | nil,
          overview: String.t() | nil,
          backdrop_url: String.t() | nil,
          logo_url: String.t() | nil
        }
end
