defmodule MediaCentaur.Repo.Migrations.CreateDiagnosticEventsAndIncidents do
  use Ecto.Migration

  # Phase 1 of the observability campaign: the durable backbone.
  #
  # `diagnostic_events` is the append-only log of redacted warning/error
  # events that feed `:log` incidents — one row per captured event, pruned
  # on a retention window. `incidents` is the stateful, durable record an
  # incident report is packaged from. In Phase 1 only the `:log` origin is
  # populated (one incident per fingerprint); `:subsystem` / `:user` origins
  # and the context-snapshot columns arrive in later phases but their columns
  # are provisioned here so the table is stable from the start.
  #
  # Purely additive (two new tables, no backfill) — safe to run against the
  # live DB.
  def change do
    create table(:diagnostic_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :fingerprint, :string, null: false
      add :component, :string, null: false
      add :level, :string, null: false
      # Already redacted + normalized at capture (see ErrorReports.Redactor).
      add :message, :text, null: false
      add :module, :string
      # Scalar-pruned logger metadata (ids kept; titles/paths redacted).
      add :metadata, :map, null: false, default: %{}
      # Domain time of the log event, distinct from row insertion time.
      add :occurred_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:diagnostic_events, [:fingerprint])
    # Retention prune walks by occurred_at.
    create index(:diagnostic_events, [:occurred_at])

    create table(:incidents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :origin, :string, null: false
      # Subsystem-defined fault symbol for `:subsystem` incidents
      # (e.g. "drive_offline"); null for `:log`/`:user`.
      add :kind, :string
      add :component, :string, null: false
      # Representative redacted/normalized message + human title for the
      # incident, refreshed to the latest occurrence. Lets a bucket render
      # without joining back to diagnostic_events.
      add :message, :text
      add :display_title, :string
      # The `:log` grouping key; null for `:user` incidents.
      add :fingerprint, :string
      add :severity, :string, null: false
      add :status, :string, null: false, default: "open"
      add :count, :integer, null: false, default: 1
      add :first_seen, :utc_datetime_usec, null: false
      add :last_seen, :utc_datetime_usec, null: false
      add :resolved_at, :utc_datetime_usec
      # Frozen snapshots (Phase 2): "at incident" context, first + latest.
      add :first_context, :map
      add :latest_context, :map
      # `:user`-origin only (Phase 4).
      add :user_description, :text
      # global / subsystem / {entity_type, entity_id} — JSON shape (Phase 4).
      add :scope, :map
      add :app_version_at_first, :string

      timestamps(type: :utc_datetime_usec)
    end

    # `:log` incidents group by fingerprint — one open incident per fingerprint.
    # Partial so the many null-fingerprint `:subsystem`/`:user` rows don't
    # collide. SQLite synthesises the constraint name from the column tuple;
    # the changeset's `unique_constraint` :name must match this exactly.
    create unique_index(:incidents, [:fingerprint],
             where: "fingerprint IS NOT NULL",
             name: :incidents_fingerprint_index
           )

    create index(:incidents, [:status])
    create index(:incidents, [:component])
  end
end
