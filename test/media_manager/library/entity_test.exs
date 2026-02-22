defmodule MediaManager.Library.EntityTest do
  use MediaManager.DataCase

  alias MediaManager.Library.Entity

  describe "Entity" do
    test "id is a UUID and survives a round-trip read" do
      entity = create_entity(%{type: :movie, name: "Round Trip"})

      assert {:ok, [found]} = Ash.read(Entity)
      assert found.id == entity.id
    end
  end
end
