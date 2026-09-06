defmodule MediaCentaur.Search.ReleasePreferenceTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Search.{Quality, ReleasePreference, SearchResult}

  defp result(title, attrs \\ []) do
    %SearchResult{
      title: title,
      guid: Keyword.get(attrs, :guid, title),
      indexer_id: 1,
      quality: Quality.parse(title),
      seeders: Keyword.get(attrs, :seeders),
      grabs: Keyword.get(attrs, :grabs),
      size_bytes: Keyword.get(attrs, :size_bytes, 8_000_000_000)
    }
  end

  describe "key/2 ordering" do
    test "resolution outranks source fidelity" do
      uhd_webrip = result("Sample.Movie.2005.2160p.WEBRip.x264")
      hd_remux = result("Sample.Movie.2005.1080p.BluRay.REMUX.AVC")

      assert ReleasePreference.key(uhd_webrip, "fidelity") >
               ReleasePreference.key(hd_remux, "fidelity")
    end

    test "the source ladder breaks a resolution tie" do
      remux = result("Sample.Movie.2005.1080p.BluRay.REMUX.AVC")
      webrip = result("Sample.Movie.2005.1080p.WEBRip.x264")

      assert ReleasePreference.key(remux, "fidelity") > ReleasePreference.key(webrip, "fidelity")
    end

    test "the save-space preference inverts the source ladder" do
      remux = result("Sample.Movie.2005.1080p.BluRay.REMUX.AVC")
      encode = result("Sample.Movie.2005.1080p.BluRay.x264")

      assert ReleasePreference.key(encode, "space") > ReleasePreference.key(remux, "space")
    end

    test "popularity breaks a tie once resolution and source are equal" do
      popular = result("Sample.Movie.2005.1080p.WEB-DL.H.264-A", seeders: 90)
      lonely = result("Sample.Movie.2005.1080p.WEB-DL.H.264-B", seeders: 2)

      assert ReleasePreference.key(popular, "fidelity") >
               ReleasePreference.key(lonely, "fidelity")
    end
  end

  describe "popularity falls back to grabs" do
    # A usenet result carries no swarm, so `seeders` is always nil and a
    # seeders-only tiebreak leaves every same-tier release equal.

    test "grabs rank a usenet release when seeders are absent" do
      many = result("Sample.Movie.2005.1080p.WEB-DL.H.264-A", grabs: 322)
      few = result("Sample.Movie.2005.1080p.WEB-DL.H.264-B", grabs: 96)

      assert ReleasePreference.key(many, "fidelity") > ReleasePreference.key(few, "fidelity")
    end

    test "a release with neither signal ranks lowest of the tier" do
      silent = result("Sample.Movie.2005.1080p.WEB-DL.H.264-A")
      grabbed = result("Sample.Movie.2005.1080p.WEB-DL.H.264-B", grabs: 1)

      assert ReleasePreference.key(grabbed, "fidelity") > ReleasePreference.key(silent, "fidelity")
    end

    test "seeders win over grabs when the indexer reports both" do
      seeded = result("Sample.Movie.2005.1080p.WEB-DL.H.264-A", seeders: 5, grabs: 0)
      grabbed = result("Sample.Movie.2005.1080p.WEB-DL.H.264-B", seeders: 1, grabs: 999)

      assert ReleasePreference.key(seeded, "fidelity") > ReleasePreference.key(grabbed, "fidelity")
    end
  end

  describe "best/2" do
    test "returns nil for an empty list" do
      assert ReleasePreference.best([], "fidelity") == nil
    end

    test "picks the highest-ranked release" do
      best =
        ReleasePreference.best(
          [
            result("Sample.Movie.2005.1080p.WEBRip.x264", guid: "webrip"),
            result("Sample.Movie.2005.2160p.BluRay.REMUX.HEVC", guid: "uhd-remux"),
            result("Sample.Movie.2005.1080p.BluRay.REMUX.AVC", guid: "hd-remux")
          ],
          "fidelity"
        )

      assert best.guid == "uhd-remux"
    end

    test "keeps the earliest candidate on an exact tie" do
      # This is what carries the movie ladder's precise-before-broad term
      # order into the pick: an equal candidate found under `Title year`
      # beats one found under the bare `Title`.
      best =
        ReleasePreference.best(
          [
            result("Sample.Movie.2005.1080p.WEB-DL.H.264-A", guid: "from-year-term"),
            result("Sample.Movie.2005.1080p.WEB-DL.H.264-B", guid: "from-broad-term")
          ],
          "fidelity"
        )

      assert best.guid == "from-year-term"
    end
  end

  describe "better_of/3" do
    test "nil stands for nothing yet, in either position" do
      candidate = result("Sample.Movie.2005.1080p.WEB-DL.H.264")

      assert ReleasePreference.better_of(nil, candidate, "fidelity") == candidate
      assert ReleasePreference.better_of(candidate, nil, "fidelity") == candidate
      assert ReleasePreference.better_of(nil, nil, "fidelity") == nil
    end

    test "the incumbent survives an exact tie" do
      incumbent = result("Sample.Movie.2005.1080p.WEB-DL.H.264-A", guid: "incumbent")
      challenger = result("Sample.Movie.2005.1080p.WEB-DL.H.264-B", guid: "challenger")

      assert ReleasePreference.better_of(incumbent, challenger, "fidelity").guid == "incumbent"
    end

    test "a strictly better challenger takes over" do
      incumbent = result("Sample.Movie.2005.1080p.WEB-DL.H.264", guid: "incumbent")
      challenger = result("Sample.Movie.2005.2160p.BluRay.REMUX.HEVC", guid: "challenger")

      assert ReleasePreference.better_of(incumbent, challenger, "fidelity").guid == "challenger"
    end
  end
end
