defmodule MediaCentaur.Library.ContainersTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library.Containers

  import MediaCentaur.TestFactory

  describe "the Writable contract" do
    # `Containers.create/2` dispatches `schema(type).create_changeset/1` on a
    # module it resolves at runtime. Nothing else checks that a newly added
    # container type actually carries the contract, and the dispatch would
    # only fail at the point a user creates one.
    test "every container schema declares MediaCentaur.Library.Writable" do
      for type <- Containers.types() do
        schema = Containers.schema(type)
        behaviours = schema.__info__(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()

        assert MediaCentaur.Library.Writable in behaviours,
               "#{inspect(schema)} backs container type #{inspect(type)} but does not declare the contract"
      end
    end
  end

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
end
