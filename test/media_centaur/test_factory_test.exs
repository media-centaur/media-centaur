defmodule MediaCentaur.TestFactoryTest do
  @moduledoc """
  Covers the factory's *forced-setup* helpers.

  These exist so tests can reach a state the public API deliberately
  refuses to produce without dropping to a raw `Repo` write (MC0023).
  If the bypass silently stopped working, every test relying on it would
  quietly assert against the wrong starting state — hence these.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.Pursuits
  alias MediaCentaur.Library

  describe "create_linked_file/1 for a TV series" do
    test "numbers each factory episode sequentially within the factory season" do
      tv = create_tv_series(%{name: "Sample Show"})
      create_linked_file(%{tv_series_id: tv.id, file_path: "/media/test/Sample.Show.a.mkv"})
      create_linked_file(%{tv_series_id: tv.id, file_path: "/media/test/Sample.Show.b.mkv"})

      [factory_season] = Library.Seasons.list_for_tv_series(tv.id)

      episode_numbers =
        factory_season.id |> Library.Episodes.list_for_season() |> Enum.map(& &1.episode_number)

      # A global counter would number these in the thousands, and the
      # series detail gap-fills every number below the highest episode.
      assert Enum.sort(episode_numbers) == [1, 2]
    end
  end

  describe "backdate/3" do
    test "moves a timestamp into the past, past the changeset that would reject it" do
      pursuit = create_pursuit()
      past = ~U[2020-01-01 00:00:00Z]

      backdated = backdate(pursuit, :inserted_at, past)

      assert backdated.inserted_at == past
      assert {:ok, reloaded} = Pursuits.fetch(pursuit.id)
      assert reloaded.inserted_at == past
    end
  end

  describe "force_state/2" do
    test "puts a record into a state no public command would produce" do
      pursuit = create_pursuit()
      refute pursuit.state == "satisfied"

      forced = force_state(pursuit, "satisfied")

      assert forced.state == "satisfied"
      assert {:ok, reloaded} = Pursuits.fetch(pursuit.id)
      assert reloaded.state == "satisfied"
    end
  end

  describe "force_where/2" do
    test "forces every matching row and reports how many it wrote" do
      import Ecto.Query

      pursuit = create_pursuit()
      past = ~U[2019-06-01 00:00:00Z]

      written =
        force_where(
          from(p in MediaCentaur.Acquisition.Pursuits.Pursuit, where: p.id == ^pursuit.id),
          inserted_at: past
        )

      assert written == 1
      assert {:ok, reloaded} = Pursuits.fetch(pursuit.id)
      assert reloaded.inserted_at == past
    end
  end

  describe "force_attrs/2" do
    test "writes several fields at once, accepting a keyword list or a map" do
      pursuit = create_pursuit()

      forced = force_attrs(pursuit, state: "cancelled", title: "Forced Title")

      assert forced.state == "cancelled"
      assert forced.title == "Forced Title"

      remapped = force_attrs(forced, %{state: "seeking"})
      assert remapped.state == "seeking"
    end
  end
end
