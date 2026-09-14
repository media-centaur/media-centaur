defmodule MediaCentaur.TMDB.TitleTest do
  @moduledoc """
  Locks the contract of the app-wide TMDB title value: identity
  `(tmdb_id, media_type)` plus a render snapshot. `new!/1` is the
  enforced constructor — a missing identity or name crashes at the data
  layer instead of rendering a broken row.
  """
  use MediaCentaur.Case, async: true

  alias MediaCentaur.TMDB.Title

  describe "from_tmdb/2" do
    test "a movie payload: name from title, year and date from release_date" do
      payload = %{
        "id" => 424_242,
        "title" => "Sample Movie",
        "release_date" => "2010-06-15",
        "poster_path" => "/poster.jpg",
        "backdrop_path" => "/backdrop.jpg",
        "overview" => "A sample overview.",
        "runtime" => 120
      }

      assert {:ok, %Title{} = title} = Title.from_tmdb(payload, :movie)

      assert title.tmdb_id == 424_242
      assert title.media_type == :movie
      assert title.name == "Sample Movie"
      assert title.year == "2010"
      assert title.release_date == ~D[2010-06-15]
      assert title.poster_path == "/poster.jpg"
      assert title.backdrop_path == "/backdrop.jpg"
      assert title.overview == "A sample overview."
    end

    test "a series payload: name from name, year and date from first_air_date" do
      payload = %{"id" => 246_810, "name" => "Sample Show", "first_air_date" => "2008-01-20"}

      assert {:ok, %Title{tmdb_id: 246_810, media_type: :tv_series, name: "Sample Show"} = title} =
               Title.from_tmdb(payload, :tv_series)

      assert title.year == "2008"
      assert title.release_date == ~D[2008-01-20]
    end

    test "an undated or partially dated title carries no date; a bare year survives as the year" do
      assert {:ok, %Title{year: nil, release_date: nil}} =
               Title.from_tmdb(%{"id" => 1, "title" => "Undated"}, :movie)

      assert {:ok, %Title{year: nil, release_date: nil}} =
               Title.from_tmdb(%{"id" => 1, "title" => "Undated", "release_date" => ""}, :movie)

      assert {:ok, %Title{year: "2031", release_date: nil}} =
               Title.from_tmdb(%{"id" => 1, "title" => "Partial", "release_date" => "2031"}, :movie)
    end

    test "a payload missing its id or name is an error, not a title" do
      assert {:error, %Ecto.Changeset{}} = Title.from_tmdb(%{"title" => "No id"}, :movie)
      assert {:error, %Ecto.Changeset{}} = Title.from_tmdb(%{"id" => 5}, :tv_series)
      # The wrong name key for the media type is the same as no name.
      assert {:error, %Ecto.Changeset{}} = Title.from_tmdb(%{"id" => 5, "name" => "Show key"}, :movie)
    end
  end

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
