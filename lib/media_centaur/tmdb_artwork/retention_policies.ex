defmodule MediaCentaur.TmdbArtwork.RetentionPolicies do
  @moduledoc """
  Retention policy for the TMDB artwork cache: an entry is removed only
  when nothing references it (`MediaCentaur.TMDB.References`) AND it
  has been unused for the TTL. The TMDB store's records follow the same
  reference set (`MediaCentaur.TMDB.RetentionPolicies`). Supersedes
  ReleaseTracking's `:tracking_artwork` orphan sweep — "a tracked item
  exists" is now just one kind of reference.
  """
  @behaviour MediaCentaur.Retention.PolicyProvider

  alias MediaCentaur.Retention.Policy
  alias MediaCentaur.TmdbArtwork

  @impl true
  def policies do
    [
      %Policy{
        key: :tmdb_artwork,
        subsystem: :tmdb,
        label: "TMDB artwork cache",
        description: "Removed 7 days after last use, once nothing references the title.",
        mode: :sweep,
        run: &TmdbArtwork.sweep/0
      }
    ]
  end
end
