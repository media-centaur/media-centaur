defmodule MediaCentaur.Repo.Migrations.FriendsDropNickname do
  @moduledoc """
  The second half of the paired migration `FriendsNameOverrideIsOptional`
  (v1.42.0): `nickname` was kept nullable for the release that still read
  it; this release, the first after it, drops the column. Down re-adds it
  empty.
  """
  use Ecto.Migration

  def change do
    alter table(:friends) do
      remove :nickname, :text
    end
  end
end
