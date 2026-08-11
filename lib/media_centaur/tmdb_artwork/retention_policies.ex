defmodule MediaCentaur.TmdbArtwork.RetentionPolicies do
  @moduledoc """
  Retention policy for the TMDB artwork cache: an entry is removed only
  when nothing references it (no registered hold) AND it has been
  unused for the TTL. Supersedes ReleaseTracking's `:tracking_artwork`
  orphan sweep — "a tracked item exists" is now just one kind of hold.
  """
  @behaviour MediaCentaur.Retention.PolicyProvider

  alias MediaCentaur.Retention.Policy
  alias MediaCentaur.TmdbArtwork

  @impl true
  def policies do
    [
      %Policy{
        key: :tmdb_artwork,
        subsystem: :acquisition,
        label: "TMDB artwork cache",
        description: "Removed 7 days after last use, once nothing tracks or pursues the title.",
        mode: :sweep,
        run: &TmdbArtwork.sweep/0
      }
    ]
  end
end
