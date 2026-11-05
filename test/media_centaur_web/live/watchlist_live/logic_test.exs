defmodule MediaCentaurWeb.WatchlistLive.LogicTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ReleaseTracking.Item, as: TrackingItem
  alias MediaCentaur.ReleaseTracking.Release
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.Watchlist.TitleIntent
  alias MediaCentaurWeb.Components.Watchlist.Row.{Item, State}
  alias MediaCentaurWeb.WatchlistLive.Logic

  @today ~D[2026-11-03]

  defp release(air_date, in_library \\ false),
    do: %Release{air_date: air_date, in_library: in_library, season_number: 1, episode_number: 1}

  defp tracking(releases), do: %TrackingItem{media_type: :tv_series, releases: releases}

  defp title(name, media_type),
    do: Title.new!(%{tmdb_id: :erlang.phash2(name), media_type: media_type, name: name})

  defp item(name, rung, state, media_type \\ :movie) do
    %Item{
      id: name,
      ref: {:erlang.phash2(name), media_type},
      title: title(name, media_type),
      rung: rung,
      state: state
    }
  end

  defp intent(rung, media_type, caught_up \\ nil) do
    {season, episode} = caught_up || {nil, nil}

    %TitleIntent{
      tmdb_id: 42,
      media_type: media_type,
      rung: rung,
      caught_up_season: season,
      caught_up_episode: episode
    }
  end

  describe "state/5 — a followed series reads its calendar through the caught-up point" do
    test "aired episodes not had: the count and the latest" do
      calendar =
        tracking([
          release(~D[2026-10-20]),
          release(~D[2026-10-27]),
          release(~D[2026-10-13], true),
          release(~D[2026-11-10])
        ])

      assert Logic.state(intent(:follow, :tv_series), calendar, nil, :returning, @today) ==
               %State{kind: :episodes_out, count: 2, date: ~D[2026-10-27], caught_up: nil}
    end

    test "episodes at or before the point are had: the count shrinks, the point rides on the state" do
      calendar =
        tracking([
          %Release{air_date: ~D[2026-10-20], season_number: 1, episode_number: 27},
          %Release{air_date: ~D[2026-10-27], season_number: 1, episode_number: 28},
          %Release{air_date: ~D[2026-11-03], season_number: 1, episode_number: 29}
        ])

      assert Logic.state(intent(:follow, :tv_series, {1, 28}), calendar, nil, :returning, @today) ==
               %State{kind: :episodes_out, count: 1, date: ~D[2026-11-03], caught_up: {1, 28}}

      assert Logic.state(intent(:follow, :tv_series, {1, 29}), calendar, nil, :returning, @today) ==
               %State{kind: :between_seasons, caught_up: {1, 29}}
    end

    test "nothing outstanding: the next dated episode" do
      calendar =
        tracking([release(~D[2026-10-27], true), release(~D[2026-11-17]), release(~D[2026-11-10])])

      assert Logic.state(intent(:grab, :tv_series), calendar, nil, :returning, @today) ==
               %State{kind: :next_episode, date: ~D[2026-11-10], caught_up: nil}
    end

    test "nothing outstanding and nothing dated: TMDB's status word" do
      calendar = tracking([release(~D[2026-10-27], true), release(nil)])

      assert Logic.state(intent(:follow, :tv_series), calendar, nil, :returning, @today) == %State{
               kind: :between_seasons
             }

      assert Logic.state(intent(:follow, :tv_series), calendar, nil, :ended, @today) == %State{
               kind: :ended
             }

      assert Logic.state(intent(:follow, :tv_series), calendar, nil, :canceled, @today) == %State{
               kind: :canceled
             }

      assert Logic.state(intent(:follow, :tv_series), calendar, nil, :unknown, @today) == %State{
               kind: :nothing_scheduled
             }

      assert Logic.state(intent(:follow, :tv_series), tracking([]), nil, nil, @today) == %State{
               kind: :nothing_scheduled
             }
    end
  end

  describe "state/5 — a movie, or a List-only title, reads its release stage" do
    test "the three stages and the unknown" do
      assert Logic.state(intent(:list, :movie), nil, %{stage: :home, date: ~D[2026-10-16]}, nil, @today) ==
               %State{kind: :out_now, date: ~D[2026-10-16]}

      assert Logic.state(
               intent(:grab, :movie),
               tracking([]),
               %{stage: :theatrical, date: ~D[2026-10-30]},
               nil,
               @today
             ) ==
               %State{kind: :in_theaters, date: ~D[2026-10-30]}

      assert Logic.state(
               intent(:list, :tv_series),
               nil,
               %{stage: :unreleased, date: ~D[2027-01-08]},
               nil,
               @today
             ) ==
               %State{kind: :coming_up, date: ~D[2027-01-08]}

      assert Logic.state(intent(:list, :movie), nil, %{stage: :unknown, date: nil}, nil, @today) ==
               %State{
                 kind: :undated
               }

      assert Logic.state(intent(:list, :movie), nil, nil, nil, @today) == %State{kind: :undated}
    end

    test "an Ignored record says so whatever else is known" do
      assert Logic.state(
               intent(:ignored, :tv_series),
               tracking([release(~D[2026-10-20])]),
               nil,
               :returning,
               @today
             ) ==
               %State{kind: :ignored}
    end
  end

  describe "the row's verbs and the page's counts" do
    test "caught_up_offered?/1: a followed series with episodes out, nothing else" do
      out = %State{kind: :episodes_out, count: 2, date: ~D[2026-10-27]}
      assert Logic.caught_up_offered?(item("Out", :follow, out, :tv_series))
      assert Logic.caught_up_offered?(item("Out", :grab, out, :tv_series))
      refute Logic.caught_up_offered?(item("Listed", :list, %State{kind: :out_now}, :tv_series))
      refute Logic.caught_up_offered?(item("Quiet", :follow, %State{kind: :next_episode}, :tv_series))
    end

    test "listed_count/1 counts records only: not the Ignored, not the series without one" do
      items = [
        item("A", :follow, %State{kind: :between_seasons}, :tv_series),
        item("B", :list, %State{kind: :undated}),
        item("C", :ignored, %State{kind: :ignored}),
        item("D", nil, %State{kind: :between_seasons}, :tv_series)
      ]

      assert Logic.listed_count(items) == 2
    end

    test "group_open?/2: a closed group opens on the person's toggle, or while a search is on" do
      refute Logic.group_open?(false, "")
      refute Logic.group_open?(false, "   ")
      assert Logic.group_open?(true, "")
      assert Logic.group_open?(false, "sample")
    end
  end

  describe "groups/1" do
    test "by rung in page order, empty groups dropped, rows by urgency within a group" do
      items = [
        item("Quiet", :follow, %State{kind: :between_seasons}, :tv_series),
        item("Ahead", :follow, %State{kind: :next_episode, date: ~D[2026-11-20]}, :tv_series),
        item("Soon", :follow, %State{kind: :next_episode, date: ~D[2026-11-10]}, :tv_series),
        item(
          "One out",
          :follow,
          %State{kind: :episodes_out, count: 1, date: ~D[2026-10-20]},
          :tv_series
        ),
        item(
          "Three out",
          :follow,
          %State{kind: :episodes_out, count: 3, date: ~D[2026-10-27]},
          :tv_series
        ),
        item("Over", :follow, %State{kind: :ended}, :tv_series),
        item("Listed", :list, %State{kind: :undated}),
        item("Older release", :grab, %State{kind: :out_now, date: ~D[2026-09-01]}),
        item("Newer release", :grab, %State{kind: :out_now, date: ~D[2026-10-16]}),
        item("Grabbed, waiting", :grab, %State{kind: :between_seasons}, :tv_series),
        item("Dismissed", :ignored, %State{kind: :ignored}),
        item("Watched", nil, %State{kind: :between_seasons}, :tv_series)
      ]

      assert [
               %{id: :grab, label: "Auto-grab", closed?: false, items: grab},
               %{id: :follow, label: "Tracking", closed?: false, items: follow},
               %{id: :list, label: "On your list", closed?: false, items: [%Item{id: "Listed"}]},
               %{id: :between_seasons, label: "Between seasons", closed?: true, items: between},
               %{id: :ignored, label: "Ignored", closed?: true, items: [%Item{id: "Dismissed"}]},
               %{
                 id: :watched,
                 label: "Series you've watched",
                 closed?: true,
                 items: [%Item{id: "Watched"}]
               }
             ] = Logic.groups(items)

      assert Enum.map(grab, & &1.id) == ["Newer release", "Older release"]
      assert Enum.map(follow, & &1.id) == ["Three out", "One out", "Soon", "Ahead", "Over"]
      assert Enum.map(between, & &1.id) == ["Grabbed, waiting", "Quiet"]
    end
  end

  describe "candidates/4 — the series you've watched with no record" do
    defp watched(name, tmdb_id),
      do: %{
        id: name,
        type: :tv_series,
        tmdb_id: tmdb_id,
        name: name,
        date_published: nil,
        description: nil
      }

    test "a returning or unknown-status series becomes an owned row with no rung; records and ended or canceled series are left out" do
      watched = [
        watched("Show A", "101"),
        watched("Show B", "102"),
        watched("Show C", "103"),
        watched("Show D", "104"),
        watched("Show E", "105")
      ]

      records = MapSet.new([{102, :tv_series}])

      statuses = %{
        {101, :tv_series} => :returning,
        {103, :tv_series} => :ended,
        {104, :tv_series} => :canceled
      }

      assert [returning, unknown] = Logic.candidates(watched, records, %{}, statuses)

      assert %Item{
               ref: {101, :tv_series},
               rung: nil,
               owned?: true,
               state: %State{kind: :between_seasons}
             } =
               returning

      assert returning.title.name == "Show A"
      assert returning.markers == ["In library"]
      assert %Item{ref: {105, :tv_series}, state: %State{kind: :nothing_scheduled}} = unknown
    end

    test "the stored snapshot is the row's title when the store holds the series" do
      stored = Title.new!(%{tmdb_id: 101, media_type: :tv_series, name: "Show A", poster_path: "/a.jpg"})

      assert [%Item{title: ^stored}] =
               Logic.candidates(
                 [watched("Show A", "101")],
                 MapSet.new(),
                 %{{101, :tv_series} => stored},
                 %{}
               )
    end
  end

  describe "narrow/3 and empty_reason/2" do
    test "the type filter and a case-blind name search" do
      movie = item("Sample Movie", :list, %State{kind: :undated})
      show = item("Sample Show", :follow, %State{kind: :between_seasons}, :tv_series)

      assert Logic.narrow([movie, show], :all, "") == [movie, show]
      assert Logic.narrow([movie, show], :movies, "") == [movie]
      assert Logic.narrow([movie, show], :series, "") == [show]
      assert Logic.narrow([movie, show], :all, "  SHOW ") == [show]
      assert Logic.narrow([movie, show], :movies, "show") == []
    end

    test "no record, nothing matching, or rows" do
      row = item("Sample Movie", :list, %State{kind: :undated})
      assert Logic.empty_reason([], []) == :no_records
      assert Logic.empty_reason([row], []) == :nothing_matches
      assert Logic.empty_reason([row], [row]) == nil
    end

    test "mark_open/2 marks the one row whose menu is open" do
      a = item("A", :list, %State{kind: :undated})
      b = item("B", :list, %State{kind: :undated})
      a_ref = MediaCentaurWeb.TitleRef.param(a.ref)

      assert [%Item{menu_open?: true}, %Item{menu_open?: false}] = Logic.mark_open([a, b], a_ref)
      assert [%Item{menu_open?: false}, %Item{menu_open?: false}] = Logic.mark_open([a, b], nil)
    end
  end

  describe "the words the events carry" do
    test "parse_filter/1 and parse_choice/1" do
      assert Logic.parse_filter("movies") == :movies
      assert Logic.parse_filter("series") == :series
      assert Logic.parse_filter("anything") == :all
      assert Logic.parse_choice("grab") == :grab
      assert Logic.parse_choice("ignored") == :ignored
      assert Logic.parse_choice("off") == :off
      assert Logic.parse_choice("nope") == nil
    end
  end

  describe "reloads?/1" do
    test "the broadcasts that change the rows" do
      assert Logic.reloads?({:title_intent_changed, %{}})
      assert Logic.reloads?({:releases_updated, ["id"]})
      assert Logic.reloads?({:item_removed, 42, :tv_series})
      assert Logic.reloads?({:entities_changed, ["id"]})
      assert Logic.reloads?({:tmdb_title_changed, {42, :tv_series}})
      assert Logic.reloads?({:activity_received, %{}})
      assert Logic.reloads?(%MediaCentaur.Acquisition.TargetEvents.Acquired{target: nil})
      refute Logic.reloads?({:queue_state, %{}})
      refute Logic.reloads?(:reload_rows)
    end
  end
end
