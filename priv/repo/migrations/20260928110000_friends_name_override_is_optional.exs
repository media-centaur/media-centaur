defmodule MediaCentaur.Repo.Migrations.FriendsNameOverrideIsOptional do
  @moduledoc """
  The reader's name for a friend becomes optional now that a published
  name exists to fall back on (UIDR-047). SQLite cannot relax NOT NULL in
  place, so the table is rebuilt: `name_override` becomes a real column,
  filled from `nickname`, and `nickname` stays as a nullable column the
  outgoing release still reads between `migrate` and its restart (the
  paired-release rule). The release after this one drops `nickname`.
  """
  use Ecto.Migration

  def up do
    create table(:friends_next, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :pubkey, :text, null: false
      add :nickname, :text
      add :name_override, :text

      timestamps(type: :utc_datetime)
    end

    execute """
    INSERT INTO friends_next (id, pubkey, nickname, name_override, inserted_at, updated_at)
    SELECT id, pubkey, nickname, nickname, inserted_at, updated_at FROM friends
    """

    drop table(:friends)
    rename table(:friends_next), to: table(:friends)
    create unique_index(:friends, [:pubkey])
  end

  def down do
    create table(:friends_prev, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :pubkey, :text, null: false
      add :nickname, :text, null: false

      timestamps(type: :utc_datetime)
    end

    execute """
    INSERT INTO friends_prev (id, pubkey, nickname, inserted_at, updated_at)
    SELECT id, pubkey, COALESCE(name_override, nickname, ''), inserted_at, updated_at FROM friends
    """

    drop table(:friends)
    rename table(:friends_prev), to: table(:friends)
    create unique_index(:friends, [:pubkey])
  end
end
