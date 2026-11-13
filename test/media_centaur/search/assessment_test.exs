defmodule MediaCentaur.Search.AssessmentTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Search.{Assessment, Criteria, SearchResult}

  @gigabyte 1024 * 1024 * 1024

  defp result(title, attrs \\ %{}) do
    struct(
      %SearchResult{
        title: title,
        guid: "guid-1",
        indexer_id: 1,
        quality: :hd_1080p,
        size_bytes: @gigabyte
      },
      attrs
    )
  end

  defp movie, do: %Criteria{type: :tmdb, tmdb_type: :movie, title: "Sample Movie", year: 2010}

  defp episode,
    do: %Criteria{type: :tmdb, tmdb_type: :tv, title: "Sample Show", season_number: 1, episode_number: 3}

  defp series, do: %Criteria{type: :tmdb, tmdb_type: :tv, title: "Sample Show"}

  describe "assess/3 — a release nothing rejects" do
    test "a movie's release is accepted with the :movie scope" do
      assessment = Assessment.assess(result("Sample.Movie.2010.1080p.WEB-DL"), movie())

      assert assessment.reasons == []
      assert assessment.scope == :movie
      assert Assessment.accepted?(assessment)
      assert Assessment.reason(assessment) == nil
    end
  end

  describe "assess/3 — each gate names its reason" do
    test "a bait-shaped release is :red_flag" do
      assert Assessment.assess(result("Sample.Movie.2010.1080p.exe"), movie()).reasons == [:red_flag]

      assert Assessment.assess(result("Sample.Movie.2010.1080p.WEB-DL", %{size_bytes: 1024}), movie()).reasons ==
               [:red_flag]
    end

    test "a release the caller excluded is :excluded" do
      assessment =
        Assessment.assess(result("Sample.Movie.2010.1080p.WEB-DL"), movie(),
          excluded: MapSet.new(["guid-1"])
        )

      assert assessment.reasons == [:excluded]
    end

    test "a release of something else is :identity" do
      assert Assessment.assess(result("Another.Movie.2010.1080p.WEB-DL"), movie()).reasons == [:identity]
      assert Assessment.assess(result("Sample.Movie.1975.1080p.BluRay"), movie()).reasons == [:identity]
    end

    test "a release outside the quality bounds is :quality, only when bounds are given" do
      release = result("Sample.Movie.2010.1080p.WEB-DL")

      assert Assessment.assess(release, movie(), quality: {"uhd_4k", "uhd_4k"}).reasons == [:quality]
      assert Assessment.assess(release, movie(), quality: {"hd_1080p", "uhd_4k"}).reasons == []
      assert Assessment.assess(release, movie()).reasons == []
    end

    test "every failed gate is listed, in gate order, and reason/1 is the first" do
      assessment =
        Assessment.assess(result("Another.Movie.2010.1080p.exe"), movie(),
          excluded: MapSet.new(["guid-1"]),
          quality: {"uhd_4k", "uhd_4k"}
        )

      assert assessment.reasons == [:red_flag, :excluded, :identity, :quality]
      assert Assessment.reason(assessment) == :red_flag
      refute Assessment.accepted?(assessment)
    end
  end

  describe "assess/3 — how much of a TV release's scope must line up" do
    test ":exact (the default) accepts only the unit itself" do
      assert Assessment.assess(result("Sample.Show.S01E03.1080p.WEB-DL"), episode()).reasons == []
      assert Assessment.assess(result("Sample.Show.S01.1080p.WEB-DL"), episode()).reasons == [:identity]
    end

    test ":covering accepts any release that contains the unit, and carries its scope" do
      single = Assessment.assess(result("Sample.Show.S01E03.1080p.WEB-DL"), episode(), scope: :covering)
      pack = Assessment.assess(result("Sample.Show.S01.1080p.WEB-DL"), episode(), scope: :covering)
      other = Assessment.assess(result("Sample.Show.S02.1080p.WEB-DL"), episode(), scope: :covering)

      assert {single.reasons, single.scope} == {[], {:episode, 1, 3}}
      assert {pack.reasons, pack.scope} == {[], {:season, 1}}
      assert {other.reasons, other.scope} == {[:identity], nil}
    end

    test ":any accepts every scope of the show, and carries it" do
      pack = Assessment.assess(result("Sample.Show.S02.1080p.WEB-DL"), series(), scope: :any)
      other = Assessment.assess(result("Another.Show.S02.1080p.WEB-DL"), series(), scope: :any)

      assert {pack.reasons, pack.scope} == {[], {:season, 2}}
      assert other.reasons == [:identity]
    end

    test ":run accepts a release named for the criteria's later broadcast run" do
      run = %{index: 1, first_ep: {1, 13}, last_ep: {1, 24}}
      criteria = %{series() | run: run}

      named = Assessment.assess(result("Sample Show 2nd Season 1080p WEB-DL"), criteria, scope: :run)
      first_run = Assessment.assess(result("Sample.Show.S01.1080p.WEB-DL"), criteria, scope: :run)

      assert {named.reasons, named.scope} == {[], {:episodes, 1, 13, 24}}
      assert first_run.reasons == [:identity]
    end

    test "a movie is judged the same under every scope" do
      for scope <- [:exact, :covering, :any] do
        assert Assessment.assess(result("Sample.Movie.2010.1080p.WEB-DL"), movie(), scope: scope).scope ==
                 :movie
      end
    end
  end

  describe "accepted?/2 — a caller that shows flagged releases" do
    test "ignores the named reasons" do
      flagged = Assessment.assess(result("Sample.Movie.2010.1080p.WEB-DL", %{size_bytes: 1024}), movie())

      refute Assessment.accepted?(flagged)
      assert Assessment.accepted?(flagged, ignoring: [:red_flag])
    end
  end
end
