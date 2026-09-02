defmodule MediaCentaur.TMDB.TitleTest do
  @moduledoc """
  Locks the contract of the app-wide TMDB title value: identity
  `(tmdb_id, media_type)` plus a render snapshot. `new!/1` is the
  enforced constructor — a missing identity or name crashes at the data
  layer instead of rendering a broken row.
  """
  use ExUnit.Case, async: true

  alias MediaCentaur.TMDB.Title

  describe "new!/1" do
    test "builds a title from identity + name, everything else nil" do
      title = Title.new!(%{tmdb_id: 1234, media_type: :movie, name: "Sample Movie"})

      assert %Title{tmdb_id: 1234, media_type: :movie, name: "Sample Movie"} = title
      assert title.year == nil
      assert title.release_date == nil
      assert title.poster_path == nil
      assert title.backdrop_path == nil
      assert title.overview == nil
    end

    test "carries the render snapshot when given" do
      title =
        Title.new!(%{
          tmdb_id: 1234,
          media_type: :tv_series,
          name: "Sample Show",
          year: "2010",
          release_date: ~D[2010-06-16],
          poster_path: "/abc.jpg",
          backdrop_path: "/bg.jpg",
          overview: "A sample overview."
        })

      assert title.year == "2010"
      assert title.release_date == ~D[2010-06-16]
      assert title.poster_path == "/abc.jpg"
      assert title.backdrop_path == "/bg.jpg"
      assert title.overview == "A sample overview."
    end

    test "raises when tmdb_id, media_type, or name is missing" do
      assert_raise ArgumentError, fn -> Title.new!(%{media_type: :movie, name: "Sample Movie"}) end
      assert_raise ArgumentError, fn -> Title.new!(%{tmdb_id: 1234, name: "Sample Movie"}) end
      assert_raise ArgumentError, fn -> Title.new!(%{tmdb_id: 1234, media_type: :movie}) end
    end

    test "rejects an unknown media_type" do
      assert_raise ArgumentError, fn ->
        Title.new!(%{tmdb_id: 1234, media_type: :book, name: "Sample"})
      end
    end
  end

  describe "changeset/2" do
    test "casts the whole snapshot and requires the identity + name" do
      changeset = Title.changeset(%Title{}, %{})
      refute changeset.valid?
      assert Keyword.keys(changeset.errors) == [:tmdb_id, :media_type, :name]
    end
  end

  describe "ref/1" do
    test "is the {tmdb_id, media_type} pair" do
      assert Title.ref(Title.new!(%{tmdb_id: 7, media_type: :movie, name: "Sample Movie"})) ==
               {7, :movie}
    end
  end
end
