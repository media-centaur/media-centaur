defmodule MediaCentaurWeb.DiscoveryLive.ShelvesTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.NewReleases.Member
  alias MediaCentaur.ReleaseTracking.Item, as: TrackingItem
  alias MediaCentaur.ReleaseTracking.Release
  alias MediaCentaur.Social.Person
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.Watchlist.TitleIntent
  alias MediaCentaurWeb.Components.PosterRow.Item
  alias MediaCentaurWeb.DiscoveryLive.Shelves

  defp member(tmdb_id, position),
    do: %Member{tmdb_id: tmdb_id, position: position, digital_date: ~D[2026-10-30]}

  defp title(tmdb_id, name),
    do:
      Title.new!(%{
        tmdb_id: tmdb_id,
        media_type: :movie,
        name: name,
        year: "2026",
        poster_path: "/p#{tmdb_id}.jpg"
      })

  describe "new_releases_items/5" do
    test "one tile per stored member in shelf order, keyed by ref, with the year and a poster" do
      members = [member(902, 0), member(901, 1)]
      snapshots = %{{901, :movie} => title(901, "Movie A"), {902, :movie} => title(902, "Movie B")}

      assert [
               %Item{id: "movie-902", ref: {902, :movie}, name: "Movie B", year: "2026", marker: nil},
               %Item{id: "movie-901", ref: {901, :movie}, name: "Movie A"}
             ] = Shelves.new_releases_items(members, snapshots, %{}, %{}, %{})

      assert [%Item{poster_url: "https://image.tmdb.org/t/p/w342/p902.jpg"} | _rest] =
               Shelves.new_releases_items(members, snapshots, %{}, %{}, %{})
    end

    test "a member the store has no record for is not drawn; an ignored one is dropped" do
      members = [member(901, 0), member(902, 1), member(903, 2)]
      snapshots = %{{901, :movie} => title(901, "Movie A"), {902, :movie} => title(902, "Movie B")}

      assert [%Item{id: "movie-901"}] =
               Shelves.new_releases_items(members, snapshots, %{{902, :movie} => :ignored}, %{}, %{})
    end

    test "the marker is the library's claim first, else the acquisition state, else the rung" do
      members = [member(901, 0), member(902, 1), member(903, 2), member(904, 3)]

      snapshots =
        Map.new([901, 902, 903, 904], &{{&1, :movie}, title(&1, "Movie #{&1}")})

      items =
        Shelves.new_releases_items(
          members,
          snapshots,
          %{{901, :movie} => :follow, {903, :movie} => :list, {904, :movie} => :grab},
          %{{901, :movie} => "owner-uuid"},
          %{{902, :movie} => :downloading}
        )

      assert Enum.map(items, & &1.marker) == ["In library", "Downloading", "On your list", "Auto-grab"]
    end
  end

  describe "watchlist_shelves/5" do
    @today ~D[2026-11-01]

    defp listed(tmdb_id, rung, media_type \\ :movie, owner \\ nil) do
      %{
        intent: %TitleIntent{
          tmdb_id: tmdb_id,
          media_type: media_type,
          rung: rung,
          title:
            Title.new!(%{
              tmdb_id: tmdb_id,
              media_type: media_type,
              name: "Title #{tmdb_id}",
              year: "2026"
            })
        },
        library_owner_id: owner
      }
    end

    test "placed by stage: Out Now newest home date first, In Theaters newest opening first with the day, Coming Up nearest first with the month" do
      stages = %{
        {1, :movie} => %{stage: :home, date: ~D[2026-10-20]},
        {2, :movie} => %{stage: :home, date: ~D[2026-10-28]},
        {3, :movie} => %{stage: :theatrical, date: ~D[2026-10-10]},
        {4, :movie} => %{stage: :theatrical, date: ~D[2026-10-24]},
        {5, :movie} => %{stage: :unreleased, date: ~D[2027-02-01]},
        {6, :tv_series} => %{stage: :unreleased, date: ~D[2026-12-05]},
        {7, :movie} => %{stage: :unknown, date: nil}
      }

      listed = [
        listed(1, :list),
        listed(2, :follow),
        listed(3, :list),
        listed(4, :grab),
        listed(5, :list),
        listed(6, :follow, :tv_series),
        listed(7, :list)
      ]

      shelves = Shelves.watchlist_shelves(listed, stages, %{}, %{{1, :movie} => :downloading}, @today)

      assert Enum.map(shelves.out_now, &{&1.id, &1.marker, &1.chip}) == [
               {"movie-2", "Tracking", nil},
               {"movie-1", "Downloading", nil}
             ]

      assert Enum.map(shelves.in_theaters, &{&1.id, &1.marker, &1.chip}) == [
               {"movie-4", "Auto-grab", "Oct 24"},
               {"movie-3", "On your list", "Oct 10"}
             ]

      assert Enum.map(shelves.coming_up, &{&1.id, &1.chip}) == [
               {"tv_series-6", "Dec"},
               {"movie-5", "Feb 2027"}
             ]
    end

    test "an owned film, an owned series nobody follows, and a title the store lacks are off every shelf" do
      stages = %{
        {1, :movie} => %{stage: :home, date: ~D[2026-10-20]},
        {3, :tv_series} => %{stage: :home, date: ~D[2020-01-01]}
      }

      listed = [
        listed(1, :list, :movie, "owner-uuid"),
        listed(2, :list),
        listed(3, :list, :tv_series, "owner-uuid")
      ]

      assert %{out_now: [], in_theaters: [], coming_up: []} =
               Shelves.watchlist_shelves(listed, stages, %{}, %{}, @today)
    end

    test "a followed series the library holds is placed by its calendar, its chip naming the seasons out" do
      releases = [
        %Release{season_number: 1, episode_number: 10, air_date: ~D[2026-01-10], in_library: true},
        %Release{season_number: 1, episode_number: 11, air_date: ~D[2026-10-20]},
        %Release{season_number: 2, episode_number: 1, air_date: ~D[2026-10-27]}
      ]

      item = %TrackingItem{
        media_type: :tv_series,
        releases: releases,
        last_library_season: 1,
        last_library_episode: 10
      }

      owned = listed(8, :follow, :tv_series, "owner-uuid")
      shelves = Shelves.watchlist_shelves([owned], %{}, %{{8, :tv_series} => item}, %{}, @today)

      assert [%Item{id: "tv_series-8", chip: "Seasons 1–2", marker: "Tracking"}] = shelves.out_now
    end

    test "a followed series is placed by its calendar through the caught-up point, never by its first air date; its chip names the season" do
      stages = %{{6, :tv_series} => %{stage: :home, date: ~D[2023-09-29]}}

      releases = [
        %Release{season_number: 1, episode_number: 28, air_date: ~D[2026-10-24]},
        %Release{season_number: 1, episode_number: 29, air_date: ~D[2026-10-31]},
        %Release{season_number: 1, episode_number: 30, air_date: ~D[2026-11-07]}
      ]

      item = %TrackingItem{media_type: :tv_series, releases: releases}
      behind = listed(6, :follow, :tv_series)
      shelves = Shelves.watchlist_shelves([behind], stages, %{{6, :tv_series} => item}, %{}, @today)
      assert [%Item{id: "tv_series-6", chip: "Season 1"}] = shelves.out_now

      caught_up =
        put_in(put_in(behind.intent.caught_up_season, 1), [:intent, Access.key(:caught_up_episode)], 29)

      shelves = Shelves.watchlist_shelves([caught_up], stages, %{{6, :tv_series} => item}, %{}, @today)
      assert shelves.out_now == []
      assert [%Item{id: "tv_series-6", chip: "Season 1 · Nov 7"}] = shelves.coming_up

      ended = %TrackingItem{media_type: :tv_series, releases: Enum.take(releases, 2)}
      shelves = Shelves.watchlist_shelves([caught_up], stages, %{{6, :tv_series} => ended}, %{}, @today)
      assert %{out_now: [], in_theaters: [], coming_up: []} = shelves
    end
  end

  describe "friends_items/5" do
    defp review(tmdb_id, author, sentiment) do
      %{
        activity: %Activity{
          kind: :review,
          sentiment: sentiment,
          author_pubkey: author,
          tmdb_id: tmdb_id,
          media_type: :movie
        },
        author: %Person{own?: false}
      }
    end

    test "one tile per reviewed title with the flags friends flew at their grade; an ignored title is dropped; an owned one is marked" do
      reviewed = [
        %{ref: {1, :movie}, title: title(1, "Movie A")},
        %{ref: {2, :movie}, title: title(2, "Movie B")},
        %{ref: {3, :movie}, title: title(3, "Movie C")}
      ]

      activity = %{
        {1, :movie} => [review(1, "aa", :love), review(1, "bb", :love), review(1, "cc", :like)],
        {3, :movie} => [review(3, "aa", nil)]
      }

      items =
        Shelves.friends_items(
          reviewed,
          activity,
          %{{2, :movie} => :ignored},
          %{{3, :movie} => "owner"},
          %{}
        )

      assert [
               %Item{
                 id: "movie-1",
                 marker: nil,
                 glyphs: %{flags: [:love, :like], grades: %{love: :silver, like: :plain}}
               },
               %Item{id: "movie-3", marker: "In library", glyphs: %{flags: [:review]}}
             ] = items
    end
  end

  describe "empty_reason/3" do
    test "TMDB never configured is the capability gap, whatever else holds" do
      assert Shelves.empty_reason(false, true, 0) == :tmdb_unconfigured
      assert Shelves.empty_reason(false, false, 3) == :tmdb_unconfigured
    end

    test "with tiles there is no reason" do
      assert Shelves.empty_reason(true, false, 1) == nil
    end

    test "nothing to show says whether TMDB is down or the first refresh has not run" do
      assert Shelves.empty_reason(true, false, 0) == :tmdb_down
      assert Shelves.empty_reason(true, true, 0) == :filling
    end
  end

  describe "reloads?/1" do
    test "the broadcasts that change the shelf, and nothing else" do
      assert Shelves.reloads?({:new_releases_changed})
      assert Shelves.reloads?({:tmdb_title_changed, {901, :movie}})
      assert Shelves.reloads?({:title_intent_changed, %{}})
      assert Shelves.reloads?({:entities_changed, %{}})
      assert Shelves.reloads?({:activity_received, %{}})
      assert Shelves.reloads?({:activity_deleted, %{}})
      assert Shelves.reloads?({:setting_changed, "feature:social", %{}})
      refute Shelves.reloads?({:setting_changed, "feature:apps", %{}})
      assert Shelves.reloads?({:integration_availability_changed, :tmdb, :up})
      refute Shelves.reloads?({:integration_availability_changed, :prowlarr, :up})
      refute Shelves.reloads?({:playback_state_changed, %{}})
    end
  end
end
