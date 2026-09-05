defmodule MediaCentaur.Library.ContainersTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library.Containers

  import MediaCentaur.TestFactory

  describe "existing_ids/2" do
    test "keeps only the ids that name a live container of that type" do
      series = create_tv_series(%{name: "Sample Show"})
      collection = create_movie_series(%{name: "Sample Collection"})
      gone = Ecto.UUID.generate()

      assert Containers.existing_ids(:tv_series, [series.id, gone, collection.id]) ==
               MapSet.new([series.id])

      assert Containers.existing_ids(:movie_series, [collection.id, gone]) ==
               MapSet.new([collection.id])
    end

    test "is empty for an empty id list without touching the database" do
      assert Containers.existing_ids(:tv_series, []) == MapSet.new()
    end
  end

  describe "list_tv_series/2" do
    test "returns the series among the ids whose status is in the given set" do
      returning = create_tv_series(%{name: "Returning", status: :returning})
      ended = create_tv_series(%{name: "Ended", status: :ended})
      planned = create_tv_series(%{name: "Planned", status: :planned})
      create_tv_series(%{name: "Unlisted", status: :returning})

      ids = [returning.id, ended.id, planned.id]

      assert ids
             |> Containers.list_tv_series(status: [:returning, :planned])
             |> Enum.map(& &1.id)
             |> Enum.sort() == Enum.sort([returning.id, planned.id])
    end
  end
end
