defmodule MediaCentaur.Library.EntityViewTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.TestFactory, only: [build_entity: 1]

  alias MediaCentaur.Library.EntityView

  describe "title_ref/1 — the TMDB identity a library entity answers to" do
    test "a movie's tmdb id, as the projection carries it (a string)" do
      assert EntityView.title_ref(build_entity(%{type: :movie, tmdb_id: "603"})) == {603, :movie}
    end

    test "a series' tmdb id" do
      assert EntityView.title_ref(build_entity(%{type: :tv_series, tmdb_id: "1399"})) ==
               {1399, :tv_series}
    end

    test "an integer id, as a collection member projection carries it" do
      assert EntityView.title_ref(%{type: :movie, tmdb_id: 603}) == {603, :movie}
    end

    test "a collection has no title identity — its collection id is not a title id" do
      assert EntityView.title_ref(build_entity(%{type: :movie_series, tmdb_id: "10"})) == nil
    end

    test "a video object has none" do
      assert EntityView.title_ref(build_entity(%{type: :video_object, tmdb_id: "5"})) == nil
    end

    test "an unmatched entity has none" do
      assert EntityView.title_ref(build_entity(%{type: :movie, tmdb_id: nil})) == nil
    end
  end
end
