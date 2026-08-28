defmodule MediaCentaur.AppsTest do
  use MediaCentaur.DataCase

  import MediaCentaur.TestFactory

  alias MediaCentaur.Apps

  describe "add_app/1" do
    test "creates an app with name, command, and origin" do
      assert {:ok, app} =
               Apps.add_app(%{
                 name: "Sample Game",
                 command: "sample-game --fullscreen",
                 origin: %{"source" => "manual"}
               })

      assert app.name == "Sample Game"
      assert app.command == "sample-game --fullscreen"
      assert app.origin == %{"source" => "manual"}
    end

    test "requires name and command" do
      assert {:error, changeset} = Apps.add_app(%{})
      assert %{name: ["can't be blank"], command: ["can't be blank"]} = errors_on(changeset)
    end

    test "re-adding the same steam origin returns the existing app" do
      {:ok, first} =
        Apps.add_app(%{
          name: "Sample Game",
          command: "steam steam://rungameid/100",
          origin: %{"source" => "steam", "app_id" => 100}
        })

      assert {:ok, second} =
               Apps.add_app(%{
                 name: "Sample Game Renamed",
                 command: "steam steam://rungameid/100",
                 origin: %{"source" => "steam", "app_id" => 100}
               })

      assert second.id == first.id
      assert length(Apps.list_apps()) == 1
    end
  end

  describe "list_apps/0" do
    test "sorts alphabetically by name, case-insensitive" do
      create_app(%{name: "zebra tool"})
      create_app(%{name: "Alpha Game"})
      create_app(%{name: "beta App"})

      assert Enum.map(Apps.list_apps(), & &1.name) == ["Alpha Game", "beta App", "zebra tool"]
    end
  end

  describe "added_steam_ids/0" do
    test "returns the set of steam app ids already added" do
      create_app(%{origin: %{"source" => "steam", "app_id" => 100}})
      create_app(%{name: "Manual One", origin: %{"source" => "manual"}})

      assert Apps.added_steam_ids() == MapSet.new([100])
    end
  end

  describe "update_app/2" do
    test "updates name and command" do
      app = create_app(%{})
      assert {:ok, updated} = Apps.update_app(app, %{name: "New Name", command: "new-cmd"})
      assert updated.name == "New Name"
      assert updated.command == "new-cmd"
    end
  end

  describe "remove_app/1" do
    test "deletes the row" do
      app = create_app(%{})
      assert :ok = Apps.remove_app(app)
      assert Apps.list_apps() == []
    end
  end
end
