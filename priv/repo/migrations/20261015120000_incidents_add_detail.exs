defmodule MediaCentaur.Repo.Migrations.IncidentsAddDetail do
  use Ecto.Migration

  # A `:subsystem` fault has no log lines; its evidence is the probe's own
  # account of what it saw (one line per relay, client, upstream…), refreshed
  # on every re-raise.
  def change do
    alter table(:incidents) do
      add :detail, :text
    end
  end
end
