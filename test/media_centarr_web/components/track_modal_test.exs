defmodule MediaCentarrWeb.Components.TrackModalTest do
  @moduledoc """
  Locks the view-model contracts for `TrackModal`. These tests don't render
  HTML — they assert the co-located structs refuse incomplete construction,
  which is the gate that makes "Logic forgot to populate `:url`"-style bugs
  crash at the data layer instead of silently rendering broken markup.
  See `~/src/media-centarr/component-contract-plan.md` Phase 4.
  """
  use ExUnit.Case, async: true

  alias MediaCentarrWeb.Components.TrackModal.{
    CollectionItem,
    ScopeItem,
    SearchResult,
    Suggestion
  }

  describe "Suggestion struct" do
    test "constructs with all enforced keys" do
      suggestion =
        struct!(Suggestion, %{
          tv_series_id: 42,
          tmdb_id: "1234",
          name: "Sample Show",
          media_type: :tv_series,
          poster_url: nil
        })

      assert %Suggestion{} = suggestion
      assert suggestion.tmdb_id == "1234"
    end

    test "raises ArgumentError when tmdb_id missing" do
      assert_raise ArgumentError, fn ->
        struct!(Suggestion, %{
          tv_series_id: 42,
          name: "Sample Show",
          media_type: :tv_series,
          poster_url: nil
        })
      end
    end

    test "raises ArgumentError when name missing" do
      assert_raise ArgumentError, fn ->
        struct!(Suggestion, %{
          tv_series_id: 42,
          tmdb_id: "1234",
          media_type: :tv_series,
          poster_url: nil
        })
      end
    end
  end

  describe "SearchResult struct" do
    test "constructs with all enforced keys" do
      result =
        struct!(SearchResult, %{
          tmdb_id: 1234,
          media_type: :movie,
          name: "Sample Movie",
          year: "2010",
          poster_path: "/abc.jpg",
          already_tracked: false
        })

      assert %SearchResult{} = result
      assert result.already_tracked == false
    end

    test "raises ArgumentError when already_tracked missing" do
      assert_raise ArgumentError, fn ->
        struct!(SearchResult, %{
          tmdb_id: 1234,
          media_type: :movie,
          name: "Sample Movie",
          year: "2010",
          poster_path: nil
        })
      end
    end

    test "raises ArgumentError when media_type missing" do
      assert_raise ArgumentError, fn ->
        struct!(SearchResult, %{
          tmdb_id: 1234,
          name: "Sample Movie",
          year: "2010",
          poster_path: nil,
          already_tracked: false
        })
      end
    end
  end

  describe "ScopeItem struct" do
    test "constructs with all enforced keys" do
      item = struct!(ScopeItem, %{tmdb_id: 1, name: "Sample Show", poster_path: nil})

      assert %ScopeItem{} = item
      assert item.tmdb_id == 1
    end

    test "raises ArgumentError when name missing" do
      assert_raise ArgumentError, fn ->
        struct!(ScopeItem, %{tmdb_id: 1, poster_path: nil})
      end
    end
  end

  describe "CollectionItem struct" do
    test "constructs with all enforced keys" do
      item =
        struct!(CollectionItem, %{
          tmdb_id: 1,
          name: "Sample Movie",
          poster_path: nil,
          collection_id: 99,
          collection_name: "Sample Collection"
        })

      assert %CollectionItem{} = item
      assert item.collection_id == 99
    end

    test "raises ArgumentError when collection_id missing" do
      assert_raise ArgumentError, fn ->
        struct!(CollectionItem, %{
          tmdb_id: 1,
          name: "Sample Movie",
          poster_path: nil,
          collection_name: "Sample Collection"
        })
      end
    end

    test "raises ArgumentError when collection_name missing" do
      assert_raise ArgumentError, fn ->
        struct!(CollectionItem, %{
          tmdb_id: 1,
          name: "Sample Movie",
          poster_path: nil,
          collection_id: 99
        })
      end
    end
  end
end
