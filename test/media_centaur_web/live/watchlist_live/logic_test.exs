defmodule MediaCentaurWeb.WatchlistLive.LogicTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ReleaseTracking.Item, as: TrackingItem
  alias MediaCentaur.ReleaseTracking.Release
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Watchlist.Row.{Item, State}
  alias MediaCentaurWeb.WatchlistLive.Logic

  @today ~D[2026-11-03]

  defp release(air_date, in_library \\ false),
    do: %Release{air_date: air_date, in_library: in_library, season_number: 1, episode_number: 1}

  defp tracking(releases), do: %TrackingItem{releases: releases}

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

  describe "state/6 — a followed series reads its calendar" do
    test "aired episodes not had: the count and the latest" do
      calendar =
        tracking([
          release(~D[2026-10-20]),
          release(~D[2026-10-27]),
          release(~D[2026-10-13], true),
          release(~D[2026-11-10])
        ])

      assert Logic.state(:follow, :tv_series, calendar, nil, :returning, @today) ==
               %State{kind: :episodes_out, count: 2, date: ~D[2026-10-27]}
    end

    test "nothing outstanding: the next dated episode" do
      calendar =
        tracking([release(~D[2026-10-27], true), release(~D[2026-11-17]), release(~D[2026-11-10])])

      assert Logic.state(:grab, :tv_series, calendar, nil, :returning, @today) ==
               %State{kind: :next_episode, date: ~D[2026-11-10]}
    end

    test "nothing outstanding and nothing dated: TMDB's status word" do
      calendar = tracking([release(~D[2026-10-27], true), release(nil)])

      assert Logic.state(:follow, :tv_series, calendar, nil, :returning, @today) == %State{
               kind: :between_seasons
             }

      assert Logic.state(:follow, :tv_series, calendar, nil, :ended, @today) == %State{kind: :ended}

      assert Logic.state(:follow, :tv_series, calendar, nil, :canceled, @today) == %State{
               kind: :canceled
             }

      assert Logic.state(:follow, :tv_series, calendar, nil, :unknown, @today) == %State{
               kind: :nothing_scheduled
             }

      assert Logic.state(:follow, :tv_series, tracking([]), nil, nil, @today) == %State{
               kind: :nothing_scheduled
             }
    end
  end

  describe "state/6 — a movie, or a List-only title, reads its release stage" do
    test "the three stages and the unknown" do
      assert Logic.state(:list, :movie, nil, %{stage: :home, date: ~D[2026-10-16]}, nil, @today) ==
               %State{kind: :out_now, date: ~D[2026-10-16]}

      assert Logic.state(
               :grab,
               :movie,
               tracking([]),
               %{stage: :theatrical, date: ~D[2026-10-30]},
               nil,
               @today
             ) ==
               %State{kind: :in_theaters, date: ~D[2026-10-30]}

      assert Logic.state(
               :list,
               :tv_series,
               nil,
               %{stage: :unreleased, date: ~D[2027-01-08]},
               nil,
               @today
             ) ==
               %State{kind: :coming_up, date: ~D[2027-01-08]}

      assert Logic.state(:list, :movie, nil, %{stage: :unknown, date: nil}, nil, @today) == %State{
               kind: :undated
             }

      assert Logic.state(:list, :movie, nil, nil, nil, @today) == %State{kind: :undated}
    end

    test "an Ignored record says so whatever else is known" do
      assert Logic.state(
               :ignored,
               :tv_series,
               tracking([release(~D[2026-10-20])]),
               nil,
               :returning,
               @today
             ) ==
               %State{kind: :ignored}
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
        item("Listed", :list, %State{kind: :undated}),
        item("Older release", :grab, %State{kind: :out_now, date: ~D[2026-09-01]}),
        item("Newer release", :grab, %State{kind: :out_now, date: ~D[2026-10-16]}),
        item("Dismissed", :ignored, %State{kind: :ignored})
      ]

      assert [
               %{rung: :grab, label: "Auto-grab", items: grab},
               %{rung: :follow, label: "Tracking", items: follow},
               %{rung: :list, label: "On your list", items: [%Item{id: "Listed"}]},
               %{rung: :ignored, label: "Ignored", items: [%Item{id: "Dismissed"}]}
             ] = Logic.groups(items)

      assert Enum.map(grab, & &1.id) == ["Newer release", "Older release"]
      assert Enum.map(follow, & &1.id) == ["Three out", "One out", "Soon", "Ahead", "Quiet"]
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
