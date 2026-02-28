defmodule MediaCentaur.Pipeline.Stages.ParseTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Pipeline.Payload
  alias MediaCentaur.Pipeline.Stages.Parse

  describe "run/1" do
    test "parses a movie file path" do
      payload = %Payload{file_path: "/media/Movies/Fight.Club.1999.BluRay.1080p.mkv"}

      assert {:ok, result} = Parse.run(payload)
      assert result.parsed.title == "Fight Club"
      assert result.parsed.year == 1999
      assert result.parsed.type == :movie
      assert is_nil(result.parsed.season)
      assert is_nil(result.parsed.episode)
    end

    test "parses a TV episode file path" do
      payload = %Payload{
        file_path: "/media/TV/Sample.Show.Eight/Season.01/Sample.Show.Eight.S01E05.1080p.mkv"
      }

      assert {:ok, result} = Parse.run(payload)
      assert result.parsed.title == "Sample Show Eight"
      assert result.parsed.type == :tv
      assert result.parsed.season == 1
      assert result.parsed.episode == 5
    end

    test "preserves existing payload fields" do
      payload = %Payload{
        file_path: "/media/Movies/Fight.Club.1999.mkv",
        watch_directory: "/media/Movies",
        entry_point: :file_detected
      }

      assert {:ok, result} = Parse.run(payload)
      assert result.watch_directory == "/media/Movies"
      assert result.entry_point == :file_detected
      assert result.parsed != nil
    end
  end
end
