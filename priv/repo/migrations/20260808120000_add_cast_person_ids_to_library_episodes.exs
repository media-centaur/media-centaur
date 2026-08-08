defmodule MediaCentaur.Repo.Migrations.AddCastPersonIdsToLibraryEpisodes do
  use Ecto.Migration

  # Per-episode cast membership: TMDB person ids referencing the parent
  # series' aggregate-cast embeds (season regulars + that episode's
  # guest stars, `TMDB.Mapper.episode_attrs/2`). The Cast view partitions
  # the series cast into "in the episode Play would start" vs "other
  # episodes" from this set.
  #
  # No backfill migration: membership needs one TMDB season fetch per
  # season, so it belongs to the rate-limited *Refresh series credits*
  # maintenance task, not a migration. Existing rows default to [] and
  # the Cast view degrades to the single aggregate list until refreshed.
  def change do
    alter table(:library_episodes) do
      add :cast_person_ids, {:array, :integer}, default: [], null: false
    end
  end
end
