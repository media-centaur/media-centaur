defmodule MediaCentaur.Repo.Migrations.AddPlayerDetails do
  @moduledoc """
  What the host learns of a paired player: the device's own declaration
  (model, OS, app version, form factor) sent when its channel opens, the
  user agent of the browser that shows its pages, and when and from where
  its channel last opened or closed.
  """
  use Ecto.Migration

  def change do
    alter table(:players) do
      add :device, :map
      add :user_agent, :text
      add :last_seen_at, :utc_datetime_usec
      add :last_address, :text
    end
  end
end
