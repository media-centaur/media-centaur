defmodule MediaCentaurWeb.IncomingLive.ViewTest do
  @moduledoc """
  Pure unit tests for the Incoming page's one composition point. The builder
  takes already-read facts and returns the per-section view structs; every
  section is a projection of the same story, so the honest-degradation rule
  (acquisition off ⇒ no operational sections, no grab-implying statuses)
  is enforced HERE, not scattered across templates.
  """
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.ViewModels.PursuitRow
  alias MediaCentaur.ReleaseTracking.UpcomingFeed
  alias MediaCentaur.TestFactory
  alias MediaCentaurWeb.Components.Incoming.Shelf.Card
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
        watching_items: [],
        pursuit_rows: [],
        ledger_rows: [],
        drafts: [],
        today: @today,
        prowlarr_ready?: true,
        acquisition_ready?: true,
        auto_grab_default_mode: "all_releases",
        grab_status_by_key: %{},
        ledger_expanded?: false
      },
      overrides
    )
  end

  describe "build/1 — shelf projection" do
    test "maps scheduled events into shelf cards nearness-first with graduated labels" do
      item = tv_item()

      releases = [
        release(item, %{
          title: "The Vanishing Reel",
          air_date: @today,
          season_number: 2,
          episode_number: 5
        }),
        release(item, %{
          title: "Signal Fires",
          air_date: Date.add(@today, 2),
          season_number: 2,
          episode_number: 6
        })
      ]

      view = View.build(inputs(%{releases: releases}))

      assert [%Card{} = first, %Card{} = second] = view.shelf.cards
      assert first.title == "Sample Show"
      assert first.subtitle == "S02E05 · “The Vanishing Reel”"
      assert first.date_label == "Tonight"
      assert first.kind == :episode
      assert second.date_label == "Tue"
      assert view.shelf.overflow_count == 0
    end

    test "statuses map into the shared pill union" do
      item = tv_item()
      movie = movie_item()

      pursued =
        release(item, %{title: "pursued", air_date: @today, season_number: 1, episode_number: 1})

      pursuit_id = Ecto.UUID.generate()

      releases = [
        pursued,
        release(item, %{
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
            grab_status_by_key: %{UpcomingFeed.release_key(pursued) => %{pursuit_id: pursuit_id}}
          })
        )

      statuses = Map.new(view.shelf.cards, &{&1.subtitle || &1.title, &1.status})

      assert %{"S01E01 · “pursued”" => :in_pursuit} = statuses
      assert %{"S01E02 · “armed”" => :armed} = statuses
      assert Enum.any?(view.shelf.cards, &(&1.status == :in_theaters))
      assert Enum.find(view.shelf.cards, &(&1.status == :in_pursuit)).pursuit_id == pursuit_id
    end

    test "a movie whose release title just repeats the movie name gets no subtitle" do
      movie = movie_item(%{name: "Movie A"})
      releases = [release(movie, %{title: "Movie A", air_date: @today, release_type: "digital"})]

      view = View.build(inputs(%{releases: releases}))

      assert [%Card{title: "Movie A", subtitle: nil}] = view.shelf.cards
    end

    test "a movie edition title distinct from the name survives as the subtitle" do
      movie = movie_item(%{name: "Movie A"})

      releases = [
        release(movie, %{title: "Restored edition", air_date: @today, release_type: "digital"})
      ]

      view = View.build(inputs(%{releases: releases}))

      assert [%Card{subtitle: "Restored edition"}] = view.shelf.cards
    end

    test "a season drop becomes one stacked card with a bare season subtitle" do
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

      view = View.build(inputs(%{releases: releases}))

      assert [%Card{kind: :season_drop, subtitle: "S3", episode_count: 8}] = view.shelf.cards
    end

    test "overflow and stragglers ride along" do
      item = tv_item()

      releases =
        for n <- 1..9 do
          release(item, %{
            title: "ep-#{n}",
            air_date: Date.add(@today, n),
            season_number: 1,
            episode_number: n
          })
        end

      straggler = %{
        id: "straggler-item",
        name: "The Golem",
        media_type: :movie,
        releases: [%{air_date: nil}]
      }

      view = View.build(inputs(%{releases: releases, watching_items: [straggler]}))

      assert length(view.shelf.cards) == 6
      assert view.shelf.overflow_count == 3
      assert [%UpcomingFeed.Straggler{name: "The Golem"}] = view.shelf.stragglers
    end
  end

  describe "build/1 — operational sections" do
    test "in-flight rows, ledger, and drafts pass through when acquisition is ready" do
      active = pursuit_row(%{state: :active})
      terminal = Enum.map(1..9, fn n -> pursuit_row(%{id: "terminal-#{n}", state: :satisfied}) end)

      view =
        View.build(
          inputs(%{
            pursuit_rows: [active],
            ledger_rows: terminal,
            drafts: [%{id: "draft-1", title: "The Golem", status: "ready"}]
          })
        )

      assert view.in_flight == [active]
      assert length(view.ledger.rows) == 4
      assert view.ledger.hidden_count == 5
      refute view.ledger.expanded?
      assert [%{id: "draft-1"}] = view.drafts
    end

    test "an expanded ledger reveals more" do
      terminal = Enum.map(1..9, fn n -> pursuit_row(%{id: "terminal-#{n}", state: :satisfied}) end)

      view = View.build(inputs(%{ledger_rows: terminal, ledger_expanded?: true}))

      assert length(view.ledger.rows) == 9
      assert view.ledger.hidden_count == 0
      assert view.ledger.expanded?
    end
  end

  describe "build/1 — honest degradation" do
    test "no indexer: operational sections empty and no grab-implying shelf statuses, whatever the caller passes" do
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
            pursuit_rows: [pursuit_row(%{})],
            ledger_rows: [pursuit_row(%{state: :satisfied})],
            drafts: [%{id: "draft-1"}],
            grab_status_by_key: %{some: :junk}
          })
        )

      assert view.in_flight == []
      assert view.ledger.rows == []
      assert view.ledger.hidden_count == 0
      assert view.drafts == []
      assert Enum.all?(view.shelf.cards, &(&1.status in [:tracked, :in_theaters, :landed]))
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
            pursuit_rows: [active]
          })
        )

      assert view.in_flight == [active]
      assert Enum.all?(view.shelf.cards, &(&1.status != :armed))
    end
  end

  describe "with_progress/2" do
    test "stamps percent onto in-pursuit cards by pursuit id and leaves the rest alone" do
      pursuit_id = Ecto.UUID.generate()

      cards = [
        %Card{
          key: "a",
          item_id: "i1",
          title: "T",
          kind: :episode,
          status: :in_pursuit,
          pursuit_id: pursuit_id
        },
        %Card{key: "b", item_id: "i2", title: "U", kind: :episode, status: :armed}
      ]

      [pursued, armed] = View.with_progress(cards, %{pursuit_id => 62})

      assert pursued.percent == 62
      assert armed.percent == nil
    end

    test "an unknown pursuit stays percentless (searching, nothing paired yet)" do
      cards = [
        %Card{
          key: "a",
          item_id: "i1",
          title: "T",
          kind: :episode,
          status: :in_pursuit,
          pursuit_id: "nope"
        }
      ]

      assert [%Card{percent: nil}] = View.with_progress(cards, %{})
    end
  end
end
