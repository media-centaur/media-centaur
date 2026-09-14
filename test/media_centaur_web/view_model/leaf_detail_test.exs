defmodule MediaCentaurWeb.ViewModel.LeafDetailTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaurWeb.ViewModel.LeafDetail

  describe "compose/2 — the entry for a movie or video object the library owns" do
    test "carries the entity, its progress summary, its records and the resume target" do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      create_linked_file(%{movie_id: movie.id})

      assert {:ok, %LeafDetail{} = entry} = LeafDetail.compose(:movie, movie.id)
      assert entry.entity.id == movie.id
      assert entry.entity.type == :movie
      assert entry.entity.name == "Sample Movie"
      assert entry.progress_records == []
      assert Map.has_key?(entry, :progress)
      assert Map.has_key?(entry, :resume_target)
    end

    test "a movie the library has no file for is not found" do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      assert LeafDetail.compose(:movie, movie.id) == :not_found
    end

    test "an unknown id is not found" do
      assert LeafDetail.compose(:movie, Ecto.UUID.generate()) == :not_found
    end
  end
end
