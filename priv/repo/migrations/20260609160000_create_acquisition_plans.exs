defmodule MediaCentaur.Repo.Migrations.CreateAcquisitionPlans do
  @moduledoc """
  The durable draft plan (media-search campaign Phase 3, design
  decision 2026-06-09): a plan exists from the moment planning starts —
  lifecycle planning → ready → committed / discarded — so a browser
  refresh or app restart mid-planning loses nothing and the committed
  pursuit carries provenance.

  Also adds `season_number` / `episode_number` to
  `acquisition_pursuit_units` — TMDB-door units are identified by
  episode, not by query term (ADR-055 anticipated this Phase 3
  migration). Additive; no backfill (query-door units keep nil).
  """
  use Ecto.Migration

  def change do
    create table(:acquisition_plans, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, null: false, default: "planning"
      add :tmdb_id, :string, null: false
      add :tmdb_type, :string, null: false
      add :title, :string, null: false
      add :year, :integer
      add :criteria, :map, null: false, default: %{}
      add :grab_future, :boolean, null: false, default: false
      add :pursuit_id, :binary_id
      add :error, :string

      timestamps(type: :utc_datetime)
    end

    create index(:acquisition_plans, [:status])
    create index(:acquisition_plans, [:tmdb_id, :tmdb_type])

    create table(:acquisition_plan_units, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :plan_id, references(:acquisition_plans, type: :binary_id, on_delete: :delete_all),
        null: false

      add :season_number, :integer
      add :episode_number, :integer
      add :label, :string, null: false
      add :position, :integer, null: false, default: 0
      add :status, :string, null: false, default: "pending"
      add :assigned_guid, :string
      add :assigned_title, :string
      add :assigned_term, :string
      add :assigned_quality, :string
      add :assigned_seeders, :integer
      add :assigned_scope, :string
      add :excluded_release_guids, {:array, :string}, null: false, default: []

      timestamps(type: :utc_datetime)
    end

    create index(:acquisition_plan_units, [:plan_id])

    alter table(:acquisition_pursuit_units) do
      add :season_number, :integer
      add :episode_number, :integer
    end
  end
end
