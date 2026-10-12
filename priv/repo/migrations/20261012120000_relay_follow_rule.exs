defmodule MediaCentaur.Repo.Migrations.RelayFollowRule do
  @moduledoc """
  A relay carries its follow rule (`members` or `added`); the roster becomes
  `contacts`, one row per key the reader has a view of, with `added_at`
  (nil for a key followed only through a relay) and `hidden`;
  `relay_members` records the keys seen publishing on a members-rule relay.
  """
  use Ecto.Migration

  def change do
    alter table(:relays) do
      add :follow, :text, null: false, default: "added"
    end

    drop unique_index(:friends, [:pubkey])
    rename table(:friends), to: table(:contacts)

    alter table(:contacts) do
      add :added_at, :utc_datetime
      add :hidden, :boolean, null: false, default: false
    end

    create unique_index(:contacts, [:pubkey])

    # Every existing row was added by hand, so it is a friend from the
    # moment the column exists: a single copy, no logic, inseparable from
    # the add — not a data migration.
    # credo:disable-for-next-line MediaCentaur.Credo.Checks.RowMutationInSchemaMigration
    execute "UPDATE contacts SET added_at = inserted_at", "UPDATE contacts SET added_at = NULL"

    create table(:relay_members, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :relay_id, references(:relays, type: :uuid, on_delete: :delete_all), null: false
      add :pubkey, :text, null: false
      add :seen_at, :utc_datetime_usec, null: false
    end

    create unique_index(:relay_members, [:relay_id, :pubkey])
    create index(:relay_members, [:pubkey])
  end
end
