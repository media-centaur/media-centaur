defmodule MediaCentarr.Repo.Migrations.AddQualityBoundsToGrabs do
  use Ecto.Migration

  def change do
    alter table(:acquisition_grabs) do
      # Snapshot of the effective quality bounds at the moment this grab
      # was enqueued. Reading them per-attempt protects in-flight grabs
      # from preference changes the user makes mid-flight.
      add :min_quality, :string
      add :max_quality, :string
      # Patience window: while the grab is younger than this many hours
      # AND `max_quality` includes 4K, search filters to 4K-only and
      # snoozes on no-results. After patience expires, floor relaxes to
      # `min_quality`. `nil` means inherit the global default.
      add :quality_4k_patience_hours, :integer
    end
  end
end
