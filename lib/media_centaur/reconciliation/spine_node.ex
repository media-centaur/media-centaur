defmodule MediaCentaur.Reconciliation.SpineNode do
  @moduledoc """
  One position on a show's **canonical episode spine** — the TMDB
  numbering, the only source of structure (reconciliation campaign).

  `present?` is whether the library already has a file placed on this
  node; the *gap* (nodes with `present? == false`) is what an incoming
  batch of artifacts gets reconciled against. The spine is never
  fabricated to fit an artifact — a node exists iff TMDB says it does.
  """

  @enforce_keys [:season, :episode]
  defstruct [:season, :episode, :title, present?: false]

  @type t :: %__MODULE__{
          season: integer(),
          episode: integer(),
          title: String.t() | nil,
          present?: boolean()
        }
end
