defmodule MediaCentaur.TMDB.RetentionPolicies do
  @moduledoc """
  Retention policy for the TMDB store (ADR-071 §2.4): a stored title is
  removed only when nothing references it — no library entry, list
  entry, tracked title, plan or friend's activity
  (`MediaCentaur.TMDB.References`) — and it was last fetched more than
  seven days ago. The same reference set keeps the title's artwork alive
  (`MediaCentaur.TmdbArtwork.RetentionPolicies`); the two sweeps differ
  only in what they measure age by — the store knows when it last
  fetched, the artwork cache when a file was last used.
  """
  @behaviour MediaCentaur.Retention.PolicyProvider

  alias MediaCentaur.Retention.Policy
  alias MediaCentaur.TMDB.Store

  @impl true
  def policies do
    [
      %Policy{
        key: :tmdb_store,
        subsystem: :tmdb,
        label: "TMDB store",
        description:
          "Removed 7 days after the last fetch, once nothing references the title — no library entry, list entry, tracked title, plan or friend's activity.",
        mode: :sweep,
        run: &Store.sweep/0
      }
    ]
  end
end
