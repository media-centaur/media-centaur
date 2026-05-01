defmodule MediaCentarr.Library.ChangeLogTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library
  alias MediaCentarr.Library.ChangeLog

  import MediaCentarr.TestFactory

  describe "record_addition/1" do
    test "creates an :added entry with correct entity snapshot" do
      movie = create_entity(%{type: :movie, name: "Sample Movie"})
      ChangeLog.record_addition(movie, :movie)

      [entry] = Library.list_recent_changes(50, nil)
      assert entry.entity_id == movie.id
      assert entry.entity_name == "Sample Movie"
      assert entry.entity_type == :movie
      assert entry.kind == :added
    end
  end

  describe "record_removal/1" do
    test "creates a :removed entry with correct entity snapshot" do
      tv_series = create_entity(%{type: :tv_series, name: "Sample Show"})
      ChangeLog.record_removal(%{id: tv_series.id, name: tv_series.name, type: :tv_series})

      [entry] = Library.list_recent_changes(50, nil)
      assert entry.entity_id == tv_series.id
      assert entry.entity_name == "Sample Show"
      assert entry.entity_type == :tv_series
      assert entry.kind == :removed
    end
  end

  describe "prune/0" do
    test "keeps only the 100 most recent entries" do
      movie = create_entity(%{name: "Test"})

      for _i <- 1..110 do
        Library.create_change_entry!(%{
          entity_id: movie.id,
          entity_name: movie.name,
          entity_type: :movie,
          kind: :added
        })
      end

      assert length(Library.list_recent_changes(150, nil)) == 110

      ChangeLog.prune()

      remaining = Library.list_recent_changes(150, nil)
      assert length(remaining) == 100
    end
  end

  describe "list_recent_changes" do
    test "returns entries ordered newest-first" do
      movie_a = create_entity(%{name: "First"})
      ChangeLog.record_addition(movie_a, :movie)
      movie_b = create_entity(%{name: "Second"})
      ChangeLog.record_addition(movie_b, :movie)

      [newest, oldest] = Library.list_recent_changes(50, nil)
      assert newest.entity_name == "Second"
      assert oldest.entity_name == "First"
    end
  end
end
