defmodule MediaCentaur.Watchlist.TitleIntentTest do
  @moduledoc """
  The rung ladder is the whole of a person's standing intent about a
  title. Off is the absence of a record, so it is never a stored value —
  which is what makes "Off deletes" a fact about the schema rather than a
  rule something has to enforce.
  """
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Watchlist.TitleIntent

  describe "the ladder" do
    test "runs Ignored · List · Follow · Grab, and Off is not on it" do
      assert TitleIntent.rungs() == [:ignored, :list, :follow, :grab]
      refute :off in TitleIntent.rungs()
    end

    test "rung_at_least?/2 orders the ladder" do
      assert TitleIntent.rung_at_least?(:follow, :follow)
      assert TitleIntent.rung_at_least?(:grab, :follow)
      refute TitleIntent.rung_at_least?(:list, :follow)
    end

    test "Ignored is a record below List — an opinion, unlike Off, but not on the list" do
      refute TitleIntent.rung_at_least?(:ignored, :list)
      assert TitleIntent.rung_at_least?(:ignored, :ignored)
      assert TitleIntent.rung_at_least?(:list, :ignored)
      refute TitleIntent.follows_releases?(:ignored)
    end

    test "a title with no record is below every rung" do
      assert TitleIntent.rung_at_least?(nil, :list) == false
      assert TitleIntent.rung_at_least?(nil, :follow) == false
    end

    test "following starts at Follow — List is on the list and nothing more" do
      refute TitleIntent.follows_releases?(:list)
      assert TitleIntent.follows_releases?(:follow)
      assert TitleIntent.follows_releases?(:grab)
      refute TitleIntent.follows_releases?(nil)
    end
  end

  describe "grabs?/1" do
    test "only Grab plans releases when they drop" do
      assert TitleIntent.grabs?(:grab)

      for rung <- [nil, :ignored, :list, :follow] do
        refute TitleIntent.grabs?(rung), "#{inspect(rung)} must never grab"
      end
    end
  end

  describe "the caught-up point" do
    test "caught_up_changeset/2 takes a season and episode of at least 1, on a series only" do
      series = %TitleIntent{tmdb_id: 1, media_type: :tv_series, rung: :follow}
      assert TitleIntent.caught_up_changeset(series, {2, 5}).valid?
      refute TitleIntent.caught_up_changeset(series, {0, 5}).valid?
      refute TitleIntent.caught_up_changeset(series, {2, 0}).valid?

      movie = %TitleIntent{tmdb_id: 1, media_type: :movie, rung: :follow}
      refute TitleIntent.caught_up_changeset(movie, {1, 1}).valid?
    end

    test "caught_up/1 is the pair, or nil when none is set" do
      assert TitleIntent.caught_up(%TitleIntent{caught_up_season: 2, caught_up_episode: 5}) == {2, 5}
      assert TitleIntent.caught_up(%TitleIntent{}) == nil
    end
  end

  describe "label/1" do
    test "is the record's name and year as a bare title with its identity" do
      intent = %TitleIntent{
        tmdb_id: 7,
        media_type: :tv_series,
        title_name: "Sample Show",
        title_year: "2019"
      }

      assert TitleIntent.label(intent) == %MediaCentaur.TMDB.Title{
               tmdb_id: 7,
               media_type: :tv_series,
               name: "Sample Show",
               year: "2019"
             }
    end
  end

  describe "friend_provenance/2" do
    test "names the activity a friend-sourced record came from, with its note" do
      assert TitleIntent.friend_provenance("activity-1", "Watch it.") ==
               %{source: :friend, activity_id: "activity-1", note: "Watch it."}

      assert TitleIntent.friend_provenance("activity-1", nil) ==
               %{source: :friend, activity_id: "activity-1", note: nil}
    end
  end
end
