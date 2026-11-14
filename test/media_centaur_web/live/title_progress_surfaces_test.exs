defmodule MediaCentaurWeb.TitleProgressSurfacesTest do
  @moduledoc """
  Every surface shows the same title progress (design of 2026-11-14).

  One fixture — a rewatch in progress: a three-episode series, every
  episode carrying its watched mark, the series watch position at episode
  1 — read by Play, by Play's label, by Continue Watching and by both
  bars. Then playback finishes the last episode, and the detail page and
  the shelf follow.

  A failure here is a reader that derives "where am I" its own way: fix
  the reader, not the test.
  """
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Library.Progress
  alias MediaCentaur.Playback.Resolver
  alias MediaCentaur.Profiles.Actor

  setup do
    if Process.whereis(Progress.Worker) == nil do
      start_supervised!({Progress.Worker, [flush_interval_ms: 60_000, name: Progress.Worker]})
    end

    Progress.reset_for_test!()

    series = create_tv_series(%{name: "Sample Show"})
    season = create_season(%{tv_series_id: series.id, season_number: 1})

    episodes =
      for number <- 1..3 do
        create_episode(%{
          season_id: season.id,
          episode_number: number,
          name: "Episode #{number}",
          content_url: "/tv/sample-show/s01e0#{number}.mkv"
        })
      end

    rows = for episode <- episodes, do: create_watch_progress(%{episode_id: episode.id, completed: true})

    create_series_watch_position(%{
      profile_id: owner_profile_id(),
      playable_item_id: hd(rows).playable_item_id
    })

    %{series: series, episodes: episodes, rows: rows}
  end

  defp play_button(target_id),
    do: ~s|#detail-modal button[phx-click="play"][phx-value-id="#{target_id}"]|

  defp shelf_card(series_id), do: "#continue-watching-#{series_id}"

  # A bar drawn at `percent`: the fill's width is the measure the user sees.
  defp bar_at(percent), do: ~s|[style="width: #{percent}%"]|

  test "Play, its label, Continue Watching and both bars read the rewatch at episode 2 of 3",
       %{conn: conn, series: series, episodes: [_first, second, _third]} do
    assert {:ok, %{entry: entry}} = Resolver.resolve(owner_profile_id(), series.id)
    assert entry.content_url == "/tv/sample-show/s01e02.mkv"
    assert entry.start_position == 0.0

    {:ok, detail, _html} = live_async!(conn, ~p"/library?entity=#{series.id}")
    assert has_element?(detail, play_button(second.id), "Play Episode 2")

    {:ok, home, _html} = live_async!(conn, ~p"/")
    assert has_element?(home, shelf_card(series.id))
    assert has_element?(home, "#{shelf_card(series.id)} #{bar_at(33)}")

    {:ok, library, _html} = live_async!(conn, ~p"/library")

    assert has_element?(
             library,
             ~s|#library-grid [data-entity-id="#{series.id}"] .progress-fill#{bar_at(33)}|
           )
  end

  test "playback finishing the last episode ends the pass: Watch again, and the series leaves the shelf",
       %{conn: conn, series: series, rows: rows} do
    assert :ok = Progress.complete(Actor.new(owner_profile_id()), List.last(rows).playable_item_id)

    {:ok, detail, _html} = live_async!(conn, ~p"/library?entity=#{series.id}")
    assert has_element?(detail, play_button(series.id), "Watch again")

    {:ok, home, _html} = live_async!(conn, ~p"/")
    refute has_element?(home, shelf_card(series.id))

    {:ok, library, _html} = live_async!(conn, ~p"/library")

    assert has_element?(
             library,
             ~s|#library-grid [data-entity-id="#{series.id}"] .progress-fill#{bar_at(100)}|
           )

    assert {:ok, %{entry: entry}} = Resolver.resolve(owner_profile_id(), series.id)
    assert entry.content_url == "/tv/sample-show/s01e01.mkv"
  end
end
