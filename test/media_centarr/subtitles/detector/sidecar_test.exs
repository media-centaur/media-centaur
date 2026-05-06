defmodule MediaCentarr.Subtitles.Detector.SidecarTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Subtitles.Detector.Sidecar
  alias MediaCentarr.Subtitles.Track

  setup do
    dir = Path.join(System.tmp_dir!(), "subs-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp touch(dir, name), do: File.write!(Path.join(dir, name), "")

  describe "scan/1" do
    test "returns [] when the directory is empty", %{dir: dir} do
      video = Path.join(dir, "Sample.Movie.2020.mkv")
      touch(dir, "Sample.Movie.2020.mkv")
      assert Sidecar.scan(video) == []
    end

    test "returns [] when no sidecar shares the video's basename", %{dir: dir} do
      video = Path.join(dir, "Sample.Movie.2020.mkv")
      touch(dir, "Sample.Movie.2020.mkv")
      touch(dir, "Other.Movie.en.srt")
      assert Sidecar.scan(video) == []
    end

    test "detects a bare-extension sidecar with no language suffix", %{dir: dir} do
      video = Path.join(dir, "Sample.Movie.2020.mkv")
      touch(dir, "Sample.Movie.2020.mkv")
      touch(dir, "Sample.Movie.2020.srt")

      assert [%Track{kind: :sidecar, language: nil, source: source}] = Sidecar.scan(video)
      assert Path.basename(source) == "Sample.Movie.2020.srt"
    end

    test "detects a 2-letter language suffix", %{dir: dir} do
      video = Path.join(dir, "Sample.Movie.2020.mkv")
      touch(dir, "Sample.Movie.2020.mkv")
      touch(dir, "Sample.Movie.2020.en.srt")

      assert [%Track{kind: :sidecar, language: "en"}] = Sidecar.scan(video)
    end

    test "detects a 3-letter language suffix and normalises it", %{dir: dir} do
      video = Path.join(dir, "Sample.Movie.2020.mkv")
      touch(dir, "Sample.Movie.2020.mkv")
      touch(dir, "Sample.Movie.2020.spa.srt")

      assert [%Track{kind: :sidecar, language: "es"}] = Sidecar.scan(video)
    end

    test "supports multiple subtitle extensions", %{dir: dir} do
      video = Path.join(dir, "Sample.Movie.2020.mkv")
      touch(dir, "Sample.Movie.2020.mkv")
      touch(dir, "Sample.Movie.2020.en.srt")
      touch(dir, "Sample.Movie.2020.fr.vtt")
      touch(dir, "Sample.Movie.2020.de.ass")
      touch(dir, "Sample.Movie.2020.it.ssa")
      touch(dir, "Sample.Movie.2020.ja.sub")

      langs = Sidecar.scan(video) |> Enum.map(& &1.language) |> Enum.sort()
      assert langs == ["de", "en", "fr", "it", "ja"]
    end

    test "ignores non-subtitle extensions", %{dir: dir} do
      video = Path.join(dir, "Sample.Movie.2020.mkv")
      touch(dir, "Sample.Movie.2020.mkv")
      touch(dir, "Sample.Movie.2020.nfo")
      touch(dir, "Sample.Movie.2020-poster.jpg")
      touch(dir, "Sample.Movie.2020.en.srt")

      assert [%Track{language: "en"}] = Sidecar.scan(video)
    end

    test "returns unknown-language tracks for non-ISO suffixes (e.g. forced/sdh)", %{dir: dir} do
      video = Path.join(dir, "Sample.Movie.2020.mkv")
      touch(dir, "Sample.Movie.2020.mkv")
      touch(dir, "Sample.Movie.2020.forced.srt")
      touch(dir, "Sample.Movie.2020.sdh.srt")

      langs = Enum.map(Sidecar.scan(video), & &1.language)
      assert langs == [nil, nil]
    end

    test "is case-insensitive on the video basename match", %{dir: dir} do
      video = Path.join(dir, "Sample.Movie.2020.mkv")
      touch(dir, "Sample.Movie.2020.mkv")
      # Sidecar with mixed case basename
      touch(dir, "sample.movie.2020.en.srt")

      assert [%Track{language: "en"}] = Sidecar.scan(video)
    end

    test "returns [] when the directory does not exist", %{dir: dir} do
      File.rm_rf!(dir)
      assert Sidecar.scan(Path.join(dir, "Nonexistent.mkv")) == []
    end
  end
end
