defmodule MediaCentaur.Repo.Migrations.AddExternalIdsToCorpusCandidates do
  use Ecto.Migration

  # Prowlarr's aggregated response carries the indexer's own answer to
  # "which title is this release?" — `imdbId` / `tmdbId` / `tvdbId` — and
  # `SearchResult` used to discard all three. The corpus claims to carry
  # every `SearchResult` field, so a corpus-served candidate would
  # otherwise reach `TitleMatcher` stripped of the exact identity a
  # live-searched one carries, and match by title parsing instead.
  #
  # Nullable with no backfill: the values only exist on a live indexer
  # response, and rows predating this migration are re-observed on the
  # next search or pruned by the 14-day retention sweep.
  def change do
    alter table(:acquisition_corpus_candidates) do
      add :imdb_id, :string
      add :tmdb_id, :string
      add :tvdb_id, :string
    end
  end
end
