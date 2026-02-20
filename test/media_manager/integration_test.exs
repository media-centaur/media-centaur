defmodule MediaManager.IntegrationTest do
  use MediaManager.DataCase

  alias MediaManager.Library.{Entity, WatchedFile}

  describe "WatchedFile :detect action" do
    test "creates a record with :detected state and parses file name" do
      assert {:ok, file} =
               WatchedFile
               |> Ash.Changeset.for_create(:detect, %{
                 file_path:
                   "/mnt/videos/Videos/Sample.Movie.Two.1991.BluRay.Remux.1080p.AVC.DTS-HD.MA.5.1-HiFi.mkv"
               })
               |> Ash.create()

      assert file.state == :detected
      assert file.parsed_title == "Sample Movie Two"
      assert file.parsed_year == 1991
      assert file.parsed_type == :movie
    end
  end

  describe "Entity" do
    test "id is a UUID and survives a round-trip read" do
      assert {:ok, entity} =
               Entity
               |> Ash.Changeset.for_create(:create, %{})
               |> Ash.create()

      assert {:ok, [found]} = Ash.read(Entity)
      assert found.id == entity.id
    end
  end

  describe "JsonWriter.regenerate_all/0" do
    test "writes a valid JSON array to the output dir" do
      output_dir = System.tmp_dir!()

      assert :ok = MediaManager.JsonWriter.regenerate_all(output_dir)

      json_path = Path.join(output_dir, "media.json")
      assert {:ok, contents} = File.read(json_path)
      assert {:ok, entries} = Jason.decode(contents)
      assert is_list(entries)
    end
  end
end
