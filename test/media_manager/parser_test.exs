# POLICY: NEVER delete or remove tests from this file. Every test case represents
# a real filename pattern observed in the wild. Removing a test risks silently
# reintroducing a regression for that pattern. If a parser change causes an
# existing test to fail, fix the parser — do not delete or weaken the test.
# Tests may only be added, never removed.

defmodule MediaManager.ParserTest do
  use ExUnit.Case, async: true

  alias MediaManager.Parser

  # ─── Movies: dot-separated ────────────────────────────────────────────────

  describe "movie — dot-separated filename" do
    test "simple title + year + quality tags" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample.Title.Fy.1991.BluRay.Remux.1080p.AVC.DTS-HD.MA.5.1-HiFi.mkv"
        )

      assert result.title == "Sample Title Fy"
      assert result.year == 1991
      assert result.type == :movie
    end

    test "multi-word title with Part" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample.Title.Bp.1993.BluRay.Remux.1080p.AVC.DTS-HD.MA.4.0-HiFi.mkv"
        )

      assert result.title == "Sample Title Bp"
      assert result.year == 1993
      assert result.type == :movie
    end

    test "Sample Title Fv Vol. 1 — number after word is part of title not year" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample.Title.Ct.1.2003.4K.HDR.DV.2160p.BDRemux Ita Eng x265-NAHOM"
        )

      assert result.title == "Sample Title Ct 1"
      assert result.year == 2003
      assert result.type == :movie
    end

    test "long title with many quality tokens" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample.Title.Aq.2023.iTA-ENG.WEBDL.2160p.HDR.x265-CYBER.mkv"
        )

      assert result.title == "Killers Of The Flower Moon"
      assert result.year == 2023
      assert result.type == :movie
    end

    test "non-English title" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample.Title.Ev.2023.Blu-ray.2160p.UHD.HDR10.DTS.5.1.x265.iTA.ENG-Peppe.mkv"
        )

      assert result.title == "Sample Title Ev"
      assert result.year == 2023
      assert result.type == :movie
    end

    test "single word title" do
      result =
        Parser.parse("/mnt/videos/Videos/Sample Title G3.2024.1080p.WEB-DL.x264.AC3.HORiZON-ArtSubs.mkv")

      assert result.title == "Cloud"
      assert result.year == 2024
      assert result.type == :movie
    end

    test "Merrily We Roll Along" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Merrily.We.Roll.Along.2025.1080p.WEBRip.10Bit.DDP.5.1.x265-NeoNoir.mkv"
        )

      assert result.title == "Merrily We Roll Along"
      assert result.year == 2025
      assert result.type == :movie
    end

    test "Sample Title Gk as directory name (no extension)" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Title Gk.1967.Criterion.1080p.BluRay.x265.HEVC.EAC3-SARTRE"
        )

      assert result.title == "Sample Title Gk"
      assert result.year == 1967
      assert result.type == :movie
    end
  end

  # ─── Movies: space-separated ──────────────────────────────────────────────

  describe "movie — space-separated filename" do
    test "title then year then quality" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Dirty Work 1998 REMASTERED DIRTIER CUT 1080p BluRay HEVC x265 BONE.mkv"
        )

      assert result.title == "Dirty Work"
      assert result.year == 1998
      assert result.type == :movie
    end

    test "single word title spaces" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Little Trouble Sample Title G5.2025.1080p.WEB-DL.AAC.x264-skyflickz.mp4"
        )

      assert result.title == "Little Trouble Girls"
      assert result.year == 2025
      assert result.type == :movie
    end

    test "Sample Title Gw 2 — sequel number not confused for year" do
      result =
        Parser.parse("/mnt/videos/Videos/Sample.Title.Gw.2.2024.4K.HDR.DV.2160p.WEBDL Ita Eng x265-NAHOM")

      assert result.title == "Sample Title Gw 2"
      assert result.year == 2024
      assert result.type == :movie
    end
  end

  # ─── Movies: year in parens or brackets ───────────────────────────────────

  describe "movie — year in parens/brackets" do
    test "year in parentheses, minimal filename" do
      result = Parser.parse("/mnt/videos/Videos/Sample Title Ba (2010).mkv")
      assert result.title == "Sample Title Ba"
      assert result.year == 2010
      assert result.type == :movie
    end

    test "year in brackets with extra quality brackets" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Smile [2022] 2160p UHD BDRip DV HDR10 x265 TrueHD Atmos 7.1 Kira [SEV].mkv"
        )

      assert result.title == "Smile"
      assert result.year == 2022
      assert result.type == :movie
    end

    test "year in parens with square bracket junk after" do
      result =
        Parser.parse("/mnt/videos/Videos/My Life As A Zucchini (2016) [BluRay] [720p] [YTS.AM]")

      assert result.title == "My Life As A Zucchini"
      assert result.year == 2016
      assert result.type == :movie
    end

    test "Sample Title Ej — dash in title, year in parens, quality in parens" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Title Af (2010) (1080p BluRay x265 HEVC 10bit AAC 5.1 Finnish Tigole)"
        )

      assert result.title == "Sample Title Af"
      assert result.year == 2010
      assert result.type == :movie
    end

    test "Sample Title Ei — parens but no quality junk" do
      result = Parser.parse("/mnt/videos/Videos/Sample Title Ei (1993).mkv")
      assert result.title == "Sample Title Ei"
      assert result.year == 1993
      assert result.type == :movie
    end
  end

  # ─── Movies: directory name as source ─────────────────────────────────────

  describe "movie — directory name as source" do
    test "title then year in parens, clean directory" do
      result = Parser.parse("/mnt/videos/Videos/Sample Title Dl 28 (2025)")
      assert result.title == "Sample Title Dl 28"
      assert result.year == 2025
      assert result.type == :movie
    end

    test "Sample Title Fu — simple directory" do
      result = Parser.parse("/mnt/videos/Videos/Sample Title Fu (2010)")
      assert result.title == "Sample Title Fu"
      assert result.year == 2010
      assert result.type == :movie
    end

    test "Sample Title Cf" do
      result = Parser.parse("/mnt/videos/Videos/Sample Title Cf (2004)")
      assert result.title == "Sample Title Cf"
      assert result.year == 2004
      assert result.type == :movie
    end

    test "Sample Title Cs 2 — sequel number in title" do
      result = Parser.parse("/mnt/videos/Videos/Sample Title Cs 2 (2016) [YTS.AG]")
      assert result.title == "Sample Title Cs 2"
      assert result.year == 2016
      assert result.type == :movie
    end
  end

  # ─── TV: direct episode files ─────────────────────────────────────────────

  describe "tv — episode file at top level" do
    test "dot-separated SxxExx with episode title" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample.Title.Eu.S02E01.Good.Sisters.2160p.ATVP.WEB-DL.DD5.1.DV.HDR10+.H265-G66.mkv"
        )

      assert result.title == "Sample Title Eu"
      assert result.season == 2
      assert result.episode == 1
      assert result.episode_title == "Good Sisters"
      assert result.type == :tv
    end

    test "dot-separated SxxExx no episode title" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample.Title.Eu.S02E02.Penance.2160p.ATVP.WEB-DL.DD5.1.DV.HDR10+.H265-G66.mkv"
        )

      assert result.title == "Sample Title Eu"
      assert result.season == 2
      assert result.episode == 2
      assert result.type == :tv
    end

    test "multi-episode range — take first episode" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample.Title.Eu.S02E06-08.2160p.ATVP.WEB-DL.ITA-ENG.DD5.1.DV.HDR10plus.H265-G66"
        )

      assert result.title == "Sample Title Eu"
      assert result.season == 2
      assert result.episode == 6
      assert result.type == :tv
    end

    test "year before SxxExx marker" do
      result =
        Parser.parse("/mnt/videos/Videos/Sample Title Gv.2024.S01E06.2160p.WEB.H265-SuccessfulCrab[TGx]")

      assert result.title == "Sample Title Gv"
      assert result.year == 2024
      assert result.season == 1
      assert result.episode == 6
      assert result.type == :tv
    end

    test "all lowercase filename" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample.Title.Co.S01.2160p.WEB.H265-SuccessfulCrab [iCMAL]/Sample.Title.Co.S01E01.2160p.WEB.H265-SuccessfulCrab/a.thousand.blows.s01e01.2160p.web.h265-successfulcrab.mkv"
        )

      assert result.title == "Sample Title Co"
      assert result.season == 1
      assert result.episode == 1
      assert result.type == :tv
    end

    test "Sample Title Gq with episode title and REPACK tag" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Title Gq.S02E01.The.Innovator.REPACK.2160p.AMZN.WEB-DL.DDP5.1.Atmos.H.265-Draken02.mkv"
        )

      assert result.title == "Sample Title Gq"
      assert result.season == 2
      assert result.episode == 1
      assert result.episode_title == "The Innovator"
      assert result.type == :tv
    end

    test "simple format no quality tags" do
      result =
        Parser.parse("/mnt/videos/Videos/Sample Title Et Season 1 Mp4 1080p/Sample Title Et S01E01.mp4")

      assert result.title == "Sample Title Et"
      assert result.season == 1
      assert result.episode == 1
      assert result.type == :tv
    end

    test "URL junk prefix stripped before show name" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/www.UIndex.org    -    Sample Title Gt S05E01 Keep It Simple 2160p CRAV WEB-DL DDP5 1 H 265-Kitsune"
        )

      assert result.title == "Sample Title Gt"
      assert result.season == 5
      assert result.episode == 1
      assert result.episode_title == "Keep It Simple"
      assert result.type == :tv
    end

    test "Sample Title Gt dot-separated no ep title" do
      result =
        Parser.parse("/mnt/videos/Videos/Sample Title Gt.S05E04.Practice.How.You.Play.720p.H.264.mp4")

      assert result.title == "Sample Title Gt"
      assert result.season == 5
      assert result.episode == 4
      assert result.episode_title == "Practice How You Play"
      assert result.type == :tv
    end
  end

  # ─── TV: episode files inside season directories ──────────────────────────

  describe "tv — episode file inside named season directory" do
    test "Sample Title Ha: generic SxxExx filename inside Season N directory" do
      result = Parser.parse("/mnt/videos/Videos/Sample Title Ha/Season 1/S01E01 - My First Day.avi")
      assert result.title == "Sample Title Ha"
      assert result.season == 1
      assert result.episode == 1
      assert result.episode_title == "My First Day"
      assert result.type == :tv
    end

    test "Sample Title Ha season 3" do
      result =
        Parser.parse("/mnt/videos/Videos/Sample Title Ha/Season 3/S03E05 - My Brother, My Keeper.avi")

      assert result.title == "Sample Title Ha"
      assert result.season == 3
      assert result.episode == 5
      assert result.type == :tv
    end
  end

  describe "tv — episode file inside show+season directory (show name in file)" do
    test "Sample Title Ft 5 with episode title, case-insensitive e" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Title Ft 5 S01-05 1080p ( 2021 Remaster ) DD51 x265/B5 S01 1080p x265/Sample.Title.Ft.5.S01e01.Midnight.On.The.Firing.Line.1080P.DD.5.1.X256.mkv"
        )

      assert result.title == "Sample Title Ft 5"
      assert result.season == 1
      assert result.episode == 1
      assert result.episode_title == "Midnight On The Firing Line"
      assert result.type == :tv
    end

    test "Sample Title Cz: show(year) - SxxExx - Episode Title format" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Title Cz (2019) Season 4 S04 (1080p ATVP WEB-DL x265 HEVC 10bit EAC3 5.1 Silence)/Sample Title Cz (2019) - S04E01 - Glasnost (1080p ATVP WEB-DL x265 Silence).mkv"
        )

      assert result.title == "Sample Title Cz"
      assert result.year == 2019
      assert result.season == 4
      assert result.episode == 1
      assert result.episode_title == "Glasnost"
      assert result.type == :tv
    end

    test "Sample Title Cy: show(year) - SxxExx - Episode Title" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Title Cy (2020) Season 1 S01 (1080p ATVP WEB-DL x265 HEVC 10bit EAC3 Atmos 5.1 t3nzin)/Sample Title Cy (2020) - S01E01 - Pilot (1080p ATVP WEB-DL x265 t3nzin).mkv"
        )

      assert result.title == "Sample Title Cy"
      assert result.year == 2020
      assert result.season == 1
      assert result.episode == 1
      assert result.episode_title == "Pilot"
      assert result.type == :tv
    end

    test "Sample Title Cp: dot-separated with episode title" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Title Cp (2019) Season 2 S02 (2160p ATVP WEB-DL x265 HEVC 10bit DDP 5.1 Vyndros)/Sample.Title.Cp.S02E01.My.Least.Favorite.Year.2160p.10bit.ATVP.WEB-DL.DDP5.1.HEVC-Vyndros.mkv"
        )

      assert result.title == "Sample Title Cp"
      assert result.season == 2
      assert result.episode == 1
      assert result.episode_title == "My Least Favorite Year"
      assert result.type == :tv
    end

    test "Nettare degli Dei: non-English title" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Nettare.degli.Dei.S02E01.Il.regalo.ITA.FRE.1080p.ATVP.WEB-DL.DUAL.DDP5.1.H.264-MeM.GP.mkv"
        )

      assert result.title == "Nettare Degli Dei"
      assert result.season == 2
      assert result.episode == 1
      assert result.type == :tv
    end
  end

  # ─── TV: bare episode file with show name in ancestor directory ───────

  describe "tv — bare episode file with show name in ancestor directory" do
    test "S01E03 inside S01 dir with show name and year in grandparent pack directory" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Title G7.2025.S01.Hybrid.MULTI.2160p.WEB-DL.DV.HDR.H265-AOC/S01/S01E03.mkv"
        )

      assert result.title == "Paradise"
      assert result.year == 2025
      assert result.season == 1
      assert result.episode == 3
      assert result.type == :tv
    end
  end

  # ─── TV: season pack directory names ──────────────────────────────────────

  describe "tv — season pack directory (no episode)" do
    test "dot-separated season pack" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Title Gt.S01.COMPLETE.720p.HULU.WEBRip.x264-GalaxyTV[TGx]"
        )

      assert result.title == "Sample Title Gt"
      assert result.season == 1
      assert result.episode == nil
      assert result.type == :tv
    end

    test "Young Sheldon season pack" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Young.Sheldon.S01.COMPLETE.720p.BluRay.x264-GalaxyTV[TGx]"
        )

      assert result.title == "Young Sheldon"
      assert result.season == 1
      assert result.type == :tv
    end
  end

  # ─── Extra: file inside extras directory ──────────────────────────────────

  describe "extra — file inside extras directory" do
    test "Criterion release Extras/ subdirectory" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Title Gk.1967.Criterion.1080p.BluRay.x265.HEVC.EAC3-SARTRE/Extras/Like Home.mkv"
        )

      assert result.title == "Like Home"
      assert result.type == :extra
      assert result.parent_title == "Sample Title Gk"
      assert result.parent_year == 1967
    end

    test "Special Features directory with no year in parent" do
      result =
        Parser.parse("/mnt/videos/Videos/Some Movie Collection/Special Features/Making Of.mkv")

      assert result.title == "Making Of"
      assert result.type == :extra
      assert result.parent_title == "Some Movie Collection"
      assert result.parent_year == nil
    end

    test "Behind The Scenes directory" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Title G6.1979.Directors.Cut.1080p.BluRay-FGT/Behind The Scenes/Production Gallery.mkv"
        )

      assert result.title == "Production Gallery"
      assert result.type == :extra
      assert result.parent_title == "Alien"
      assert result.parent_year == 1979
    end

    test "case-insensitive extras directory matching" do
      result =
        Parser.parse("/mnt/videos/Videos/Sample Title G6.1979.UHD.BluRay/extras/Final Cut.mkv")

      assert result.title == "Final Cut"
      assert result.type == :extra
      assert result.parent_title == "Alien"
      assert result.parent_year == 1979
    end

    test "custom extras_dirs option" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Some.Movie.2020.BluRay/supplements/Interview.mkv",
          extras_dirs: ["supplements"]
        )

      assert result.title == "Interview"
      assert result.type == :extra
      assert result.parent_title == "Some Movie"
      assert result.parent_year == 2020
    end

    test "non-extras directory is not detected as extra" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Title Gk.1967.Criterion.1080p.BluRay.x265.HEVC.EAC3-SARTRE/Sample Title Gk.1967.Criterion.1080p.BluRay.x265.HEVC.EAC3-SARTRE.mkv"
        )

      assert result.type == :movie
      refute result.type == :extra
    end
  end

  # ─── Unknown fallback ─────────────────────────────────────────────────────

  describe "unknown fallback" do
    test "completely unrecognised filename" do
      result = Parser.parse("/mnt/videos/Videos/logitech-support-video-312.mp4")
      assert result.type == :unknown
    end

    test "desktop.ini and other junk files" do
      result = Parser.parse("/mnt/videos/Videos/desktop.ini")
      assert result.type == :unknown
    end
  end
end
