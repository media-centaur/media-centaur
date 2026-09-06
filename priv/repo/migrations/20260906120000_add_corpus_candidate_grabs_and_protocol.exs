defmodule MediaCentaur.Repo.Migrations.AddCorpusCandidateGrabsAndProtocol do
  use Ecto.Migration

  # The corpus claims to carry every `Search.SearchResult` field so a
  # candidate rehydrates into the struct `Prowlarr.grab/1` accepts. Two
  # were missing:
  #
  #   * `grabs`    — the usenet analogue of `seeders`. Without it the
  #                  automatic pick's popularity tiebreak is permanently
  #                  nil on a usenet indexer and same-tier ties fall to
  #                  pool order.
  #   * `protocol` — round-tripped as nil, so every corpus-resolved
  #                  result lost the :torrent/:usenet discriminator the
  #                  queue matches on.
  #
  # Both are nullable with no backfill: the values only exist on a live
  # indexer response, and rows predating this migration are re-observed
  # on the next search or pruned by the 14-day retention sweep.
  def change do
    alter table(:acquisition_corpus_candidates) do
      add :grabs, :integer
      add :protocol, :string
    end
  end
end
