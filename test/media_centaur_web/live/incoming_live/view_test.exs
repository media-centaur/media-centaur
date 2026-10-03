defmodule MediaCentaurWeb.IncomingLive.ViewTest do
  @moduledoc """
  Pure unit tests for the Incoming page's one composition point. The builder
  takes already-read facts and returns the per-section view structs; every
  section is a projection of the same story, so the honest-degradation rule
  (acquisition off ⇒ no operational sections, no grab-implying statuses)
  is enforced HERE, not scattered across templates.
  """
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Acquisition.ViewModels.PursuitRow
  alias MediaCentaur.Watchlist.TitleIntent
  alias MediaCentaur.ReleaseTracking.UpcomingFeed
  alias MediaCentaur.TestFactory
  alias MediaCentaurWeb.Components.Title.Row.NextRelease
  alias MediaCentaurWeb.IncomingLive.View

  @today ~D[2026-06-14]

  defp tv_item(overrides \\ %{}) do
    TestFactory.build_tracking_item(
      Map.merge(%{media_type: :tv_series, name: "Sample Show", tmdb_id: 1001}, overrides)
    )
  end

  defp movie_item(overrides \\ %{}) do
    TestFactory.build_tracking_item(
      Map.merge(%{media_type: :movie, name: "Movie A", tmdb_id: 2002}, overrides)
    )
  end

  defp release(item, overrides) do
    TestFactory.build_tracking_release(Map.merge(%{item_id: item.id, item: item}, overrides))
  end

  # A watchlist read row for a fixture item, at `rung`.
  defp listed(item, rung \\ :grab) do
    %{
      intent: %TitleIntent{
        tmdb_id: item.tmdb_id,
        media_type: item.media_type,
        rung: rung,
        inserted_at: ~N[2026-06-01 00:00:00],
        title:
          MediaCentaur.TMDB.Title.new!(%{
            tmdb_id: item.tmdb_id,
            media_type: item.media_type,
            name: item.name
          })
      },
      library_owner_id: nil
    }
  end

  defp pursuit_row(overrides) do
    Map.merge(
      %PursuitRow{id: Ecto.UUID.generate(), title: "Sample Show", state: :active, status: "Grabbing"},
      overrides
    )
  end

  defp inputs(overrides) do
    Map.merge(
      %{
        releases: [],
        pursuit_rows: [],
        drafts: [],
        today: @today,
        prowlarr_ready?: true,
        acquisition_ready?: true,
        approval_policy: "automatic",
        # Every fixture title sits at Grab, so the policy above is what
        # decides whether a release reads as armed.
        rungs: %{{1001, :tv_series} => :grab, {2002, :movie} => :grab},
        grab_status_by_key: %{},
        watchlist: [],
        social_activity: %{},
        acquisition_states: %{},
        posters: %{}
      },
      overrides
    )
  end

  describe "build/1 — watchlist rows" do
    test "a followed title's row carries its next release, nearest first, with graduated labels" do
      first_item = tv_item(%{tmdb_id: 1})
      second_item = tv_item(%{tmdb_id: 2, name: "Other Show"})

      releases = [
        release(first_item, %{
          title: "The Vanishing Reel",
          air_date: @today,
          season_number: 2,
          episode_number: 5
        }),
        release(second_item, %{
          title: "Signal Fires",
          air_date: Date.add(@today, 2),
          season_number: 2,
          episode_number: 6
        })
      ]

      view =
        View.build(
          inputs(%{
            releases: releases,
            watchlist: [listed(second_item), listed(first_item)],
            rungs: %{{1, :tv_series} => :grab, {2, :tv_series} => :grab}
          })
        )

      assert [first, second] = view.watchlist
      assert first.title.name == "Sample Show"
      assert first.next_release.subtitle == "S02E05 · “The Vanishing Reel”"
      assert first.next_release.date_label == "Tonight"
      assert second.next_release.date_label == "Tue"
    end

    test "statuses map into the shared pill union" do
      movie = movie_item()
      pursued_item = tv_item(%{tmdb_id: 1})
      armed_item = tv_item(%{tmdb_id: 2, name: "Other Show"})

      pursued =
        release(pursued_item, %{
          title: "pursued",
          air_date: @today,
          season_number: 1,
          episode_number: 1
        })

      pursuit_id = Ecto.UUID.generate()

      releases = [
        pursued,
        release(armed_item, %{
          title: "armed",
          air_date: Date.add(@today, 1),
          season_number: 1,
          episode_number: 2
        }),
        release(movie, %{title: "theatrical", air_date: @today, release_type: "theatrical"})
      ]

      view =
        View.build(
          inputs(%{
            releases: releases,
            watchlist: [listed(pursued_item), listed(armed_item), listed(movie)],
            rungs: %{
              {1, :tv_series} => :grab,
              {2, :tv_series} => :grab,
              {2002, :movie} => :grab
            },
            grab_status_by_key: %{UpcomingFeed.release_key(pursued) => %{pursuit_id: pursuit_id}}
          })
        )

      by_ref = Map.new(view.watchlist, &{&1.ref, &1.next_release})

      assert %NextRelease{status: :in_pursuit, pursuit_id: ^pursuit_id} = by_ref[{1, :tv_series}]
      assert %NextRelease{status: :armed} = by_ref[{2, :tv_series}]
      assert %NextRelease{status: :in_theaters} = by_ref[{2002, :movie}]
    end

    test "a past armed release reads Searching — the app is looking for it now, not waiting for a drop" do
      item = tv_item()

      old =
        release(item, %{
          title: "old",
          air_date: ~D[1998-05-18],
          released: true,
          season_number: 10,
          episode_number: 21
        })

      view = View.build(inputs(%{releases: [old], watchlist: [listed(item)]}))

      assert [%{next_release: %NextRelease{status: :searching}}] = view.watchlist
    end

    test "a movie whose release title just repeats the movie name gets no subtitle" do
      movie = movie_item(%{name: "Movie A"})
      releases = [release(movie, %{title: "Movie A", air_date: @today, release_type: "digital"})]

      view = View.build(inputs(%{releases: releases, watchlist: [listed(movie)]}))

      assert [%{next_release: %NextRelease{subtitle: nil}}] = view.watchlist
    end

    test "a movie edition title distinct from the name survives as the subtitle" do
      movie = movie_item(%{name: "Movie A"})

      releases = [
        release(movie, %{title: "Restored edition", air_date: @today, release_type: "digital"})
      ]

      view = View.build(inputs(%{releases: releases, watchlist: [listed(movie)]}))

      assert [%{next_release: %NextRelease{subtitle: "Restored edition"}}] = view.watchlist
    end

    test "a season drop is one next release naming the season and the count" do
      item = tv_item()

      releases =
        for n <- 1..8 do
          release(item, %{
            title: "ep-#{n}",
            air_date: Date.add(@today, 10),
            season_number: 3,
            episode_number: n
          })
        end

      view = View.build(inputs(%{releases: releases, watchlist: [listed(item)]}))

      assert [%{next_release: %NextRelease{subtitle: "S3 · all 8 episodes at once"}}] = view.watchlist
    end

    test "a listed-only title is a row with no next release, after the dated rows" do
      dated = tv_item(%{tmdb_id: 1})
      listed_only = movie_item(%{tmdb_id: 2002})

      releases = [
        release(dated, %{title: "ep", air_date: Date.add(@today, 3), season_number: 1, episode_number: 1})
      ]

      view =
        View.build(
          inputs(%{
            releases: releases,
            watchlist: [listed(listed_only, :list), listed(dated)],
            rungs: %{{1, :tv_series} => :grab}
          })
        )

      assert [%{ref: {1, :tv_series}}, %{ref: {2002, :movie}, next_release: nil}] = view.watchlist
    end
  end

  describe "build/1 — operational sections" do
    test "in-flight rows and drafts pass through when acquisition is ready" do
      active = pursuit_row(%{state: :active})

      view =
        View.build(
          inputs(%{
            pursuit_rows: [active],
            drafts: [%{id: "draft-1", title: "The Golem", status: "ready"}]
          })
        )

      assert view.in_flight == [active]
      assert [%{id: "draft-1"}] = view.drafts
    end
  end

  describe "build/1 — honest degradation" do
    test "no indexer: operational sections empty and no grab-implying statuses, whatever the caller passes" do
      item = tv_item()

      releases = [
        release(item, %{title: "ep", air_date: Date.add(@today, 1), season_number: 1, episode_number: 1})
      ]

      view =
        View.build(
          inputs(%{
            prowlarr_ready?: false,
            acquisition_ready?: false,
            releases: releases,
            watchlist: [listed(item)],
            pursuit_rows: [pursuit_row(%{})],
            drafts: [%{id: "draft-1"}],
            grab_status_by_key: %{some: :junk}
          })
        )

      assert view.in_flight == []
      assert view.drafts == []
      assert [%{next_release: %NextRelease{status: :tracked}}] = view.watchlist
    end

    test "indexer without a download client: sections stay (pursuits can search) but nothing reads armed" do
      item = tv_item()

      releases = [
        release(item, %{title: "ep", air_date: Date.add(@today, 1), season_number: 1, episode_number: 1})
      ]

      active = pursuit_row(%{})

      view =
        View.build(
          inputs(%{
            prowlarr_ready?: true,
            acquisition_ready?: false,
            releases: releases,
            watchlist: [listed(item)],
            pursuit_rows: [active]
          })
        )

      assert view.in_flight == [active]
      assert [%{next_release: %NextRelease{status: :tracked}}] = view.watchlist
    end
  end

  describe "with_progress/2" do
    test "stamps the percent onto an in-pursuit row and leaves the rest alone" do
      rows = [
        %{
          ref: {1, :tv_series},
          next_release: %NextRelease{
            air_date: @today,
            date_label: "Today",
            status: :in_pursuit,
            pursuit_id: "p-1"
          }
        },
        %{
          ref: {2, :tv_series},
          next_release: %NextRelease{air_date: @today, date_label: "Today", status: :tracked}
        },
        %{ref: {3, :movie}, next_release: nil}
      ]

      [a, b, c] = View.with_progress(rows, %{"p-1" => 62})
      assert a.next_release.percent == 62
      assert b.next_release.percent == nil
      assert c.next_release == nil
    end

    test "an unknown pursuit stays percentless (searching, nothing paired yet)" do
      rows = [
        %{
          ref: {1, :tv_series},
          next_release: %NextRelease{
            air_date: @today,
            date_label: "Today",
            status: :in_pursuit,
            pursuit_id: "nope"
          }
        }
      ]

      assert [%{next_release: %NextRelease{percent: nil}}] = View.with_progress(rows, %{})
    end
  end
end
