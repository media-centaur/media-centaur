defmodule MediaCentaur.Repo.Migrations.ProfilesHueRequired do
  @moduledoc """
  A viewer profile always has a hue (UIDR-053, amended 2026-10-11): one is
  given at birth, so the people of an install differ at a glance. Every
  profile without one takes one here, oldest first: Blue, 250, while it is
  free — the angle a hueless profile was drawn at by CSS, so the owner
  profile the upgrade created keeps its look — then the first palette hue
  no profile holds, in the swatch row's order. The column stays nullable
  (SQLite rebuilds a table to change that); the changeset is the guard.
  """
  use Ecto.Migration

  # `MediaCentaur.Hue.palette/0` on the day; inlined so the migration does
  # not move when the palette does.
  @palette [12, 45, 80, 150, 195, 250, 290, 335]

  def up do
    execute(fn ->
      %{rows: rows} = repo().query!("SELECT id, hue FROM profiles ORDER BY inserted_at, id")
      taken = for [_id, hue] <- rows, hue != nil, do: hue

      rows
      |> Enum.filter(fn [_id, hue] -> hue == nil end)
      |> Enum.reduce(taken, fn [id, nil], taken ->
        hue = if 250 in taken, do: Enum.find(@palette, &(&1 not in taken)), else: 250
        repo().query!("UPDATE profiles SET hue = ?1 WHERE id = ?2", [hue, id])
        [hue | taken]
      end)
    end)
  end

  def down, do: :ok
end
