defmodule MediaCentarr.Subtitles.Detector.FfprobeTest do
  use ExUnit.Case, async: false

  alias MediaCentarr.Subtitles.Detector.Ffprobe
  alias MediaCentarr.Subtitles.Track

  setup do
    # Override the runner seam for this test process. Each test sets the
    # runner to whatever shape it needs, then we restore the default.
    on_exit(fn -> Application.delete_env(:media_centarr, :subtitles_runner) end)
    :ok
  end

  defp set_runner(fun), do: Application.put_env(:media_centarr, :subtitles_runner, fun)

  describe "probe/1 — happy paths" do
    test "parses ffprobe JSON with multiple subtitle streams" do
      json = ~s({
        "streams": [
          {"index": 2, "tags": {"language": "eng"}},
          {"index": 3, "tags": {"language": "spa"}},
          {"index": 4, "tags": {"language": "fra"}}
        ]
      })

      set_runner(fn "ffprobe", _args -> {json, 0} end)

      assert [
               %Track{kind: :embedded, language: "en", source: "stream:2"},
               %Track{kind: :embedded, language: "es", source: "stream:3"},
               %Track{kind: :embedded, language: "fr", source: "stream:4"}
             ] = Ffprobe.probe("/whatever.mkv")
    end

    test "handles streams with no language tag (language: nil)" do
      json = ~s({"streams": [{"index": 5}]})
      set_runner(fn _, _ -> {json, 0} end)

      assert [%Track{kind: :embedded, language: nil, source: "stream:5"}] =
               Ffprobe.probe("/whatever.mkv")
    end

    test "returns [] when there are no subtitle streams" do
      set_runner(fn _, _ -> {~s({"streams": []}), 0} end)
      assert Ffprobe.probe("/whatever.mkv") == []
    end
  end

  describe "probe/1 — graceful degradation" do
    test "returns [] when the runner reports the binary is missing" do
      set_runner(fn _, _ -> {:error, :enoent} end)
      assert Ffprobe.probe("/whatever.mkv") == []
    end

    test "returns [] when ffprobe exits non-zero" do
      set_runner(fn _, _ -> {"some error output", 1} end)
      assert Ffprobe.probe("/whatever.mkv") == []
    end

    test "returns [] when stdout is not valid JSON" do
      set_runner(fn _, _ -> {"not json", 0} end)
      assert Ffprobe.probe("/whatever.mkv") == []
    end

    test "returns [] when the runner raises (treated as :error)" do
      set_runner(fn _, _ -> {:error, %RuntimeError{message: "boom"}} end)
      assert Ffprobe.probe("/whatever.mkv") == []
    end
  end

  describe "probe/1 — command construction" do
    test "passes the file path as the last arg with the documented flags" do
      test_pid = self()

      set_runner(fn executable, args ->
        send(test_pid, {:invoked, executable, args})
        {~s({"streams": []}), 0}
      end)

      Ffprobe.probe("/path/to/Movie.mkv")

      assert_received {:invoked, "ffprobe", args}
      assert "/path/to/Movie.mkv" == List.last(args)
      assert "-of" in args
      assert "json" in args
      assert "-select_streams" in args
      assert "s" in args
    end
  end
end
