defmodule MediaCentaurWeb.Components.TrackModalTest do
  @moduledoc """
  Locks the view-model contracts for `TrackModal`. These tests don't render
  HTML — they assert the co-located structs refuse incomplete construction,
  which is the gate that makes "Logic forgot to populate `:url`"-style bugs
  crash at the data layer instead of silently rendering broken markup.
  See `~/src/media-centaur/component-contract-plan.md` Phase 4.
  """
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.Components.TrackModal.{
    CollectionItem,
    ScopeItem,
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

  # The TMDB search-result row contract moved to the context —
  # `MediaCentaur.ReleaseTracking.TitleResult`, locked in
  # `test/media_centaur/release_tracking/title_result_test.exs`.

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
