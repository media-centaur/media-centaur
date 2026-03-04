defmodule MediaCentaur.Library.HelpersTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Library.Helpers

  describe "entity_ids_all_absent/0" do
    test "includes entity where all files are absent" do
      entity = create_entity()
      file = create_linked_file(%{entity: entity})
      Ash.update!(Ash.Changeset.for_update(file, :mark_absent))

      assert entity.id in Helpers.entity_ids_all_absent()
    end

    test "excludes entity with mixed states" do
      entity = create_entity()
      create_linked_file(%{entity: entity})

      file2 = create_linked_file(%{entity: entity})
      Ash.update!(Ash.Changeset.for_update(file2, :mark_absent))

      refute entity.id in Helpers.entity_ids_all_absent()
    end

    test "excludes entity with all files complete" do
      entity = create_entity()
      create_linked_file(%{entity: entity})

      refute entity.id in Helpers.entity_ids_all_absent()
    end

    test "excludes entity with no watched files" do
      entity = create_entity()

      refute entity.id in Helpers.entity_ids_all_absent()
    end
  end

  describe "entity_ids_all_absent_for/1" do
    test "scoped to provided entity IDs only" do
      entity1 = create_entity()
      file1 = create_linked_file(%{entity: entity1})
      Ash.update!(Ash.Changeset.for_update(file1, :mark_absent))

      entity2 = create_entity()
      file2 = create_linked_file(%{entity: entity2})
      Ash.update!(Ash.Changeset.for_update(file2, :mark_absent))

      result = Helpers.entity_ids_all_absent_for([entity1.id])

      assert entity1.id in result
      refute entity2.id in result
    end

    test "returns empty MapSet for empty list" do
      assert Helpers.entity_ids_all_absent_for([]) == MapSet.new()
    end
  end
end
