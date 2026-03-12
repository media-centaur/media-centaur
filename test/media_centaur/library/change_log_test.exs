defmodule MediaCentaur.Library.ChangeLogTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library
  alias MediaCentaur.Library.ChangeLog

  import MediaCentaur.TestFactory

  describe "record_addition/1" do
    test "creates an :added entry with correct entity snapshot" do
      entity = create_entity(%{type: :movie, name: "Inception"})
      ChangeLog.record_addition(entity)

      [entry] = Library.list_recent_changes!(50, nil)
      assert entry.entity_id == entity.id
      assert entry.entity_name == "Inception"
      assert entry.entity_type == :movie
      assert entry.kind == :added
    end
  end

  describe "record_removal/1" do
    test "creates a :removed entry with correct entity snapshot" do
      entity = create_entity(%{type: :tv_series, name: "Sample Show Eight"})
      ChangeLog.record_removal(entity)

      [entry] = Library.list_recent_changes!(50, nil)
      assert entry.entity_id == entity.id
      assert entry.entity_name == "Sample Show Eight"
      assert entry.entity_type == :tv_series
      assert entry.kind == :removed
    end
  end

  describe "prune/0" do
    test "keeps only the 100 most recent entries" do
      entity = create_entity(%{name: "Test"})

      for _i <- 1..110 do
        Library.create_change_entry!(%{
          entity_id: entity.id,
          entity_name: entity.name,
          entity_type: entity.type,
          kind: :added
        })
      end

      assert length(Library.list_recent_changes!(150, nil)) == 110

      ChangeLog.prune()

      remaining = Library.list_recent_changes!(150, nil)
      assert length(remaining) == 100
    end
  end

  describe "list_recent_changes" do
    test "returns entries ordered newest-first" do
      entity_a = create_entity(%{name: "First"})
      ChangeLog.record_addition(entity_a)
      entity_b = create_entity(%{name: "Second"})
      ChangeLog.record_addition(entity_b)

      [newest, oldest] = Library.list_recent_changes!(50, nil)
      assert newest.entity_name == "Second"
      assert oldest.entity_name == "First"
    end
  end
end
