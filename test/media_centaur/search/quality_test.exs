defmodule MediaCentaur.Search.QualityTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Search.Quality

  describe "parse/1" do
    test "detects 2160p marker" do
      title = "Sample.Movie.2023.2160p.UHD.BluRay.REMUX.HDR10.HEVC.TrueHD.7.1.Atmos-FGT"
      assert Quality.parse(title) == :uhd_4k
    end

    test "detects 4K marker" do
      title = "Sample.Movie.2024.4K.BluRay.REMUX.HDR10.HEVC.TrueHD"
      assert Quality.parse(title) == :uhd_4k
    end

    test "detects UHD marker without resolution number" do
      title = "Other.Sample.Movie.2022.UHD.BluRay.TrueHD.Atmos.7.1-FGT"
      assert Quality.parse(title) == :uhd_4k
    end

    test "detects 2160p case-insensitively" do
      title = "Some.Movie.2023.2160P.WEB-DL"
      assert Quality.parse(title) == :uhd_4k
    end

    test "detects 1080p marker" do
      title = "Sample.Movie.2023.1080p.BluRay.x264-SPARKS"
      assert Quality.parse(title) == :hd_1080p
    end

    test "detects 1080p WEB-DL release" do
      title = "Sample.Movie.2024.1080p.WEB-DL.DDP5.1.H264-NTG"
      assert Quality.parse(title) == :hd_1080p
    end

    test "detects 1080p case-insensitively" do
      title = "Some.Show.S01E01.1080P.HDTV"
      assert Quality.parse(title) == :hd_1080p
    end

    test "returns nil for 720p" do
      title = "Sample.Movie.2023.720p.BluRay.x264-GROUP"
      assert Quality.parse(title) == nil
    end

    test "returns nil for 480p SD release" do
      title = "Some.Old.Movie.1999.480p.DVDRip.XviD"
      assert Quality.parse(title) == nil
    end

    test "returns nil when no resolution marker present" do
      title = "Some.Movie.BluRay.x264-GROUP"
      assert Quality.parse(title) == nil
    end
  end

  describe "rank/1" do
    test "4K ranks higher than 1080p" do
      assert Quality.rank(:uhd_4k) > Quality.rank(:hd_1080p)
    end

    test "nil (unknown) has lowest rank" do
      assert Quality.rank(nil) == 0
    end

    test "1080p has positive rank" do
      assert Quality.rank(:hd_1080p) > 0
    end

    test "4K has highest rank" do
      assert Quality.rank(:uhd_4k) > Quality.rank(:hd_1080p)
    end
  end

  describe "acceptable?/1" do
    test "4K is acceptable" do
      assert Quality.acceptable?(:uhd_4k)
    end

    test "1080p is acceptable" do
      assert Quality.acceptable?(:hd_1080p)
    end

    test "nil (unknown/lower quality) is not acceptable" do
      refute Quality.acceptable?(nil)
    end
  end

  describe "acceptable?/3 — bounded" do
    test "1080p is acceptable when bounds are 1080p..4K" do
      assert Quality.acceptable?(:hd_1080p, "hd_1080p", "uhd_4k")
    end

    test "4K is acceptable when bounds are 1080p..4K" do
      assert Quality.acceptable?(:uhd_4k, "hd_1080p", "uhd_4k")
    end

    test "1080p is NOT acceptable when min is 4K (4K-only)" do
      refute Quality.acceptable?(:hd_1080p, "uhd_4k", "uhd_4k")
    end

    test "4K is NOT acceptable when max is 1080p (1080p-only)" do
      refute Quality.acceptable?(:uhd_4k, "hd_1080p", "hd_1080p")
    end

    test "nil quality is never acceptable (unknown tier)" do
      refute Quality.acceptable?(nil, "hd_1080p", "uhd_4k")
    end
  end

  describe "display_label/1 — presentation-only parse from the release title" do
    test "labels the ranked tiers like label/1" do
      assert Quality.display_label("Sample.Movie.2023.2160p.UHD.BluRay.REMUX") == "4K"
      assert Quality.display_label("Sample.Movie.2023.1080p.BluRay.x264-GROUP") == "1080p"
    end

    test "labels lower resolutions the ladder does not rank" do
      assert Quality.display_label("Sample.Movie.2005.720p.WEBRip.x264") == "720p"
      assert Quality.display_label("Sample.Show.S01E01.576p.DVDRip") == "576p"
      assert Quality.display_label("Some.Old.Movie.1999.480p.DVDRip.XviD") == "480p"
    end

    test "labels a DVD rip with no resolution token as DVD" do
      assert Quality.display_label("Sample.Movie.2005.DVDRip.x264-GROUP") == "DVD"
    end

    test "a resolution token wins over the DVD source token" do
      assert Quality.display_label("Some.Old.Movie.1999.480p.DVDRip.XviD") == "480p"
    end

    test "returns nil when the title carries no quality signal" do
      assert Quality.display_label("Sample.Movie.2005.AMZN.WEB-DL.DDP2.0.H.264") == nil
    end
  end

  describe "label/1" do
    test "returns human-readable label for 4K" do
      assert Quality.label(:uhd_4k) == "4K"
    end

    test "returns human-readable label for 1080p" do
      assert Quality.label(:hd_1080p) == "1080p"
    end

    test "returns unknown for nil" do
      assert Quality.label(nil) == "Unknown"
    end
  end
end
