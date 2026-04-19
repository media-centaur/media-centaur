defmodule MediaCentarrWeb.SettingsLive.WatchDirsLogicTest do
  use ExUnit.Case, async: true

  alias MediaCentarrWeb.SettingsLive.WatchDirsLogic

  defp entry(dir, opts \\ []),
    do: %{
      "id" => opts[:id] || dir,
      "dir" => dir,
      "images_dir" => opts[:images_dir],
      "name" => opts[:name]
    }

  describe "default_images_dir_hint/1" do
    test "returns <dir>/.media-centarr/images when dir is set" do
      assert WatchDirsLogic.default_images_dir_hint("/mnt/media") ==
               "/mnt/media/.media-centarr/images"
    end

    test "returns a placeholder when dir is blank or nil" do
      assert WatchDirsLogic.default_images_dir_hint("") == "<watch dir>/.media-centarr/images"
      assert WatchDirsLogic.default_images_dir_hint(nil) == "<watch dir>/.media-centarr/images"
    end
  end

  test "display_label/1 falls back from name to dir" do
    assert WatchDirsLogic.display_label(entry("/mnt/a", name: "Movies")) == "Movies"
    assert WatchDirsLogic.display_label(entry("/mnt/a")) == "/mnt/a"
    assert WatchDirsLogic.display_label(entry("/mnt/a", name: "")) == "/mnt/a"
  end

  test "new_entry/0 returns a blank entry with a UUID id" do
    e = WatchDirsLogic.new_entry()
    assert is_binary(e["id"])
    assert e["dir"] == ""
    assert is_nil(e["images_dir"])
    assert is_nil(e["name"])
  end

  test "upsert/2 replaces an existing entry by id" do
    list = [entry("/mnt/a", id: "a"), entry("/mnt/b", id: "b")]
    updated = %{"id" => "a", "dir" => "/mnt/a2", "images_dir" => nil, "name" => nil}

    assert [
             %{"id" => "a", "dir" => "/mnt/a2"},
             %{"id" => "b"}
           ] = WatchDirsLogic.upsert(list, updated)
  end

  test "upsert/2 appends when id is not in the list" do
    list = [entry("/mnt/a", id: "a")]
    new = %{"id" => "c", "dir" => "/mnt/c", "images_dir" => nil, "name" => nil}

    assert [_, %{"id" => "c"}] = WatchDirsLogic.upsert(list, new)
  end

  test "remove/2 drops the entry with the given id" do
    list = [entry("/mnt/a", id: "a"), entry("/mnt/b", id: "b")]
    assert [%{"id" => "b"}] = WatchDirsLogic.remove(list, "a")
  end

  test "saveable?/1 is true only when no errors" do
    refute WatchDirsLogic.saveable?(%{errors: [{:dir, :not_found}], warnings: [], preview: nil})
    assert WatchDirsLogic.saveable?(%{errors: [], warnings: [], preview: nil})

    assert WatchDirsLogic.saveable?(%{
             errors: [],
             warnings: [{:dir, :unmounted, "/mnt/nas"}],
             preview: nil
           })
  end

  test "error_message/1 produces human-readable strings" do
    assert WatchDirsLogic.error_message({:dir, :not_found}) =~ "not found"
    assert WatchDirsLogic.error_message({:dir, :duplicate}) =~ "already configured"
    assert WatchDirsLogic.error_message({:dir, :nested}) =~ "nested"
    assert WatchDirsLogic.error_message({:name, :too_long}) =~ "60"
  end
end
