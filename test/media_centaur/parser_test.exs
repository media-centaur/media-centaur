# POLICY: NEVER delete or remove tests from this file. Every test case represents
# a real filename pattern observed in the wild. Removing a test risks silently
# reintroducing a regression for that pattern. If a parser change causes an
# existing test to fail, fix the parser — do not delete or weaken the test.
# Tests may only be added, never removed.

defmodule MediaCentaur.ParserTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Parser

  # ─── Movies: dot-separated ────────────────────────────────────────────────

  describe "movie — dot-separated filename" do
    test "simple title + year + quality tags" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample.Movie.Two.1991.BluRay.Remux.1080p.AVC.DTS-HD.MA.5.1-HiFi.mkv"
        )

      assert result.title == "Sample Movie Two"
      assert result.year == 1991
      assert result.type == :movie
    end

    test "multi-word title with Part" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample.Movie.Two.Part.Deux.1993.BluRay.Remux.1080p.AVC.DTS-HD.MA.4.0-HiFi.mkv"
        )

      assert result.title == "Sample Movie Two Part Deux"
      assert result.year == 1993
      assert result.type == :movie
    end

    test "Slay Foe Vol. 1 — number after word is part of title not year" do
      result =
        Parser.parse("/mnt/videos/Videos/Slay.Foe.Vol.1.2003.4K.HDR.DV.2160p.BDRemux Ita Eng x265-NAHOM")

      assert result.title == "Slay Foe Vol 1"
      assert result.year == 2003
      assert result.type == :movie
    end

    test "long title with many quality tokens" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample.Movie.of.the.Distant.Field.2023.iTA-ENG.WEBDL.2160p.HDR.x265-CYBER.mkv"
        )

      assert result.title == "Sample Movie Of The Distant Field"
      assert result.year == 2023
      assert result.type == :movie
    end

    test "non-English title" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Io.Marinaio.2023.Blu-ray.2160p.UHD.HDR10.DTS.5.1.x265.iTA.ENG-Peppe.mkv"
        )

      assert result.title == "Io Marinaio"
      assert result.year == 2023
      assert result.type == :movie
    end

    test "single word title" do
      result =
        Parser.parse("/mnt/videos/Videos/Cloud.2024.1080p.WEB-DL.x264.AC3.HORiZON-ArtSubs.mkv")

      assert result.title == "Cloud"
      assert result.year == 2024
      assert result.type == :movie
    end

    test "Brightly We Stroll Onward" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Brightly.We.Stroll.Onward.2025.1080p.WEBRip.10Bit.DDP.5.1.x265-NeoNoir.mkv"
        )

      assert result.title == "Brightly We Stroll Onward"
      assert result.year == 2025
      assert result.type == :movie
    end

    test "Sample Movie One as directory name (no extension)" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Movie One.1967.Criterion.1080p.BluRay.x265.HEVC.EAC3-SARTRE"
        )

      assert result.title == "Sample Movie One"
      assert result.year == 1967
      assert result.type == :movie
    end
  end

  # ─── Movies: space-separated ──────────────────────────────────────────────

  describe "movie — space-separated filename" do
    test "title then year then quality" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Grimy Labor 1998 REMASTERED DIRTIER CUT 1080p BluRay HEVC x265 BONE.mkv"
        )

      assert result.title == "Grimy Labor"
      assert result.year == 1998
      assert result.type == :movie
    end

    test "single word title spaces" do
      result =
        Parser.parse("/mnt/videos/Videos/Little Trouble Kids.2025.1080p.WEB-DL.AAC.x264-skyflickz.mp4")

      assert result.title == "Little Trouble Kids"
      assert result.year == 2025
      assert result.type == :movie
    end

    test "Sample Movie Twelve 2 — sequel number not confused for year" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample.Movie.Twelve.2.2024.4K.HDR.DV.2160p.WEBDL Ita Eng x265-NAHOM"
        )

      assert result.title == "Sample Movie Twelve 2"
      assert result.year == 2024
      assert result.type == :movie
    end

    test "One Skirmish After Another — year at end of basename with no trailing tokens" do
      result =
        Parser.parse(
          "/home/shawn/videos/media-library/One Skirmish After Another 2025 UHD BluRay 2160p HDR10 DV HEVC TrueHD Atmos 7.1 x265-E/One Skirmish After Another 2025.mkv"
        )

      assert result.title == "One Skirmish After Another"
      assert result.year == 2025
      assert result.type == :movie
    end
  end

  # ─── Movies: year in parens or brackets ───────────────────────────────────

  describe "movie — year in parens/brackets" do
    test "year in parentheses, minimal filename" do
      result = Parser.parse("/mnt/videos/Videos/Sample Hero And Sidekick Vs Foe (2010).mkv")
      assert result.title == "Sample Hero And Sidekick Vs Foe"
      assert result.year == 2010
      assert result.type == :movie
    end

    test "year in brackets with extra quality brackets" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Movie Twelve [2022] 2160p UHD BDRip DV HDR10 x265 TrueHD Atmos 7.1 Kira [SEV].mkv"
        )

      assert result.title == "Sample Movie Twelve"
      assert result.year == 2022
      assert result.type == :movie
    end

    test "year in parens with square bracket junk after" do
      result =
        Parser.parse("/mnt/videos/Videos/Ma Vie De Petit Legume (2016) [BluRay] [720p] [YTS.AM]")

      assert result.title == "Ma Vie De Petit Legume"
      assert result.year == 2016
      assert result.type == :movie
    end

    test "Rare Exports — dash in title, year in parens, quality in parens" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Movie Three - A Winter Story (2010) (1080p BluRay x265 HEVC 10bit AAC 5.1 Finnish Tigole)"
        )

      assert result.title == "Sample Movie Three - A Winter Story"
      assert result.year == 2010
      assert result.type == :movie
    end

    test "Sample Movie Four — parens but no quality junk" do
      result = Parser.parse("/mnt/videos/Videos/Sample Movie Four (1993).mkv")
      assert result.title == "Sample Movie Four"
      assert result.year == 1993
      assert result.type == :movie
    end
  end

  # ─── Movies: directory name as source ─────────────────────────────────────

  describe "movie — directory name as source" do
    test "title then year in parens, clean directory" do
      result = Parser.parse("/mnt/videos/Videos/84 Years Later (2025)")
      assert result.title == "84 Years Later"
      assert result.year == 2025
      assert result.type == :movie
    end

    test "Sample Movie Seven — simple directory" do
      result = Parser.parse("/mnt/videos/Videos/Sample Movie Seven (2010)")
      assert result.title == "Sample Movie Seven"
      assert result.year == 2010
      assert result.type == :movie
    end

    test "Sample Movie Five" do
      result = Parser.parse("/mnt/videos/Videos/Sample Movie Five (2004)")
      assert result.title == "Sample Movie Five"
      assert result.year == 2004
      assert result.type == :movie
    end

    test "Sample Movie Six 2 — sequel number in title" do
      result = Parser.parse("/mnt/videos/Videos/Sample Movie Six 2 (2016) [YTS.AG]")
      assert result.title == "Sample Movie Six 2"
      assert result.year == 2016
      assert result.type == :movie
    end
  end

  # ─── TV: direct episode files ─────────────────────────────────────────────

  describe "tv — episode file at top level" do
    test "dot-separated SxxExx with episode title" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample.Show.Two.S02E01.Sample.Episode.Two.2160p.ATVP.WEB-DL.DD5.1.DV.HDR10+.H265-G66.mkv"
        )

      assert result.title == "Sample Show Two"
      assert result.season == 2
      assert result.episode == 1
      assert result.episode_title == "Sample Episode Two"
      assert result.type == :tv
    end

    test "dot-separated SxxExx no episode title" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample.Show.Two.S02E02.Penance.2160p.ATVP.WEB-DL.DD5.1.DV.HDR10+.H265-G66.mkv"
        )

      assert result.title == "Sample Show Two"
      assert result.season == 2
      assert result.episode == 2
      assert result.type == :tv
    end

    test "multi-episode range — take first episode" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample.Show.Two.S02E06-08.2160p.ATVP.WEB-DL.ITA-ENG.DD5.1.DV.HDR10plus.H265-G66"
        )

      assert result.title == "Sample Show Two"
      assert result.season == 2
      assert result.episode == 6
      assert result.type == :tv
    end

    test "year before SxxExx marker" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Show Fourteen.2024.S01E06.2160p.WEB.H265-SuccessfulCrab[TGx]"
        )

      assert result.title == "Sample Show Fourteen"
      assert result.year == 2024
      assert result.season == 1
      assert result.episode == 6
      assert result.type == :tv
    end

    test "all lowercase filename" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/A.Thousand.Hits.S01.2160p.WEB.H265-SuccessfulCrab [iCMAL]/A.Thousand.Hits.S01E01.2160p.WEB.H265-SuccessfulCrab/a.thousand.hits.s01e01.2160p.web.h265-successfulcrab.mkv"
        )

      assert result.title == "A Thousand Hits"
      assert result.season == 1
      assert result.episode == 1
      assert result.type == :tv
    end

    test "Sample Show Five with episode title and REPACK tag" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Show Five.S02E01.The.Pioneer.REPACK.2160p.AMZN.WEB-DL.DDP5.1.Atmos.H.265-Draken02.mkv"
        )

      assert result.title == "Sample Show Five"
      assert result.season == 2
      assert result.episode == 1
      assert result.episode_title == "The Pioneer"
      assert result.type == :tv
    end

    test "simple format no quality tags" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Show Three Season 1 Mp4 1080p/Sample Show Three S01E01.mp4"
        )

      assert result.title == "Sample Show Three"
      assert result.season == 1
      assert result.episode == 1
      assert result.type == :tv
    end

    test "URL junk prefix stripped before show name" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/www.UIndex.org    -    Sample Show Four S05E01 Keep It Plain 2160p CRAV WEB-DL DDP5 1 H 265-Kitsune"
        )

      assert result.title == "Sample Show Four"
      assert result.season == 5
      assert result.episode == 1
      assert result.episode_title == "Keep It Plain"
      assert result.type == :tv
    end

    test "Sample Show Four dot-separated no ep title" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Show Four.S05E04.Sample.Episode.How.You.Go.720p.H.264.mp4"
        )

      assert result.title == "Sample Show Four"
      assert result.season == 5
      assert result.episode == 4
      assert result.episode_title == "Sample Episode How You Go"
      assert result.type == :tv
    end
  end

  # ─── TV: episode files inside season directories ──────────────────────────

  describe "tv — episode file inside named season directory" do
    test "Sample Show One: generic SxxExx filename inside Season N directory" do
      result =
        Parser.parse("/mnt/videos/Videos/Sample Show One/Season 1/S01E01 - Sample Episode One.avi")

      assert result.title == "Sample Show One"
      assert result.season == 1
      assert result.episode == 1
      assert result.episode_title == "Sample Episode One"
      assert result.type == :tv
    end

    test "Sample Show One season 3" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Show One/Season 3/S03E05 - Sample Episode, Sample Keeper.avi"
        )

      assert result.title == "Sample Show One"
      assert result.season == 3
      assert result.episode == 5
      assert result.type == :tv
    end

    test "Sample Show One: NxNN format (7x02) inside Season directory" do
      result =
        Parser.parse(
          "/home/shawn/videos/media-library/Sample Show One/Season 7/Sample Show One 7x02 - Sample Episode Toil.avi"
        )

      assert result.title == "Sample Show One"
      assert result.season == 7
      assert result.episode == 2
      assert result.episode_title == "Sample Episode Toil"
      assert result.type == :tv
    end

    test "Sample Show One: compact 3-digit season+episode (501) inside Season directory" do
      result =
        Parser.parse(
          "/home/shawn/videos/media-library/Sample Show One/Season 5/501- Sample Intern's Eyes.avi"
        )

      assert result.title == "Sample Show One"
      assert result.season == 5
      assert result.episode == 1
      assert result.episode_title == "Sample Intern's Eyes"
      assert result.type == :tv
    end
  end

  describe "tv — episode file inside show+season directory (show name in file)" do
    test "Citadel 5 with episode title, case-insensitive e" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Citadel 5 S01-05 1080p ( 2021 Remaster ) DD51 x265/B5 S01 1080p x265/Citadel.5.S01e01.Sample.Episode.On.The.Distant.Line.1080P.DD.5.1.X256.mkv"
        )

      assert result.title == "Citadel 5"
      assert result.season == 1
      assert result.episode == 1
      assert result.episode_title == "Sample Episode On The Distant Line"
      assert result.type == :tv
    end

    test "Sample Show Eleven: show(year) - SxxExx - Episode Title format" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Show Eleven (2019) Season 4 S04 (1080p ATVP WEB-DL x265 HEVC 10bit EAC3 5.1 Silence)/Sample Show Eleven (2019) - S04E01 - Openness (1080p ATVP WEB-DL x265 Silence).mkv"
        )

      assert result.title == "Sample Show Eleven"
      assert result.year == 2019
      assert result.season == 4
      assert result.episode == 1
      assert result.episode_title == "Openness"
      assert result.type == :tv
    end

    test "Sample Show Six: show(year) - SxxExx - Episode Title" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Show Six (2020) Season 1 S01 (1080p ATVP WEB-DL x265 HEVC 10bit EAC3 Atmos 5.1 t3nzin)/Sample Show Six (2020) - S01E01 - Pilot (1080p ATVP WEB-DL x265 t3nzin).mkv"
        )

      assert result.title == "Sample Show Six"
      assert result.year == 2020
      assert result.season == 1
      assert result.episode == 1
      assert result.episode_title == "Pilot"
      assert result.type == :tv
    end

    test "Sample Show Seven: dot-separated with episode title" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Show Seven (2019) Season 2 S02 (2160p ATVP WEB-DL x265 HEVC 10bit DDP 5.1 Vyndros)/Sample.Show.Seven.S02E01.Sample.Least.Favorite.Year.2160p.10bit.ATVP.WEB-DL.DDP5.1.HEVC-Vyndros.mkv"
        )

      assert result.title == "Sample Show Seven"
      assert result.year == 2019
      assert result.season == 2
      assert result.episode == 1
      assert result.episode_title == "Sample Least Favorite Year"
      assert result.type == :tv
    end

    test "Citadel 5: remaster year in grandparent directory is not the premiere year" do
      result =
        Parser.parse(
          "/home/shawn/videos/media-library/Citadel 5 S01-05 1080p ( 2021 Remaster ) DD51 x265/B5 S01 1080p x265/Citadel.5.S01e01.Sample.Episode.On.The.Distant.Line.1080P.DD.5.1.X256.mkv"
        )

      assert result.title == "Citadel 5"
      assert result.year == nil
      assert result.season == 1
      assert result.episode == 1
      assert result.episode_title == "Sample Episode On The Distant Line"
      assert result.type == :tv
    end

    test "Nettare della Notte: non-English title" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Nettare.della.Notte.S02E01.Il.regalo.ITA.FRE.1080p.ATVP.WEB-DL.DUAL.DDP5.1.H.264-MeM.GP.mkv"
        )

      assert result.title == "Nettare Della Notte"
      assert result.season == 2
      assert result.episode == 1
      assert result.type == :tv
    end

    test "Sample Show Pack: multi-season pack folder + Season N subdir does not leak pack descriptor into title" do
      result =
        Parser.parse(
          "/home/shawn/videos/media-library/Sample Show Pack (2006) Season 1-7 S01-S07 (1080p AMZN WEBRip x265 HEVC 10bit AAC 5.1 Group)/Season 1/Sample Show Pack (2006) - S01E13 - Sample Episode (1080p AMZN WEBRip x265 Group).mkv"
        )

      assert result.title == "Sample Show Pack"
      assert result.year == 2006
      assert result.season == 1
      assert result.episode == 13
      assert result.episode_title == "Sample Episode"
      assert result.type == :tv
    end

    test "Sample Show Four: spelled-out Season N Episode N with year and episode title" do
      result =
        Parser.parse(
          "/home/shawn/videos/media-library/Sample Show Four S05E01-02 - Primewire/Sample Show Four (2022) Season 5 Episode 1- Keep It Plain - PrimeWire.mp4"
        )

      assert result.title == "Sample Show Four"
      assert result.year == 2022
      assert result.season == 5
      assert result.episode == 1
      assert result.episode_title == "Keep It Plain"
      assert result.type == :tv
    end
  end

  # ─── TV: bare episode file with show name in ancestor directory ───────

  describe "tv — bare episode file with show name in ancestor directory" do
    test "S01E03 inside S01 dir with show name and year in grandparent pack directory" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Show Fifteen.2025.S01.Hybrid.MULTI.2160p.WEB-DL.DV.HDR.H265-AOC/S01/S01E03.mkv"
        )

      assert result.title == "Sample Show Fifteen"
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
          "/mnt/videos/Videos/Sample Show Four.S01.COMPLETE.720p.HULU.WEBRip.x264-GalaxyTV[TGx]"
        )

      assert result.title == "Sample Show Four"
      assert result.season == 1
      assert result.episode == nil
      assert result.type == :tv
    end

    test "Sample Show Ten season pack" do
      result =
        Parser.parse("/mnt/videos/Videos/Sample.Show.Ten.S01.COMPLETE.720p.BluRay.x264-GalaxyTV[TGx]")

      assert result.title == "Sample Show Ten"
      assert result.season == 1
      assert result.type == :tv
    end
  end

  # ─── Extra: file inside extras directory ──────────────────────────────────

  describe "extra — file inside extras directory" do
    test "Criterion release Extras/ subdirectory" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Movie One.1967.Criterion.1080p.BluRay.x265.HEVC.EAC3-SARTRE/Extras/Like Home.mkv"
        )

      assert result.title == "Like Home"
      assert result.type == :extra
      assert result.parent_title == "Sample Movie One"
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
          "/mnt/videos/Videos/Alien.1979.Directors.Cut.1080p.BluRay-FGT/Behind The Scenes/Production Gallery.mkv"
        )

      assert result.title == "Production Gallery"
      assert result.type == :extra
      assert result.parent_title == "Alien"
      assert result.parent_year == 1979
    end

    test "case-insensitive extras directory matching" do
      result =
        Parser.parse("/mnt/videos/Videos/Alien.1979.UHD.BluRay/extras/Final Cut.mkv")

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

    test "nested subdirectory under Featurettes — subdirectory name prepended to title" do
      result =
        Parser.parse(
          "/home/shawn/videos/media-library/The Far Far Off (2013) (1080p BluRay x265 HEVC 10bit AAC 5.1 Silence)/Featurettes/Sample Featurette Subdir/Sample Clip.mkv"
        )

      assert result.type == :extra

      assert result.title ==
               "Sample Featurette Subdir - Sample Clip"

      assert result.parent_title == "The Far Far Off"
      assert result.parent_year == 2013
    end

    test "extras parent title preserves hyphenated suffix (Project B-ko)" do
      result =
        Parser.parse(
          "/home/shawn/videos/media-library/Project B-ko/Featurettes/The Found CD-ROM Video Disc.mkv"
        )

      assert result.type == :extra
      assert result.parent_title == "Project B-ko"
      assert result.parent_year == nil
      assert result.title == "The Found CD-ROM Video Disc"
    end

    test "extras title preserves hyphenated suffix in filename (Music of Project B-ko)" do
      result =
        Parser.parse(
          "/home/shawn/videos/media-library/Project B-ko/Featurettes/Music of Project B-ko.mkv"
        )

      assert result.type == :extra
      assert result.title == "Music Of Project B-ko"
      assert result.parent_title == "Project B-ko"
    end

    test "non-extras directory is not detected as extra" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Movie One.1967.Criterion.1080p.BluRay.x265.HEVC.EAC3-SARTRE/Sample Movie One.1967.Criterion.1080p.BluRay.x265.HEVC.EAC3-SARTRE.mkv"
        )

      assert result.type == :movie
      refute result.type == :extra
    end
  end

  # ─── Extra: TV season extras ─────────────────────────────────────────────

  describe "extra — TV season extras" do
    test "Featurettes dir with season marker in release-style grandparent (Layout B)" do
      result =
        Parser.parse(
          "/home/shawn/videos/media-library/Sample Saga of Creatures (2023) Season 1 S01 REPACK (1080p ATVP WEB-DL x265 HEVC 10bit EAC3 Atmos 5.1 Ghost)/Featurettes/Season 1 - Sample Interview with Cast - Sample Talk Show.mkv"
        )

      assert result.type == :extra
      assert result.season == 1
      assert result.parent_title == "Sample Saga Of Creatures"
      assert result.parent_year == 2023
    end

    test "Layout A: Show/Season 3/Extras/file.mkv — grandparent is pure season dir" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Show Eight/Season 3/Extras/Deleted Scene - Sample Person at the Place.mkv"
        )

      assert result.type == :extra
      assert result.season == 3
      assert result.parent_title == "Sample Show Eight"
      assert result.parent_year == nil
    end

    test "Layout A with S-prefix: Show (2022)/S02/Extras/file.mkv" do
      result =
        Parser.parse("/mnt/videos/Videos/Sample Show Nine (2022)/S02/Extras/Inside the Segment.mkv")

      assert result.type == :extra
      assert result.season == 2
      assert result.parent_title == "Sample Show Nine"
      assert result.parent_year == 2022
    end

    test "regression: movie extra remains season nil" do
      result =
        Parser.parse(
          "/mnt/videos/Videos/Sample Movie One.1967.Criterion.1080p.BluRay.x265.HEVC.EAC3-SARTRE/Extras/Like Home.mkv"
        )

      assert result.type == :extra
      assert result.season == nil
      assert result.parent_title == "Sample Movie One"
      assert result.parent_year == 1967
    end
  end

  # ─── Extra: sample files ────────────────────────────────────────────────

  describe "extra — sample files" do
    test "file in Sample/ subdirectory of movie release directory" do
      result =
        Parser.parse(
          "/mnt/videos/Sample.Mascot.Cosmos.2024.1080p.BluRay/Sample/super.mario.galaxy.2024-sample.mkv"
        )

      assert result.type == :extra
      assert result.parent_title == "Sample Mascot Cosmos"
      assert result.parent_year == 2024
    end

    test "file with -SAMPLE suffix alongside movie in release directory" do
      result =
        Parser.parse(
          "/mnt/videos/Sample Mascot Cosmos (2024)/Sample.Mascot.Cosmos.2024.1080p.BluRay-SAMPLE.mkv"
        )

      assert result.type == :extra
      assert result.parent_title == "Sample Mascot Cosmos"
      assert result.parent_year == 2024
    end

    test "Samples/ directory variant" do
      result =
        Parser.parse("/mnt/videos/Alien.1979.UHD.BluRay/Samples/Alien.1979-sample.mkv")

      assert result.type == :extra
      assert result.parent_title == "Alien"
      assert result.parent_year == 1979
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
