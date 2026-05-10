defmodule MediaCentarr.Library.Views.ContinueWatchingItem do
  @moduledoc """
  View-model for one row of the Continue Watching projection.

  This is the public read contract of `MediaCentarr.Library.Views`'s
  `continue_watching/1` function. Per ADR-041, the view-model struct
  decouples render shape from storage shape — UI consumers depend
  only on the field set declared here.
  """

  @enforce_keys [:entity_id, :entity_name]
  defstruct [
    :entity_id,
    :entity_name,
    :last_episode_label,
    :progress_pct,
    :backdrop_url,
    :logo_url,
    :last_watched_at
  ]

  @type t :: %__MODULE__{
          entity_id: String.t(),
          entity_name: String.t(),
          last_episode_label: String.t() | nil,
          progress_pct: 0..100 | nil,
          backdrop_url: String.t() | nil,
          logo_url: String.t() | nil,
          last_watched_at: DateTime.t() | nil
        }
end
