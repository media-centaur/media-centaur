defmodule MediaCentaur.Status.LibraryOverview do
  @moduledoc """
  Typed view-model for the "Your library" overview at the top of `/status`.

  Built by `MediaCentaur.Status.load_overview/0` (the cross-context read
  aggregator) and rendered by the library-overview components. Lives in the
  data layer because `Status` constructs it — the web layer depends on this
  struct, not the reverse (mirrors how `SubsystemView` is web-side because
  `HealthBoard`, a web module, builds it).

  Storage figures (per-drive headroom, at-risk files) are deliberately NOT
  carried here: the Status page already measures them via its own
  `:status_storage` async, and the storage-outlook card reads those assigns
  directly rather than measuring the disks twice.
  """

  @enforce_keys [
    :movie_count,
    :show_count,
    :episode_count,
    :total_size_bytes,
    :recently_added,
    :pending_review_count,
    :in_flight_count,
    :missing_artwork_count,
    :missing_metadata_count,
    :incomplete_season_count
  ]
  defstruct [
    :movie_count,
    :show_count,
    :episode_count,
    :total_size_bytes,
    :recently_added,
    :pending_review_count,
    :in_flight_count,
    :missing_artwork_count,
    :missing_metadata_count,
    :incomplete_season_count
  ]

  @type recent_item :: %{
          id: Ecto.UUID.t(),
          name: String.t(),
          year: String.t() | nil,
          poster_url: String.t() | nil
        }

  @type t :: %__MODULE__{
          movie_count: non_neg_integer(),
          show_count: non_neg_integer(),
          episode_count: non_neg_integer(),
          total_size_bytes: non_neg_integer(),
          recently_added: [recent_item()],
          pending_review_count: non_neg_integer(),
          in_flight_count: non_neg_integer(),
          missing_artwork_count: non_neg_integer(),
          missing_metadata_count: non_neg_integer(),
          incomplete_season_count: non_neg_integer()
        }

  @doc """
  True when every completeness-gap counter is zero — the library has no
  surfaced quality issues.
  """
  @spec no_gaps?(t()) :: boolean()
  def no_gaps?(%__MODULE__{} = overview) do
    overview.missing_artwork_count == 0 and
      overview.missing_metadata_count == 0 and
      overview.incomplete_season_count == 0
  end
end
